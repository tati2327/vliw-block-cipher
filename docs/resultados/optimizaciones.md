# Optimizaciones del compilador medidas en el procesador

Commit de ccom: `96bd97a`  
Simulador: Icarus Verilog version 12.0 (stable)  
Fecha: 22 de noviembre de 2026  
MEM_DIV=4; 24 versiones y tres configuraciones de caché (72 corridas).

Se utilizaron los `.hex` originales, sin reensamblar. Los ciclos proceden del
procesador; no se usan los «ciclos sin cache» de `info.txt` del compilador.

```bash
mkdir -p build/optimizaciones/asm build/optimizaciones/logs
cp /home/luis/entrega_arqui/*.hex build/optimizaciones/
cp /home/luis/entrega_arqui/*.mem build/optimizaciones/
cp /home/luis/entrega_arqui/*.asm build/optimizaciones/asm/
cp /home/luis/entrega_arqui/info.txt build/optimizaciones/
for programa in test1 test2 test3 test4 test5 test6 ejercicio1 ejercicio2; do
  for nivel in O0 O1 O2; do
    v="${programa}_${nivel}"
    for c in 0 1 2; do
      make sim PROG="build/optimizaciones/$v" CACHE="$c" MEM_DIV=4 WAVES=0 MAX_CYCLES=10000000 > "build/optimizaciones/logs/${v}_c${c}.txt" 2>&1
      cp "build/$v/dump.mem" "build/optimizaciones/logs/${v}_c${c}.dump.mem"
    done
  done
done
```

Hay 24 `.hex`, 24 `.mem` y 24 `.asm` copiados; la entrada original se conserva.
Los comandos expresan la secuencia ejecutada. Cada volcado se conservó y validó
antes de ejecutar la siguiente configuración de esa versión.

Bundles e instrucciones son conteos dinámicos. Los accesos de L1 suman lecturas y
escrituras. Las tasas usan aciertos / accesos, combinando ambas operaciones;
`—` indica un nivel ausente. El CSV conserva la precisión impresa, y deja AMAT
vacío en CACHE=0 y 1 porque el testbench solo lo imprime con CACHE=2.

## test1

| Nivel | CACHE | Ciclos | Bundles | Instrucciones | IPC | Pausa memoria | Accesos L1 | Hit L1 | Hit L2 | Lecturas RAM | Escrituras RAM |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| O0 | 0 | 22925 | 4299 | 4031 | 0.175834 | 17914 | — | — | — | 225 | 113 |
| O0 | 1 | 5276 | 4299 | 4031 | 0.764026 | 265 | 338 | 0.985207 | — | 5 | 0 |
| O0 | 2 | 5316 | 4299 | 4031 | 0.758277 | 305 | 338 | 0.985207 | 0.000000 | 5 | 0 |
| O1 | 0 | 19746 | 4017 | 3858 | 0.195381 | 14999 | — | — | — | 190 | 93 |
| O1 | 1 | 5012 | 4017 | 3858 | 0.769753 | 265 | 283 | 0.982332 | — | 5 | 0 |
| O1 | 2 | 5052 | 4017 | 3858 | 0.763658 | 305 | 283 | 0.982332 | 0.000000 | 5 | 0 |
| O2 | 0 | 18321 | 3975 | 3824 | 0.208722 | 13621 | — | — | — | 175 | 82 |
| O2 | 1 | 5018 | 3975 | 3824 | 0.762057 | 318 | 257 | 0.976654 | — | 6 | 0 |
| O2 | 2 | 5066 | 3975 | 3824 | 0.754836 | 366 | 257 | 0.976654 | 0.000000 | 6 | 0 |

## test2

| Nivel | CACHE | Ciclos | Bundles | Instrucciones | IPC | Pausa memoria | Accesos L1 | Hit L1 | Hit L2 | Lecturas RAM | Escrituras RAM |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| O0 | 0 | 5919 | 335 | 259 | 0.043757 | 5565 | — | — | — | 79 | 26 |
| O0 | 1 | 566 | 335 | 259 | 0.457597 | 212 | 105 | 0.961905 | — | 4 | 0 |
| O0 | 2 | 598 | 335 | 259 | 0.433110 | 244 | 105 | 0.961905 | 0.000000 | 4 | 0 |
| O1 | 0 | 5191 | 237 | 190 | 0.036602 | 4929 | — | — | — | 67 | 26 |
| O1 | 1 | 474 | 237 | 190 | 0.400844 | 212 | 93 | 0.956989 | — | 4 | 0 |
| O1 | 2 | 506 | 237 | 190 | 0.375494 | 244 | 93 | 0.956989 | 0.000000 | 4 | 0 |
| O2 | 0 | 3201 | 164 | 136 | 0.042487 | 3021 | — | — | — | 40 | 17 |
| O2 | 1 | 392 | 164 | 136 | 0.346939 | 212 | 57 | 0.929825 | — | 4 | 0 |
| O2 | 2 | 424 | 164 | 136 | 0.320755 | 244 | 57 | 0.929825 | 0.000000 | 4 | 0 |

