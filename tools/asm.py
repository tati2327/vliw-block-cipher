#!/usr/bin/env python3
"""Ensamblador independiente VLIW (Grupo 6). Uso: asm.py programa.asm -o programa.hex"""
import re
import sys

REGS = {"rz": 0, "rl": 1, "rx": 2, "rg": 3}
REGS.update({"t%d" % i: 4 + i for i in range(12)})
REGS.update({"r%d" % i: i for i in range(16)})

ALU_R = {"add": 1, "sub": 2, "and": 3, "or": 4, "xor": 5, "sll": 6, "srl": 7,
         "sra": 8, "slt": 9, "sle": 10, "seq": 11, "sne": 12, "ifmov": 13}
ALU_I = {"saddi": 16, "xori": 17}
BRU_B = {"beq": 1, "bne": 2, "blt": 3, "bge": 4}
LSU = {"lw": 1, "sw": 2, "lb": 3, "sb": 4}
CRYPTO = {"feis": 1, "auth": 2, "logout": 3, "kv_write": 4, "kv_lock": 5, "sanc": 6}
UNIT = {}
for _n in list(ALU_R) + list(ALU_I) + ["mov"]:
    UNIT[_n] = "alu"
for _n in CRYPTO:
    UNIT[_n] = "crypto"
for _n in list(BRU_B) + ["jef", "jas", "jefR"]:
    UNIT[_n] = "bru"
for _n in LSU:
    UNIT[_n] = "lsu"

SLOT_UNITS = {0: ("alu",), 1: ("alu", "crypto"), 2: ("bru",), 3: ("lsu",)}


class AsmError(Exception):
    pass


def reg(tok):
    if tok not in REGS:
        raise AsmError("registro invalido '%s'" % tok)
    return REGS[tok]


def integer(tok, lo, hi, what):
    try:
        v = int(tok, 0)
    except ValueError:
        raise AsmError("%s invalido '%s'" % (what, tok))
    if not lo <= v <= hi:
        raise AsmError("%s %d fuera de rango [%d, %d]" % (what, v, lo, hi))
    return v


def field(v, bits):
    return v & ((1 << bits) - 1)


def target(tok, pc, labels, bits, what):
    if tok in labels:
        v = labels[tok] - pc
    elif re.fullmatch(r"[A-Za-z_.][\w.]*", tok):
        raise AsmError("etiqueta no definida '%s'" % tok)
    else:
        v = integer(tok, -(1 << 31), 1 << 31, what)
    lim = 1 << (bits - 1)
    if not -lim <= v < lim:
        raise AsmError("%s %d fuera de rango [%d, %d]" % (what, v, -lim, lim - 1))
    return field(v, bits)


def enc_r(funct, rd, rs1, rs2, sel=0):
    return (sel << 31) | (funct << 26) | (rd << 22) | (rs1 << 18) | (rs2 << 14)


def enc_i(funct, rd, rs1, imm, sel=0):
    return (sel << 31) | (funct << 26) | (rd << 22) | (rs1 << 18) | imm


def need(ops, n, name):
    if len(ops) != n:
        raise AsmError("'%s' espera %d operandos, recibio %d" % (name, n, len(ops)))


def mem_operand(tok):
    m = re.fullmatch(r"(\S+)\((\w+)\)", tok)
    if not m:
        raise AsmError("operando de memoria invalido '%s' (se espera imm(reg))" % tok)
    return integer(m.group(1), -(1 << 17), (1 << 17) - 1, "inmediato") & 0x3FFFF, reg(m.group(2))


