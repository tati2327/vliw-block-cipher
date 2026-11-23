# Análisis de rendimiento y validación

## 1. Objetivo

Medir el efecto de L1 y L2 sobre el tiempo de ejecución, la sensibilidad a la
latencia de la memoria principal y la presión sobre el write buffer y el
eviction buffer.

## 2. Metodología

Cada comparación fija el programa, los datos y las cuatro vueltas. Se cambia
`CACHE` o `MEM_DIV`. La comparación adicional de reemplazo cambia solo `L1_REPL`, con CACHE=2, MEM_DIV=4 y cuatro vueltas. LRU sigue por defecto. Los patrones emplean distinto número de instrucciones y
accesos. En particular, el aleatorio también lee índices. Las diferencias de
ciclos entre patrones incluyen ese trabajo.

| Contador | Qué mide |
| --- | --- |
| Ciclos, bundles e instrucciones | Tiempo en ciclos del núcleo, grupos de instrucciones y operaciones contabilizadas |
| Saltos y pausas | Saltos tomados y ciclos de espera de memoria, CRYPTO y pausa total |
| L1 y L2 | Lecturas y escrituras, aciertos, fallos y pausas clasificadas por origen |
| Write buffer y eviction buffer | Líneas recibidas, forwarding, ocupación máxima y ciclos llenos |
| Memoria principal | Lecturas y escrituras físicas y ciclos de transferencia |

