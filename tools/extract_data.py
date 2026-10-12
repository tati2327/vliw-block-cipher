#!/usr/bin/env python3
"""Tarea 19: extrae bytes del volcado completo de memory.sv."""
import argparse
from pathlib import Path
from mem_format import check_range, describe_zone, read_words


def extract_data(memory: Path, output: Path, address: int, size: int) -> int:
    check_range(address, size)
    words = read_words(memory)
    result = bytearray()
    for pos in range(address, address + size):
        index, lane = divmod(pos, 4)
        if index not in words:
            raise ValueError(f"Falta la palabra de la direccion 0x{index * 4:04X} en el volcado")
        result.append((words[index] >> (8 * lane)) & 0xFF)
    # Solo se escribe después de validar y reconstruir todos los bytes.
    output.write_bytes(result)
    return len(result)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--memory", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--address", required=True, type=lambda x: int(x, 0))
    parser.add_argument("--size", required=True, type=lambda x: int(x, 0))
    args = parser.parse_args()
    try:
        size = extract_data(args.memory, args.output, args.address, args.size)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"ERROR: {exc}\n")
    print(describe_zone(args.address, size))
    print(f"Archivo extraido: {args.output}")


if __name__ == "__main__":
    main()
