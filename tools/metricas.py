"""Ejecuta los benchmarks y reúne resultados verificados por programa y recorrido."""
import argparse
import csv
import hashlib
import itertools
import json
from collections import defaultdict
from pathlib import Path
import subprocess

from bench_data import (ROOT, PATTERNS, EXTRA_PATTERNS, SIZES, contents, access_counts,
                        expected_transactions, validate)
from mem_format import read_words

CONFIG_FIELDS = ("programa", "tamano_kib", "cache", "mem_div", "vueltas")
STATE_FIELDS = {"recorrido", "buffer_max", "buffer_inicio", "buffer_fin", "sucias_inicio",
                "sucias_fin", "mem_pendiente_inicio", "mem_pendiente_fin", "ebuf_max",
                "ebuf_inicio", "ebuf_fin", "ex_anulado",
                "l2_lecturas_pendientes_inicio", "l2_lecturas_pendientes_fin",
                "l2_escrituras_pendientes_inicio", "l2_escrituras_pendientes_fin"}


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


def verify_l2_accounting(rows):
    """Una solicitud aceptada puede clasificarse en el intervalo siguiente."""
    pending = dict(lecturas=0, escrituras=0)
    for row in rows:
        endings = {}
        for operation, suffix in (("lecturas", "lectura"), ("escrituras", "escritura")):
            start = 0 if row["segmento"] == "total" else pending[operation]
            end = start + row[f"l2_{operation}"] - row[f"l2_hits_{suffix}"] - row[f"l2_misses_{suffix}"]
            if end not in (0, 1):
                raise ValueError("Los accesos y clasificaciones de L2 no conservan una solicitud pendiente válida")
            row[f"l2_{operation}_pendientes_inicio"] = start
            row[f"l2_{operation}_pendientes_fin"] = end
            endings[operation] = end
        if sum(endings.values()) > 1 or (row["segmento"] == "total" and endings != pending):
            raise ValueError("Las clasificaciones pendientes de L2 no reconstruyen el total")
        pending = endings


def verify_segments(path, pattern, size, passes, cache):
    raw = load_csv(path)
    expected_order = [("preparacion", 0)] + [("recorrido", p) for p in range(1, passes+1)]
    expected_order += [("cierre", 0), ("total", 0)]
    if [(r["segmento"], int(r["recorrido"])) for r in raw] != expected_order:
        raise ValueError("Faltan segmentos o recorridos en la medición")
    rows = [{key: value if key == "segmento" else int(value) for key, value in row.items()}
            for row in raw]
    verify_l2_accounting(rows)
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
            useful_reads, writes, index_reads = access_counts(pattern, words)
            reads = useful_reads + index_reads
            if row["lecturas_cpu"] != reads or row["escrituras_cpu"] != writes:
                raise ValueError("Una vuelta no contiene los accesos útiles previstos")
        if row["segmento"] == "preparacion" and (row["lecturas_cpu"], row["escrituras_cpu"]) != (4, 0):
            raise ValueError("La preparación no está separada de los recorridos")
        if row["segmento"] == "cierre" and (row["lecturas_cpu"], row["escrituras_cpu"]) != (0, 4):
            raise ValueError("Las cuatro salidas no están separadas de los recorridos")
        if not 0 <= row["ebuf_inicio"] <= row["ebuf_max"] or not 0 <= row["ebuf_fin"] <= row["ebuf_max"]:
            raise ValueError("La ocupación del eviction buffer supera su máximo observado")
    total = rows[-1]
    if total["ciclos"] != total["bundles"]+total["saltos"]+total["pausa_total"]+2-total["ex_anulado"]:
        raise ValueError("No se cumple la identidad de ciclos del programa")
    return rows


