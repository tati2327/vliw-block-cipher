# Caso 1 (enunciado §5.2): ALU en paralelo con LSU y BRU.
# Bundle: { slot 0 (ALU0) | slot 1 (ALU1) | slot 2 (BRU) | slot 3 (LSU) }
inicio:
  { mov t0, 5       | mov t1, 7       | nopi              | nopi }
  { nopi            | nopi            | nopi              | nopi }
  { add t2, t0, t1  | sub t3, t1, t0  | nopi              | sw t0, 64(rz) }
  { xor t4, t0, t1  | slt t5, t0, t1  | nopi              | nopi }
  { and t6, t0, t1  | or t7, t0, t1   | beq t0, t0, fin   | lw t8, 64(rz) }
  { mov t9, 99      | nopi            | nopi              | nopi }   # se descarta
fin:
  { nopi            | nopi            | nopi              | nopi }
