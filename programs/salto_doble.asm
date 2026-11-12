# Prueba del salto doble (tb_front y make sim PROG=salto_doble): el bundle que sigue a un salto
# tomado es otro salto tomado (no nulo) y debe quedar anulado.
# Camino correcto: bundle 0 salta a .A; escribe 7 en 0x40. Camino incorrecto (el salto del
# bundle 1 llegara a ID): salta a .B y escribiria 9 en 0x44. Termina con un jef a si mismo.
  { nopi | nopi | jef .A | nopi }                                        # 0000
  { nopi | nopi | jef .B | nopi }                                        # 0001
  { nopi | nopi | nopi | nopi }                                          # 0002
  { nopi | nopi | nopi | nopi }                                          # 0003
.A:
  { mov t0, 7 | nopi | nopi | nopi }                                     # 0004
  { nopi | nopi | nopi | nopi }                                          # 0005
  { nopi | nopi | nopi | sw t0, 64(rz) }                                 # 0006
  { nopi | nopi | jef .FIN | nopi }                                      # 0007
.B:
  { mov t0, 9 | nopi | nopi | nopi }                                     # 0008
  { nopi | nopi | nopi | nopi }                                          # 0009
  { nopi | nopi | nopi | sw t0, 68(rz) }                                 # 0010
  { nopi | nopi | jef .FIN | nopi }                                      # 0011
.FIN:
  { nopi | nopi | jef .FIN | nopi }                                      # 0012