## test3

| Nivel | CACHE | Ciclos | Bundles | Instrucciones | IPC | Pausa memoria | Accesos L1 | Hit L1 | Hit L2 | Lecturas RAM | Escrituras RAM |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| O0 | 0 | 23655 | 4749 | 4467 | 0.188840 | 18126 | — | — | — | 256 | 86 |
| O0 | 1 | 5794 | 4749 | 4467 | 0.770970 | 265 | 342 | 0.985380 | — | 5 | 0 |
| O0 | 2 | 5834 | 4749 | 4467 | 0.765684 | 305 | 342 | 0.985380 | 0.000000 | 5 | 0 |
| O1 | 0 | 21967 | 4471 | 4248 | 0.193381 | 16695 | — | — | — | 229 | 86 |
| O1 | 1 | 5537 | 4471 | 4248 | 0.767202 | 265 | 315 | 0.984127 | — | 5 | 0 |
| O1 | 2 | 5577 | 4471 | 4248 | 0.761700 | 305 | 315 | 0.984127 | 0.000000 | 5 | 0 |
| O2 | 0 | 16390 | 4224 | 4088 | 0.249420 | 11395 | — | — | — | 159 | 56 |
| O2 | 1 | 5260 | 4224 | 4088 | 0.777186 | 265 | 215 | 0.976744 | — | 5 | 0 |
| O2 | 2 | 5300 | 4224 | 4088 | 0.771321 | 305 | 215 | 0.976744 | 0.000000 | 5 | 0 |

## test4

| Nivel | CACHE | Ciclos | Bundles | Instrucciones | IPC | Pausa memoria | Accesos L1 | Hit L1 | Hit L2 | Lecturas RAM | Escrituras RAM |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| O0 | 0 | 7272 | 471 | 367 | 0.050468 | 6784 | — | — | — | 90 | 38 |
| O0 | 1 | 700 | 471 | 367 | 0.524286 | 212 | 128 | 0.968750 | — | 4 | 0 |
| O0 | 2 | 732 | 471 | 367 | 0.501366 | 244 | 128 | 0.968750 | 0.000000 | 4 | 0 |
| O1 | 0 | 6472 | 301 | 255 | 0.039400 | 6148 | — | — | — | 78 | 38 |
| O1 | 1 | 536 | 301 | 255 | 0.475746 | 212 | 116 | 0.965517 | — | 4 | 0 |
| O1 | 2 | 568 | 301 | 255 | 0.448944 | 244 | 116 | 0.965517 | 0.000000 | 4 | 0 |
| O2 | 0 | 4742 | 173 | 201 | 0.042387 | 4558 | — | — | — | 54 | 32 |
| O2 | 1 | 396 | 173 | 201 | 0.507576 | 212 | 86 | 0.953488 | — | 4 | 0 |
| O2 | 2 | 428 | 173 | 201 | 0.469626 | 244 | 86 | 0.953488 | 0.000000 | 4 | 0 |

## test5

| Nivel | CACHE | Ciclos | Bundles | Instrucciones | IPC | Pausa memoria | Accesos L1 | Hit L1 | Hit L2 | Lecturas RAM | Escrituras RAM |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| O0 | 0 | 12987 | 993 | 813 | 0.062601 | 11925 | — | — | — | 165 | 60 |
| O0 | 1 | 1380 | 993 | 813 | 0.589130 | 318 | 225 | 0.973333 | — | 6 | 0 |
| O0 | 2 | 1428 | 993 | 813 | 0.569328 | 366 | 225 | 0.973333 | 0.000000 | 6 | 0 |
| O1 | 0 | 11656 | 713 | 627 | 0.053792 | 10865 | — | — | — | 145 | 60 |
| O1 | 1 | 1109 | 713 | 627 | 0.565374 | 318 | 205 | 0.970732 | — | 6 | 0 |
| O1 | 2 | 1157 | 713 | 627 | 0.541919 | 366 | 205 | 0.970732 | 0.000000 | 6 | 0 |
| O2 | 0 | 8026 | 491 | 539 | 0.067157 | 7473 | — | — | — | 101 | 40 |
| O2 | 1 | 871 | 491 | 539 | 0.618829 | 318 | 141 | 0.957447 | — | 6 | 0 |
| O2 | 2 | 919 | 491 | 539 | 0.586507 | 366 | 141 | 0.957447 | 0.000000 | 6 | 0 |

