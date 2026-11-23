# Reutilización con conflictos en L1

Este experimento complementa los cinco patrones históricos. Se eligió para observar reutilización frecuente de una línea mientras otras compiten por su conjunto de dos vías. Es un caso dirigido y no representa todas las cargas de trabajo.

Para cada uno de los 64 conjuntos se alterna A, B, A, C, A, D y se continúa hasta agotar las líneas de ese conjunto dentro de la región. A es la línea caliente. Las direcciones competidoras están separadas por 2048 bytes. Se lee la primera palabra de cada línea. En 8 KiB se hacen 384 lecturas por recorrido y en 32 KiB, 1920. El tamaño identifica la región cubierta, no la cantidad de bytes transferidos.

Cada política ejecuta el mismo ensamblador y las mismas entradas durante cuatro recorridos. Se conservan L2, sus ocho ciclos, la semilla LFSR, NINE, los buffers y MEM_DIV=4. Hay reset antes de cada ejecución y las cachés se mantienen entre recorridos.

```sh
make metricas PATRONES=reuso TAMANOS="8 32" DIVISORES=4 CACHES=2 L1_REPL=0 METRICAS_OUT=build/reuso_lru
make metricas PATRONES=reuso TAMANOS="8 32" DIVISORES=4 CACHES=2 L1_REPL=1 METRICAS_OUT=build/reuso_fifo
python3 tools/metricas.py --show docs/resultados/reuso_div4/fifo --compare-to docs/resultados/reuso_div4/lru
```

| KiB | Ciclos LRU | Ciclos FIFO | Aumento FIFO | Fallos LRU | Fallos FIFO |
| --- | --- | --- | --- | --- | --- |
| 8 | 27037 | 29597 | 9.468506 % | 834 | 1154 |
| 32 | 235191 | 275479 | 17.129907 % | 3906 | 5762 |

Las cuatro ejecuciones y sus dieciséis recorridos pasaron las comprobaciones de resultados, trazas e identidad de ciclos. Las parejas coinciden en trabajo del procesador. Un modelo independiente de listas ordenadas reproduce los cuatro contadores de L1 de cada corrida. Se guardan manifiestos, datos globales y por recorrido. Los registros y trazas completos permanecen en `build/reuso_lru` y `build/reuso_fifo`. Sus huellas se conservan en los manifiestos.

LRU conserva mejor A y reduce fallos en este patrón. Con 8 KiB, los fallos adicionales de FIFO se atienden en L2 y no aumentan las lecturas de memoria principal. Con 32 KiB, también cambia el tráfico hacia memoria principal, por lo que la diferencia de ciclos refleja toda la jerarquía. Esto ilustra una ventaja de LRU para esta reutilización concreta, sin establecer superioridad para todos los programas.

Las diez mediciones anteriores permanecen en `../fifo_div4/` y sus referencias LRU en `../div4/`. Este caso se selecciona expresamente con PATRONES=reuso y no modifica la matriz histórica predeterminada. No admite 1 KiB porque necesita al menos tres líneas del mismo conjunto.
