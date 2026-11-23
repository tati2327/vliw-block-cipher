# Ejercicios del compilador

Fecha: 2026-11-22  
Commit indicado por la referencia local: `e30b725`  
Simulador: Icarus Verilog version 12.0 (stable) ()  


Divisor 4. Los valores conservan la precisión impresa por `tb_programa`. El guion indica que la configuración carece del contador o que el testbench no imprime ese valor.

## Ejercicio 1

| Contador | CACHE=0 | CACHE=1 | CACHE=2 |
| --- | --- | --- | --- |
| Ciclos | 2562 | 389 | 413 |
| Bundles | 202 | 202 | 202 |
| Instrucciones | 167 | 167 | 167 |
| IPC | 0.065183 | 0.429306 | 0.404358 |
| Saltos | 27 | 27 | 27 |
| Pausa crypto | 0 | 0 | 0 |
| Pausa memoria | 2332 | 159 | 183 |
| Pausa total | 2332 | 159 | 183 |
| AUTH ejecutados | 0 | 0 | 0 |
| Memoria principal / MEM_DIV | 4 | 4 | 4 |
| Memoria principal / Lecturas | 27 | 3 | 3 |
| Memoria principal / Escrituras | 17 | 0 | 0 |
| Memoria principal / Transferencia | 2332 | 159 | 159 |
| Memoria principal / Ciclos totales | 2562 | 389 | 413 |
| Memoria principal / Utilizacion | 0.910226 | 0.408740 | 0.384988 |
| Loads comprobados | 27 | 27 | 27 |
| Stores aplicados | 17 | 17 | 17 |
| Discrepancias | 0 | 0 | 0 |
| Identidad de ciclos | cumple | cumple | cumple |
| Pausas de L1 verificadas | — | PASS | PASS |
| Comparaciones de palabras esperadas | 5 | 5 | 5 |
| Resultado del testbench | PASS | PASS | PASS |
| L1 / Lecturas / total | — | 27 | 27 |
| L1 / Lecturas / aciertos | — | 27 | 27 |
| L1 / Lecturas / fallos | — | 0 | 0 |
| L1 / Escrituras / total | — | 17 | 17 |
| L1 / Escrituras / aciertos | — | 14 | 14 |
| L1 / Escrituras / fallos | — | 3 | 3 |
| L1 / hit | — | 0.931818 | 0.931818 |
| L1 / miss | — | 0.068182 | 0.068182 |
| L1 / pausa / buffer | — | 0 | 0 |
| L1 / pausa / L2 | — | 0 | 0 |
| L1 / pausa / memoria | — | 159 | 183 |
| L1 / pausa / lleno | — | 0 | 0 |
| L1 / pausa / pendientes | — | 0 | 0 |
| Write buffer / Lineas recibidas | — | 0 | 0 |
| Write buffer / Forwarding | — | 0 | 0 |
| Write buffer / Ciclos lleno | — | 0 | 0 |
| Write buffer / Ocupacion maxima | — | 0 | 0 |
| L2 / Lecturas / total | — | — | 3 |
| L2 / Lecturas / aciertos | — | — | 0 |
| L2 / Lecturas / fallos | — | — | 3 |
| L2 / Escrituras / total | — | — | 0 |
| L2 / Escrituras / aciertos | — | — | 0 |
| L2 / Escrituras / fallos | — | — | 0 |
| L2 / hit | — | — | 0.000000 |
| L2 / miss | — | — | 1.000000 |
| L2 / pausa / eviction buffer lleno | — | — | 0 |
| Eviction buffer / Lineas recibidas | — | — | 0 |
| Eviction buffer / Forwarding | — | — | 0 |
| Eviction buffer / Ciclos lleno | — | — | 0 |
| Eviction buffer / Ocupacion maxima | — | — | 0 |
| AMAT medido | — | — | 5.159091 |
| AMAT formula | — | — | 5.159091 |
| Miss rate L1 | — | — | 0.068182 |
| Miss rate L2 | — | — | 1.000000 |
| Tmem | — | — | 53 |

