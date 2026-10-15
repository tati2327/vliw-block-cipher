# Tarea 26. Programa del plan actualizado; slots 0 | 1 | 2 | 3.
{ mov t0, 4096 | mov t1, 170 | nopi | nopi }
{ nopi | nopi | nopi | nopi }
{ mov t8, 4104 | nopi | nopi | lw t2, 0(t0) }
{ nopi | nopi | nopi | lb t3, 2(t0) }
{ nopi | nopi | nopi | lb t4, 3(t0) }
{ nopi | nopi | nopi | sb t1, 2(t0) }
{ nopi | nopi | nopi | lw t5, 0(t0) }
{ nopi | nopi | nopi | sw t2, 4(t0) }
{ nopi | nopi | nopi | lw t6, 6(t0) }
{ nopi | nopi | nopi | lw t7, -4(t8) }
