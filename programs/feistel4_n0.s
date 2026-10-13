# Feistel4 (casos 5 y 7, enunciado §5.2): cifra N bloques de 8 bytes de 0x1000 a 0x2000
# y los descifra de 0x2000 a 0x3000. Plantillas de crypto_para_ccom.md §4.
# auth con el token x99 y carga de la llave 0 (4 palabras) con kv_write.
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
  { nopi                  | nopi                    | nopi | nopi }
  { nopi                  | kv_write t9, 0, 3       | nopi | nopi }
# --- Cifrado: 0x1000 -> 0x2000 ---
  { mov t4, 0             | mov t5, 0             | nopi | nopi }
  { mov t2, 0x1000        | mov t3, 0x2000          | nopi | nopi }
  { nopi                  | nopi                    | bge rz, t5, fin_cifra | nopi }
cifra:
  { nopi | nopi | nopi | lw t0, 0(t2) }
  { nopi | nopi | nopi | lw t1, 4(t2) }
  { saddi t2, t2, 8 | nopi | nopi | nopi }
  { nopi | feis t0, t0, t1, 0, 0 | nopi | nopi }
  { saddi t4, t4, 1 | nopi | nopi | nopi }
  { nopi | feis t1, t1, t0, 0, 1 | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { nopi | feis t0, t0, t1, 0, 2 | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { nopi | feis t1, t1, t0, 0, 3 | nopi | nopi }
  { nopi | nopi | nopi | sw t0, 0(t3) }
  { saddi t3, t3, 8 | nopi | blt t4, t5, cifra | sw t1, 4(t3) }
fin_cifra:
# --- Descifrado: 0x2000 -> 0x3000 (subllaves 3..0 y mitades intercambiadas, C-17) ---
  { mov t4, 0             | mov t5, 0             | nopi | nopi }
  { mov t2, 0x2000        | mov t3, 0x3000          | nopi | nopi }
  { nopi                  | nopi                    | bge rz, t5, fin_descifra | nopi }
descifra:
  { nopi | nopi | nopi | lw t0, 4(t2) }
  { nopi | nopi | nopi | lw t1, 0(t2) }
  { saddi t2, t2, 8 | nopi | nopi | nopi }
  { nopi | feis t0, t0, t1, 0, 3 | nopi | nopi }
  { saddi t4, t4, 1 | nopi | nopi | nopi }
  { nopi | feis t1, t1, t0, 0, 2 | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { nopi | feis t0, t0, t1, 0, 1 | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { nopi | feis t1, t1, t0, 0, 0 | nopi | nopi }
  { nopi | nopi | nopi | sw t0, 4(t3) }
  { saddi t3, t3, 8 | nopi | blt t4, t5, descifra | sw t1, 0(t3) }
fin_descifra:
fin:
  { nopi                  | nopi                    | jef fin | nopi }