El corte es un `jef 0` válido en ID sin pausa. La identidad comprobada es
`ciclos = bundles + saltos + pausa_total + 2 − EX_anulado`.
[Contadores del procesador y criterio de corte](microarchitecture.md#5-medición-y-verificación).

| Métrica | Cálculo |
| --- | --- |
| IPC | Instrucciones / ciclos |
| Tasa de aciertos y fallos | Aciertos / accesos y 1 − tasa de aciertos. En L2 se usan accesos ya clasificados en la matriz |
| AMAT medido | Pausa de memoria / accesos del núcleo, más un ciclo base para CACHE=1 o 2 |
| AMAT por fórmula | 1 + miss L1 × (8 + miss L2 × Tmem), solo para CACHE=2 |
| Mejora | Ciclos con CACHE=0 / ciclos de la configuración |
| Utilización de memoria | Ciclos de transferencia / ciclos totales |

Fecha: 2026-11-22  
Commit: `e30b725`  
Simulador: Icarus Verilog version 12.0 (stable)  

Las mediciones de la matriz y de los ejercicios corresponden al commit
`e30b725`. Los casos de la matriz se corrieron en paralelo con `run_case` de
`tools/metricas.py`, que invoca `make sim` y verifica cada corrida. Los comandos
mostrados son su equivalente en serie.

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

El secuencial pasa de 87177 a 54681 ciclos en 8 KiB. En 1 KiB pasa de 5929 a 6201. Los fallos en frío añaden la consulta de L2 antes de llegar a memoria, mientras que los aciertos posteriores de L1 evitan esa consulta. En 32 KiB, los recorridos de escritura también dependen del tráfico de desalojo y de los buffers. [metricas.csv, divisor 4](resultados/div4/metricas.csv).

En stride de 8 KiB, CACHE=0 tarda 467560 ciclos, CACHE=1 tarda 467242
(1.001×) y CACHE=2 tarda 112186 (4.168×). El stride lee una palabra por línea
en cada fase y vuelve a esa línea después de recorrer todo el arreglo. Los
8 KiB no caben en L1 de 4 KiB: al regresar, la línea ya fue reemplazada y la
tasa de acierto es apenas 0.001. Sin L2 cada fallo paga Tmem completo. El
arreglo sí cabe en L2 de 16 KiB, cuya tasa de acierto es 0.969, y esos aciertos
resuelven los fallos de L1 en 8 ciclos. En aleatorio de 8 KiB, CACHE=1 tarda
554282 ciclos (1.686×) y CACHE=2 tarda 154842 (6.035×), frente a 934504 sin
caché. El mismo efecto aparece en menor medida en L1 porque las lecturas de
la tabla de índices sí aciertan allí. [Datos](resultados/div4/metricas.csv).

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

El AMAT coincide con la fórmula a tres decimales en los tres recorridos de
lectura y en todos los patrones de 1 KiB. Las cuatro diferencias aparecen al
escribir. La columna adicional recalcula
`1 + m_L1 · (8 + (1 − hits_lectura_L2 / lecturas_L2) · 53)` con los contadores
del CSV, donde `m_L1` conserva la tasa de fallos combinada de L1.

| Recorrido | KiB | Medido | Fórmula | Fórmula con tasa L2 solo de lecturas |
| --- | --- | --- | --- | --- |
| escritura | 8 | 3.669 | 2.891 | 3.669 |
| lectura_escritura | 8 | 2.335 | 1.946 | 2.335 |
| escritura | 32 | 9.570 | 5.844 | 8.069 |
| lectura_escritura | 32 | 4.644 | 3.422 | 4.535 |

La fórmula original mezcla lecturas de L2 (llenados de L1 que detienen el
pipeline) con escrituras de L2 (drenajes del write buffer que no lo detienen
directamente). En ambos casos de 8 KiB, L2 clasificó 896 aciertos de escritura
de 897 solicitudes aceptadas; la última escritura seguía sin clasificar al
corte. Los aciertos de escritura elevan la tasa combinada sobre operaciones
clasificadas a 0.866, frente a 0.749 en lecturas (768 de 1026). Con la tasa de
lecturas, la fórmula coincide con la medición.

En 32 KiB queda una diferencia aun usando solo lecturas: 8.069 frente a 9.570
en escritura y 4.535 frente a 4.644 en lectura–modificación–escritura. La
memoria también atiende 3325 escrituras de desalojo por caso; la contención
hace esperar algunos llenados. El máximo observado de un store con fallo fue
130 ciclos frente a 61 nominales. En escritura, el eviction buffer estuvo
lleno 7574 ciclos y L2 se detuvo 760 ciclos por esa causa.
[Contadores](resultados/div4/metricas.csv).
[Latencias de stores](resultados/div4/costos_escritura.csv).

### 4.6 Buffers

El write buffer alcanzó una ocupación máxima de 2 de 4 líneas y nunca estuvo
lleno en las 135 corridas. Para el eviction buffer se muestra la fila de mayor
tiempo lleno entre los tres divisores. Los contadores de forwarding cuentan
líneas servidas desde el buffer.

| Buffer | Recorrido | KiB | CACHE | MEM_DIV | Recibidas | Forwarding | Máximo | Ciclos lleno |
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

### 4.9 Efecto de las optimizaciones del compilador

Se midieron ocho programas de ccom `96bd97a` en `-O0`, `-O1` y `-O2`, con
MEM_DIV=4 y CACHE=0, 1 y 2. Son 72 corridas; no incluyen ejercicio3. Las
reducciones usan como referencia O0 del mismo programa y CACHE. Los ciclos
proceden del procesador. [Contadores y validación](resultados/optimizaciones.md).
[CSV de las 72 corridas](resultados/optimizaciones.csv).

| Programa | Nivel | Ciclos CACHE=0 | Ciclos CACHE=2 | Reducción CACHE=0 | Reducción CACHE=2 |
| --- | --- | --- | --- | --- | --- |
| test1 | -O0 | 22925 | 5316 | — | — |
| test1 | -O1 | 19746 | 5052 | 13.867% | 4.966% |
| test1 | -O2 | 18321 | 5066 | 20.083% | 4.703% |
| test2 | -O0 | 5919 | 598 | — | — |
| test2 | -O1 | 5191 | 506 | 12.299% | 15.385% |
| test2 | -O2 | 3201 | 424 | 45.920% | 29.097% |
| test3 | -O0 | 23655 | 5834 | — | — |
| test3 | -O1 | 21967 | 5577 | 7.136% | 4.405% |
| test3 | -O2 | 16390 | 5300 | 30.712% | 9.153% |
| test4 | -O0 | 7272 | 732 | — | — |
| test4 | -O1 | 6472 | 568 | 11.001% | 22.404% |
| test4 | -O2 | 4742 | 428 | 34.791% | 41.530% |
| test5 | -O0 | 12987 | 1428 | — | — |
| test5 | -O1 | 11656 | 1157 | 10.249% | 18.978% |
| test5 | -O2 | 8026 | 919 | 38.200% | 35.644% |
| test6 | -O0 | 5976 | 557 | — | — |
| test6 | -O1 | 5507 | 451 | 7.848% | 19.031% |
| test6 | -O2 | 5390 | 440 | 9.806% | 21.005% |
| ejercicio1 | -O0 | 2562 | 413 | — | — |
| ejercicio1 | -O1 | 2449 | 406 | 4.411% | 1.695% |
| ejercicio1 | -O2 | 2444 | 401 | 4.606% | 2.906% |
| ejercicio2 | -O0 | 5682 | 687 | — | — |
| ejercicio2 | -O1 | 4918 | 559 | 13.446% | 18.632% |
| ejercicio2 | -O2 | 4912 | 553 | 13.552% | 19.505% |

En O1, la reducción está entre 4.411% y 13.867% sin caché, y entre 1.695% y
22.404% con CACHE=2. En O2, los intervalos son 4.606%–45.920% y
2.906%–41.530%, respectivamente. CACHE=1 sigue la misma tendencia: O1 reduce
1.799%–23.429% y O2 reduce 3.085%–43.429%.
[Reducciones por configuración](resultados/optimizaciones.md#comparaciones-entre-niveles).

La siguiente comparación muestra O0 → O1 → O2. Las instrucciones y los accesos
son iguales para las tres configuraciones de cada versión; los accesos se
muestran desde los contadores de L1 con CACHE=2.

| Programa | Instrucciones | Accesos L1 | Pausa memoria CACHE=0 | Pausa memoria CACHE=2 |
| --- | --- | --- | --- | --- |
| test1 | 4031 → 3858 → 3824 | 338 → 283 → 257 | 17914 → 14999 → 13621 | 305 → 305 → 366 |
| test2 | 259 → 190 → 136 | 105 → 93 → 57 | 5565 → 4929 → 3021 | 244 → 244 → 244 |
| test3 | 4467 → 4248 → 4088 | 342 → 315 → 215 | 18126 → 16695 → 11395 | 305 → 305 → 305 |
| test4 | 367 → 255 → 201 | 128 → 116 → 86 | 6784 → 6148 → 4558 | 244 → 244 → 244 |
| test5 | 813 → 627 → 539 | 225 → 205 → 141 | 11925 → 10865 → 7473 | 366 → 366 → 366 |
| test6 | 206 → 181 → 179 | 108 → 100 → 98 | 5724 → 5300 → 5194 | 305 → 244 → 244 |
| ejercicio1 | 167 → 161 → 161 | 44 → 42 → 42 | 2332 → 2226 → 2226 | 183 → 183 → 183 |
| ejercicio2 | 290 → 198 → 198 | 100 → 88 → 88 | 5300 → 4664 → 4664 | 305 → 305 → 305 |

Sin caché, reducir accesos reduce directamente la pausa: en test3 los accesos
bajan de 342 a 315 y 215, y la pausa de 18126 a 16695 y 11395 ciclos. Con
CACHE=2, esos mismos niveles mantienen 305 ciclos de pausa y las instrucciones
bajan de 4467 a 4248 y 4088. Así, con caché pesa más reducir el trabajo del
núcleo. En ejercicio1, O1 y O2 ejecutan las mismas 161 instrucciones y los
mismos 42 accesos; O2 baja de 191 a 186 bundles dinámicos y de 406 a 401 ciclos
con CACHE=2, sin cambiar los 183 ciclos de pausa.

El beneficio porcentual no es siempre mayor sin caché. Para O1 lo es en test1,
test3 y ejercicio1; para O2 también en test2 y test5. En test4 ocurre lo
contrario: O2 reduce 34.791% sin caché y 41.530% con CACHE=2, pues las
instrucciones bajan de 367 a 201 mientras la pausa con caché permanece en 244.
En test6, O1 baja la pausa con CACHE=2 de 305 a 244 ciclos al pasar de cinco a
cuatro fallos fríos, y reduce los ciclos 19.031%, frente a 7.848% sin caché.

Hay un retroceso de O2 frente a O1 en test1 con caché: 5052 → 5066 ciclos con
CACHE=2 y 5012 → 5018 con CACHE=1. Aunque reduce los accesos de 283 a 257,
produce seis fallos fríos frente a cinco, elevando la pausa de 305 a 366 con
L2 (de 265 a 318 con L1). Su código también crece de 174 a 328 bundles
estáticos; en test2 crece de 79 a 218 y en test3 de 246 a 302, aunque estos
dos programas sí reducen ciclos. Ninguna versión aumenta los accesos respecto
de O0 ni de O1. [Tamaño estático y contadores](resultados/optimizaciones.md).

Estos programas tienen pocos datos y caben en L1. Todos los fallos de L2 son
fríos y no hay aciertos en L2; CACHE=2 añade de 24 a 48 ciclos frente a
CACHE=1, ocho por fallo de L1. Por ello sus tiempos son cercanos. La conducta
con datos grandes se estudia en §4.1 a §4.7.

### 4.10 LRU contra FIFO en L1

Se compararon los cinco patrones de 8 y 32 KiB con LRU y FIFO. Se reutilizaron las filas LRU de la matriz original y se ejecutaron diez corridas FIFO. También se agregó un caso dirigido de reutilización con conflictos, ejecutado con ambas políticas. Se mantuvieron capacidades, vías, escritura, L2, NINE, buffers y latencia. Las nuevas corridas parten de `99528f9` con cambios locales de FIFO. Los manifiestos guardan las condiciones y huellas de los archivos utilizados.

La tabla muestra ciclos globales, incluidos preparación y cierre. El cambio es `(FIFO − LRU) / LRU × 100`. Un valor positivo indica que FIFO tarda más. Los resultados por recorrido se conservan en los CSV enlazados.

| Recorrido | KiB | Ciclos LRU | Ciclos FIFO | Cambio FIFO |
| --- | --- | --- | --- | --- |
| secuencial | 8 | 54681 | 54681 | +0.000000 % |
| secuencial | 32 | 349864 | 349864 | +0.000000 % |
| stride | 8 | 112186 | 112186 | +0.000000 % |
| stride | 32 | 1832639 | 1832639 | +0.000000 % |
| aleatorio | 8 | 154842 | 154842 | +0.000000 % |
| aleatorio | 32 | 2275842 | 2276098 | +0.011249 % |
| escritura | 8 | 54685 | 54685 | +0.000000 % |
| escritura | 32 | 411983 | 411983 | +0.000000 % |
| lectura_escritura | 8 | 87449 | 87449 | +0.000000 % |
| lectura_escritura | 32 | 500986 | 500986 | +0.000000 % |
| reuso con conflictos | 8 | 27037 | 29597 | +9.468506 % |
| reuso con conflictos | 32 | 235191 | 275479 | +17.129907 % |

Nueve casos originales empatan. Su orden de uso ofrece poca diferencia de reutilización para las víctimas seleccionadas. En aleatorio de 32 KiB, FIFO añade 32 fallos de L1 atendidos con acierto en L2, de ocho ciclos cada uno. Son 256 ciclos adicionales y ocho fallos por recorrido. No aumenta el tráfico de memoria principal. El empate de los otros patrones no significa que las políticas sean equivalentes. [Datos originales y comparación](resultados/fifo_div4/validacion.md).

El caso de reutilización alterna una línea caliente A con líneas B, C, D y las siguientes del mismo conjunto. LRU conserva A por su uso frecuente, mientras FIFO puede expulsarla por su antigüedad de entrada. En 8 KiB, FIFO registra 1154 fallos frente a 834 de LRU y tarda un 9.469 % más. Las 320 lecturas adicionales aciertan en L2. En 32 KiB registra 5762 fallos frente a 3906 y tarda un 17.130 % más. Las lecturas de memoria principal también aumentan, de 3316 a 3796. El costo depende de toda la jerarquía, no solo del número de fallos de L1. [Datos y condiciones del caso dirigido](resultados/reuso_div4/validacion.md).

Este experimento demuestra una ventaja de LRU para reutilización frecuente con conflictos. No demuestra superioridad en todas las cargas ni mide diferencias de área, potencia o frecuencia. El caso dirigido lee la primera palabra de cada línea, con 384 y 1920 accesos por recorrido para regiones de 8 y 32 KiB. Sus tiempos solo se comparan entre políticas del mismo caso.

Para mostrar ambas comparaciones sin repetir las simulaciones

```sh
python3 tools/metricas.py --show docs/resultados/fifo_div4 --compare-to docs/resultados/div4
python3 tools/metricas.py --show docs/resultados/reuso_div4/fifo --compare-to docs/resultados/reuso_div4/lru
```

[Comandos para reproducir las mediciones](simulation.md#seleccionar-lru-o-fifo-y-consultar-resultados).

## 5. Validación

- La ampliación de políticas pasó 14 corridas nuevas y sus 56 recorridos, sin discrepancias y con identidad de ciclos correcta. Un modelo independiente reproduce los contadores de L1. `make tb_l1_cache` pasó 16686 comprobaciones, `make all` pasó 41 testbenches y las 17 pruebas Python pasaron. [Evidencia de FIFO](resultados/fifo_div4/validacion.md). [Evidencia de reutilización](resultados/reuso_div4/validacion.md).
- Las 72 corridas por nivel de optimización terminaron con PASS, identidad correcta y cero discrepancias del monitor. Todas las variables de `info.txt` coincidieron en las tres configuraciones: 999 palabras comprobadas, incluidos arreglos y ámbitos de función. [Validación](resultados/optimizaciones.md#validación).
- `make all` terminó con código 0 y ejecutó 41 testbenches. [Salida completa](resultados/make_all.log).
- Se verificaron las 135 corridas de la matriz, 45 por divisor, y los 9 ejercicios. Todas cumplieron la identidad de ciclos y registraron cero discrepancias del monitor. [metricas.csv, divisor 2](resultados/div2/metricas.csv). [metricas.csv, divisor 4](resultados/div4/metricas.csv). [metricas.csv, divisor 5](resultados/div5/metricas.csv). [Ejercicios](resultados/ejercicios.md).
- Las 135 corridas comprobaron las palabras de resultado, secuencia de transacciones, datos escritos físicamente y reconstrucción de segmentos. En los ejercicios, la comparación contra `.exp.mem` pasó en las seis corridas de los ejercicios 1 y 2. [Ejercicios](resultados/ejercicios.md).
- En cada corrida con L1, sus pausas por origen más las pendientes coincidieron con la pausa de memoria del núcleo. [metricas.csv, divisor 2](resultados/div2/metricas.csv). [metricas.csv, divisor 4](resultados/div4/metricas.csv). [metricas.csv, divisor 5](resultados/div5/metricas.csv). [Ejercicios](resultados/ejercicios.md).
- `make costos_bench` pasó los casos controlados de L1 y memoria directa. La matriz clasifica los stores por origen. Los aciertos de escritura en L1 tienen cero ciclos de pausa. Para L2, 8 ciclos con acierto y 8 + Tmem con fallo son referencias nominales del acceso sin contención. Los mínimos y máximos observados incluyen el estado de la jerarquía. [Pruebas controladas](resultados/costos_bench.log). [costos_escritura.csv, divisor 4](resultados/div4/costos_escritura.csv).

[Resultados de los casos controlados por divisor](resultados/costos_controlados.csv).

[Registro de validación](resultados/validacion.md).

## 6. Limitaciones

Se midió un núcleo con LRU y FIFO seleccionables en L1, LFSR fijo en L2 y buffers de 4 y 8 líneas. La comparación de reemplazo fija CACHE=2 y MEM_DIV=4, y el caso de reutilización es una carga dirigida.
La simulación no mide frecuencia máxima, área ni potencia. Al llegar a `jef 0`
pueden quedar datos sucios, transferencias en curso y solicitudes de L2 por
clasificar. Los resultados de memoria se observan desde el testbench con el
estado disponible en ese corte. Las escrituras físicas contabilizadas cubren
las transferencias completadas hasta ese instante.

## 7. Conclusiones

- LRU y FIFO empatan en nueve casos originales. FIFO tarda un 0.011249 % más en aleatorio de 32 KiB y un 9.469 % y un 17.130 % más en reutilización con conflictos de 8 y 32 KiB. La ventaja de LRU depende del patrón de acceso. [Comparación](#410-lru-contra-fifo-en-l1).
- La jerarquía reduce el secuencial de 8 KiB de 467399 a 54681 ciclos con MEM_DIV=4. [metricas.csv, divisor 4](resultados/div4/metricas.csv).
- En secuencial de 1 KiB, incorporar L2 añade 272 ciclos frente a L1. En 8 KiB ahorra 32496. [metricas.csv, divisor 4](resultados/div4/metricas.csv).
- En aleatorio de 32 KiB con L2, la tasa de L1 es 0.438 y la de L2 es 0.120. [metricas.csv, divisor 4](resultados/div4/metricas.csv).
- Al aumentar la latencia de 39 a 60 ciclos, el secuencial de 32 KiB tarda 688296 ciclos más en acceso directo y 73689 más con L2. [metricas.csv, divisor 2](resultados/div2/metricas.csv). [metricas.csv, divisor 5](resultados/div5/metricas.csv).
- Los buffers registraron hasta 2 líneas en el write buffer y 8 en el eviction buffer. [metricas.csv, divisor 2](resultados/div2/metricas.csv). [metricas.csv, divisor 4](resultados/div4/metricas.csv). [metricas.csv, divisor 5](resultados/div5/metricas.csv).
- Las 135 corridas de matriz y los 9 ejercicios cumplieron la identidad de ciclos con cero discrepancias. [metricas.csv, divisor 2](resultados/div2/metricas.csv). [metricas.csv, divisor 4](resultados/div4/metricas.csv). [metricas.csv, divisor 5](resultados/div5/metricas.csv). [Ejercicios](resultados/ejercicios.md).
- En stride de 8 KiB, L1 apenas cambia 467560 a 467242 ciclos (1.001×), mientras L2 baja a 112186 (4.168×); en aleatorio de 8 KiB la mejora pasa de 1.686× a 6.035×. La capacidad de L2 conserva las líneas que L1 reemplaza entre fases. [Datos](resultados/div4/metricas.csv).
- O2 reduce los ciclos frente a O0 entre 4.606% y 45.920% sin caché y entre 2.906% y 41.530% con L2. El beneficio combina menos instrucciones y accesos; con L1 predomina el trabajo del núcleo cuando no cambia la pausa fría. [Optimizaciones](resultados/optimizaciones.md).
- Optimizar no garantiza una mejora entre niveles: test1 con CACHE=2 pasa de 5052 ciclos en O1 a 5066 en O2 porque añade un fallo frío, pese a reducir instrucciones y accesos. [Optimizaciones](resultados/optimizaciones.csv).