def enrich(row, config):
    result = dict(config, **row)
    accesses = row["l1_lecturas"]+row["l1_escrituras"]
    hits = row["l1_hits_lectura"]+row["l1_hits_escritura"]
    result["ipc"] = row["instrucciones"] / row["ciclos"] if row["ciclos"] else 0
    result["l1_hit_rate"] = hits/accesses if config["cache"] and accesses else ""
    result["l1_miss_rate"] = (accesses-hits)/accesses if config["cache"] and accesses else ""
    l2_hits = row["l2_hits_lectura"]+row["l2_hits_escritura"]
    l2_misses = row["l2_misses_lectura"]+row["l2_misses_escritura"]
    l2_accesses = l2_hits+l2_misses
    result["l2_hit_rate"] = l2_hits/l2_accesses if config["cache"] == 2 and l2_accesses else ""
    result["l2_miss_rate"] = l2_misses/l2_accesses if config["cache"] == 2 and l2_accesses else ""
    cpu_accesses = row["lecturas_cpu"]+row["escrituras_cpu"]
    result["amat_medido"] = (int(bool(config["cache"])) + row["pausa_memoria"]/cpu_accesses
                              if cpu_accesses else "")
    result["amat_formula"] = (1 + result["l1_miss_rate"]*(8 + result["l2_miss_rate"]*(25+7*config["mem_div"]))
                               if config["cache"] == 2 and accesses and l2_accesses else "")
    rounds = config["vueltas"] if row["segmento"] == "total" else 1
    useful_reads, useful_writes, index_reads = access_counts(config["programa"], config["tamano_kib"]*256)
    measured_rounds = rounds if row["segmento"] in ("total", "recorrido") else 0
    result["lecturas_utiles"] = useful_reads*measured_rounds
    result["escrituras_utiles"] = useful_writes*measured_rounds
    result["lecturas_indices"] = index_reads*measured_rounds
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
    if config["cache"] == 2:
        allowed.add("l1_miss_l2")
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
             "lectura_escritura": "Lectura y escritura", "reuso": "Reuso con conflicto"}
    groups = {}
    for row in totals:
        group = int(row["mem_div"]), int(row["vueltas"]), row.get("politica_l1", "LRU")
        case = str(row["programa"]), int(row["tamano_kib"])
        groups.setdefault(group, {}).setdefault(case, {})[int(row["cache"])] = row
    sections = ["Los tiempos y las pausas se expresan en ciclos del procesador."]
    incomplete = False
    for (divisor, passes, policy), cases in sorted(groups.items()):
        cycles, details = [], []
        for (pattern, size), configurations in cases.items():
            direct = configurations.get(0)
            for cache in range(3):
                row = configurations.get(cache)
                incomplete |= row is None

                def number(key):
                    return (str(int(row[key])) if key in row else "—") if row is not None else "No medido"

                def decimal(key):
                    if row is None:
                        return "No medido"
                    value = row.get(key, "")
                    return f"{float(value):.6f}" if value != "" else "—"

                factor = (f'{int(direct["ciclos"])/int(row["ciclos"]):.2f}x'
                          if direct is not None and row is not None else "No calculable")
                name = names.get(pattern, pattern)
                cycles.append([name, str(size), str(cache), number("ciclos"), decimal("ipc"),
                               decimal("l1_hit_rate"), decimal("l1_miss_rate"),
                               decimal("l2_hit_rate"), decimal("l2_miss_rate"),
                               decimal("amat_medido"), decimal("amat_formula"), factor])
                details.append([name, str(size), str(cache), number("pausa_memoria"),
                                number("buffer_recibidas"), number("buffer_forwarding"),
                                number("buffer_ciclos_lleno"), number("buffer_max"),
                                number("ebuf_recibidas"), number("ebuf_forwarding"),
                                number("ebuf_ciclos_lleno"), number("ebuf_max"),
                                number("l2_pausa_lleno"), number("l2_lecturas_pendientes_fin"),
                                number("l2_escrituras_pendientes_fin")])
        sections += [f"Memoria de {25+7*divisor} ciclos nominales por acceso "
                     f"(MEM_DIV={divisor}). {passes} recorridos. Política L1 {policy}.",
                     aligned_table(["Programa", "KiB", "CACHE", "Ciclos", "IPC", "Hit L1", "Miss L1",
                                    "Hit L2", "Miss L2", "AMAT medido", "AMAT fórmula", "Mejora"], cycles),
                     "Tráfico y ocupación de buffers. Las tasas son fracciones; — indica que no aplica o no hay accesos.",
                     aligned_table(["Programa", "KiB", "CACHE", "Pausa memoria", "WB recibidas", "WB forwarding",
                                    "WB lleno", "WB máximo", "EB recibidas", "EB forwarding", "EB lleno",
                                    "EB máximo", "L2 pausa lleno", "L2 lect pendientes", "L2 esc pendientes"], details)]
    sections.append("La mejora divide los ciclos sin caché entre los de la configuración de la fila.")
    if incomplete:
        sections.append('No medido indica que falta una configuración. Para compararlas, '
                        'ejecuta make metricas con CACHES="0 1 2".')
    return "\n\n".join(sections)



