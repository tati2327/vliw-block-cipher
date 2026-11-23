# Análisis de rendimiento y validación

## 1. Objetivo

Medir el efecto de L1 y L2 sobre el tiempo de ejecución, la sensibilidad a la
latencia de la memoria principal y la presión sobre los búferes de escritura y
desalojo.

## 2. Metodología

Cada comparación fija el programa, los datos y las cuatro vueltas. Se cambia
`CACHE` o `MEM_DIV`. Los patrones emplean distinto número de instrucciones y
accesos. En particular, el aleatorio también lee índices. Las diferencias de
ciclos entre patrones incluyen ese trabajo.

| Contador | Qué mide |
| --- | --- |
| Ciclos, bundles e instrucciones | Tiempo en ciclos del núcleo, grupos de instrucciones y operaciones contabilizadas |
| Saltos y pausas | Saltos tomados y ciclos de espera de memoria, CRYPTO y pausa total |
| L1 y L2 | Lecturas y escrituras, aciertos, fallos y pausas clasificadas por origen |
| Write buffer y eviction buffer | Líneas recibidas, reenvíos, ocupación máxima y ciclos llenos |
| Memoria principal | Lecturas y escrituras físicas y ciclos de transferencia |

El corte es un `jef 0` válido en ID sin pausa. La identidad comprobada es
`ciclos = bundles + saltos + pausa_total + 2 − EX_anulado`.
[Contadores del procesador y criterio de corte](microarchitecture.md#7-contadores-de-rendimiento).

| Métrica | Cálculo |
| --- | --- |
| IPC | Instrucciones / ciclos |
| Tasa de aciertos y fallos | Aciertos / accesos y 1 − tasa de aciertos. En L2 se usan accesos ya clasificados en la matriz |
| AMAT medido | Pausa de memoria / accesos del núcleo, más un ciclo base para CACHE=1 o 2 |
| AMAT por fórmula | 1 + miss L1 × (8 + miss L2 × Tmem), solo para CACHE=2 |
| Mejora | Ciclos con CACHE=0 / ciclos de la configuración |
| Utilización de memoria | Ciclos de transferencia / ciclos totales |

Fecha: 2026-11-22  
Commit indicado por la referencia local: `e30b725`  
Simulador: Icarus Verilog version 12.0 (stable) ()  

La referencia identifica el commit local. La simulación usó una copia de los
archivos de trabajo con sus fechas de modificación. Los comandos siguientes
reproducen la matriz y los ejercicios en una copia desechable. En la medición se
ejecutaron casos en paralelo con la función `run_case` de `tools/metricas.py`,
que invoca `make sim` y verifica cada corrida. Se empleó una salida independiente
por ejercicio y configuración. `make all` y `make costos_bench` se corrieron
en esa misma copia temporal.

```bash
make metricas DIVISORES=2 METRICAS_OUT=build/metricas_div2
make metricas DIVISORES=4 METRICAS_OUT=build/metricas_div4
make metricas DIVISORES=5 METRICAS_OUT=build/metricas_div5
for ejercicio in ejercicio1 ejercicio2 ejercicio3; do
  for cache in 0 1 2; do
    make sim PROG="$ejercicio" CACHE="$cache" MEM_DIV=4 WAVES=0 OUT="build/${ejercicio}_cache${cache}"
  done
done
make all
make costos_bench
```

## 3. Benchmarks

| Recorrido | Trabajo y localidad |
| --- | --- |
| Secuencial | Lee y suma palabras contiguas. Una línea contiene ocho palabras |
| Stride | Recorre con salto de ocho palabras y cambia el desplazamiento para cubrir todo el arreglo. Separa los usos de una línea |
| Aleatorio | Permuta el orden de las líneas con índices y recorre las posiciones de palabra por fases. Escasa localidad inmediata en los datos |
| Escritura | Escribe secuencialmente el valor previsto para cada vuelta |
| Lectura–modificación–escritura | Lee, incrementa y reescribe cada palabra en orden |

| Arreglo | Relación con la capacidad |
| --- | --- |
| 1 KiB | Cabe en L1 de 4 KiB |
| 8 KiB | Supera L1 y cabe en L2 de 16 KiB |
| 32 KiB | Supera ambas capacidades |

Los ejercicios son factorial, búsqueda en matriz y cifrado por segmentos.
[Diseño de los recorridos](benchmarks_memoria.md).
[Ejercicios del compilador](compiler-integration.md#9-validación-conjunta-62).

## 4. Resultados y análisis

Las razones derivadas se muestran con tres decimales. Las cifras de ciclos y
contadores se conservan íntegras. El guion señala un valor sin denominador o un
contador ausente.

### 4.1 Efecto de la caché con MEM_DIV=4

Cada celda muestra ciclos / IPC / mejora frente a memoria directa.

| Recorrido | KiB | CACHE=0 | CACHE=1 | CACHE=2 |
| --- | --- | --- | --- | --- |
| secuencial | 1 | 58823 / 0.105 / 1.000× | 5929 / 1.042 / 9.921× | 6201 / 0.996 / 9.486× |
| secuencial | 8 | 467399 / 0.105 / 1.000× | 87177 / 0.564 / 5.361× | 54681 / 0.899 / 8.548× |
| secuencial | 32 | 1868231 / 0.105 / 1.000× | 348297 / 0.565 / 5.364× | 349864 / 0.562 / 5.340× |
| stride | 1 | 58984 / 0.107 / 1.000× | 6090 / 1.035 / 9.685× | 6362 / 0.991 / 9.271× |
| stride | 8 | 467560 / 0.105 / 1.000× | 467242 / 0.106 / 1.001× | 112186 / 0.440 / 4.168× |
| stride | 32 | 1868392 / 0.105 / 1.000× | 1868074 / 0.105 / 1.000× | 1832639 / 0.107 / 1.020× |
| aleatorio | 1 | 117352 / 0.080 / 1.000× | 10398 / 0.905 / 11.286× | 10702 / 0.879 / 10.965× |
| aleatorio | 8 | 934504 / 0.079 / 1.000× | 554282 / 0.133 / 1.686× | 154842 / 0.477 / 6.035× |
| aleatorio | 32 | 3736168 / 0.079 / 1.000× | 2216234 / 0.133 / 1.686× | 2275842 / 0.130 / 1.642× |
| escritura | 1 | 58827 / 0.122 / 1.000× | 5933 / 1.214 / 9.915× | 6205 / 1.161 / 9.481× |
| escritura | 8 | 467403 / 0.123 / 1.000× | 107769 / 0.532 / 4.337× | 54685 / 1.049 / 8.547× |
| escritura | 32 | 1868235 / 0.123 / 1.000× | 439545 / 0.522 / 4.250× | 411983 / 0.557 / 4.535× |
| lectura_escritura | 1 | 117191 / 0.079 / 1.000× | 10025 / 0.923 / 11.690× | 10297 / 0.898 / 11.381× |
| lectura_escritura | 8 | 934343 / 0.079 / 1.000× | 119945 / 0.615 / 7.790× | 87449 / 0.843 / 10.684× |
| lectura_escritura | 32 | 3736007 / 0.079 / 1.000× | 479369 / 0.615 / 7.794× | 500986 / 0.589 / 7.457× |

En 1 KiB, la menor mejora con CACHE=2 fue 9.271× en stride y la mayor fue 11.381× en lectura_escritura.

En 8 KiB, la menor mejora con CACHE=2 fue 4.168× en stride y la mayor fue 10.684× en lectura_escritura.

En 32 KiB, la menor mejora con CACHE=2 fue 1.020× en stride y la mayor fue 7.457× en lectura_escritura.

El secuencial reutiliza las ocho palabras de cada línea. En 32 KiB, su tasa de L1 con CACHE=2 fue 0.875 frente a 0.438 del aleatorio. Las lecturas de la tabla de índices contribuyen a los aciertos del aleatorio. [metricas.csv, divisor 4](resultados/div4/metricas.csv).

La única mejora inferior a 1× fue 0.970× en stride de 32 KiB con CACHE=2 y MEM_DIV=2. La tasa de aciertos de L2 fue 0.171. Las consultas de L2 añadieron más espera de la que ahorraron las lecturas evitadas en memoria. El total subió de 1409528 a 1452469 ciclos. [metricas.csv, divisor 2](resultados/div2/metricas.csv).

### 4.2 Efecto del tamaño

Cada celda muestra tasa de L1 / tasa de L2 / ciclos de pausa de memoria con CACHE=2 y MEM_DIV=4.

| Recorrido | 1 KiB | 8 KiB | 32 KiB |
| --- | --- | --- | --- |
| secuencial | 0.967 / 0.000 / 2074 | 0.875 / 0.749 / 21882 | 0.875 / 0.144 / 218761 |
| stride | 0.967 / 0.000 / 2074 | 0.001 / 0.969 / 79226 | 0.000 / 0.171 / 1701375 |
| aleatorio | 0.982 / 0.000 / 2318 | 0.438 / 0.969 / 89114 | 0.438 / 0.120 / 2013506 |
| escritura | 0.967 / 0.000 / 2074 | 0.875 / 0.866 / 21882 | 0.875 / 0.420 / 280876 |
| lectura_escritura | 0.983 / 0.000 / 2074 | 0.937 / 0.866 / 21882 | 0.937 / 0.420 / 238811 |

En el secuencial, la pausa sube de 2074 a 21882 y 218761 ciclos. La capacidad de L1 explica la reutilización del arreglo pequeño. Para 8 KiB, L2 conserva las líneas entre vueltas y resuelve parte de los fallos de L1. Para 32 KiB, la tasa global depende del patrón, incluidos índices y escrituras. [metricas.csv, divisor 4](resultados/div4/metricas.csv).

Secuencial con CACHE=2 en la primera y cuarta vuelta.

| KiB | Vuelta | Hit L1 | Hit L2 | Pausa de memoria |
| --- | --- | --- | --- | --- |
| 1 | 1 | 0.875 | 0.000 | 1952 |
| 1 | 4 | 1.000 | — | 0 |
| 8 | 1 | 0.875 | 0.000 | 15616 |
| 8 | 4 | 0.875 | 1.000 | 2048 |
| 32 | 1 | 0.875 | 0.000 | 62464 |
| 32 | 4 | 0.875 | 0.191 | 52076 |

La separación por vuelta distingue la carga inicial de la reutilización posterior. [recorridos.csv, divisor 4](resultados/div4/recorridos.csv).

### 4.3 Aporte de L2

Ahorro en ciclos al pasar de CACHE=1 a CACHE=2 con MEM_DIV=4. Un valor negativo indica más ciclos con L2.

| Recorrido | 1 KiB | 8 KiB | 32 KiB |
| --- | --- | --- | --- |
| secuencial | -272 | 32496 | -1567 |
| stride | -272 | 355056 | 35435 |
| aleatorio | -304 | 399440 | -59608 |
| escritura | -272 | 53084 | 27562 |
| lectura_escritura | -272 | 32496 | -21617 |

El secuencial pasa de 87177 a 54681 ciclos en 8 KiB. En 1 KiB pasa de 5929 a 6201. Los fallos en frío añaden la consulta de L2 antes de llegar a memoria, mientras que los aciertos posteriores de L1 evitan esa consulta. En 32 KiB, los recorridos de escritura también dependen del tráfico de desalojo y de los búferes. [metricas.csv, divisor 4](resultados/div4/metricas.csv).

### 4.4 Sensibilidad a la latencia de memoria

Cada celda muestra ciclos con MEM_DIV=2 / 4 / 5 y el incremento de 39 a 60 ciclos nominales por transferencia.

| Recorrido | KiB | CACHE=0 | CACHE=1 | CACHE=2 |
| --- | --- | --- | --- | --- |
| secuencial | 1 | 44375 / 58823 / 66047 (+21672) | 5453 / 5929 / 6167 (+714) | 5725 / 6201 / 6439 (+714) |
| secuencial | 8 | 352599 / 467399 / 524799 (+172200) | 72813 / 87177 / 94359 (+21546) | 51069 / 54681 / 56487 (+5418) |
| secuencial | 32 | 1409367 / 1868231 / 2097663 (+688296) | 290925 / 348297 / 376983 (+86058) | 300738 / 349864 / 374427 (+73689) |
| stride | 1 | 44536 / 58984 / 66208 (+21672) | 5614 / 6090 / 6328 (+714) | 5886 / 6362 / 6600 (+714) |
| stride | 8 | 352760 / 467560 / 524960 (+172200) | 352526 / 467242 / 524600 (+172074) | 108574 / 112186 / 113992 (+5418) |
| stride | 32 | 1409528 / 1868392 / 2097824 (+688296) | 1409294 / 1868074 / 2097464 (+688170) | 1452469 / 1832639 / 2022724 (+570255) |
| aleatorio | 1 | 88568 / 117352 / 131744 (+43176) | 9866 / 10398 / 10664 (+798) | 10170 / 10702 / 10968 (+798) |
| aleatorio | 8 | 705016 / 934504 / 1049248 (+344232) | 425230 / 554282 / 618808 (+193578) | 150782 / 154842 / 156872 (+6090) |
| aleatorio | 32 | 2818552 / 3736168 / 4194976 (+1376424) | 1700110 / 2216234 / 2474296 (+774186) | 1821878 / 2275842 / 2502824 (+680946) |
| escritura | 1 | 44379 / 58827 / 66051 (+21672) | 5457 / 5933 / 6171 (+714) | 5729 / 6205 / 6443 (+714) |
| escritura | 8 | 352603 / 467403 / 524803 (+172200) | 80861 / 107769 / 121223 (+40362) | 51073 / 54685 / 56491 (+5418) |
| escritura | 32 | 1409371 / 1868235 / 2097667 (+688296) | 326621 / 439545 / 496007 (+169386) | 315369 / 411983 / 460090 (+144721) |
| lectura_escritura | 1 | 88407 / 117191 / 131583 (+43176) | 9549 / 10025 / 10263 (+714) | 9821 / 10297 / 10535 (+714) |
| lectura_escritura | 8 | 704855 / 934343 / 1049087 (+344232) | 105581 / 119945 / 127127 (+21546) | 83837 / 87449 / 89255 (+5418) |
| lectura_escritura | 32 | 2818391 / 3736007 / 4194815 (+1376424) | 421997 / 479369 / 508055 (+86058) | 443049 / 500986 / 529966 (+86917) |

Para secuencial de 32 KiB, el incremento es 688296 ciclos sin caché y 73689 con la jerarquía. En memoria directa cada acceso paga la latencia. Los aciertos y la reutilización de líneas evitan transferencias en las configuraciones con caché. [metricas.csv, divisor 2](resultados/div2/metricas.csv). [metricas.csv, divisor 4](resultados/div4/metricas.csv). [metricas.csv, divisor 5](resultados/div5/metricas.csv).

### 4.5 AMAT medido y por fórmula

Comparación para CACHE=2 con MEM_DIV=4. Cada celda muestra medido / fórmula.

| Recorrido | 1 KiB | 8 KiB | 32 KiB |
| --- | --- | --- | --- |
| secuencial | 3.010 / 3.010 | 3.669 / 3.669 | 7.674 / 7.674 |
| stride | 3.010 / 3.010 | 10.662 / 10.662 | 52.909 / 52.909 |
| aleatorio | 2.127 / 2.127 | 6.436 / 6.436 | 31.720 / 31.720 |
| escritura | 3.010 / 3.010 | 3.669 / 2.891 | 9.570 / 5.844 |
| lectura_escritura | 2.009 / 2.009 | 2.335 / 1.946 | 4.644 / 3.422 |

El AMAT coincide con la fórmula a tres decimales en los tres recorridos de lectura y en todos los patrones de 1 KiB. La mayor brecha se observa en escritura de 32 KiB, con 9.570 ciclos medidos frente a 5.844 nominales. Hubo 760 ciclos de pausa de L2 por búfer lleno, cero reenvíos y una escritura de L2 sin clasificar al corte. La fórmula combina los aciertos de lectura y escritura de L2 en una sola tasa y omite la contención, el solapamiento y el reenvío. En esta fila, combinar las tasas diluye el costo de traer una línea en un fallo de L1, y la contención aumenta la espera medida. [metricas.csv, divisor 4](resultados/div4/metricas.csv).

### 4.6 Búferes

Filas de mayor tiempo lleno para cada búfer entre todos los divisores. Los contadores de reenvío cuentan líneas servidas desde el búfer.

| Búfer | Recorrido | KiB | CACHE | MEM_DIV | Recibidas | Reenvíos | Máximo | Ciclos lleno |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Write buffer | escritura | 32 | 1 | 2 | 3969 | 0 | 2 | 0 |
| Eviction buffer | escritura | 32 | 2 | 5 | 3325 | 0 | 8 | 10080 |

El write buffer alcanzó 2 de 4 líneas y acumuló cero ciclos lleno. La capacidad observada fue suficiente para estas cargas. [metricas.csv, divisor 2](resultados/div2/metricas.csv). [metricas.csv, divisor 4](resultados/div4/metricas.csv). [metricas.csv, divisor 5](resultados/div5/metricas.csv).

El eviction buffer alcanzó 8 de 8 líneas y se llenó en tres corridas de escritura de 32 KiB, una por divisor. La capacidad permite completar la carga, con episodios de saturación. [metricas.csv, divisor 2](resultados/div2/metricas.csv). [metricas.csv, divisor 4](resultados/div4/metricas.csv). [metricas.csv, divisor 5](resultados/div5/metricas.csv).

### 4.7 Escrituras y desalojos

Con MEM_DIV=4, cada celda muestra desalojos sucios entregados por L1 al write buffer / desalojos sucios entregados por L2 al eviction buffer / escrituras físicas completadas.

| Recorrido | KiB | CACHE=0 | CACHE=1 | CACHE=2 |
| --- | --- | --- | --- | --- |
| escritura | 1 | 0 / 0 / 1028 | 0 / 0 / 0 | 0 / 0 / 0 |
| escritura | 8 | 0 / 0 / 8196 | 897 / 0 / 897 | 897 / 0 / 0 |
| escritura | 32 | 0 / 0 / 32772 | 3969 / 0 / 3969 | 3969 / 3325 / 3325 |
| lectura_escritura | 1 | 0 / 0 / 1028 | 0 / 0 / 0 | 0 / 0 / 0 |
| lectura_escritura | 8 | 0 / 0 / 8196 | 897 / 0 / 897 | 897 / 0 / 0 |
| lectura_escritura | 32 | 0 / 0 / 32772 | 3969 / 0 / 3969 | 3969 / 3325 / 3325 |

Con write-allocate, un store que falla puede necesitar la línea antes de actualizarla. Con write-back, las escrituras se acumulan en líneas sucias y pueden combinarse antes de llegar a la memoria. Para escritura de 32 KiB, se observan 32772 escrituras físicas en acceso directo y 3325 con L2. Son conteos hasta el corte, con 128 líneas sucias de L1 al final. [metricas.csv, divisor 4](resultados/div4/metricas.csv). [costos_escritura.csv, divisor 4](resultados/div4/costos_escritura.csv).

Pausas de stores con CACHE=2 y MEM_DIV=4, agregadas sobre las cuatro vueltas de cada caso. Preparación y cierre quedan fuera.

| Caso | Cantidad | Mínimo | Máximo |
| --- | --- | --- | --- |
| l1_hit | 78816 | 0 | 0 |
| l1_miss_l2 | 1113 | 8 | 8 |
| l1_miss_memoria | 4039 | 61 | 130 |

La latencia de referencia es 8 para acierto en L2 y 61 para fallo con acceso a memoria libre. [costos_escritura.csv, divisor 4](resultados/div4/costos_escritura.csv).

### 4.8 Ejercicios del compilador

MEM_DIV=4. Las tasas son fracciones y el AMAT se expresa en ciclos. El testbench imprime AMAT para CACHE=2.

| Ejercicio | CACHE | Ciclos | IPC | Hit L1 | Hit L2 | AMAT medido | AMAT fórmula |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 0 | 2562 | 0.065 | — | — | — | — |
| 1 | 1 | 389 | 0.429 | 0.932 | — | — | — |
| 1 | 2 | 413 | 0.404 | 0.932 | 0.000 | 5.159 | 5.159 |
| 2 | 0 | 5682 | 0.051 | — | — | — | — |
| 2 | 1 | 647 | 0.448 | 0.950 | — | — | — |
| 2 | 2 | 687 | 0.422 | 0.950 | 0.000 | 4.050 | 4.050 |
| 3 | 0 | 139832 | 0.100 | — | — | — | — |
| 3 | 1 | 23642 | 0.591 | 0.947 | — | — | — |
| 3 | 2 | 23682 | 0.590 | 0.947 | 0.272 | 3.849 | 3.435 |

Los ejercicios 1 y 2 compararon la memoria esperada. El ejercicio 3 carece de `.exp.mem` y esta corrida verifica el monitor y los controles del testbench. [Contadores y trazas por ejercicio](resultados/ejercicios.md).

El ejercicio 3 pasa de 139832 ciclos con memoria directa a 23642 con L1 y 23682 con L2. La tabla de detalle permite comparar las pausas de memoria y CRYPTO para ese mismo programa. [Ejercicio 3](resultados/ejercicios.md#ejercicio-3).

En el ejercicio 3 con CACHE=2, L2 aceptó 122 lecturas y 25 escrituras. Clasificó 122 lecturas y 24 escrituras al corte. La solicitud de escritura restante explica que las tasas impresas (0.272109 y 0.721088) sumen menos de 1. La matriz calcula sus tasas con solicitudes ya clasificadas. [Contadores del ejercicio 3](resultados/ejercicios.md#ejercicio-3).

## 5. Validación

- `make all` terminó con código 0 y ejecutó 41 testbenches. [Salida completa](resultados/make_all.log).
- Se verificaron las 135 corridas de la matriz, 45 por divisor, y los 9 ejercicios. Todas cumplieron la identidad de ciclos y registraron cero discrepancias del monitor. [metricas.csv, divisor 2](resultados/div2/metricas.csv). [metricas.csv, divisor 4](resultados/div4/metricas.csv). [metricas.csv, divisor 5](resultados/div5/metricas.csv). [Ejercicios](resultados/ejercicios.md).
- Las 135 corridas comprobaron las palabras de resultado, secuencia de transacciones, datos escritos físicamente y reconstrucción de segmentos. En los ejercicios, la comparación contra `.exp.mem` pasó en las seis corridas de los ejercicios 1 y 2. [Ejercicios](resultados/ejercicios.md).
- En cada corrida con L1, sus pausas por origen más las pendientes coincidieron con la pausa de memoria del núcleo. [metricas.csv, divisor 2](resultados/div2/metricas.csv). [metricas.csv, divisor 4](resultados/div4/metricas.csv). [metricas.csv, divisor 5](resultados/div5/metricas.csv). [Ejercicios](resultados/ejercicios.md).
- `make costos_bench` pasó los casos controlados de L1 y memoria directa. La matriz clasifica los stores por origen. Los aciertos de escritura en L1 tienen cero ciclos de pausa. Para L2, 8 ciclos con acierto y 8 + Tmem con fallo son referencias nominales del acceso sin contención. Los mínimos y máximos observados incluyen el estado de la jerarquía. [Pruebas controladas](resultados/costos_bench.log). [costos_escritura.csv, divisor 4](resultados/div4/costos_escritura.csv).

[Resultados de los casos controlados por divisor](resultados/costos_controlados.csv).

[Registro de validación](resultados/validacion.md).

## 6. Limitaciones

Se midió un núcleo y una política fija por nivel, con búferes de 4 y 8 líneas.
La simulación no mide frecuencia máxima, área ni potencia. Al llegar a `jef 0`
pueden quedar datos sucios, transferencias en curso y solicitudes de L2 por
clasificar. Los resultados de memoria se observan desde el testbench con el
estado disponible en ese corte. Las escrituras físicas contabilizadas cubren
las transferencias completadas hasta ese instante.

## 7. Conclusiones

- La jerarquía reduce el secuencial de 8 KiB de 467399 a 54681 ciclos con MEM_DIV=4. [metricas.csv, divisor 4](resultados/div4/metricas.csv).
- En secuencial de 1 KiB, incorporar L2 añade 272 ciclos frente a L1. En 8 KiB ahorra 32496. [metricas.csv, divisor 4](resultados/div4/metricas.csv).
- En aleatorio de 32 KiB con L2, la tasa de L1 es 0.438 y la de L2 es 0.120. [metricas.csv, divisor 4](resultados/div4/metricas.csv).
- Al aumentar la latencia de 39 a 60 ciclos, el secuencial de 32 KiB tarda 688296 ciclos más en acceso directo y 73689 más con L2. [metricas.csv, divisor 2](resultados/div2/metricas.csv). [metricas.csv, divisor 5](resultados/div5/metricas.csv).
- Los búferes registraron hasta 2 líneas en el write buffer y 8 en el de desalojo. [metricas.csv, divisor 2](resultados/div2/metricas.csv). [metricas.csv, divisor 4](resultados/div4/metricas.csv). [metricas.csv, divisor 5](resultados/div5/metricas.csv).
- Las 135 corridas de matriz y los 9 ejercicios cumplieron la identidad de ciclos con cero discrepancias. [metricas.csv, divisor 2](resultados/div2/metricas.csv). [metricas.csv, divisor 4](resultados/div4/metricas.csv). [metricas.csv, divisor 5](resultados/div5/metricas.csv). [Ejercicios](resultados/ejercicios.md).
