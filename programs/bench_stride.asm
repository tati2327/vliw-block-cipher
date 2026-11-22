# Recorre el arreglo con un salto de ocho palabras entre lecturas.
# Una vuelta tiene ocho fases. Cada fase toma una palabra distinta de todas
# las líneas, hasta visitar cada palabra del arreglo exactamente una vez.
#
# t0 conserva la base del arreglo, t1 su cantidad de palabras y t2 las vueltas
# pendientes. t3 recibe la base de la tabla, aunque aquí no se utiliza.
# t4 acumula la suma y t5 las lecturas útiles. t6 permanece en cero y t7 cuenta
# las vueltas completas. t8 es la dirección actual, t9 las líneas pendientes
# y t10 el dato leído. t11 guarda el desplazamiento de palabra de la fase.
# rx conserva la cantidad de líneas y rl el límite de 32 bytes de cada línea.
# rg vale tres y se usa para dividir la cantidad de palabras entre ocho.
#
# Cada paquete de cuatro instrucciones se llama bundle. Un paquete intermedio
# separa la escritura de un registro de cualquier lectura de su nuevo valor.
# Se requiere una cantidad positiva de palabras que sea múltiplo de ocho.

# La cantidad de recorridos también debe ser positiva.

    { mov t4, 0 | mov t5, 0 | nopi | lw t0, 0(rz) }
    { mov t6, 0 | mov t7, 0 | nopi | lw t1, 4(rz) }
    { mov rg, 3 | mov rl, 32 | nopi | lw t2, 8(rz) }
    { nopi | nopi | nopi | lw t3, 12(rz) }

    # Desplazar tres bits a la derecha divide entre ocho y obtiene las líneas.
    { srl rx, t1, rg | nopi | nopi | nopi }

.VUELTA:
    { mov t11, 0 | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }

.FASE:
    # La fase empieza en base más 0, 4, 8 y hasta 28 bytes según la palabra.
    { add t8, t0, t11 | add t9, rx, rz | nopi | nopi }
    { nopi | nopi | nopi | nopi }

.LEER:
    # Avanzar 32 bytes lleva a la misma palabra de la siguiente línea.
    # El paquete que actualiza la dirección separa la carga de su uso en la suma.
    { saddi t9, t9, -1 | saddi t5, t5, 1 | nopi | lw t10, 0(t8) }
    { saddi t8, t8, 32 | nopi | nopi | nopi }
    { add t4, t4, t10 | nopi | bne t9, rz, .LEER | nopi }

    # Después de recorrer todas las líneas se pasa a la palabra siguiente.
    { saddi t11, t11, 4 | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | blt t11, rl, .FASE | nopi }

.FIN_RECORRIDO:
    { saddi t7, t7, 1 | saddi t2, t2, -1 | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | bne t2, rz, .VUELTA | nopi }

    # La tabla no se consulta, por lo que su contador debe seguir en cero.
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