## test6

| Nivel | CACHE | Ciclos | Bundles | Instrucciones | IPC | Pausa memoria | Accesos L1 | Hit L1 | Hit L2 | Lecturas RAM | Escrituras RAM |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| O0 | 0 | 5976 | 225 | 206 | 0.034471 | 5724 | — | — | — | 62 | 46 |
| O0 | 1 | 517 | 225 | 206 | 0.398453 | 265 | 108 | 0.953704 | — | 5 | 0 |
| O0 | 2 | 557 | 225 | 206 | 0.369838 | 305 | 108 | 0.953704 | 0.000000 | 5 | 0 |
| O1 | 0 | 5507 | 176 | 181 | 0.032867 | 5300 | — | — | — | 58 | 42 |
| O1 | 1 | 419 | 176 | 181 | 0.431981 | 212 | 100 | 0.960000 | — | 4 | 0 |
| O1 | 2 | 451 | 176 | 181 | 0.401330 | 244 | 100 | 0.960000 | 0.000000 | 4 | 0 |
| O2 | 0 | 5390 | 165 | 179 | 0.033210 | 5194 | — | — | — | 58 | 40 |
| O2 | 1 | 408 | 165 | 179 | 0.438725 | 212 | 98 | 0.959184 | — | 4 | 0 |
| O2 | 2 | 440 | 165 | 179 | 0.406818 | 244 | 98 | 0.959184 | 0.000000 | 4 | 0 |

## ejercicio1

| Nivel | CACHE | Ciclos | Bundles | Instrucciones | IPC | Pausa memoria | Accesos L1 | Hit L1 | Hit L2 | Lecturas RAM | Escrituras RAM |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| O0 | 0 | 2562 | 202 | 167 | 0.065183 | 2332 | — | — | — | 27 | 17 |
| O0 | 1 | 389 | 202 | 167 | 0.429306 | 159 | 44 | 0.931818 | — | 3 | 0 |
| O0 | 2 | 413 | 202 | 167 | 0.404358 | 183 | 44 | 0.931818 | 0.000000 | 3 | 0 |
| O1 | 0 | 2449 | 191 | 161 | 0.065741 | 2226 | — | — | — | 26 | 16 |
| O1 | 1 | 382 | 191 | 161 | 0.421466 | 159 | 42 | 0.928571 | — | 3 | 0 |
| O1 | 2 | 406 | 191 | 161 | 0.396552 | 183 | 42 | 0.928571 | 0.000000 | 3 | 0 |
| O2 | 0 | 2444 | 186 | 161 | 0.065876 | 2226 | — | — | — | 26 | 16 |
| O2 | 1 | 377 | 186 | 161 | 0.427056 | 159 | 42 | 0.928571 | — | 3 | 0 |
| O2 | 2 | 401 | 186 | 161 | 0.401496 | 183 | 42 | 0.928571 | 0.000000 | 3 | 0 |

## ejercicio2

| Nivel | CACHE | Ciclos | Bundles | Instrucciones | IPC | Pausa memoria | Accesos L1 | Hit L1 | Hit L2 | Lecturas RAM | Escrituras RAM |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| O0 | 0 | 5682 | 366 | 290 | 0.051038 | 5300 | — | — | — | 73 | 27 |
| O0 | 1 | 647 | 366 | 290 | 0.448223 | 265 | 100 | 0.950000 | — | 5 | 0 |
| O0 | 2 | 687 | 366 | 290 | 0.422125 | 305 | 100 | 0.950000 | 0.000000 | 5 | 0 |
| O1 | 0 | 4918 | 228 | 198 | 0.040260 | 4664 | — | — | — | 62 | 26 |
| O1 | 1 | 519 | 228 | 198 | 0.381503 | 265 | 88 | 0.943182 | — | 5 | 0 |
| O1 | 2 | 559 | 228 | 198 | 0.354204 | 305 | 88 | 0.943182 | 0.000000 | 5 | 0 |
| O2 | 0 | 4912 | 222 | 198 | 0.040309 | 4664 | — | — | — | 62 | 26 |
| O2 | 1 | 513 | 222 | 198 | 0.385965 | 265 | 88 | 0.943182 | — | 5 | 0 |
| O2 | 2 | 553 | 222 | 198 | 0.358047 | 305 | 88 | 0.943182 | 0.000000 | 5 | 0 |

## Comparaciones entre niveles

Reducción de ciclos respecto de O0 de la misma configuración.

