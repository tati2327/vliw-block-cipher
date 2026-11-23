# Visita las líneas del arreglo en el orden precalculado de una tabla.
# Cada entrada contiene el desplazamiento en bytes de una línea desde la base.
# Ocho fases seleccionan sus ocho palabras y forman una vuelta completa.
# La tabla se vuelve a leer en cada fase y conserva el mismo orden en cada vuelta.
#
# t0 conserva la base del arreglo y t2 las vueltas pendientes. t3 apunta a la tabla.
# t1 recibe al principio la cantidad de palabras y después guarda la dirección
# de la palabra de la fase dentro de la primera línea. rx conserva la cantidad
# de líneas, calculada antes de reutilizar t1.
# t4 acumula la suma, t5 las lecturas útiles, t6 las lecturas de tabla y t7 las
# vueltas completas. t8 recorre la tabla, t9 cuenta las líneas pendientes y t10
# recibe tanto el desplazamiento como el dato final, en momentos distintos.
# t11 guarda el desplazamiento de palabra de la fase. rl contiene la dirección
# calculada del dato. rg empieza en tres para dividir entre ocho y después vale
# 32 para reconocer el final de las ocho fases.
#
# Cada bundle es un paquete de cuatro instrucciones. Los paquetes de separación
# permiten usar un registro recién escrito sin depender de pausas de memoria.
# La cantidad de palabras debe ser positiva y múltiplo de ocho. La tabla debe
# contener una vez el desplazamiento de cada línea, siempre múltiplo de 32.

# La cantidad de palabras debe ser positiva y múltiplo de ocho.
# La cantidad de recorridos también debe ser positiva.

    { mov t4, 0 | mov t5, 0 | nopi | lw t0, 0(rz) }
    { mov t6, 0 | mov t7, 0 | nopi | lw t1, 4(rz) }
    { mov rg, 3 | nopi | nopi | lw t2, 8(rz) }
    { nopi | nopi | nopi | lw t3, 12(rz) }
    { srl rx, t1, rg | nopi | nopi | nopi }

.VUELTA:
    { mov t11, 0 | mov rg, 32 | nopi | nopi }
    { nopi | nopi | nopi | nopi }

.FASE:
    # Se reinician el puntero de tabla y la cantidad de líneas pendientes.
    # El paquete que calcula la base de esta fase también separa la escritura
    # de t8 de la primera lectura de la tabla.
    { add t8, t3, rz | add t9, rx, rz | nopi | nopi }
    { add t1, t0, t11 | nopi | nopi | nopi }

.LEER_INDICE:
    # Cada línea necesita dos cargas. Primero se obtiene su desplazamiento y
    # después se lee la palabra. Los contadores distinguen ambos tipos de acceso.
    { saddi t9, t9, -1 | saddi t6, t6, 1 | nopi | lw t10, 0(t8) }
    { saddi t8, t8, 4 | nopi | nopi | nopi }
    { add rl, t1, t10 | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { saddi t5, t5, 1 | nopi | nopi | lw t10, 0(rl) }
    { nopi | nopi | nopi | nopi }
    { add t4, t4, t10 | nopi | bne t9, rz, .LEER_INDICE | nopi }

    # La próxima fase utiliza la palabra siguiente dentro de cada línea.
    { saddi t11, t11, 4 | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | blt t11, rg, .FASE | nopi }

.FIN_RECORRIDO:
    { saddi t7, t7, 1 | saddi t2, t2, -1 | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | bne t2, rz, .VUELTA | nopi }

    # La cantidad de lecturas de tabla debe coincidir con la de lecturas útiles.
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