[CACHE=0](ejercicio1_cache0.log) [CACHE=1](ejercicio1_cache1.log) [CACHE=2](ejercicio1_cache2.log)

## Ejercicio 2

| Contador | CACHE=0 | CACHE=1 | CACHE=2 |
| --- | --- | --- | --- |
| Ciclos | 5682 | 647 | 687 |
| Bundles | 366 | 366 | 366 |
| Instrucciones | 290 | 290 | 290 |
| IPC | 0.051038 | 0.448223 | 0.422125 |
| Saltos | 15 | 15 | 15 |
| Pausa crypto | 0 | 0 | 0 |
| Pausa memoria | 5300 | 265 | 305 |
| Pausa total | 5300 | 265 | 305 |
| AUTH ejecutados | 0 | 0 | 0 |
| Memoria principal / MEM_DIV | 4 | 4 | 4 |
| Memoria principal / Lecturas | 73 | 5 | 5 |
| Memoria principal / Escrituras | 27 | 0 | 0 |
| Memoria principal / Transferencia | 5300 | 265 | 265 |
| Memoria principal / Ciclos totales | 5682 | 647 | 687 |
| Memoria principal / Utilizacion | 0.932770 | 0.409583 | 0.385735 |
| Loads comprobados | 73 | 73 | 73 |
| Stores aplicados | 27 | 27 | 27 |
| Discrepancias | 0 | 0 | 0 |
| Identidad de ciclos | cumple | cumple | cumple |
| Pausas de L1 verificadas | — | PASS | PASS |
| Comparaciones de palabras esperadas | 3 | 3 | 3 |
| Resultado del testbench | PASS | PASS | PASS |
| L1 / Lecturas / total | — | 73 | 73 |
| L1 / Lecturas / aciertos | — | 72 | 72 |
| L1 / Lecturas / fallos | — | 1 | 1 |
| L1 / Escrituras / total | — | 27 | 27 |
| L1 / Escrituras / aciertos | — | 23 | 23 |
| L1 / Escrituras / fallos | — | 4 | 4 |
| L1 / hit | — | 0.950000 | 0.950000 |
| L1 / miss | — | 0.050000 | 0.050000 |
| L1 / pausa / buffer | — | 0 | 0 |
| L1 / pausa / L2 | — | 0 | 0 |
| L1 / pausa / memoria | — | 265 | 305 |
| L1 / pausa / lleno | — | 0 | 0 |
| L1 / pausa / pendientes | — | 0 | 0 |
| Write buffer / Lineas recibidas | — | 0 | 0 |
| Write buffer / Forwarding | — | 0 | 0 |
| Write buffer / Ciclos lleno | — | 0 | 0 |
| Write buffer / Ocupacion maxima | — | 0 | 0 |
| L2 / Lecturas / total | — | — | 5 |
| L2 / Lecturas / aciertos | — | — | 0 |
| L2 / Lecturas / fallos | — | — | 5 |
| L2 / Escrituras / total | — | — | 0 |
| L2 / Escrituras / aciertos | — | — | 0 |
| L2 / Escrituras / fallos | — | — | 0 |
| L2 / hit | — | — | 0.000000 |
| L2 / miss | — | — | 1.000000 |
| L2 / pausa / eviction buffer lleno | — | — | 0 |
| Eviction buffer / Lineas recibidas | — | — | 0 |
| Eviction buffer / Forwarding | — | — | 0 |
| Eviction buffer / Ciclos lleno | — | — | 0 |
| Eviction buffer / Ocupacion maxima | — | — | 0 |
| AMAT medido | — | — | 4.050000 |
| AMAT formula | — | — | 4.050000 |
| Miss rate L1 | — | — | 0.050000 |
| Miss rate L2 | — | — | 1.000000 |
| Tmem | — | — | 53 |

[CACHE=0](ejercicio2_cache0.log) [CACHE=1](ejercicio2_cache1.log) [CACHE=2](ejercicio2_cache2.log)

