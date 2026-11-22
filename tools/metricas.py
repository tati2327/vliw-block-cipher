"""Ejecuta los benchmarks y reúne resultados verificados por programa y recorrido."""
import argparse
import csv
import hashlib
import itertools
import json
from collections import defaultdict
from pathlib import Path
import subprocess

from bench_data import (ROOT, PATTERNS, SIZES, contents,
                        expected_transactions, validate)
from mem_format import read_words

CONFIG_FIELDS = ("programa", "tamano_kib", "cache", "mem_div", "vueltas")
STATE_FIELDS = {"recorrido", "buffer_max", "buffer_inicio", "buffer_fin", "sucias_inicio",
                "sucias_fin", "mem_pendiente_inicio", "mem_pendiente_fin"}


def load_csv(path):
    with path.open(newline="") as source:
        return list(csv.DictReader(source))


def verify_trace(path, pattern, size, passes):
    """Un resultado correcto también debe haberse obtenido en el orden previsto."""
    with path.open() as source:
        if next(source).split() != ["ciclo", "tipo", "direccion", "dato", "espera"]:
            raise ValueError("La traza no tiene el formato esperado")
        expected = expected_transactions(pattern, size, passes)
        store_waits = []
        for index, pair in enumerate(itertools.zip_longest(source, expected), 1):
            line, wanted = pair
            if line is None or wanted is None:
                raise ValueError(f"Cantidad incorrecta de accesos en la transacción {index}")
            fields = line.split()
            if len(fields) != 5:
                raise ValueError(f"Transacción mal formada en la línea {index}")
            observed = fields[1], int(fields[2], 16), int(fields[3], 16)
            if observed != wanted or int(fields[4]) < 0:
                raise ValueError(f"Acceso inesperado en la transacción {index}")
            if fields[1] == "store":
                store_waits.append((fields[2].lower(), int(fields[4])))
    return store_waits


def verify_segments(path, pattern, size, passes, cache):
    raw = load_csv(path)
    expected_order = [("preparacion", 0)] + [("recorrido", p) for p in range(1, passes+1)]
    expected_order += [("cierre", 0), ("total", 0)]
    if [(r["segmento"], int(r["recorrido"])) for r in raw] != expected_order:
        raise ValueError("Faltan segmentos o recorridos en la medición")
    rows = [{key: value if key == "segmento" else int(value) for key, value in row.items()}
            for row in raw]
    for key in rows[-1]:
        if key != "segmento" and key not in STATE_FIELDS:
            if sum(row[key] for row in rows[:-1]) != rows[-1][key]:
                raise ValueError(f"Los intervalos no reconstruyen el contador {key}")
    words = validate(size, passes)
    for row in rows:
        if row["discrepancias"] or row["ciclos"] < 0:
            raise ValueError("Hay discrepancias o ciclos inválidos")
        if cache and (row["l1_hits_lectura"]+row["l1_misses_lectura"] != row["l1_lecturas"] or
                      row["l1_hits_escritura"]+row["l1_misses_escritura"] != row["l1_escrituras"]):
            raise ValueError("Los aciertos y fallos no coinciden con los accesos a L1")
        if cache and (row["l1_lecturas"] != row["lecturas_cpu"] or
                      row["l1_escrituras"] != row["escrituras_cpu"]):
            raise ValueError("Los accesos de L1 no coinciden con las operaciones del procesador")
        if row["segmento"] == "recorrido":
            reads = 0 if pattern == "escritura" else words * (2 if pattern == "aleatorio" else 1)
            writes = words if pattern in ("escritura", "lectura_escritura") else 0
            if row["lecturas_cpu"] != reads or row["escrituras_cpu"] != writes:
                raise ValueError("Una vuelta no contiene los accesos útiles previstos")
        if row["segmento"] == "preparacion" and (row["lecturas_cpu"], row["escrituras_cpu"]) != (4, 0):
            raise ValueError("La preparación no está separada de los recorridos")
        if row["segmento"] == "cierre" and (row["lecturas_cpu"], row["escrituras_cpu"]) != (0, 4):
            raise ValueError("Las cuatro salidas no están separadas de los recorridos")
    total = rows[-1]
    if total["ciclos"] != total["bundles"]+total["saltos"]+total["pausa_total"]+1:
        raise ValueError("No se cumple la identidad de ciclos del programa")
    return rows


