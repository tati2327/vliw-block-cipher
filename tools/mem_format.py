"""Formato de memory.sv: palabras de 32 bits, little endian y memoria de 64 KB."""
from pathlib import Path
import re

MEMORY_BYTES = 65536
WORD_BYTES = 4


def check_range(address: int, size: int, *, aligned: bool = False) -> None:
    if address < 0 or size < 0:
        raise ValueError("La direccion y el tamaño deben ser no negativos")
    if address >= MEMORY_BYTES or address + size > MEMORY_BYTES:
        raise ValueError("La zona solicitada queda fuera de 0x0000–0xFFFF")
    if aligned and address % WORD_BYTES:
        raise ValueError("La direccion inicial debe ser multiplo de 4")


def read_words(path: Path) -> dict[int, int]:
    """Lee volcado completo y, para ida/vuelta de carga, archivos con marcas @."""
    text = path.read_text(encoding="ascii")
    text = re.sub(r"/\*.*?\*/|//[^\n]*", " ", text, flags=re.S)
    words: dict[int, int] = {}
    index = 0
    for token in text.split():
        token = token.replace("_", "")
        if token.startswith("@"):
            if not re.fullmatch(r"@[0-9a-fA-F]+", token):
                raise ValueError(f"Marca de direccion invalida: {token}")
            index = int(token[1:], 16)
            if index >= MEMORY_BYTES // WORD_BYTES:
                raise ValueError("Marca @ fuera de la memoria")
            continue
        if not re.fullmatch(r"[0-9a-fA-F]{1,8}", token):
            raise ValueError(f"Palabra invalida o desconocida en memoria: {token}")
        if index >= MEMORY_BYTES // WORD_BYTES:
            raise ValueError("El archivo contiene palabras fuera de la memoria")
        words[index] = int(token, 16)
        index += 1
    return words


def describe_zone(address: int, size: int) -> str:
    if size == 0:
        return f"0 bytes, zona vacia en 0x{address:04X}"
    return f"{size} bytes, 0x{address:04X}–0x{address + size - 1:04X}"
