# Validación de FIFO y comparación con LRU

Fecha 2026-11-22. Base `99528f9` con cambios locales de FIFO sin commit. La referencia LRU corresponde a `e30b725`.

Se ejecutaron los cinco programas de 8 y 32 KiB con CACHE=2, MEM_DIV=4 y cuatro recorridos. L1 usa FIFO y L2 conserva LFSR con semilla 0xA5. Las cachés empiezan vacías y se conservan entre recorridos.

```sh
L1_REPL=1 make metricas TAMANOS="8 32" DIVISORES=4 CACHES=2 METRICAS_OUT=build/metricas_fifo
```

Las diez corridas y sus cuarenta recorridos pasaron las comprobaciones de datos, trazas, contadores e identidad de ciclos. Cada registro confirma FIFO. Se verificaron las huellas del ensamblador y las entradas contra los archivos ejecutados. Los manifiestos guardan la semilla del generador de datos, que es distinta de la semilla LFSR de L2.

Los componentes originales de RTL, ensamblador, generador de datos, programas y medición coinciden entre la base histórica y HEAD. Los cambios locales introducen la política seleccionable y su identificación. Cada pareja mantiene instrucciones, bundles, saltos y accesos del procesador. Los archivos LRU existentes conservan sus huellas SHA-256.

Un modelo independiente reprodujo las direcciones de cada traza con LRU y FIFO. Sus cuatro contadores de aciertos y fallos de lectura y escritura coinciden con los resultados de cada política.

Nueve casos empatan en todas las métricas históricas. En aleatorio de 32 KiB, FIFO tiene 32 fallos adicionales de lectura en L1. Las 32 lecturas adicionales aciertan en L2 y cuestan ocho ciclos cada una, sumando 256 ciclos. No cambia el tráfico de memoria principal. Cada recorrido aporta ocho fallos y 64 ciclos adicionales. El empate de los otros patrones no implica equivalencia general entre políticas.

Un delta positivo significa que FIFO tarda más ciclos que LRU. Uno negativo significa que tarda menos. El porcentaje usa los ciclos LRU como referencia. La tabla global incluye preparación y cierre, además de los cuatro recorridos. `comparacion_recorridos.csv` separa cada recorrido.

| Programa | KiB | Ciclos LRU | Ciclos FIFO | Diferencia de ciclos | Cambio porcentual |
| --- | --- | --- | --- | --- | --- |
| secuencial | 8 | 54681 | 54681 | 0 | 0.000000 % |
| secuencial | 32 | 349864 | 349864 | 0 | 0.000000 % |
| stride | 8 | 112186 | 112186 | 0 | 0.000000 % |
| stride | 32 | 1832639 | 1832639 | 0 | 0.000000 % |
| aleatorio | 8 | 154842 | 154842 | 0 | 0.000000 % |
| aleatorio | 32 | 2275842 | 2276098 | 256 | 0.011249 % |
| escritura | 8 | 54685 | 54685 | 0 | 0.000000 % |
| escritura | 32 | 411983 | 411983 | 0 | 0.000000 % |
| lectura_escritura | 8 | 87449 | 87449 | 0 | 0.000000 % |
| lectura_escritura | 32 | 500986 | 500986 | 0 | 0.000000 % |

Los resultados originales y por recorrido están en `metricas.csv`, `recorridos.csv`, `segmentos.csv` y `costos_escritura.csv`. `comparacion.csv` reúne ambas políticas y sus diferencias. Los registros completos permanecen en `build/metricas_fifo`. `manifiestos.json` conserva sus huellas y las condiciones de ejecución. Las trazas completas permanecen en `build/metricas_fifo` y no se duplican en la documentación.
