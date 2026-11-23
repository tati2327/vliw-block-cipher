# Reutiliza una línea caliente mientras otras líneas compiten por el mismo conjunto.
# L1 tiene 64 conjuntos y dos vías. Separar direcciones por 2048 bytes conserva
# el conjunto y cambia la etiqueta. Para cada conjunto se lee la secuencia
# A, B, A, C, A, D y se continúa hasta el final de la región de 8 o 32 KiB.
# A es la primera línea del conjunto y se consulta antes de cada línea variable.
# LRU puede conservar A por su uso frecuente. FIFO conserva el orden de entrada.
#
# Se lee la primera palabra de cada línea. La región tiene el tamaño indicado,
# pero una vuelta no lee todas sus palabras. Los contadores y la suma esperada
# usan el número real de accesos. Las cuatro vueltas conservan las cachés.
#
# t0 guarda la base y t1 la cantidad de líneas variables por conjunto. t2 cuenta
# vueltas pendientes y t3 conjuntos pendientes. t4 acumula la suma, t5 lecturas,
# t6 permanece en cero y t7 cuenta vueltas terminadas. t8 apunta a la línea
# caliente, t9 a la línea variable, t10 recibe datos y t11 cuenta pares pendientes.
# rg se usa para dividir la cantidad de palabras entre 512 antes del recorrido.
# Se deja un paquete intermedio entre escribir un registro y usar su resultado.

    { mov t4, 0 | mov t5, 0 | nopi | lw t0, 0(rz) }
    { mov t6, 0 | mov t7, 0 | nopi | lw t1, 4(rz) }
    { mov rg, 9 | nopi | nopi | lw t2, 8(rz) }
    { nopi | nopi | nopi | lw t3, 12(rz) }
    { srl t1, t1, rg | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { saddi t1, t1, -1 | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }

.VUELTA:
    { add t8, t0, rz | mov t3, 64 | nopi | nopi }
    { nopi | nopi | nopi | nopi }

.CONJUNTO:
    { saddi t9, t8, 2048 | add t11, t1, rz | nopi | nopi }
    { nopi | nopi | nopi | nopi }

.PAREJA:
    # La línea caliente se usa justo antes de traer una línea competidora.
    { saddi t5, t5, 1 | nopi | nopi | lw t10, 0(t8) }
    { nopi | nopi | nopi | nopi }
    { add t4, t4, t10 | nopi | nopi | nopi }
    { saddi t11, t11, -1 | saddi t5, t5, 1 | nopi | lw t10, 0(t9) }
    { saddi t9, t9, 2048 | nopi | nopi | nopi }
    { add t4, t4, t10 | nopi | bne t11, rz, .PAREJA | nopi }

    # Cambiar 32 bytes desplaza ambas direcciones al conjunto siguiente.
    { saddi t8, t8, 32 | saddi t3, t3, -1 | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | bne t3, rz, .CONJUNTO | nopi }

.FIN_RECORRIDO:
    { saddi t7, t7, 1 | saddi t2, t2, -1 | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | bne t2, rz, .VUELTA | nopi }

    # Se guardan suma, lecturas útiles, lecturas de índices y vueltas terminadas.
    { nopi | nopi | nopi | sw t4, 32(rz) }
    { nopi | nopi | nopi | sw t5, 36(rz) }
    { nopi | nopi | nopi | sw t6, 40(rz) }
    { nopi | nopi | nopi | sw t7, 44(rz) }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | jef .FIN | nopi }
    { nopi | nopi | nopi | nopi }
.FIN:
    { nopi | nopi | jef .FIN | nopi }
