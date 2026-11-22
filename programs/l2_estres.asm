# Prueba de estres de la jerarquia de memoria L1/L2.
# Arreglo: 0x1000..0x5FFF (5120 palabras, 20 KiB).
# Resultado: 0x7000 = 0x00C80A00; estado: 0x7004 = 1.
# Se deja un bundle entre instrucciones dependientes.

inicio:
    { mov r4, 4096 | mov r5, 5120 | nopi | nopi }
    { mov r6, 1 | mov r7, 4 | nopi | nopi }
    { nopi | nopi | nopi | nopi }

escribir:
    { nopi | nopi | nopi | sw r6, 0(r4) }
    { saddi r4, r4, 4 | saddi r6, r6, 1 | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { saddi r5, r5, -1 | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | bne r5, rz, escribir | nopi }
    { nopi | nopi | nopi | nopi }

    { mov r4, 4096 | mov r5, 5120 | nopi | nopi }
    { mov r6, 0 | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }

leer:
    { nopi | nopi | nopi | lw r8, 0(r4) }
    { saddi r4, r4, 4 | saddi r5, r5, -1 | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { add r6, r6, r8 | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | bne r5, rz, leer | nopi }
    { nopi | nopi | nopi | nopi }

    { mov r9, 28672 | mov r10, 12800 | nopi | nopi }
    { mov r11, 10 | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { sll r10, r10, r11 | nopi | nopi | sw r6, 0(r9) }
    { nopi | nopi | nopi | nopi }
    { saddi r10, r10, 2560 | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { seq r12, r6, r10 | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | nopi | sw r12, 4(r9) }

    { nopi | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | nopi | nopi }

fin_main:
    { nopi | nopi | jef fin_main | nopi }
