# Escribe todas las palabras sin leer primero su contenido.
# En la vuelta p escribe i+1+p en la posición i. Los valores se calculan en
# registros y cada escritura se suma al resultado acumulado de las cuatro vueltas.
#
# t0 guarda la base del arreglo y t1 su cantidad de palabras. t2 contiene las
# vueltas pendientes y t3 recibe la base de tabla para mantener la misma entrada.
# t4 suma los valores escritos, t5 cuenta las escrituras útiles, t6 vale cero y
# t7 cuenta las vueltas terminadas. t8 recorre el arreglo, t9 cuenta las palabras
# pendientes y t10 contiene el próximo valor que se escribirá.
#
# La configuración debe indicar cantidades positivas de palabras y recorridos.
# Un paquete intermedio separa la escritura de un registro de su próximo uso.

    { mov t4, 0 | mov t5, 0 | nopi | lw t0, 0(rz) }
    { mov t6, 0 | mov t7, 0 | nopi | lw t1, 4(rz) }
    { nopi | nopi | nopi | lw t2, 8(rz) }
    { nopi | nopi | nopi | lw t3, 12(rz) }

.VUELTA:
    { add t8, t0, rz | add t9, t1, rz | nopi | nopi }
    # t7 cuenta vueltas terminadas. La primera palabra de la siguiente vuelta
    # debe valer t7+2, porque su valor inicial era uno y la vuelta empieza en uno.
    { saddi t10, t7, 2 | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }

.ESCRIBIR:
    # La suma y la escritura leen el mismo valor ya calculado de t10.
    # La actualización del valor queda separada de su próximo uso en el lazo.
    { saddi t9, t9, -1 | add t4, t4, t10 | nopi | sw t10, 0(t8) }
    { saddi t8, t8, 4 | saddi t10, t10, 1 | nopi | nopi }
    { saddi t5, t5, 1 | nopi | bne t9, rz, .ESCRIBIR | nopi }

.FIN_RECORRIDO:
    { saddi t7, t7, 1 | saddi t2, t2, -1 | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | bne t2, rz, .VUELTA | nopi }

    # Se guardan la suma de valores escritos, las escrituras útiles, cero lecturas
    # útiles y la cantidad de vueltas. El contenido final del arreglo se valida aparte.
    { nopi | nopi | nopi | sw t4, 32(rz) }
    { nopi | nopi | nopi | sw t5, 36(rz) }
    { nopi | nopi | nopi | sw t6, 40(rz) }
    { nopi | nopi | nopi | sw t7, 44(rz) }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | jef .FIN | nopi }
    { nopi | nopi | nopi | nopi }
.FIN:
    { nopi | nopi | jef .FIN | nopi }
