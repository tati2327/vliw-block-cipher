# Caso 4 (enunciado §5.2): una ronda feis.
# auth con el token x99, carga de la llave 0 (4 palabras) con kv_write,
# L y R desde memoria (0x1000, 0x1004), feis t0, t0, t1, 0, 0 y guardado en 0x2000.
# Constantes de 32 bits con la secuencia de isa.md §4.3 (t11 = 15).
inicio:
  { mov t0, 0x1E8F7       | mov t11, 15             | nopi | nopi }   # token 0xF47BD70B, parte alta
  { mov t6, 0x1E3C        | mov t7, 0x96B4          | nopi | nopi }   # K0, K1 parte alta
  { sll t0, t0, t11       | mov t8, 0x10F2D         | nopi | nopi }   # K2 parte alta
  { sll t6, t6, t11       | sll t7, t7, t11         | nopi | nopi }
  { saddi t0, t0, 0x570B  | sll t8, t8, t11         | nopi | nopi }   # t0 = token
  { saddi t6, t6, 0x2D3C  | saddi t7, t7, 0x6978    | nopi | nopi }   # t6 = K0, t7 = K1
  { saddi t8, t8, 0x25B4  | auth t0                 | nopi | nopi }   # t8 = K2; auth (pausa de 13 ciclos)
  { mov t9, 0x187A5       | kv_write t6, 0, 0       | nopi | nopi }   # K3 parte alta; llave 0, palabra 0
  { nopi                  | kv_write t7, 0, 1       | nopi | nopi }
  { sll t9, t9, t11       | kv_write t8, 0, 2       | nopi | nopi }
  { nopi                  | nopi                    | nopi | nopi }
  { saddi t9, t9, 0x61F0  | nopi                    | nopi | nopi }   # t9 = K3
  { mov t2, 0x1000        | mov t3, 0x2000          | nopi | nopi }
  { nopi                  | kv_write t9, 0, 3       | nopi | nopi }
  { nopi                  | nopi                    | nopi | lw t0, 0(t2) }   # L
  { nopi                  | nopi                    | nopi | lw t1, 4(t2) }   # R
  { nopi                  | nopi                    | nopi | nopi }
  { nopi                  | feis t0, t0, t1, 0, 0   | nopi | nopi }   # t0 = L XOR F(R, K[0][0])
  { nopi                  | nopi                    | nopi | nopi }
  { nopi                  | nopi                    | nopi | sw t0, 0(t3) }
fin:
  { nopi                  | nopi                    | jef fin | nopi }