def enrich(row, config):
    result = dict(config, **row)
    accesses = row["l1_lecturas"]+row["l1_escrituras"]
    hits = row["l1_hits_lectura"]+row["l1_hits_escritura"]
    result["ipc"] = row["instrucciones"] / row["ciclos"] if row["ciclos"] else 0
    result["l1_hit_rate"] = hits/accesses if config["cache"] and accesses else ""
    result["l1_miss_rate"] = (accesses-hits)/accesses if config["cache"] and accesses else ""
    rounds = config["vueltas"] if row["segmento"] == "total" else 1
    useful = config["tamano_kib"]*256*rounds if row["segmento"] in ("total", "recorrido") else 0
    result["lecturas_utiles"] = 0 if config["programa"] == "escritura" else useful
    result["escrituras_utiles"] = useful if config["programa"] in ("escritura", "lectura_escritura") else 0
    result["lecturas_indices"] = useful if config["programa"] == "aleatorio" else 0
    denominator = result["lecturas_utiles"]+result["escrituras_utiles"]
    result["ciclos_por_acceso_util"] = row["ciclos"]/denominator if denominator else ""
    return result


def write_csv(path, rows):
    if not rows:
        return
    with path.open("w", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def costs(folder, config, expected_stores):
    stores = load_csv(folder/"escrituras.csv")
    if [(r["direccion"].lower(), int(r["ciclos_pausa"])) for r in stores] != expected_stores:
        raise ValueError("La medición de stores no coincide con la traza de memoria")
    groups = defaultdict(list)
    nominal = 25+7*config["mem_div"]
    allowed = ({"memoria_directa"} if config["cache"] == 0 else
               {"l1_hit", "l1_miss_memoria", "l1_miss_buffer"})
    for row in stores:
        if row["caso"] not in allowed:
            raise ValueError("La clasificación de escritura no pertenece a esta configuración")
        pause = int(row["ciclos_pausa"])
        if config["cache"] == 0 and (row["caso"] != "memoria_directa" or pause != nominal):
            raise ValueError("El store directo no tiene la latencia prevista")
        if row["caso"] == "l1_hit" and pause != 0:
            raise ValueError("Un acierto de escritura en L1 agregó una pausa")
        if int(row["recorrido"]):
            groups[("store_cpu", int(row["recorrido"]), row["caso"])].append(pause)
    for row in load_csv(folder/"memoria_escrituras.csv"):
        duration = int(row["ciclos"])
        if duration != nominal:
            raise ValueError("La escritura física no tiene la latencia nominal de memoria")
        kind = "drenaje_memoria" if config["cache"] else "memoria_directa"
        groups[("escritura_inferior", int(row["recorrido_fin"]), kind)].append(duration)
    return [dict(config, nivel=level, recorrido=turn, caso=kind, cantidad=len(values),
                 ciclos_min=min(values), ciclos_media=sum(values)/len(values), ciclos_max=max(values))
            for (level, turn, kind), values in sorted(groups.items())]


def aligned_table(headers, rows):
    """Alinea el texto a la izquierda y las cifras a la derecha."""
    widths = [max(len(row[index]) for row in [headers]+rows) for index in range(len(headers))]

    def line(values):
        cells = [value.ljust(width) if index == 0 else value.rjust(width)
                 for index, (value, width) in enumerate(zip(values, widths))]
        return "| " + " | ".join(cells) + " |"

    return "\n".join([line(headers), line(["-"*width for width in widths])] +
                     [line(row) for row in rows])


def format_summary(totals):
    """Compara configuraciones manteniendo programa, tamaño, vueltas y memoria."""
    names = {"secuencial": "Secuencial", "stride": "Salto de 8 palabras",
             "aleatorio": "Aleatorio por líneas", "escritura": "Escritura",
             "lectura_escritura": "Lectura y escritura"}
    groups = {}
    for row in totals:
        group = int(row["mem_div"]), int(row["vueltas"])
        case = str(row["programa"]), int(row["tamano_kib"])
        groups.setdefault(group, {}).setdefault(case, {})[int(row["cache"])] = row
    sections = ["Los tiempos y las pausas se expresan en ciclos del procesador."]
    incomplete = False
    for (divisor, passes), cases in sorted(groups.items()):
        cycles, details = [], []
        for (pattern, size), configurations in cases.items():
            direct, cached = configurations.get(0), configurations.get(1)
            incomplete |= direct is None or cached is None

            def number(row, key):
                return f'{int(row[key]):,}'.replace(",", " ") if row is not None else "No medido"

            def ipc(row):
                return f'{float(row["ipc"]):.3f}' if row is not None else "No medido"

            factor = "No calculable"
            if direct is not None and cached is not None:
                factor = f'{int(direct["ciclos"])/int(cached["ciclos"]):.2f}x'
            name = names.get(pattern, pattern)
            cycles.append([name, str(size), number(direct, "ciclos"), number(cached, "ciclos"), factor])
            details.append([name, str(size), number(direct, "pausa_memoria"),
                            number(cached, "pausa_memoria"), ipc(direct), ipc(cached)])
        sections += [f"Memoria de {25+7*divisor} ciclos nominales por acceso "
                     f"(MEM_DIV={divisor}). {passes} recorridos.",
                     aligned_table(["Programa", "KiB", "Sin caché", "Con L1", "Mejora"], cycles),
                     "Esperas de memoria e instrucciones por ciclo (IPC).",
                     aligned_table(["Programa", "KiB", "Pausa sin caché", "Pausa con L1",
                                    "IPC sin caché", "IPC con L1"], details)]
    sections.append("La mejora divide los ciclos sin caché entre los ciclos con L1.")
    if incomplete:
        sections.append("No medido indica que esa configuración falta en esta selección. "
                        "Para compararlas, ejecuta make metricas con CACHES=\"0 1\".")
    return "\n\n".join(sections)


def write_summary(folder, totals):
    lines = ["# Mediciones de memoria", "", "Cada fila compara el mismo programa y entrada entre configuraciones medidas.", "",
             format_summary(totals), "",
             "Las cifras por vuelta están en recorridos.csv y la preparación y el cierre en segmentos.csv.",
             "Los casos de escritura observados están en costos_escritura.csv.",
             "La confirmación de un store no demuestra persistencia de todo el arreglo en memoria.", ""]
    (folder/"metricas.md").write_text("\n".join(lines))


def summarize(folder, totals, segments, write_costs):
    write_csv(folder/"metricas.csv", totals)
    write_csv(folder/"recorridos.csv", [r for r in segments if r["segmento"] == "recorrido"])
    write_csv(folder/"segmentos.csv", segments)
    write_csv(folder/"costos_escritura.csv", write_costs)
    write_summary(folder, totals)


def verify_memory_payloads(folder, pattern, size, passes, cache):
    """Comprueba los datos enviados a memoria sin exigir vaciar todas las cachés."""
    transfers = load_csv(folder/"memoria_escrituras.csv")
    if cache == 0:
        stores = [item for item in expected_transactions(pattern, size, passes)
                  if item[0] == "store"]
        if len(transfers) != len(stores):
            raise ValueError("Faltan escrituras directas terminadas en memoria")
        for row, (_, address, value) in zip(transfers, stores):
            offset = address % 32
            mask = 15 << offset
            payload = int(row["datos"], 16)
            if (int(row["linea"])*32 != address-offset or
                    int(row["mascara"], 16) != mask or
                    (payload >> (8*offset)) & 0xFFFFFFFF != value):
                raise ValueError("La escritura física no coincide con el store del programa")
        return
    if pattern not in ("escritura", "lectura_escritura"):
        if transfers:
            raise ValueError("Un programa de lectura drenó una línea modificada inesperada")
        return
    versions = {}
    for row in transfers:
        address = int(row["linea"])*32
        if not 0x1000 <= address < 0x1000+size*1024 or int(row["mascara"], 16) != 0xFFFFFFFF:
            raise ValueError("El drenaje no corresponde a una línea completa del arreglo")
        first_index = (address-0x1000)//4
        payload = int(row["datos"], 16)
        turn = (payload & 0xFFFFFFFF)-first_index-1
        if not 1 <= turn <= passes or turn != versions.get(address, 0)+1:
            raise ValueError("El drenaje no conserva el orden de versiones del arreglo")
        for word in range(8):
            if (payload >> (32*word)) & 0xFFFFFFFF != first_index+word+1+turn:
                raise ValueError("El drenaje contiene una palabra distinta de la versión esperada")
        versions[address] = turn


def verify_store_counts(rows, case_costs):
    """Contrasta la clasificación de cada store con los contadores originales de L1."""
    for row in rows:
        if row["segmento"] != "recorrido":
            continue
        measured = [cost for cost in case_costs if cost["nivel"] == "store_cpu"
                    and cost["recorrido"] == row["recorrido"]]
        hits = sum(cost["cantidad"] for cost in measured if cost["caso"] == "l1_hit")
        misses = sum(cost["cantidad"] for cost in measured if cost["caso"] != "l1_hit")
        if (hits, misses) != (row["l1_hits_escritura"], row["l1_misses_escritura"]):
            raise ValueError("Los costos clasificados no reconstruyen los aciertos y fallos de escritura")


def run_case(args, pattern, size, cache, divisor):
    config = dict(zip(CONFIG_FIELDS, (pattern, size, cache, divisor, args.passes)))
    folder = args.out/pattern/f"{size}k"/f"cache{cache}"/f"div{divisor}"
    folder.mkdir(parents=True, exist_ok=True)
    data, expected = contents(pattern, size, args.passes)
    (folder/"entrada.mem").write_text(data)
    (folder/"esperado.mem").write_text(expected)
    source = ROOT/"programs"/f"bench_{pattern}.asm"
    manifest = dict(config, semilla="0xC0FFEE11", archivo_asm=str(source.relative_to(ROOT)),
                    sha256_asm=hashlib.sha256(source.read_bytes()).hexdigest(),
                    sha256_entrada=hashlib.sha256(data.encode()).hexdigest())
    (folder/"configuracion.json").write_text(json.dumps(manifest, indent=2)+"\n")
    command = ["make", "sim", f"PROG=bench_{pattern}", f"CACHE={cache}", f"MEM_DIV={divisor}",
               f"DATA={folder/'entrada.mem'}", f"EXP={folder/'esperado.mem'}", f"OUT={folder}",
               f"MAX_CYCLES={args.max_cycles}", "WAVES=0", "VVP_ARGS=+LOG_MEM"]
    with (folder/"simulacion.log").open("w") as log:
        completed = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    log = (folder/"simulacion.log").read_text()
    if completed.returncode or "PASS tb_programa" not in log or "FAIL" in log:
        raise ValueError(f"Falló la simulación. Revise {folder/'simulacion.log'}")
    actual = read_words(folder/"dump.mem")
    for address, value in read_words(folder/"esperado.mem").items():
        if actual.get(address) != value:
            raise ValueError("El volcado no conserva el resultado esperado")
    waits = verify_trace(folder/"transacciones.txt", pattern, size, args.passes)
    rows = verify_segments(folder/"recorridos.csv", pattern, size, args.passes, cache)
    case_costs = costs(folder, config, waits)
    verify_memory_payloads(folder, pattern, size, args.passes, cache)
    if cache:
        verify_store_counts(rows, case_costs)
    return ([enrich(row, config) for row in rows], case_costs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--patterns", nargs="+", choices=PATTERNS, default=list(PATTERNS))
    parser.add_argument("--sizes", nargs="+", type=int, choices=SIZES, default=list(SIZES))
    parser.add_argument("--divisors", nargs="+", type=int, choices=(2, 4, 5), default=[2, 4, 5])
    parser.add_argument("--caches", nargs="+", type=int, choices=(0, 1), default=[0, 1])
    parser.add_argument("--passes", type=int, default=4)
    parser.add_argument("--max-cycles", type=int, default=10000000)
    parser.add_argument("--out", type=Path, default=ROOT/"build/metricas")
    parser.add_argument("--show", type=Path, metavar="CARPETA",
                        help="Mostrar resultados existentes sin ejecutar simulaciones")
    args = parser.parse_args()
    if args.show is not None:
        try:
            print(format_summary(load_csv(args.show/"metricas.csv")))
        except (OSError, ValueError, KeyError) as error:
            parser.exit(1, f"{error}\n")
        return
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    for filename in ("metricas.csv", "recorridos.csv", "segmentos.csv",
                     "costos_escritura.csv", "metricas.md"):
        (args.out/filename).unlink(missing_ok=True)
    totals, segments, write_costs = [], [], []
    try:
        if args.max_cycles <= 0:
            raise ValueError("El límite de ciclos debe ser positivo")
        for size in args.sizes:
            validate(size, args.passes)
        for pattern, size, cache, divisor in itertools.product(args.patterns, args.sizes, args.caches, args.divisors):
            print(f"Midiendo {pattern} de {size} KiB con CACHE={cache} y MEM_DIV={divisor}", flush=True)
            rows, case_costs = run_case(args, pattern, size, cache, divisor)
            totals.append(rows[-1])
            segments.extend(rows[:-1])
            write_costs.extend(case_costs)
            summarize(args.out, totals, segments, write_costs)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"{error}\n")
    print(format_summary(totals))
    print(f"Ejecuciones verificadas {len(totals)}. Resultados en {args.out}")


if __name__ == "__main__":
    main()
