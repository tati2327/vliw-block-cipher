# Las 34 instrucciones (33 + nopi), cada una en su slot correcto.
inicio:
  { add t0, t1, t2   | sub t3, t4, t5     | beq t0, t1, fin    | lw t6, 4(rg) }
  { and t0, t1, t2   | or t3, t4, t5      | bne t0, t1, fin    | lb t7, -3(rx) }
  { xor t0, t1, t2   | sll t3, t4, t5     | blt t0, t1, inicio | sw t8, 8(rg) }
  { srl t0, t1, t2   | sra t3, t4, t5     | bge t0, t1, inicio | sb t9, 0(rz) }
  { slt t0, t1, t2   | sle t3, t4, t5     | jef adelante       | nopi }
  { seq t0, t1, t2   | sne t3, t4, t5     | nopi               | nopi }
adelante:
  { ifmov t0, t1, t2 | saddi t3, t4, -100 | jas rl, subrut     | nopi }
  { xori t0, t1, 0x1F | mov t3, -131072    | jef -1             | nopi }
  { mov t0, 131071   | mov t3, 0x7FF      | jefR rz, rl        | nopi }
subrut:
  { nopi             | feis t4, t5, t6, 2, 3 | nopi            | nopi }
  { saddi t0, t0, 1  | auth t1            | nopi               | nopi }
  { nopi             | logout             | nopi               | nopi }
  { nopi             | kv_write t2, 1, 2  | nopi               | nopi }
  { nopi             | kv_lock            | nopi               | nopi }
  { nopi             | sanc t3            | nopi               | nopi }
fin:
  { nopi | nopi | nopi | nopi }
