# Recorre el arreglo palabra por palabra y acumula la suma de todas las vueltas.
# La configuración contiene la base del arreglo, su cantidad de palabras, la
# cantidad de vueltas y la base de la tabla. Se lee una sola vez al comenzar.
#
# t0 conserva la base del arreglo y t1 su cantidad de palabras. t2 indica las
# vueltas que faltan. t3 recibe la base de la tabla, aunque aquí no se utiliza.
# t4 acumula la suma, t5 cuenta las lecturas útiles, t6 permanece en cero y
# t7 cuenta las vueltas completas. t8 es la dirección actual, t9 indica cuántas
# palabras faltan y t10 recibe el dato leído.
#
# Cada línea entre llaves es un paquete de cuatro instrucciones, llamado bundle.
# Entre escribir un registro y usar su nuevo valor se deja un paquete intermedio.

# La configuración debe indicar cantidades positivas de palabras y recorridos.

    { mov t4, 0 | mov t5, 0 | nopi | lw t0, 0(rz) }
    { mov t6, 0 | mov t7, 0 | nopi | lw t1, 4(rz) }
    { nopi | nopi | nopi | lw t2, 8(rz) }
    { nopi | nopi | nopi | lw t3, 12(rz) }

.VUELTA:
    # Cada vuelta vuelve al principio sin borrar la suma ni las métricas.
    { add t8, t0, rz | add t9, t1, rz | nopi | nopi }
    { nopi | nopi | nopi | nopi }

.LEER:
    # La lectura y el control de la vuelta usan registros independientes.
    # Actualizar la dirección en el paquete siguiente deja tiempo para recibir
    # t10 antes de sumarlo y para utilizar t9 en el salto.
    { saddi t9, t9, -1 | saddi t5, t5, 1 | nopi | lw t10, 0(t8) }
    { saddi t8, t8, 4 | nopi | nopi | nopi }
    { add t4, t4, t10 | nopi | bne t9, rz, .LEER | nopi }

    # El salto revisa t2 después de un paquete de separación.
.FIN_RECORRIDO:
    { saddi t7, t7, 1 | saddi t2, t2, -1 | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | bne t2, rz, .VUELTA | nopi }

    # Los resultados se escriben solo después de completar todas las lecturas.
    # Se guardan suma, lecturas útiles, lecturas de tabla y vueltas completas.
    { nopi | nopi | nopi | sw t4, 32(rz) }
    { nopi | nopi | nopi | sw t5, 36(rz) }
    { nopi | nopi | nopi | sw t6, 40(rz) }
    { nopi | nopi | nopi | sw t7, 44(rz) }

    # Se deja terminar la última escritura antes de saltar al lazo de fin.
    # El salto de salida se completa antes de anunciar el fin del programa.
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | jef .FIN | nopi }
    { nopi | nopi | nopi | nopi }
.FIN:
    { nopi | nopi | jef .FIN | nopi }
