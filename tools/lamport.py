#!/usr/bin/env python3
"""Genera tokens Lamport de 32 bits compatibles con auth_hash32.sv."""

import argparse
import json
from pathlib import Path

MASK64 = (1 << 64) - 1
MASK32 = (1 << 32) - 1
INITIAL_STATE = (
    0x9B1E5494E934D681, 0x4BC3A01E333751D2, 0xAE65396C6B34B81A,
    0x3C7FD4A4D56A4DB3, 0x1A5C464906C5976D,
)
ROUND_CONSTANTS = (0xF0, 0xE1, 0xD2, 0xC3, 0xB4, 0xA5,
                   0x96, 0x87, 0x78, 0x69, 0x5A, 0x4B)
ROTATIONS = ((19, 28), (61, 39), (1, 6), (10, 17), (7, 41))

# Los valores provienen de la referencia C de ascon/ascon-c ya verificada.
REFERENCE_VECTORS = (
    (0x03020100, 0xEDC7E4D7), (0x00000000, 0x8F28B790),
    (0x00000001, 0xEC267D58), (0x80000000, 0xF5C202DC),
    (0x80000001, 0xFEFEC6C6), (0x12345678, 0x88035407),
    (0xFFFFFFFF, 0x8A6AD37E), (0xA5A55A5A, 0xD020C92A),
)


def ror64(value: int, distance: int) -> int:
    """Rota una palabra a la derecha y conserva exactamente 64 bits."""
    return ((value >> distance) | (value << (64 - distance))) & MASK64


def h(token: int) -> int:
    """Calcula Ascon-Hash256 de cuatro bytes y devuelve su prefijo little-endian."""
    if not 0 <= token <= MASK32:
        raise ValueError("el token debe ser un entero sin signo de 32 bits")
    state = list(INITIAL_STATE)
    # Convierte el token en cuatro bytes little-endian y añade el relleno 01.
    message = token.to_bytes(4, "little") + b"\x01\x00\x00\x00"
    state[0] ^= int.from_bytes(message, "little")
    for constant in ROUND_CONSTANTS:
        state[2] ^= constant
        state[0] ^= state[4]
        state[4] ^= state[3]
        state[2] ^= state[1]
        # Calcula los cinco temporales con el mismo estado preparado.
        temp = [state[j] ^ ((~state[(j + 1) % 5] & MASK64) & state[(j + 2) % 5])
                for j in range(5)]
        temp[1] ^= temp[0]
        temp[0] ^= temp[4]
        temp[3] ^= temp[2]
        temp[2] = ~temp[2] & MASK64
        state = [word ^ ror64(word, r1) ^ ror64(word, r2)
                 for word, (r1, r2) in zip(temp, ROTATIONS)]
    # Solo necesitamos los primeros cuatro bytes, igual que s0[31:0] del RTL.
    return state[0] & MASK32


def generate_chain(seed: int, length: int) -> list[int]:
    """Construye x0..xN y rechaza repeticiones dentro de la cadena."""
    if not 0 <= seed <= MASK32:
        raise ValueError("la semilla debe tener entre 0 y 0xFFFFFFFF")
    if length < 1:
        raise ValueError("la longitud debe ser al menos 1")
    chain = [seed]
    seen = {seed}
    for index in range(1, length + 1):
        value = h(chain[-1])
        if value in seen:
            raise ValueError(f"la cadena repite un valor en x{index}; usa otra semilla o longitud")
        chain.append(value)
        seen.add(value)
    return chain


def self_test() -> None:
    """Comprueba vectores externos, orden de uso y rechazo del token consumido."""
    for token, expected in REFERENCE_VECTORS:
        obtained = h(token)
        if obtained != expected:
            raise ValueError(f"FAIL H({token:08X}) = {obtained:08X}, esperado {expected:08X}")
    chain = generate_chain(0x12345678, 100)
    anchor = chain[-1]
    for token in reversed(chain[:-1]):
        if h(token) != anchor:
            raise ValueError("FAIL orden de uso de los tokens")
        anchor = token
        if h(token) == anchor:
            raise ValueError("FAIL token consumido reutilizable")
    if anchor != chain[0] or len(generate_chain(0, 1)) != 2:
        raise ValueError("FAIL extremos de la cadena")
    for invalid in (-1, 1 << 32):
        try:
            h(invalid)
        except ValueError:
            continue
        raise ValueError("FAIL rango de entrada")
    print("PASS: 8 vectores externos, cadena de 100 tokens, orden inverso y rechazo de reutilización")


def save_chain(chain: list[int], directory: Path) -> None:
    """Escribe la cadena, los tokens en orden de uso y constantes para simulación."""
    directory.mkdir(parents=True, exist_ok=True)
    length = len(chain) - 1
    tokens = list(reversed(chain[:-1]))
    document = {
        "hash": "Ascon-Hash256 de 4 bytes little-endian, prefijo de 32 bits little-endian",
        "seed": f"0x{chain[0]:08X}",
        "length": length,
        "reset_anchor": f"0x{chain[-1]:08X}",
        "chain_x0_to_xN": [f"0x{value:08X}" for value in chain],
        "tokens_in_use_order": [f"0x{value:08X}" for value in tokens],
    }
    (directory / "chain.json").write_text(json.dumps(document, indent=2) + "\n")
    # El primer renglón contiene xN-1, seguido de xN-2 hasta x0.
    (directory / "tokens.mem").write_text("".join(f"{value:08X}\n" for value in tokens))
    # Cada renglón concatena la entrada de 32 bits y su hash esperado de 32 bits.
    (directory / "hash_vectors.mem").write_text(
        "".join(f"{chain[j]:08X}{chain[j + 1]:08X}\n" for j in range(length)))
    (directory / "lamport_config.svh").write_text(
        "// Generado por tools/lamport.py; configura la cadena seleccionada.\n"
        "`ifndef LAMPORT_CONFIG_SVH\n`define LAMPORT_CONFIG_SVH\n"
        f"`define LAMPORT_RESET_ANCHOR 32'h{chain[-1]:08X}\n"
        f"`define LAMPORT_TOKEN_COUNT {length}\n"
        "`endif\n")


def uint32(text: str) -> int:
    try:
        value = int(text, 0)
    except ValueError as error:
        raise argparse.ArgumentTypeError("usa decimal o hexadecimal con prefijo 0x") from error
    if not 0 <= value <= MASK32:
        raise argparse.ArgumentTypeError("la semilla debe tener entre 0 y 0xFFFFFFFF")
    return value


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=uint32, help="semilla de 32 bits, por ejemplo 0xCAFEDECE")
    parser.add_argument("--length", type=int, default=100, help="cantidad de tokens (predeterminado: 100)")
    parser.add_argument("--out", type=Path, help="carpeta de archivos para hardware y programas")
    parser.add_argument("--self-test", action="store_true", help="comprueba el hash y la cadena")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
        if args.seed is None:
            if args.self_test and args.out is None:
                return
            parser.error("la generación requiere --seed")
        chain = generate_chain(args.seed, args.length)
        print(f"RESET_ANCHOR = 32'h{chain[-1]:08X} (x{args.length})")
        if args.out is not None:
            save_chain(chain, args.out)
            print(f"Archivos generados en {args.out}")
            print(f"Primer token: x{args.length - 1} = 0x{chain[-2]:08X}")
            if args.length > 1:
                print(f"Segundo token: x{args.length - 2} = 0x{chain[-3]:08X}")
        else:
            for index in range(args.length - 1, -1, -1):
                print(f"x{index} = 0x{chain[index]:08X}")
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