def format_console(totals):
    """Divide el reporte en tablas estrechas y muestra solo casos medidos."""
    names = {"secuencial": "Secuencial", "stride": "Stride", "aleatorio": "Aleatorio",
             "escritura": "Escritura", "lectura_escritura": "Lectura/escritura", "reuso": "Reuso"}
    groups = {}
    for row in totals:
        key = int(row["mem_div"]), int(row["vueltas"]), row.get("politica_l1", "LRU"), int(row["cache"])
        groups.setdefault(key, []).append(row)
    sections = ["Tiempos y pausas en ciclos del procesador. Solo se muestran casos medidos."]
    for (divisor, passes, policy, cache), rows in sorted(groups.items()):
        level = {0: "Sin caché", 1: "L1", 2: "L1 + L2"}[cache]
        sections.append(f"{level} · MEM_DIV={divisor} · {passes} recorridos" +
                        (f" · Reemplazo L1 {policy}" if cache else ""))
        timings, rates, buffers, traffic = [], [], [], []
        for row in rows:
            label = [names.get(row["programa"], row["programa"]), str(row["tamano_kib"])]

            def number(key):
                value = row.get(key, "")
                return str(int(value)) if value != "" else "—"

            def decimal(key):
                value = row.get(key, "")
                return f"{float(value):.6f}" if value != "" else "—"

            timings.append(label + [number("ciclos"), decimal("ipc"), number("pausa_memoria")])
            rates.append(label + [decimal("l1_hit_rate"), decimal("l2_hit_rate"),
                                  decimal("amat_medido"), decimal("amat_formula")])
            for prefix, name in (("buffer", "WB"), ("ebuf", "EB")):
                if cache == 0 or (prefix == "ebuf" and cache != 2):
                    continue
                buffers.append(label + [name, number(prefix+"_recibidas"), number(prefix+"_forwarding"),
                                        number(prefix+"_ciclos_lleno"), number(prefix+"_max")])
            traffic.append(label + [number("mem_lecturas"), number("mem_escrituras"),
                                    number("l2_pausa_lleno"), number("l2_lecturas_pendientes_fin"),
                                    number("l2_escrituras_pendientes_fin")])
        sections += ["Tiempo de ejecución", aligned_table(
            ["Programa", "KiB", "Ciclos", "IPC", "Pausa memoria"], timings)]
        if cache:
            sections += ["Tasas de acierto como fracciones. AMAT es el tiempo medio de acceso en ciclos.",
                         "Med. es medido y est. es estimado. — indica que no aplica.",
                         aligned_table(["Programa", "KiB", "Hit L1", "Hit L2", "AMAT med.", "AMAT est."], rates),
                         "Buffers. WB es write buffer y EB es eviction buffer.",
                         "Recib. cuenta líneas. Forward cuenta lecturas resueltas por el buffer.",
                         "Lleno cuenta ciclos y Máx. indica la mayor ocupación en líneas.",
                         aligned_table(["Programa", "KiB", "Buffer", "Recib.", "Forward", "Lleno", "Máx."], buffers)]
        sections += ["Memoria cuenta accesos físicos. L2 lleno cuenta ciclos por buffer lleno.",
                     "L significa lecturas y E significa escrituras. Pend. cuenta pedidos de L2",
                     "sin clasificar al corte. Los contadores completos se conservan en el CSV.",
                     aligned_table(["Programa", "KiB", "Mem. L", "Mem. E", "L2 lleno", "Pend. L", "Pend. E"], traffic)]
    return "\n\n".join(sections)


