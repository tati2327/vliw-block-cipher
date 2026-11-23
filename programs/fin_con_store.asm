# Store a una línea fría inmediatamente antes del fin.
    { mov r4, 64 | mov r5, 123 | nopi | nopi }
    { nopi | nopi | nopi | nopi }
    { nopi | nopi | nopi | sw r5, 0(r4) }
fin_main:
    { nopi | nopi | jef fin_main | nopi }