| Programa | CACHE | O1 frente a O0 | O2 frente a O0 |
| --- | --- | --- | --- |
| test1 | 0 | 13.867% | 20.083% |
| test1 | 1 | 5.004% | 4.890% |
| test1 | 2 | 4.966% | 4.703% |
| test2 | 0 | 12.299% | 45.920% |
| test2 | 1 | 16.254% | 30.742% |
| test2 | 2 | 15.385% | 29.097% |
| test3 | 0 | 7.136% | 30.712% |
| test3 | 1 | 4.436% | 9.216% |
| test3 | 2 | 4.405% | 9.153% |
| test4 | 0 | 11.001% | 34.791% |
| test4 | 1 | 23.429% | 43.429% |
| test4 | 2 | 22.404% | 41.530% |
| test5 | 0 | 10.249% | 38.200% |
| test5 | 1 | 19.638% | 36.884% |
| test5 | 2 | 18.978% | 35.644% |
| test6 | 0 | 7.848% | 9.806% |
| test6 | 1 | 18.956% | 21.083% |
| test6 | 2 | 19.031% | 21.005% |
| ejercicio1 | 0 | 4.411% | 4.606% |
| ejercicio1 | 1 | 1.799% | 3.085% |
| ejercicio1 | 2 | 1.695% | 2.906% |
| ejercicio2 | 0 | 13.446% | 13.552% |
| ejercicio2 | 1 | 19.784% | 20.711% |
| ejercicio2 | 2 | 18.632% | 19.505% |

Bundles estáticos: líneas del `.hex` original (un bundle por línea). Estos
conteos describen el tamaño del código y se distinguen de los bundles dinámicos
de las tablas anteriores.

| Programa | Nivel | Bundles estáticos |
| --- | --- | --- |
| test1 | O0 | 231 |
| test1 | O1 | 174 |
| test1 | O2 | 328 |
| test2 | O0 | 112 |
| test2 | O1 | 79 |
| test2 | O2 | 218 |
| test3 | O0 | 295 |
| test3 | O1 | 246 |
| test3 | O2 | 302 |
| test4 | O0 | 136 |
| test4 | O1 | 89 |
| test4 | O2 | 83 |
| test5 | O0 | 195 |
| test5 | O1 | 130 |
| test5 | O2 | 125 |
| test6 | O0 | 100 |
| test6 | O1 | 71 |
| test6 | O2 | 67 |
| ejercicio1 | O0 | 80 |
| ejercicio1 | O1 | 71 |
| ejercicio1 | O2 | 69 |
| ejercicio2 | O0 | 162 |
| ejercicio2 | O1 | 100 |
| ejercicio2 | O2 | 99 |

## Validación

Las 72 corridas terminaron con `PASS fin del programa antes del limite` y
`PASS tb_programa`, código 0 y ningún `FAIL`. Todas cumplieron la identidad y
registraron cero discrepancias. Se verificó también la identidad con los
contadores extraídos, incluido `EX_anulado`.

Se resolvió cada variable de `info.txt` en la tabla de símbolos de su `.asm`,
incluidos los ámbitos de función y los ámbitos internos asociados. Se comparó
cada palabra de los arreglos y cada escalar en `dump.mem`, dirección / 4,
interpretando booleanos, punteros y enteros de 32 bits. El volcado corresponde
al monitor de memoria de CPU y contiene los stores aunque sigan en caché; no
implica persistencia de todos los datos en RAM al corte.

Se comprobaron 999 palabras en total, sin diferencias.