def format_policy_comparison(totals, reference):
    """Compara políticas manteniendo programa, tamaño, memoria y recorridos."""
    keys = ("programa", "tamano_kib", "cache", "mem_div", "vueltas")

    def identity(row):
        return tuple(str(row[key]) for key in keys)

    indexed = {}
    for row in reference:
        key = identity(row)
        if key in indexed:
            raise ValueError("La referencia contiene más de una fila para las mismas condiciones")
        indexed[key] = row
    groups = {}
    seen = set()
    for row in totals:
        key = identity(row)
        if key in seen:
            raise ValueError("Los resultados contienen condiciones duplicadas")
        seen.add(key)
        previous = indexed.get(key)
        if previous is None:
            raise ValueError("Falta una referencia con el mismo programa, tamaño y condiciones")
        old_policy = previous.get("politica_l1", "LRU")
        policy = row.get("politica_l1", "LRU")
        if old_policy == policy or int(row["cache"]) == 0:
            raise ValueError("La comparación requiere dos políticas distintas con L1 habilitada")
        group = int(row["cache"]), int(row["mem_div"]), int(row["vueltas"]), old_policy, policy
        groups.setdefault(group, []).append((previous, row))
    sections = ["Comparación de políticas con el mismo programa, tamaño y condiciones."]
    for (cache, divisor, passes, old_policy, policy), pairs in sorted(groups.items()):
        sections.append(f"CACHE={cache} · MEM_DIV={divisor} · {passes} recorridos")
        cycles, misses = [], []
        for previous, row in pairs:
            label = [str(row["programa"]), str(row["tamano_kib"])]
            before, after = int(previous["ciclos"]), int(row["ciclos"])
            if before <= 0:
                raise ValueError("La referencia debe tener una cantidad positiva de ciclos")
            delta = after-before
            cycles.append(label + [str(before), str(after), f"{delta:+d}", f"{100*delta/before:+.6f}%"])
            def count(item):
                return int(item["l1_misses_lectura"]) + int(item["l1_misses_escritura"])
            misses.append(label + [str(count(previous)), str(count(row)),
                                   f"{int(row['pausa_memoria'])-int(previous['pausa_memoria']):+d}"])
        sections += [aligned_table(["Programa", "KiB", old_policy, policy, "Delta ciclos", "Cambio"], cycles),
                     "Fallos de L1 de lectura y escritura, y cambio de la pausa de memoria.",
                     aligned_table(["Programa", "KiB", f"Fallos {old_policy}", f"Fallos {policy}", "Delta pausa"], misses)]
    sections += ["Delta y cambio restan la referencia a la política comparada.",
                 "Un valor positivo significa más ciclos y uno negativo significa menos ciclos."]
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
        if (not 1 <= turn <= passes or turn <= versions.get(address, 0) or
                (cache == 1 and turn != versions.get(address, 0)+1)):
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
    # La política acompaña cada fila y cada manifiesto. El directorio de salida
    # se elige por separado para cada política y conserva las rutas existentes.
    config["politica_l1"] = "LRU" if args.l1_repl == 0 else "FIFO"
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
    command = ["make", "sim", f"PROG=bench_{pattern}", f"CACHE={cache}", f"MEM_DIV={divisor}", f"L1_REPL={args.l1_repl}",
               f"DATA={folder/'entrada.mem'}", f"EXP={folder/'esperado.mem'}", f"OUT={folder}",
               f"MAX_CYCLES={args.max_cycles}", "WAVES=0", "VVP_ARGS=+LOG_MEM"]
    with (folder/"simulacion.log").open("w") as log:
        completed = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    log = (folder/"simulacion.log").read_text()
    if completed.returncode or "PASS tb_programa" not in log or "FAIL" in log:
        raise ValueError(f"Falló la simulación. Revise {folder/'simulacion.log'}")
    return verify_case(folder, config)


