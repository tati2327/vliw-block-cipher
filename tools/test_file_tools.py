#!/usr/bin/env python3
"""Pruebas autoverificables de la tarea 19; archivos temporales en build/."""
from pathlib import Path
import random
import subprocess
import sys
from mem_format import read_words

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "build" / "file_tools"
WORK.mkdir(parents=True, exist_ok=True)
cases = 0
failures = 0


def run(script: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(ROOT / "tools" / script), *map(str, args)],
                          cwd=ROOT, capture_output=True, text=True)


def check(name: str, condition: bool) -> None:
    global cases, failures
    cases += 1
    if condition:
        print(f"PASS {name}")
    else:
        failures += 1
        print(f"FAIL {name}")


def roundtrip(name: str, filename: str, data: bytes) -> None:
    source, mem, result = WORK / filename, WORK / f"{filename}.mem", WORK / f"{filename}.out"
    source.write_bytes(data)
    loaded = run("load_file.py", "--input", source, "--output", mem, "--address", "0x1000")
    check(f"{name}: carga", loaded.returncode == 0)
    if loaded.returncode:
        print(loaded.stderr)
        return
    extracted = run("extract_data.py", "--memory", mem, "--output", result,
                    "--address", "0x1000", "--size", len(data))
    check(f"{name}: ida/vuelta exacta", extracted.returncode == 0 and result.read_bytes() == data)


hola = WORK / "hola.txt"
hola.write_bytes(b"Hola")
mem = WORK / "hola.mem"
r = run("load_file.py", "--input", hola, "--output", mem, "--address", "0x1000")
check("Hola: @400 y 616C6F48", r.returncode == 0 and mem.read_text().splitlines() == ["@400", "616C6F48"])
check("Hola: informa tamaño y zona", "4 bytes, 0x1000–0x1003" in r.stdout)
roundtrip("texto UTF-8", "texto.txt", "Prueba de energía: áéíóú\n".encode())
roundtrip("binario 1 KB", "entrada.bin", random.Random(4301).randbytes(1024))
roundtrip("imagen PPM", "imagen.ppm", b"P6\n2 1\n255\n" + bytes([255, 0, 0, 0, 255, 0]))
roundtrip("cinco bytes", "cinco.bin", b"ABCDE")
check("relleno de la ultima palabra", (WORK / "cinco.bin.mem").read_text().splitlines()[-1] == "00000045")
roundtrip("archivo vacio", "vacio.bin", b"")

for name, address in [("direccion no alineada", "0x1001"), ("direccion negativa", "-4"),
                      ("zona fuera de memoria", "0x10000"), ("padding excede memoria", "0xFFFC")]:
    source = hola if address != "0xFFFC" else WORK / "cinco.bin"
    r = run("load_file.py", "--input", source, "--output", WORK / "invalido.mem", "--address", address)
    check(name, r.returncode != 0)

# Volcado completo sin marcas @ y con comentarios, como produce Icarus.
dump = WORK / "completo.mem"
words = ["00000000"] * 16384
words[0x400] = "616c6f48"
words[-1] = "44332211"
dump.write_text("// 0x00000000\n" + "\n".join(words[:1024]) + "\n// comentario que no cuenta\n" +
                "\n".join(words[1024:]) + "\n", encoding="ascii")
out = WORK / "extraido.bin"
r = run("extract_data.py", "--memory", dump, "--output", out, "--address", "0x1000", "--size", "4")
check("volcado completo y comentarios", r.returncode == 0 and out.read_bytes() == b"Hola")
r = run("extract_data.py", "--memory", dump, "--output", out, "--address", "0xFFFD", "--size", "3")
check("extraccion por byte hasta 0xFFFF", r.returncode == 0 and out.read_bytes() == b"\x22\x33\x44")
for name, address, size in [("extraccion fuera de memoria", "0xFFFF", "2"),
                            ("tamaño negativo", "0x1000", "-1"),
                            ("direccion negativa al extraer", "-1", "4")]:
    r = run("extract_data.py", "--memory", dump, "--output", out, "--address", address, "--size", size)
    check(name, r.returncode != 0)

missing = WORK / "corto.mem"
missing.write_text("00000000\n")
r = run("extract_data.py", "--memory", missing, "--output", out, "--address", "4", "--size", "1")
check("rechaza palabra ausente", r.returncode != 0)
missing.write_text("xxxxxxxx\n")
r = run("extract_data.py", "--memory", missing, "--output", out, "--address", "0", "--size", "1")
check("rechaza datos desconocidos X", r.returncode != 0)

# Este archivo lo produce el testbench real de Luis; debe correrse antes.
real_dump = ROOT / "build" / "tb_memory_dump.mem"
r = run("extract_data.py", "--memory", real_dump, "--output", out, "--address", "0x1000", "--size", "4")
check("volcado real de tb_memory contiene Hola", r.returncode == 0 and out.read_bytes() == b"Hola")
try:
    check("volcado real tiene 16384 palabras", len(read_words(real_dump)) == 16384)
except (OSError, ValueError):
    check("volcado real tiene 16384 palabras", False)

print(f"Casos: {cases}; Fallos: {failures}")
if failures:
    raise SystemExit(1)
print("PASS test_file_tools")