## Ejercicio 3

| Contador | CACHE=0 | CACHE=1 | CACHE=2 |
| --- | --- | --- | --- |
| Ciclos | 139832 | 23642 | 23682 |
| Bundles | 14771 | 14771 | 14771 |
| Instrucciones | 13978 | 13978 | 13978 |
| IPC | 0.099963 | 0.591236 | 0.590237 |
| Saltos | 2299 | 2299 | 2299 |
| Pausa crypto | 13 | 13 | 13 |
| Pausa memoria | 122748 | 6558 | 6598 |
| Pausa total | 122761 | 6571 | 6611 |
| AUTH ejecutados | 1 | 1 | 1 |
| Memoria principal / MEM_DIV | 4 | 4 | 4 |
| Memoria principal / Lecturas | 1245 | 121 | 106 |
| Memoria principal / Escrituras | 1071 | 25 | 0 |
| Memoria principal / Transferencia | 122748 | 7687 | 5618 |
| Memoria principal / Ciclos totales | 139832 | 23642 | 23682 |
| Memoria principal / Utilizacion | 0.877825 | 0.325142 | 0.237227 |
| Loads comprobados | 1245 | 1245 | 1245 |
| Stores aplicados | 1071 | 1071 | 1071 |
| Discrepancias | 0 | 0 | 0 |
| Identidad de ciclos | cumple | cumple | cumple |
| Pausas de L1 verificadas | — | PASS | PASS |
| Comparaciones de palabras esperadas | Sin .exp.mem | Sin .exp.mem | Sin .exp.mem |
| Resultado del testbench | PASS | PASS | PASS |
| L1 / Lecturas / total | — | 1245 | 1245 |
| L1 / Lecturas / aciertos | — | 1209 | 1209 |
| L1 / Lecturas / fallos | — | 36 | 36 |
| L1 / Escrituras / total | — | 1071 | 1071 |
| L1 / Escrituras / aciertos | — | 985 | 985 |
| L1 / Escrituras / fallos | — | 86 | 86 |
| L1 / hit | — | 0.947323 | 0.947323 |
| L1 / miss | — | 0.052677 | 0.052677 |
| L1 / pausa / buffer | — | 0 | 0 |
| L1 / pausa / L2 | — | 0 | 132 |
| L1 / pausa / memoria | — | 6558 | 6466 |
| L1 / pausa / lleno | — | 0 | 0 |
| L1 / pausa / pendientes | — | 0 | 0 |
| Write buffer / Lineas recibidas | — | 25 | 25 |
| Write buffer / Forwarding | — | 1 | 0 |
| Write buffer / Ciclos lleno | — | 0 | 0 |
| Write buffer / Ocupacion maxima | — | 2 | 2 |
| L2 / Lecturas / total | — | — | 122 |
| L2 / Lecturas / aciertos | — | — | 16 |
| L2 / Lecturas / fallos | — | — | 106 |
| L2 / Escrituras / total | — | — | 25 |
| L2 / Escrituras / aciertos | — | — | 24 |
| L2 / Escrituras / fallos | — | — | 0 |
| L2 / hit | — | — | 0.272109 |
| L2 / miss | — | — | 0.721088 |
| L2 / pausa / eviction buffer lleno | — | — | 0 |
| Eviction buffer / Lineas recibidas | — | — | 0 |
| Eviction buffer / Forwarding | — | — | 0 |
| Eviction buffer / Ciclos lleno | — | — | 0 |
| Eviction buffer / Ocupacion maxima | — | — | 0 |
| AMAT medido | — | — | 3.848877 |
| AMAT formula | — | — | 3.434610 |
| Miss rate L1 | — | — | 0.052677 |
| Miss rate L2 | — | — | 0.721088 |
| Tmem | — | — | 53 |

[CACHE=0](ejercicio3_cache0.log) [CACHE=1](ejercicio3_cache1.log) [CACHE=2](ejercicio3_cache2.log)
