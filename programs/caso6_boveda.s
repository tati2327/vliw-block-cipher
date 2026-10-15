# Caso 6 (enunciado §5.2): bóveda de llaves.
# Parte 1: auth con token FALSO; un feis sin sesión no escribe.
# Parte 2: auth con el token bueno (x99), kv_write de las 4 llaves x 4 palabras, borrado
#          de los registros que las tuvieron, kv_lock y un kv_write rechazado tras el sello.
# Parte 3: auth con el siguiente token (x98), logout y un intento de leer la llave con
#          feis t9, rz, rz (F(0, K) = K) que ya no escribe; t9 se guarda en memoria.
# Las etiquetas marca1..marca4 son bundles vacíos donde el tb revisa el estado.
inicio:
  { mov t11, 15 | mov t3, 0x77 | nopi | nopi }      # t3 = centinela
  { mov t1, 5 | nopi | nopi | nopi }
# --- Parte 1 ---
  { mov t0, 0x2468 | nopi | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { sll t0, t0, t11 | nopi | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { saddi t0, t0, 0x5678 | nopi | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { nopi | auth t0 | nopi | nopi }                 # token falso: AUTH = 0, EXC = 1
  { nopi | feis t3, t1, t1, 0, 0 | nopi | nopi }   # sin sesión: no escribe t3
  { nopi | nopi | nopi | nopi }
marca1:
  { nopi | nopi | nopi | nopi }
# --- Parte 2 ---
  { mov t0, 0x1e8f7 | nopi | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { sll t0, t0, t11 | nopi | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { saddi t0, t0, 0x570b | nopi | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { nopi | auth t0 | nopi | nopi }                 # token bueno x99: AUTH = 1, EXC = 0
  { mov t4, 0x1a010 | nopi | nopi | nopi }
  { mov t5, 0x1a121 | nopi | nopi | nopi }
  { mov t6, 0x1a232 | kv_write t4, 0, 0 | nopi | nopi }
  { mov t4, 0x1a343 | kv_write t5, 0, 1 | nopi | nopi }
  { mov t5, 0x1a454 | kv_write t6, 0, 2 | nopi | nopi }
  { mov t6, 0x1a565 | kv_write t4, 0, 3 | nopi | nopi }
  { mov t4, 0x1a676 | kv_write t5, 1, 0 | nopi | nopi }
  { mov t5, 0x1a787 | kv_write t6, 1, 1 | nopi | nopi }
  { mov t6, 0x1a898 | kv_write t4, 1, 2 | nopi | nopi }
  { mov t4, 0x1a9a9 | kv_write t5, 1, 3 | nopi | nopi }
  { mov t5, 0x1aaba | kv_write t6, 2, 0 | nopi | nopi }
  { mov t6, 0x1abcb | kv_write t4, 2, 1 | nopi | nopi }
  { mov t4, 0x1acdc | kv_write t5, 2, 2 | nopi | nopi }
  { mov t5, 0x1aded | kv_write t6, 2, 3 | nopi | nopi }
  { mov t6, 0x1aefe | kv_write t4, 3, 0 | nopi | nopi }
  { mov t4, 0x1b00f | kv_write t5, 3, 1 | nopi | nopi }
  { nopi | kv_write t6, 3, 2 | nopi | nopi }
  { nopi | kv_write t4, 3, 3 | nopi | nopi }
  { mov t4, 0 | mov t5, 0 | nopi | nopi }          # borra las palabras de llave de los registros
  { mov t6, 0 | kv_lock | nopi | nopi }            # sella la bóveda
  { nopi | nopi | nopi | nopi }
marca2:
  { mov t7, 0x1BEEF | nopi | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { nopi | kv_write t7, 1, 1 | nopi | nopi }       # tras kv_lock: rechazado, EXC = 1
  { nopi | nopi | nopi | nopi }
  { nopi | feis t8, t1, t1, 0, 0 | nopi | nopi }   # con sesión: t8 = 5 XOR F(5, K[0][0])
  { nopi | nopi | nopi | nopi }
marca3:
  { nopi | nopi | nopi | nopi }
# --- Parte 3 ---
  { mov t0, 0x148a6 | nopi | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { sll t0, t0, t11 | nopi | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { saddi t0, t0, 0x26ba | nopi | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { nopi | auth t0 | nopi | nopi }                 # token x98: AUTH = 1, EXC = 0
  { nopi | nopi | nopi | nopi }
marca4:
  { nopi | logout | nopi | nopi }                  # AUTH = 0
  { nopi | feis t9, rz, rz, 0, 0 | nopi | nopi }   # intento de fuga F(0, K) = K sin sesión: no escribe t9, EXC = 1
  { nopi | nopi | nopi | nopi }
  { nopi | nopi | nopi | sw t9, 0x100(rz) }         # guarda t9 en 0x100: debe quedar 0, no la llave
  { nopi | nopi | nopi | nopi }
fin:
  { nopi | nopi | jef fin | nopi }
