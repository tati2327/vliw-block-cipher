# Lee cada palabra, le suma uno y guarda el nuevo valor en la misma dirección.
# Cada vuelta deja i+1+p en la posición i y acumula los valores que se escribieron.
#
# t0 guarda la base del arreglo, t1 su cantidad de palabras y t2 las vueltas
# pendientes. t3 recibe la base de tabla, aunque este programa no la consulta.
# t4 suma los valores escritos y t5 cuenta escrituras útiles. t6 cuenta lecturas
# útiles y t7 las vueltas completas. t8 recorre el arreglo, t9 cuenta las palabras
# pendientes y t10 conserva el dato hasta completar su modificación y escritura.
#
# La cantidad de palabras y la cantidad de vueltas deben ser positivas.
# Los paquetes de separación también se respetan cuando la lectura acierta en L1.

    { mov t4, 0 | mov t5, 0 | nopi | lw t0, 0(rz) }
    { mov t6, 0 | mov t7, 0 | nopi | lw t1, 4(rz) }
    { nopi | nopi | nopi | lw t2, 8(rz) }
    { nopi | nopi | nopi | lw t3, 12(rz) }

.VUELTA:
    { add t8, t0, rz | add t9, t1, rz | nopi | nopi }
    { nopi | nopi | nopi | nopi }

.LEER:
    { saddi t9, t9, -1 | saddi t6, t6, 1 | nopi | lw t10, 0(t8) }
    { nopi | nopi | nopi | nopi }
    { saddi t10, t10, 1 | nopi | nopi | nopi }
    # Contar la escritura ocupa el paquete necesario antes de usar el dato nuevo.
    { saddi t5, t5, 1 | nopi | nopi | nopi }
    { add t4, t4, t10 | nopi | nopi | sw t10, 0(t8) }
    { saddi t8, t8, 4 | nopi | nopi | nopi }
    { nopi | nopi | bne t9, rz, .LEER | nopi }

.FIN_RECORRIDO:
    { saddi t7, t7, 1 | saddi t2, t2, -1 | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | bne t2, rz, .VUELTA | nopi }

    # Las salidas contienen la suma de valores escritos, escrituras útiles,
    # lecturas útiles y vueltas completas. Se verifican además todas las palabras.
    { nopi | nopi | nopi | sw t4, 32(rz) }
    { nopi | nopi | nopi | sw t5, 36(rz) }
    { nopi | nopi | nopi | sw t6, 40(rz) }
    { nopi | nopi | nopi | sw t7, 44(rz) }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | jef .FIN | nopi }
    { nopi | nopi | nopi | nopi }
.FIN:
    { nopi | nopi | jef .FIN | nopi }