def encode(text, slot, pc, labels):
    """Devuelve (palabra, registro_escrito o None)."""
    parts = text.split(None, 1)
    name = parts[0]
    ops = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []
    if name == "nopi":
        need(ops, 0, name)
        return 0, None
    if name not in UNIT:
        raise AsmError("mnemonico desconocido '%s'" % name)
    unit = UNIT[name]
    if unit not in SLOT_UNITS[slot]:
        raise AsmError("'%s' (%s) no puede ir en el slot %d" % (name, unit.upper(), slot))
    imm18 = lambda t: integer(t, -(1 << 17), (1 << 17) - 1, "inmediato") & 0x3FFFF
    if name in ALU_R:
        need(ops, 3, name)
        rd = reg(ops[0])
        return enc_r(ALU_R[name], rd, reg(ops[1]), reg(ops[2])), rd
    if name in ALU_I:
        need(ops, 3, name)
        rd = reg(ops[0])
        return enc_i(ALU_I[name], rd, reg(ops[1]), imm18(ops[2])), rd
    if name == "mov":
        need(ops, 2, name)
        rd = reg(ops[0])
        return enc_i(18, rd, 0, imm18(ops[1])), rd
    if name in BRU_B:
        need(ops, 3, name)
        off = target(ops[2], pc, labels, 18, "desplazamiento")
        return enc_i(BRU_B[name], reg(ops[1]), reg(ops[0]), off), None
    if name == "jefR":
        need(ops, 2, name)
        rd = reg(ops[0])
        return enc_r(5, rd, reg(ops[1]), 0), rd
    if name == "jef":
        need(ops, 1, name)
        return (16 << 26) | target(ops[0], pc, labels, 22, "destino"), None
    if name == "jas":
        need(ops, 2, name)
        rd = reg(ops[0])
        return (17 << 26) | (rd << 22) | target(ops[1], pc, labels, 22, "destino"), rd
    if name in ("lw", "lb"):
        need(ops, 2, name)
        rd = reg(ops[0])
        imm, base = mem_operand(ops[1])
        return enc_i(LSU[name], rd, base, imm), rd
    if name in ("sw", "sb"):
        need(ops, 2, name)
        src = reg(ops[0])
        imm, base = mem_operand(ops[1])
        return enc_i(LSU[name], src, base, imm), None
    # CRYPTO (slot 1, sel = 1)
    f = CRYPTO[name]
    if name == "feis":
        need(ops, 5, name)
        rd = reg(ops[0])
        w = enc_r(f, rd, reg(ops[1]), reg(ops[2]), 1)
        w |= integer(ops[3], 0, 3, "k") << 12
        w |= integer(ops[4], 0, 3, "i") << 10
        return w, rd
    if name in ("auth", "sanc"):
        need(ops, 1, name)
        return enc_r(f, 0, reg(ops[0]), 0, 1), None
    if name == "kv_write":
        need(ops, 3, name)
        w = enc_r(f, 0, reg(ops[0]), 0, 1)
        w |= integer(ops[1], 0, 3, "k") << 12
        w |= integer(ops[2], 0, 3, "w") << 10
        return w, None
    need(ops, 0, name)  # logout, kv_lock
    return enc_r(f, 0, 0, 0, 1), None


def parse(path):
    """Primera pasada: devuelve (bundles [(lineno, [slots])], etiquetas)."""
    bundles, labels = [], {}
    with open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.split("#", 1)[0].strip()
            while True:
                m = re.match(r"([A-Za-z_.][\w.]*)\s*:\s*", line)
                if not m:
                    break
                if m.group(1) in labels:
                    raise AsmError_at(lineno, "etiqueta '%s' definida dos veces" % m.group(1))
                labels[m.group(1)] = len(bundles)
                line = line[m.end():]
            if not line:
                continue
            if not (line.startswith("{") and line.endswith("}")):
                raise AsmError_at(lineno, "se esperaba un bundle '{ s0 | s1 | s2 | s3 }'")
            slots = [s.strip() for s in line[1:-1].split("|")]
            if len(slots) != 4 or any(not s for s in slots):
                raise AsmError_at(lineno, "el bundle debe tener exactamente 4 slots")
            bundles.append((lineno, slots))
    return bundles, labels


def AsmError_at(lineno, msg):
    return LineError(lineno, msg)


class LineError(Exception):
    def __init__(self, lineno, msg):
        super().__init__(msg)
        self.lineno = lineno
        self.msg = msg


def assemble(path):
    bundles, labels = parse(path)
    out = []
    for pc, (lineno, slots) in enumerate(bundles):
        words, written = [], {}
        try:
            for s, text in enumerate(slots):
                w, rd = encode(text, s, pc, labels)
                words.append(w)
                if rd:  # rz se excluye (§9.3)
                    if rd in written:
                        raise AsmError("los slots %d y %d escriben el mismo registro r%d"
                                       % (written[rd], s, rd))
                    written[rd] = s
        except AsmError as e:
            raise LineError(lineno, str(e))
        out.append("_".join("%08X" % words[s] for s in (3, 2, 1, 0)))
    return out


def main(argv):
    if len(argv) != 4 or argv[2] != "-o":
        sys.stderr.write("uso: asm.py programa.asm -o programa.hex\n")
        return 2
    try:
        lines = assemble(argv[1])
    except LineError as e:
        sys.stderr.write("%s:%d: error: %s\n" % (argv[1], e.lineno, e.msg))
        return 1
    except OSError as e:
        sys.stderr.write("error: %s\n" % e)
        return 1
    with open(argv[3], "w") as fh:
        fh.write("".join(l + "\n" for l in lines))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
