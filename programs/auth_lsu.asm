# Dos autenticaciones válidas comparten bundle con un store y un load.
  { nopi | nopi | nopi | lw t0, 0(rz) }
  { nopi | nopi | nopi | lw t1, 4(rz) }
  { nopi | nopi | nopi | lw t2, 8(rz) }
  { nopi | nopi | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { nopi | auth t0 | nopi | sw t2, 64(rz) }
  { nopi | nopi | nopi | nopi }
  { nopi | auth t1 | nopi | lw t3, 64(rz) }
  { nopi | nopi | nopi | nopi }
  { nopi | nopi | nopi | nopi }
  { nopi | nopi | nopi | sw t3, 68(rz) }
  { nopi | nopi | nopi | nopi }
  { nopi | nopi | jef .FIN | nopi }
.FIN:
  { nopi | nopi | jef 0 | nopi }
