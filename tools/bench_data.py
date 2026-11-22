"""Prepara entradas reproducibles y describe los recorridos de memoria."""
import argparse
from pathlib import Path

from asm import parse

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = ("secuencial", "stride", "aleatorio", "escritura", "lectura_escritura")
SIZES = (1, 8, 32)
SEED = 0xC0FFEE11
ARRAY_BASE = 0x1000
TABLE_BASE = 0xA000


def line_order(words):
    """Devuelve todas las líneas una vez, en un orden fijo para cada tamaño."""
    if words <= 0 or words % 8:
        raise ValueError("La cantidad de palabras debe ser positiva y múltiplo de ocho")
    order = list(range(words // 8))
    state = SEED
    for end in range(len(order) - 1, 0, -1):
        state = (state ^ (state << 13)) & 0xFFFFFFFF
        state = (state ^ (state >> 17)) & 0xFFFFFFFF
        state = (state ^ (state << 5)) & 0xFFFFFFFF
        chosen = state % (end + 1)
        order[end], order[chosen] = order[chosen], order[end]
    if sorted(order) != list(range(words // 8)):
        raise ValueError("La tabla debe contener cada línea exactamente una vez")
    return order


def validate(size, passes):
    if size not in SIZES or not 1 <= passes <= 100:
        raise ValueError("Se admiten tamaños de 1, 8 o 32 KiB y entre una y cien vueltas")
    words = size * 256
    if ARRAY_BASE + 4 * words > TABLE_BASE or TABLE_BASE + words // 2 > 65536:
        raise ValueError("Las regiones no caben en memoria o se superponen")
    return words


def results(pattern, words, passes):
    """Calcula las salidas sin ejecutar las instrucciones del procesador."""
    initial = words * (words + 1) // 2
    if pattern in ("escritura", "lectura_escritura"):
        checksum = passes * initial + words * passes * (passes + 1) // 2
        auxiliary = words * passes if pattern == "lectura_escritura" else 0
    else:
        checksum = passes * initial
        auxiliary = words * passes if pattern == "aleatorio" else 0
    if checksum > 0xFFFFFFFF:
        raise ValueError("La suma esperada no cabe en 32 bits")
    return checksum, words * passes, auxiliary, passes


def case_paths(root, pattern, size):
    folder = root / "programs" if size == 1 else root / "data/benchmarks" / f"{size}k"
    name = folder / f"bench_{pattern}"
    return name.with_suffix(".mem"), name.with_suffix(".exp.mem")


def serialize(sections):
    """Las marcas del archivo cuentan palabras y las direcciones del programa bytes."""
    return "".join(f"@{address // 4:08x}\n" + "".join(f"{value:08x}\n" for value in values)
                   for address, values in sections)


def contents(pattern, size, passes):
    words = validate(size, passes)
    inputs = [(0, (ARRAY_BASE, words, passes, TABLE_BASE)),
              (ARRAY_BASE, range(1, words + 1))]
    if pattern == "aleatorio":
        inputs.append((TABLE_BASE, [32 * line for line in line_order(words)]))
    expected = [(32, results(pattern, words, passes))]
    if pattern in ("escritura", "lectura_escritura"):
        expected.append((ARRAY_BASE, range(1 + passes, words + 1 + passes)))
    return serialize(inputs), serialize(expected)


def generate(root=ROOT, sizes=SIZES, passes=4, check=False):
    """Crea o comprueba los datos de los cinco programas sin generar ensamblador."""
    for size in sizes:
        for pattern in PATTERNS:
            for path, text in zip(case_paths(root, pattern, size), contents(pattern, size, passes)):
                if check:
                    if not path.exists() or path.read_text() != text:
                        raise ValueError(f"El archivo no coincide con los datos reproducibles {path}")
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(text)


def expected_transactions(pattern, size, passes):
    """Describe cada operación útil en el orden previsto para comprobar la traza."""
    words = validate(size, passes)
    for address, value in zip((0, 4, 8, 12), (ARRAY_BASE, words, passes, TABLE_BASE)):
        yield "load", address, value
    order = line_order(words) if pattern == "aleatorio" else None
    for turn in range(1, passes + 1):
        if pattern == "aleatorio":
            for phase in range(8):
                for index, line in enumerate(order):
                    yield "load", TABLE_BASE + 4 * index, 32 * line
                    yield "load", ARRAY_BASE + 32 * line + 4 * phase, line * 8 + phase + 1
        else:
            indices = (range(words) if pattern != "stride" else
                       (i for phase in range(8) for i in range(phase, words, 8)))
            for index in indices:
                address = ARRAY_BASE + 4 * index
                if pattern == "escritura":
                    yield "store", address, index + 1 + turn
                elif pattern == "lectura_escritura":
                    yield "load", address, index + turn
                    yield "store", address, index + 1 + turn
                else:
                    yield "load", address, index + 1
    for address, value in zip((32, 36, 40, 44), results(pattern, words, passes)):
        yield "store", address, value


def metadata(path):
    """Las etiquetas identifican límites sin insertar instrucciones de medición."""
    if not path.is_file():
        return ""
    _, labels = parse(path)
    if ".VUELTA" not in labels or ".FIN_RECORRIDO" not in labels:
        return ""
    pattern = path.stem.removeprefix("bench_")
    if pattern not in PATTERNS:
        raise ValueError("El programa con etiquetas de medición no está registrado")
    return (f"-DBENCH_START_PC={labels['.VUELTA']} "
            f"-DBENCH_END_PC={labels['.FIN_RECORRIDO']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    gen = commands.add_parser("generate", help="Crear datos y resultados esperados")
    gen.add_argument("--root", type=Path, default=ROOT)
    gen.add_argument("--sizes", type=int, nargs="+", choices=SIZES, default=SIZES)
    gen.add_argument("--passes", type=int, default=4)
    gen.add_argument("--check", action="store_true")
    meta = commands.add_parser("metadata", help="Obtener los límites de medición")
    meta.add_argument("source", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "metadata":
            print(metadata(args.source))
        else:
            generate(args.root, args.sizes, args.passes, args.check)
            print("Datos reproducibles comprobados" if args.check else "Datos reproducibles generados")
    except (ValueError, OSError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
