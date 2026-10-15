# Tarea 27. Programa del plan; las etiquetas representan indices de bundle.
{ mov t0, -3 | mov t1, 5 | nopi | nopi }
{ nopi | nopi | nopi | nopi }
{ nopi | nopi | blt t0, t1, b4 | nopi }
{ mov t2, 1 | nopi | nopi | nopi }
b4:
{ nopi | nopi | bge t0, t1, b6 | nopi }
{ mov t3, 1 | nopi | nopi | nopi }
b6:
{ nopi | nopi | beq t0, t0, b8 | nopi }
{ mov t4, 1 | nopi | nopi | nopi }
b8:
{ nopi | nopi | bne t0, t0, b10 | nopi }
{ mov t5, 1 | nopi | nopi | nopi }
b10:
{ nopi | nopi | jas rl, sub | nopi }
{ nopi | nopi | jef b16 | nopi }
{ mov t6, 1 | nopi | nopi | nopi }
{ nopi | nopi | nopi | nopi }
sub:
{ mov t7, 1 | nopi | nopi | nopi }
{ nopi | nopi | jefR rz, rl | nopi }
b16:
{ mov t8, 1 | nopi | nopi | nopi }
fin:
{ nopi | nopi | jef fin | nopi }