| Programa | Nivel | CACHE | Controles de corrida | Variables |
| --- | --- | --- | --- | --- |
| test1 | O0 | 0 | PASS | PASS (18 palabras) |
| test1 | O0 | 1 | PASS | PASS (18 palabras) |
| test1 | O0 | 2 | PASS | PASS (18 palabras) |
| test1 | O1 | 0 | PASS | PASS (18 palabras) |
| test1 | O1 | 1 | PASS | PASS (18 palabras) |
| test1 | O1 | 2 | PASS | PASS (18 palabras) |
| test1 | O2 | 0 | PASS | PASS (18 palabras) |
| test1 | O2 | 1 | PASS | PASS (18 palabras) |
| test1 | O2 | 2 | PASS | PASS (18 palabras) |
| test2 | O0 | 0 | PASS | PASS (11 palabras) |
| test2 | O0 | 1 | PASS | PASS (11 palabras) |
| test2 | O0 | 2 | PASS | PASS (11 palabras) |
| test2 | O1 | 0 | PASS | PASS (11 palabras) |
| test2 | O1 | 1 | PASS | PASS (11 palabras) |
| test2 | O1 | 2 | PASS | PASS (11 palabras) |
| test2 | O2 | 0 | PASS | PASS (11 palabras) |
| test2 | O2 | 1 | PASS | PASS (11 palabras) |
| test2 | O2 | 2 | PASS | PASS (11 palabras) |
| test3 | O0 | 0 | PASS | PASS (14 palabras) |
| test3 | O0 | 1 | PASS | PASS (14 palabras) |
| test3 | O0 | 2 | PASS | PASS (14 palabras) |
| test3 | O1 | 0 | PASS | PASS (14 palabras) |
| test3 | O1 | 1 | PASS | PASS (14 palabras) |
| test3 | O1 | 2 | PASS | PASS (14 palabras) |
| test3 | O2 | 0 | PASS | PASS (14 palabras) |
| test3 | O2 | 1 | PASS | PASS (14 palabras) |
| test3 | O2 | 2 | PASS | PASS (14 palabras) |
| test4 | O0 | 0 | PASS | PASS (16 palabras) |
| test4 | O0 | 1 | PASS | PASS (16 palabras) |
| test4 | O0 | 2 | PASS | PASS (16 palabras) |
| test4 | O1 | 0 | PASS | PASS (16 palabras) |
| test4 | O1 | 1 | PASS | PASS (16 palabras) |
| test4 | O1 | 2 | PASS | PASS (16 palabras) |
| test4 | O2 | 0 | PASS | PASS (16 palabras) |
| test4 | O2 | 1 | PASS | PASS (16 palabras) |
| test4 | O2 | 2 | PASS | PASS (16 palabras) |
| test5 | O0 | 0 | PASS | PASS (19 palabras) |
| test5 | O0 | 1 | PASS | PASS (19 palabras) |
| test5 | O0 | 2 | PASS | PASS (19 palabras) |
| test5 | O1 | 0 | PASS | PASS (19 palabras) |
| test5 | O1 | 1 | PASS | PASS (19 palabras) |
| test5 | O1 | 2 | PASS | PASS (19 palabras) |
| test5 | O2 | 0 | PASS | PASS (19 palabras) |
| test5 | O2 | 1 | PASS | PASS (19 palabras) |
| test5 | O2 | 2 | PASS | PASS (19 palabras) |
| test6 | O0 | 0 | PASS | PASS (7 palabras) |
| test6 | O0 | 1 | PASS | PASS (7 palabras) |
| test6 | O0 | 2 | PASS | PASS (7 palabras) |
| test6 | O1 | 0 | PASS | PASS (7 palabras) |
| test6 | O1 | 1 | PASS | PASS (7 palabras) |
| test6 | O1 | 2 | PASS | PASS (7 palabras) |
| test6 | O2 | 0 | PASS | PASS (7 palabras) |
| test6 | O2 | 1 | PASS | PASS (7 palabras) |
| test6 | O2 | 2 | PASS | PASS (7 palabras) |
| ejercicio1 | O0 | 0 | PASS | PASS (5 palabras) |
| ejercicio1 | O0 | 1 | PASS | PASS (5 palabras) |
| ejercicio1 | O0 | 2 | PASS | PASS (5 palabras) |
| ejercicio1 | O1 | 0 | PASS | PASS (5 palabras) |
| ejercicio1 | O1 | 1 | PASS | PASS (5 palabras) |
| ejercicio1 | O1 | 2 | PASS | PASS (5 palabras) |
| ejercicio1 | O2 | 0 | PASS | PASS (5 palabras) |
| ejercicio1 | O2 | 1 | PASS | PASS (5 palabras) |
| ejercicio1 | O2 | 2 | PASS | PASS (5 palabras) |
| ejercicio2 | O0 | 0 | PASS | PASS (21 palabras) |
| ejercicio2 | O0 | 1 | PASS | PASS (21 palabras) |
| ejercicio2 | O0 | 2 | PASS | PASS (21 palabras) |
| ejercicio2 | O1 | 0 | PASS | PASS (21 palabras) |
| ejercicio2 | O1 | 1 | PASS | PASS (21 palabras) |
| ejercicio2 | O1 | 2 | PASS | PASS (21 palabras) |
| ejercicio2 | O2 | 0 | PASS | PASS (21 palabras) |
| ejercicio2 | O2 | 1 | PASS | PASS (21 palabras) |
| ejercicio2 | O2 | 2 | PASS | PASS (21 palabras) |

Los logs, volcados y el detalle de direcciones y valores comparados se conservan
en `build/optimizaciones/`. Solo aparece el aviso de `$readmemh` por programas
que no llenan las 4096 entradas de ROM.
