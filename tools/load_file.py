#!/usr/bin/env python3
"""Tarea 19: convierte cualquier archivo binario al .mem de memory.sv."""
import argparse
from pathlib import Path
from mem_format import check_range, describe_zone


def load_file(source: Path, output: Path, address: int) -> int:
    data = source.read_bytes()
    padded_size = (len(data) + 3) // 4 * 4
    check_range(address, padded_size, aligned=True)
    lines = [f"@{address // 4:X}"]
    for start in range(0, len(data), 4):
        word = data[start:start + 4].ljust(4, b"\0")
        lines.append(f"{int.from_bytes(word, 'little'):08X}")
    output.write_text("\n".join(lines) + "\n", encoding="ascii")
    return len(data)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--address", required=True, type=lambda x: int(x, 0))
    args = parser.parse_args()
    try:
        size = load_file(args.input, args.output, args.address)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"ERROR: {exc}\n")
    print(describe_zone(args.address, size))
    print(f"Archivo de memoria: {args.output}")


if __name__ == "__main__":
    main()