def verify_case(folder, config):
    """Valida los artefactos de una ejecución antes de incluirla en los resúmenes."""
    pattern, size, cache, _, passes = (config[key] for key in CONFIG_FIELDS)
    log = (folder/"simulacion.log").read_text()
    if "PASS tb_programa" not in log or "FAIL" in log:
        raise ValueError(f"La simulación no pasó: {folder}")
    # Un resultado correcto no basta si se ejecutó con una política distinta.
    # Los archivos antiguos sin este campo siguen admitiendo su validación.
    if cache and "politica_l1" in config:
        expected_policy = f"Politica de reemplazo L1 {config['politica_l1']}"
        if expected_policy not in log:
            raise ValueError("El registro no confirma la política de L1 solicitada")
    actual = read_words(folder/"dump.mem")
    for address, value in read_words(folder/"esperado.mem").items():
        if actual.get(address) != value:
            raise ValueError("El volcado no conserva el resultado esperado")
    waits = verify_trace(folder/"transacciones.txt", pattern, size, passes)
    rows = verify_segments(folder/"recorridos.csv", pattern, size, passes, cache)
    case_costs = costs(folder, config, waits)
    verify_memory_payloads(folder, pattern, size, passes, cache)
    if cache:
        verify_store_counts(rows, case_costs)
    return ([enrich(row, config) for row in rows], case_costs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--patterns", nargs="+", choices=PATTERNS + EXTRA_PATTERNS, default=list(PATTERNS))
    parser.add_argument("--sizes", nargs="+", type=int, choices=SIZES, default=list(SIZES))
    parser.add_argument("--divisors", nargs="+", type=int, choices=(2, 4, 5), default=[2, 4, 5])
    parser.add_argument("--caches", nargs="+", type=int, choices=(0, 1, 2), default=[0, 1, 2])
    parser.add_argument("--l1-repl", type=int, choices=(0, 1), default=0,
                        help="Reemplazo de L1, 0 para LRU y 1 para FIFO")
    parser.add_argument("--passes", type=int, default=4)
    parser.add_argument("--max-cycles", type=int, default=10000000)
    parser.add_argument("--out", type=Path, default=ROOT/"build/metricas")
    parser.add_argument("--show", type=Path, metavar="CARPETA",
                        help="Mostrar resultados existentes sin ejecutar simulaciones")
    parser.add_argument("--compare-to", type=Path, metavar="CARPETA",
                        help="Comparar --show con las métricas de otra política")
    args = parser.parse_args()
    if args.compare_to is not None and args.show is None:
        parser.error("--compare-to requiere --show")
    if args.show is not None:
        try:
            totals = load_csv(args.show/"metricas.csv")
            if args.compare_to is not None:
                print(format_policy_comparison(totals, load_csv(args.compare_to/"metricas.csv")))
            else:
                print(format_console(totals))
        except (OSError, ValueError, KeyError) as error:
            parser.exit(1, f"{error}\n")
        return
    # Se validan todas las combinaciones antes de modificar resultados previos.
    # El caso de reutilización necesita al menos tres líneas por conjunto y no
    # admite el tamaño de 1 KiB que sí usan los programas de la matriz original.
    try:
        if args.max_cycles <= 0:
            raise ValueError("El límite de ciclos debe ser positivo")
        for pattern, size in itertools.product(args.patterns, args.sizes):
            access_counts(pattern, validate(size, args.passes))
    except ValueError as error:
        parser.exit(1, f"{error}\n")
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    for filename in ("metricas.csv", "recorridos.csv", "segmentos.csv",
                     "costos_escritura.csv", "metricas.md"):
        (args.out/filename).unlink(missing_ok=True)
    totals, segments, write_costs = [], [], []
    try:
        for pattern, size, cache, divisor in itertools.product(args.patterns, args.sizes, args.caches, args.divisors):
            print(f"Midiendo {pattern} de {size} KiB con CACHE={cache}, MEM_DIV={divisor} y L1 {'LRU' if args.l1_repl == 0 else 'FIFO'}", flush=True)
            rows, case_costs = run_case(args, pattern, size, cache, divisor)
            totals.append(rows[-1])
            segments.extend(rows[:-1])
            write_costs.extend(case_costs)
            summarize(args.out, totals, segments, write_costs)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"{error}\n")
    print(format_console(totals))
    print(f"Ejecuciones verificadas {len(totals)}. Resultados en {args.out}")


if __name__ == "__main__":
    main()
