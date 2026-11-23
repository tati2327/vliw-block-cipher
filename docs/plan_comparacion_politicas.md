# Plan de comparación de políticas de caché

## Estado y alcance

La rama `feat/l1-fifo` parte de `develop` limpio en `99528f9`. Los cuatro pasos están completos, sin commits. La rama anterior permanece disponible.

Se agregó FIFO y se conectó `L1_REPL` en ambas instancias de L1, el testbench, Makefile y métricas. Los resultados incluyen `politica_l1` y el ejecutor exige que el registro confirme la política solicitada. Las rutas de los casos conservan su estructura anterior. Cada política debe usar un `METRICAS_OUT` distinto.

La validación del paso 1 pasó las 8367 comprobaciones existentes de L1 y las 11 pruebas Python. Además se verificó el programa secuencial de 1 KiB con FIFO en CACHE=1 y CACHE=2, y con LRU predeterminado en CACHE=2. Esta última ejecución coincide en todas las columnas históricas con el caso equivalente de `docs/resultados/div4/metricas.csv`. Son comprobaciones pequeñas de conexión y compatibilidad, no las diez mediciones de la comparación. Sus archivos temporales están en `/tmp/vliw-paso1-fifo` y `/tmp/vliw-paso1-lru`.

El paso 2 amplió el comprobador de L1 para ejecutar ambas políticas. Conserva los casos específicos de LRU y comprueba la víctima FIFO tras aciertos de lectura y escritura, el avance del orden en reemplazos sucesivos, los datos sucios, las máscaras de bytes, el buffer lleno, las respuestas inmediatas, el tráfico reproducible y el arranque en frío tras reset.

`make tb_l1_cache` terminó con 16686 comprobaciones y cero fallos. `make all` ejecutó los 41 testbenches sin errores ni fallos. `make test_benchmarks` pasó sus 13 pruebas, incluidas dos nuevas sobre separación de políticas y rechazo de registros incorrectos. Durante la regresión se corrigió un problema previo de compilación en `tb/tb_l2_cache.sv`, moviendo la declaración de F antes de la tarea que la usa, sin modificar su valor ni el comportamiento de la prueba. Los registros de validación están en `/tmp/vliw-paso2-l1.log`, `/tmp/vliw-paso2-all.log` y `/tmp/vliw-paso2-python.log`.

El paso 3 ejecutó las diez corridas FIFO y verificó sus cuarenta recorridos. Los registros confirman FIFO y no hubo discrepancias. Los resultados y la comparación global y por recorrido están en `docs/resultados/fifo_div4/`. Los archivos históricos LRU conservan sus huellas. Un modelo independiente de L1 reproduce los cuatro contadores de aciertos y fallos para ambas políticas en las diez trazas.

Nueve casos empatan. Aleatorio de 32 KiB pasa de 2275842 ciclos con LRU a 2276098 con FIFO. Son 32 fallos adicionales de lectura atendidos por L2 y 256 ciclos adicionales, un 0.011249 %. Cada recorrido aporta ocho fallos y 64 ciclos. No cambia el tráfico de memoria principal.

Antes del paso 4 se ajustó la presentación de consola. `--show` muestra solo casos medidos y divide tiempos, tasas, buffers y tráfico en tablas pequeñas. `--compare-to` permite comparar los resultados guardados con otra política bajo las mismas condiciones. La salida FIFO ocupa como máximo 78 columnas y la comparación 77. Las 15 pruebas Python pasan. Los CSV y los resultados históricos permanecen intactos.

```sh
python3 tools/metricas.py --show build/metricas_fifo
python3 tools/metricas.py --show build/metricas_fifo --compare-to docs/resultados/div4
```

Se amplió la medición con `bench_reuso.asm` para observar reutilización con conflictos. El caso adicional se selecciona explícitamente y conserva la matriz original de cinco patrones. Se ejecutaron LRU y FIFO en 8 y 32 KiB con CACHE=2, MEM_DIV=4 y cuatro recorridos. Las cuatro corridas y sus dieciséis recorridos pasaron la validación de resultados, trazas e identidad de ciclos. Un modelo independiente reproduce los contadores de L1 de ambas políticas. Las 17 pruebas Python pasan.

En reutilización de 8 KiB, LRU tarda 27037 ciclos y FIFO 29597, un 9.468506 % más. En 32 KiB, LRU tarda 235191 y FIFO 275479, un 17.129907 % más. La evidencia está en `docs/resultados/reuso_div4/`. Se documentaron el recorrido y sus comandos en `docs/benchmarks_memoria.md`. Este caso dirigido demuestra una ventaja de LRU para esa reutilización y no reemplaza los empates observados en los patrones originales.

