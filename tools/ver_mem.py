#!/usr/bin/env python3
"""Muestra un volcado de memory.sv (una palabra de 32 bits por línea; línea n = dirección 4n)."""
import argparse
import sys
from pathlib import Path
from mem_format import MEMORY_BYTES, read_words


def entero(texto: str) -> int:
    return int(texto, 0)


def firmado(valor: int) -> int:
    return valor - (1 << 32) if valor & 0x80000000 else valor


def mostrar_palabras(words: dict[int, int], desde: int, hasta: int, todas: bool) -> None:
    for idx in range(desde // 4, hasta // 4 + 1):
        valor = words.get(idx, 0)
        if valor or todas:
            print(f"0x{4 * idx:04X}  0x{valor:08X}  {firmado(valor)}")


def mostrar_bytes(words: dict[int, int], desde: int, hasta: int) -> None:
    datos = bytes((words.get(pos // 4, 0) >> (8 * (pos % 4))) & 0xFF for pos in range(desde, hasta + 1))
    for inicio in range(0, len(datos), 16):
        fila = datos[inicio:inicio + 16]
        hexa = " ".join(f"{b:02X}" for b in fila)
        texto = "".join(chr(b) if 32 <= b < 127 else "." for b in fila)
        print(f"0x{desde + inicio:04X}  {hexa:<47}  |{texto}|")


def comparar_esperado(words: dict[int, int], esperado: dict[int, int]) -> int:
    fallas = 0
    for idx in sorted(esperado):
        obtenido = words.get(idx, 0)
        ok = obtenido == esperado[idx]
        fallas += not ok
        detalle = "" if ok else f" (esperado 0x{esperado[idx]:08X}, obtenido 0x{obtenido:08X})"
        print(f"{'OK   ' if ok else 'FALLA'} 0x{4 * idx:04X}  0x{obtenido:08X}  {firmado(obtenido)}{detalle}")
    print(f"Resumen: {len(esperado)} palabras comparadas; {len(esperado) - fallas} OK; {fallas} fallas")
    return fallas


def comparar_contra(a: dict[int, int], b: dict[int, int], desde: int, hasta: int) -> int:
    difieren = 0
    for idx in range(desde // 4, hasta // 4 + 1):
        va, vb = a.get(idx, 0), b.get(idx, 0)
        if va != vb:
            difieren += 1
            print(f"0x{4 * idx:04X}  0x{va:08X}  !=  0x{vb:08X}")
    print(f"Resumen: {difieren} palabras difieren en 0x{desde:04X}-0x{hasta:04X}")
    return difieren


def leer(ruta: str) -> dict[int, int]:
    path = Path(ruta)
    if not path.is_file():
        raise ValueError(f"No existe el archivo: {ruta}")
    return read_words(path)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("volcado", help="volcado de memoria (p. ej. build/<nombre>/dump.mem)")
    p.add_argument("--desde", type=entero, default=0x0000, help="dirección de byte inicial (por defecto 0x0000)")
    p.add_argument("--hasta", type=entero, default=0x00FF, help="dirección de byte final, inclusive (por defecto 0x00FF)")
    p.add_argument("--formato", choices=("palabras", "bytes"), default="palabras")
    p.add_argument("--todas", action="store_true", help="en formato palabras, incluye también las que valen 0")
    p.add_argument("--esperado", help="archivo .exp.mem: compara solo las palabras que lista")
    p.add_argument("--contra", help="otro volcado: imprime solo las palabras que difieren en el rango")
    args = p.parse_args()
    try:
        if args.desde < 0 or args.hasta < args.desde or args.hasta >= MEMORY_BYTES:
            raise ValueError(f"Rango invalido 0x{args.desde:X}-0x{args.hasta:X}: debe estar dentro de 0x0000-0xFFFF y desde <= hasta")
        words = leer(args.volcado)
        if args.esperado:
            sys.exit(1 if comparar_esperado(words, leer(args.esperado)) else 0)
        if args.contra:
            sys.exit(1 if comparar_contra(words, leer(args.contra), args.desde, args.hasta) else 0)
        if args.formato == "bytes":
            mostrar_bytes(words, args.desde, args.hasta)
        else:
            mostrar_palabras(words, args.desde, args.hasta, args.todas)
    except (OSError, ValueError) as exc:
        p.exit(2, f"ERROR: {exc}\n")


if __name__ == "__main__":
    main()
