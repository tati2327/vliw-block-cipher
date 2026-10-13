# Ensayo del caso 7 (sin CRYPTO): recorre 1 KB desde 0x1000.
# "Cifra" con xor hacia 0x2000 y "descifra" con xor hacia 0x3000.
# Al integrar CRYPTO, los dos xor se reemplazan por feis.
# t0 = puntero (0x1000..0x13FC), t3 = llave, t4 = fin, t5 = palabra, t6 = cifrada, t7 = descifrada
inicio:
  { mov t0, 0x1000      | mov t3, 0x1A5A5      | nopi                 | nopi }
  { mov t4, 0x1400      | nopi                 | nopi                 | nopi }
lazo:
  { nopi                | nopi                 | nopi                 | lw t5, 0(t0) }
  { nopi                | nopi                 | nopi                 | nopi }
  { xor t6, t5, t3      | nopi                 | nopi                 | nopi }
  { nopi                | nopi                 | nopi                 | nopi }
  { xor t7, t6, t3      | saddi t0, t0, 4      | nopi                 | sw t6, 0x1000(t0) }
  { nopi                | nopi                 | nopi                 | nopi }
  { nopi                | nopi                 | blt t0, t4, lazo     | sw t7, 0x1FFC(t0) }
  { nopi                | nopi                 | nopi                 | nopi }   # se descarta si salta
fin:
  { nopi                | nopi                 | jef fin              | nopi }