El paso 4 actualizó microarquitectura, documentación de L1, simulación, README y rendimiento. El informe incluye doce parejas medidas, explicación de los empates, el caso dirigido y referencias a los datos globales y por recorrido. La documentación conserva LRU por defecto y distingue el selector de L1 del parámetro independiente de L2.

Se comprobaron las cifras del informe contra los CSV, los enlaces locales y los comandos de comparación en consola. El ejemplo FIFO del README pasó `tb_programa` con once comprobaciones y cero fallos. Los resultados LRU anteriores conservan sus huellas. La implementación queda lista para revisión del usuario, sin commits ni publicaciones.

Se agrega FIFO como alternativa a LRU en L1. LRU sigue siendo el valor predeterminado. Se mantienen tamaños, vías, escritura, L2, NINE, buffers y latencias. El parámetro `REPL` de L1 usa 0 para LRU y 1 para FIFO. `L1_REPL` permite seleccionarlo desde top, el testbench, Makefile y el ejecutor de métricas.

## Pasos

1. Completar la selección de política. FIFO actualiza el bit de próxima víctima solo al llenar. LRU lo actualiza también en aciertos. Conectar ambas instancias de L1 en top y comprobar que `L1_REPL=1 make metricas` llega a cada simulación. Los registros y resultados identifican la política por nombre.

2. Agregar pruebas en `tb/tb_l1_cache.sv`. La secuencia A, B, A, C con tres líneas del mismo conjunto debe expulsar B con LRU y A con FIFO. Comprobar conservación de datos y mantener las pruebas existentes de LRU. Ejecutar `make tb_l1_cache`, `make all` y las comprobaciones Python de benchmarks.

3. Ejecutar únicamente las diez mediciones FIFO acordadas. Usar los cinco programas, tamaños de 8 y 32 KiB, CACHE=2, MEM_DIV=4 y cuatro recorridos. Comparar con las filas equivalentes de `docs/resultados/div4/metricas.csv`. Revisar que cada registro indique FIFO y que coincidan programas, entradas y condiciones de medición. No modificar los resultados LRU existentes. Si las condiciones no coinciden, documentar la diferencia antes de interpretar la comparación.

4. Actualizar la documentación y guardar evidencia FIFO bajo `docs/resultados/`. En `docs/microarchitecture.md` actualizar los apartados 1.4, 2.14, 3.14, 3.16, 4.3 y 6. Actualizar también `docs/l1_cache.md`, `docs/simulation.md` y un ejemplo en README. En `docs/rendimiento.md` agregar la subsección «LRU contra FIFO en L1» con tabla y análisis, más una línea en metodología, validación y conclusiones. Explicar las diferencias observadas sin asumir que una política siempre gana.

## Comando de medición

```sh
L1_REPL=1 make metricas TAMANOS="8 32" DIVISORES=4 CACHES=2 METRICAS_OUT=build/metricas_fifo
```

## Entrega

Los comentarios explican el funcionamiento sin referencias a tareas ni secciones del documento. LRU conserva el comportamiento predeterminado y los resultados previos permanecen intactos. La entrega se prepara para revisión mediante PR hacia develop. No se hacen commits, push ni se abre el PR sin una instrucción posterior del usuario.

## Revisión final

Se revisaron la implementación, la propagación de parámetros, las pruebas, el nuevo ensamblador y los resultados documentados. Copias temporales que fuerzan la política equivocada fueron rechazadas por las pruebas de L1. El RTL original volvió a pasar las 16686 comprobaciones. Las catorce corridas se revalidaron con las herramientas finales y el archivo hexadecimal del caso de reutilización coincide con su ensamblador.

Se corrigió la validación de argumentos del ejecutor para que una combinación inválida, como reutilización con 1 KiB, no borre resúmenes previos. Una nueva prueba comprueba esa conservación. Las 17 pruebas Python pasan y la regresión completa de 41 testbenches ya pasó con este RTL. No quedan fallos funcionales identificados en la revisión. La simulación no sustituye una validación de síntesis ni demuestra superioridad de una política en todas las cargas.

Las carpetas nuevas de `docs/resultados/` forman parte de la entrega. `build/` conserva los artefactos temporales y sigue ignorado. No se hicieron commits ni publicaciones.

## Evidencia de entrega

Se retiraron ocho archivos auxiliares que duplicaban las tablas y los registros de build. La entrega conserva los CSV de métricas, recorridos, segmentos, costos y comparación, los manifiestos y las explicaciones de validación. Los reportes de consola se reconstruyen con los comandos documentados. Las comprobaciones independientes se realizaron durante la validación, pero sus tablas auxiliares no forman parte de la entrega.
