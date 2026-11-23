# Diseño de los programas de prueba de memoria

Este documento define los recorridos, los datos de entrada y los resultados
esperados, y registra el avance de su implementación. La jerarquía integrada admite `CACHE=0` (memoria directa), `CACHE=1`
(L1 y write buffer) y `CACHE=2` (L1, write buffer, L2 y eviction buffer).
`make sim` usa `CACHE=2` por defecto.

## Métricas de la jerarquía completa

`make metricas DIVISORES=4 CACHES="0 1 2"` ejecuta 45 combinaciones de los cinco
programas y tamaños de 1, 8 y 32 KiB. Sin limitar divisores ejecuta 135.
El límite de ciclos sigue siendo configurable y `WAVES=0` evita generar ondas
durante la matriz. `WAVE_FILE` conserva la ruta seleccionada por `make sim`.

| Columnas | Significado |
|---|---|
| `l2_lecturas`, `l2_escrituras` | Solicitudes contadas por L2; las escrituras vienen del write buffer |
| `l2_hits_lectura`, `l2_misses_lectura`, `l2_hits_escritura`, `l2_misses_escritura` | Aciertos y fallos separados por operación |
| `l2_hit_rate`, `l2_miss_rate` | Tasas de L2 sobre lecturas y escrituras ya clasificadas |
| `l2_pausa_lleno` | Pausas de L2 por eviction buffer lleno |
| `ebuf_recibidas`, `ebuf_forwarding`, `ebuf_ciclos_lleno` | Contadores aditivos del eviction buffer |
| `ebuf_max`, `ebuf_inicio`, `ebuf_fin` | Máximo observado durante el intervalo y ocupación en sus límites |
| `amat_medido` | `1 + pausa_memoria/accesos_cpu` con caché; `pausa_memoria/accesos_cpu` sin caché |
| `amat_formula` | `1 + miss_L1 * (8 + miss_L2 * (25 + 7*MEM_DIV))`, solo con `CACHE=2` |
| `l2_lecturas_pendientes_inicio/fin`, `l2_escrituras_pendientes_inicio/fin` | Solicitudes aceptadas que todavía no completaron la clasificación hit/miss |
| `ex_anulado` | Estado de EX en el corte, usado en la identidad global `ciclos = bundles + saltos + pausa_total + 2 - ex_anulado` |

L2 cuenta solicitudes al aceptarlas y clasifica acierto o fallo ocho ciclos
después. La validación reconstruye las clasificaciones pendientes por operación
y exige que haya como máximo una entre lecturas y escrituras. Por intervalo se
cumple `aceptadas = hits + misses + pendientes_fin - pendientes_inicio`. Las
tasas de L2 usan `hits + misses` como denominador; así no clasifican una solicitud
pendiente como fallo ni mezclan intervalos de aceptación y clasificación. Los
campos pendientes son estados derivados de los contadores acumulados. El reporte
habitual del testbench conserva su fórmula original con solicitudes aceptadas;
puede diferir ligeramente en un corte con clasificación pendiente.

Las tasas se calculan con los contadores del intervalo y se dejan vacías si no
hay accesos o el nivel está ausente. El resumen Markdown muestra `—` en esos
casos. Los contadores de niveles ausentes valen cero. La tabla de buffers
incluye el write buffer y el eviction buffer; sus máximos se observan ciclo a
ciclo y no se calculan restando máximos acumulados. Los campos de estado no se
suman al reconstruir los contadores aditivos.

El AMAT medido expresa ciclos de espera por acceso más el ciclo base de L1,
sin incluir el cálculo restante del programa. La fórmula es una referencia
nominal y puede diferir por forwarding, colas, escrituras de línea, solapamiento
y operaciones pendientes al corte. No se fuerza un vaciado entre recorridos.

El fin conserva el criterio de `jef 0` válido en ID y `stall === 0`. La identidad
usa la validez de EX capturada en ese corte. El reporte habitual conserva L2,
eviction buffer, AMAT y `l2.txt`; el monitor de benchmark toma sus diferencias
en el mismo corte. Los casos controlados de `make costos_bench` siguen midiendo
memoria directa y L1; la matriz integrada mide también los orígenes de L2.

Las cifras y procedimientos de las secciones históricas que solo incluyen
`CACHE=0` y `1` corresponden a la implementación anterior a L2.

## Propósito y alcance

Los programas permitirán medir cómo cambia el costo de acceder a memoria según
el orden de las lecturas y el tamaño de los datos. Se usará el mismo programa y
la misma entrada al comparar configuraciones del procesador. Cambiar la caché
o la velocidad de memoria debe cambiar los tiempos, pero nunca el resultado.

Los cuatro pasos están implementados. Ya existen los cinco programas, el
generador de datos y la ejecución automática con cifras por recorrido. La sección
final conserva la validación histórica de L1. La sección siguiente describe
las mediciones actuales de la jerarquía completa.

El plan incluye tres programas de lectura, una prueba de escritura secuencial
y otra de lectura, modificación y escritura. Los tres programas de lectura ya
están implementados. Las dos pruebas de escritura y la medición por recorrido
también están disponibles desde el paso 3. Las escrituras finales de resultados se
contarán como cierre del programa, separadas de las escrituras útiles del arreglo.

## Tamaños y repeticiones

Una palabra ocupa cuatro bytes. Cada línea de caché contiene 32 bytes, por lo
que agrupa ocho palabras. KiB significa 1024 bytes.

| Tamaño del arreglo | Palabras N | Líneas de datos | Relación con las cachés |
|---|---|---|---|
| 1 KiB | 256 | 32 | Cabe en L1 |
| 8 KiB | 2048 | 256 | Supera L1 y cabe en L2 |
| 32 KiB | 8192 | 1024 | Supera L1 y L2 |

Cada ejecución comenzará con reset y realizará cuatro recorridos completos.
Antes del primero se leerá la configuración, por lo que esos accesos ya pueden
ocupar una línea de caché. Los tres recorridos siguientes permitirán observar
la reutilización de datos. No se aplicará reset entre recorridos. La suma y los
contadores se inicializarán una sola vez y acumularán las cuatro vueltas.

Se conservarán las métricas globales y se añadirá una fila independiente para
cada uno de los cuatro recorridos. Las cifras por recorrido se obtendrán de
muestras de los contadores, sin reiniciar el procesador ni vaciar las cachés.
El mecanismo y sus límites se detallan en la ampliación del plan.

Se mantienen los tamaños acordados de 1, 8 y 32 KiB. Para que el caso grande
quepa junto con sus índices y resultados en los 64 KiB de memoria, la tabla
aleatoria guardará el orden de las líneas, no una entrada por palabra. Las ocho
fases descritas más adelante permiten visitar todas las palabras sin reducir
el arreglo ni tomar solo una muestra.

## Contenido del arreglo

La palabra de posición i contendrá el valor i+1, para i desde cero hasta N-1.
Los datos iniciales serán iguales para todos los programas de un mismo tamaño.
Los tres patrones de lectura no modificarán el arreglo ni la tabla de índices.
Las dos pruebas de escritura modificarán el arreglo de forma controlada, según
los resultados esperados que se definen en la ampliación.

Esta elección permite calcular la suma esperada sin ejecutar el procesador.
En un recorrido completo, la suma es N multiplicado por N+1 y dividido entre
dos. Al completar cuatro recorridos, ese valor se multiplica por cuatro.
Todos los resultados elegidos caben en 32 bits sin desbordamiento.

## Recorridos

### Secuencial

`bench_secuencial` leerá las posiciones de cero a N-1 en orden y sumará cada
palabra. Al terminar, volverá al principio hasta completar las cuatro vueltas.

Las ocho palabras consecutivas de una línea pueden aprovechar la misma carga
desde el nivel inferior. En un primer recorrido sencillo se espera un fallo de
datos por línea y aciertos al acceder a sus palabras restantes. Es una expectativa
sobre el patrón, no un total impuesto a los contadores del programa completo.
La configuración inicial y las escrituras finales también generan accesos.

### Recorrido con salto de ocho palabras

`bench_stride` avanzará ocho palabras, equivalentes a 32 bytes, entre lecturas.
Cada vuelta completa se dividirá en ocho fases. La primera visitará las posiciones
0, 8, 16 y las siguientes hasta el final. La segunda visitará 1, 9, 17 y las
siguientes. El proceso continuará hasta la fase que comienza en la posición 7.

Así cada fase lee una palabra de cada línea y las ocho fases juntas visitan
exactamente las N palabras. El programa procesa la misma cantidad de datos y
obtiene la misma suma que el secuencial. Terminar una fase no reinicia la caché.

Si el arreglo cabe en caché, las fases posteriores pueden reutilizar las líneas
traídas en la primera. Si no cabe, la distancia entre esas reutilizaciones puede
provocar más fallos. Por ello no se presupone que toda lectura de este patrón
vaya a fallar. Las métricas deben mostrar el comportamiento real.

Este recorrido evita comparar una sola fase de N/8 lecturas contra un programa
secuencial que realiza N lecturas.

### Orden aleatorio reproducible

`bench_aleatorio` leerá una tabla que indica en qué orden visitar las líneas del
arreglo. Una línea contiene ocho palabras. La tabla tendrá una entrada de cuatro
bytes por línea, con su desplazamiento en bytes respecto del inicio del arreglo.
Su tamaño será un octavo del tamaño del arreglo y llegará como máximo a 4 KiB.
Esto permite conservar los tamaños de 1, 8 y 32 KiB dentro de la memoria disponible.

Una vuelta se dividirá en ocho fases. En la primera, el programa leerá la primera
palabra de cada línea siguiendo el orden aleatorio de la tabla. En la segunda
leerá la segunda palabra de cada línea en ese mismo orden. Continuará hasta
leer la octava palabra. Las ocho fases visitarán cada palabra exactamente una vez.

El salto entre líneas sigue un orden precalculado, mientras que la posición de
la palabra dentro de la línea avanza de forma ordenada entre fases. Por tanto,
este programa mide un recorrido aleatorio de líneas. No se presentará como una
permutación independiente de todas las palabras ni como un muestreo uniforme
con reemplazo. Esta distinción debe conservarse en las tablas de resultados.

Las cuatro vueltas utilizarán la misma tabla. Esto conserva el orden exacto
entre ejecuciones y permite comparar configuraciones con la misma carga.
La generación del orden se hará antes de simular, no dentro del procesador.

La tabla se construirá con el método Fisher-Yates, que intercambia posiciones
desde el final hasta el principio. Se usará un generador xorshift32 con semilla
`0xC0FFEE11`, reiniciada para cada tamaño. Este generador combina su estado con
desplazamientos de 13 bits a la izquierda, 17 a la derecha y 5 a la izquierda,
en ese orden, conservando 32 bits en cada paso. En la posición j se intercambiará
su entrada con la posición dada por el nuevo estado módulo j+1.

La definición completa del generador evita depender de cambios de implementación
de una biblioteca aleatoria. Antes de simular se comprobará que cada línea aparece
exactamente una vez en la tabla y que los ocho recorridos parciales cubren todas
las palabras, sin duplicados ni posiciones fuera del arreglo.

Cada lectura útil necesita además una lectura de la tabla. Esos accesos
adicionales se incluirán en las métricas y se informarán por separado. El
programa sumará el desplazamiento leído, la base del arreglo y la posición de
la palabra de la fase actual para obtener la dirección de datos.

El conjunto activo incluye el arreglo y su tabla. Ocupa 1152 bytes en el caso
pequeño, 9 KiB en el mediano y 36 KiB en el grande, además de la configuración
y los resultados. La configuración solo se lee al iniciar. Los tres casos
mantienen, por capacidad total, las categorías previstas de caber en L1,
caber únicamente en L2 o superar ambas. La distribución por conjuntos y el
reemplazo también pueden producir fallos y deben considerarse al interpretar
las mediciones.

## Distribución de los 64 KiB de memoria

Las siguientes direcciones están expresadas en bytes. Los arreglos y las tablas
comienzan alineados con una línea de 32 bytes y no se superponen.

| Región | Inicio | Final máximo incluido | Uso |
|---|---|---|---|
| Configuración | `0x0000` | `0x000F` | Cuatro palabras de entrada |
| Resultados | `0x0020` | `0x002F` | Cuatro palabras escritas al terminar |
| Arreglo | `0x1000` | `0x8FFF` | Hasta 32 KiB de datos |
| Tabla de índices | `0xA000` | `0xAFFF` | Hasta 4 KiB, solo para el patrón aleatorio |

Las posiciones fuera de estas regiones permanecen disponibles. Los casos de
menor tamaño utilizan únicamente el comienzo de las regiones del arreglo y
de la tabla. Los programas secuencial y stride no leen la tabla.

| Dirección de configuración | Contenido |
|---|---|
| `0x0000` | Dirección inicial del arreglo, siempre `0x1000` |
| `0x0004` | Cantidad N de palabras |
| `0x0008` | Cantidad de recorridos, siempre 4 |
| `0x000C` | Dirección inicial de la tabla, siempre `0xA000` |

Los tres programas cargarán estas cuatro palabras una sola vez al iniciar y
mantendrán sus variables de trabajo en registros. Esto fija el mismo costo de
lectura de configuración y evita introducir accesos de control dentro de los lazos.

Los archivos `.mem` y `.exp.mem` usan índices de palabra, aunque el procesador
recibe direcciones de byte. Por ejemplo, el arreglo comienza en la posición
`@00000400` del archivo y la tabla en `@00002800`. Los resultados comienzan
en `@00000008`.

## Resultados esperados de los tres programas de lectura

| Dirección del resultado | Valor almacenado al terminar |
|---|---|
| `0x0020` | Suma acumulada de los cuatro recorridos |
| `0x0024` | Cantidad de lecturas útiles del arreglo, igual a 4N |
| `0x0028` | Cantidad de lecturas de índices, cero o 4N según el patrón |
| `0x002C` | Cantidad de recorridos terminados, igual a 4 |

Estas cuatro palabras se escribirán después de completar todas las lecturas.
Cada archivo `.exp.mem` comprobará esas posiciones. El programa terminará con
la secuencia de fin que reconoce `tb_programa`.

| Arreglo | Suma decimal | Suma hexadecimal | Lecturas útiles | Lecturas de índices en aleatorio |
|---|---|---|---|---|
| 1 KiB | 131584 | `00020200` | 1024 | 1024 |
| 8 KiB | 8392704 | `00801000` | 8192 | 8192 |
| 32 KiB | 134234112 | `08004000` | 32768 | 32768 |

Los tres patrones deben obtener la misma suma para un tamaño dado. En secuencial
y stride, la palabra de lecturas de índices debe valer cero. Además de los
resultados almacenados, la validación comprobará la secuencia de direcciones.
Una suma correcta por sí sola no demuestra que se haya usado el recorrido previsto.

Si no se añaden otras operaciones de memoria, los accesos del procesador deben
ser 4N+4 lecturas para secuencial y stride, 8N+4 lecturas para aleatorio y cuatro
escrituras para todos los casos. Los cuatro accesos adicionales de lectura
corresponden a la configuración. Las lecturas de líneas de memoria principal
serán distintas cuando las cachés estén activas.

## Organización prevista de los archivos

Se escribirán a mano tres fuentes de ensamblador en `programs/`, una para cada
patrón. Sus nombres serán `bench_secuencial.asm`, `bench_stride.asm` y
`bench_aleatorio.asm`. Los tamaños y las repeticiones se leerán de la configuración,
por lo que no hacen falta nueve copias del mismo código.

Cada programa tendrá sus archivos `.mem` y `.exp.mem` de 1 KiB junto a su fuente,
para permitir la ejecución habitual con `make sim PROG=bench_secuencial` o el
nombre equivalente del otro patrón. Los casos de 8 y 32 KiB se ubicarán en
`data/benchmarks/8k/` y `data/benchmarks/32k/`, usando los mismos nombres base.
Se seleccionarán con las opciones existentes `DATA` y `EXP`.

El ensamblador producirá los archivos `.hex` mediante `tools/asm.py`. La
herramienta de preparación de datos usará solo Python estándar y no generará
las instrucciones de los programas. No se agregarán scripts `.sh`.

## Condiciones para escribir el ensamblador

Cada bundle contendrá instrucciones independientes. En este procesador debe
existir al menos un bundle intermedio entre una instrucción que escribe un
registro y otra que utiliza su nuevo valor. Ese espacio se aprovechará con
operaciones independientes y se usará `nopi` cuando sea necesario.

La separación también se respetará en los saltos que comparan un contador
recién actualizado. Los programas deben cumplirla aunque las lecturas acierten
en caché y no generen pausas.

## Matriz de medición y límites de interpretación

La matriz ampliada tendrá quince casos de entrada, correspondientes a cinco
programas y tres tamaños. Cada uno se ejecutará con `MEM_DIV` igual a 2, 4 y 5.
Este parámetro cambia la velocidad del reloj de memoria principal.

La matriz actual mide `CACHE=0`, `1` y `2`: 135 ejecuciones, 540 filas de
recorridos y 135 resúmenes globales. Con `DIVISORES=4` se limita a 45 ejecuciones
y 180 filas de recorridos, conservando los cinco programas y los tres tamaños.

Cada fila identificará el patrón, el tamaño, los recorridos, la selección de
caché y el divisor de memoria. También distinguirá lecturas útiles y lecturas
de índices. Los resultados de cada combinación se conservarán por separado
para que una ejecución no sobrescriba la evidencia de otra.

Los tiempos de los tres patrones incluyen distinto trabajo de cálculo y, en
el aleatorio, lecturas adicionales. Por ello, una diferencia de ciclos entre
patrones no se interpretará por sí sola como una mejora causada por la caché.
La comparación principal mantendrá fijos el programa y sus datos, cambiando
únicamente la configuración de memoria. También se informarán ciclos por
lectura útil e IPC, que es la cantidad de instrucciones completadas por ciclo.

El tamaño de la caché no garantiza una cantidad exacta de aciertos. La primera
carga, los conflictos entre conjuntos, la tabla de índices y la política de
reemplazo influyen en el resultado. Las métricas de L2 se obtienen únicamente
con `CACHE=2`.

El caso aleatorio grande sin caché realiza 65540 lecturas del procesador. Con
`MEM_DIV=5`, los 60 ciclos nominales de cada acceso suman aproximadamente
3,93 millones de ciclos de espera, antes de considerar el resto del programa.
El límite habitual de dos millones de ciclos de `tb_programa` no alcanza para
este caso. El límite ya es configurable y la matriz de métricas
usa diez millones de ciclos por ejecución. El tiempo real se obtendrá de los
contadores, no de esta estimación.

La ejecución de métricas desactiva el archivo de ondas mediante `WAVES=0`.
Ese archivo registra señales ciclo a ciclo y puede crecer mucho en estas
simulaciones largas. Las ejecuciones habituales conservarán la posibilidad de
generarlo para depurar los programas.

## Criterios de aceptación

- Los tres patrones de lectura visitan cada palabra del arreglo exactamente una
  vez por recorrido y completan cuatro recorridos.
- Cada desplazamiento aleatorio es válido y cada tabla contiene todas las líneas
  una sola vez. Las ocho fases cubren todas las palabras del arreglo.
- Todas las regiones de entrada y salida quedan dentro de los 64 KiB disponibles.
- Las cuatro palabras finales coinciden con los valores definidos en este diseño.
- Una traza de accesos de cada patrón confirma el orden de las direcciones,
  además de la cantidad de operaciones y de la suma.
- Las ejecuciones con y sin L1 producen los mismos resultados y no presentan
  discrepancias con el monitor de memoria ni errores de la identidad de ciclos.
- Se conservan resultados separados para todas las combinaciones medidas.
- Las pruebas existentes siguen pasando y el hardware de las cachés no se modifica
  para implementar estos programas.

## Implementación del paso 2

Los tres programas están escritos a mano y se ensamblan con `tools/asm.py`.
El secuencial ocupa 20 paquetes de instrucciones, stride ocupa 26 y aleatorio
ocupa 30. Sus archivos `.hex` acompañan a las fuentes. Los tres leen los tamaños
y la cantidad de recorridos desde la configuración, por lo que su código no
cambia entre las entradas de 1, 8 y 32 KiB.

Los comentarios describen la función de cada registro y de cada lazo. Las
actualizaciones de dirección y contadores se colocan entre operaciones
dependientes cuando son independientes de ellas. En los demás casos se deja
un paquete de separación. Esto también se respeta en los saltos que usan
contadores recién actualizados.

Los programas requieren una configuración válida. La cantidad de palabras y
la cantidad de recorridos deben ser positivas. Stride y aleatorio también
requieren que la cantidad de palabras sea múltiplo de ocho. Los archivos de
entrada previstos cumplen estas condiciones y el generador deberá verificarlas.

El programa aleatorio calcula una sola vez la cantidad de líneas. Después
reutiliza el registro que contenía N para guardar la base de la palabra de cada
fase. El contador de líneas queda en otro registro y no depende de ese cambio.
Cada acceso al arreglo tiene su propia carga de tabla y ambos se cuentan por
separado.

La salida escribe los cuatro resultados y realiza un salto hacia el lazo que
anuncia el fin. La separación permite terminar la última escritura antes de
alcanzar ese lazo y tomar la muestra de contadores con la convención existente
de `tb_programa`.

### Entrada disponible y ejecución

Cada fuente ya tiene su `.mem` y `.exp.mem` de 1 KiB en `programs/`. Esa entrada
usa cuatro recorridos. Los programas pueden ejecutarse directamente con los
comandos siguientes. Para medir la versión con L1 se cambia `CACHE=0` por
`CACHE=1`.

```console
make sim PROG=bench_secuencial CACHE=0 MEM_DIV=4
make sim PROG=bench_stride CACHE=0 MEM_DIV=4
make sim PROG=bench_aleatorio CACHE=0 MEM_DIV=4
```

El paso 2 no requirió cambios al hardware, al ensamblador ni al testbench.
El paso 3 añadió las entradas de mayor tamaño y el observador del testbench
que se describe al final de este documento.

### Comprobaciones realizadas

Una comprobación temporal e independiente interpretó las instrucciones de los
archivos `.hex`. Verificó los nueve casos de patrón y tamaño con cuatro
recorridos, además de nueve casos pequeños con otras cantidades de palabras y
recorridos. En los 18 casos coincidieron los resultados y el orden completo de
las lecturas. No hubo lecturas de registros escritos en el paquete inmediatamente
anterior. Esta comprobación no utiliza las pausas de memoria para separar
instrucciones y por ello también permite revisar el caso de cargas sin espera.

Además, se ejecutaron los tres casos de 1 KiB en el procesador real simulado,
con `CACHE=0` y `CACHE=1`, usando `MEM_DIV=4`. Las seis ejecuciones terminaron
sin fallos, sin discrepancias del monitor de memoria y con la identidad de
ciclos correcta. Sus trazas confirmaron todas las direcciones en el orden
previsto, no únicamente la suma final.

| Programa con cuatro recorridos de 1 KiB | Lecturas del procesador | Escrituras | Ciclos sin caché | Ciclos con L1 |
|---|---|---|---|---|
| Secuencial | 1028 | 4 | 58823 | 5929 |
| Stride | 1028 | 4 | 58984 | 6090 |
| Aleatorio por líneas | 2052 | 4 | 117352 | 10398 |

Estas cifras corresponden únicamente a las ejecuciones de comprobación de
1 KiB. La matriz completa con tres tamaños y tres divisores se realizará en
los pasos posteriores. La validación en el procesador de los tamaños grandes
no se considera sustituida por la comprobación de las instrucciones.

## Ampliación aprobada del plan

La implementación de las lecturas permanece como avance del paso 2. El siguiente
trabajo incluirá las dos fuentes nuevas y los puntos de observación de los
recorridos. El paso 3 generará sus datos, los resultados esperados y la matriz
de métricas. El paso 4 validará los resultados y las mediciones controladas.
La ampliación está implementada desde el paso 3. Los resultados anteriores
siguen describiendo únicamente las seis comprobaciones iniciales de lectura.

### Cifras separadas por recorrido

Se identificarán el inicio del primer recorrido y el final de cada vuelta
mediante etiquetas del ensamblador y la dirección del paquete que se confirma
en ejecución. Confirmar un paquete significa que sus operaciones han terminado
y el procesador permite avanzar. Las etiquetas no agregan instrucciones ni
operaciones de memoria. El observador se implementará en el testbench.

La muestra inicial se tomará antes de confirmar el primer paquete del recorrido.
Las siguientes muestras se tomarán después de confirmar el paquete que aumenta
el contador de vueltas completas. Cada fila será la diferencia entre dos muestras
consecutivas. Los saltos y la preparación entre vueltas quedarán incluidos en
el intervalo siguiente. La preparación inicial y el cierre posterior a la
última vuelta se informarán por separado, junto con el resumen global.

Se comprobará que la suma de preparación, cuatro recorridos y cierre reconstruya
el total de cada contador aditivo. Las diferencias incluirán ciclos,
instrucciones, paquetes confirmados, pausas, lecturas, escrituras, aciertos,
fallos y tráfico de memoria de los niveles disponibles. El IPC se calculará
con las instrucciones y ciclos del intervalo. Las tasas de acierto y fallo
se calcularán con los accesos del intervalo, no restando tasas acumuladas.

La ocupación máxima de un buffer no se obtiene restando máximos acumulados.
El testbench observará su ocupación en cada ciclo y calculará el máximo de
cada intervalo. También guardará la ocupación y las operaciones inferiores
pendientes al comenzar y terminar cada recorrido.

No se esperará a que los buffers se vacíen entre vueltas, porque eso alteraría
el tráfico que se quiere medir. Una operación inferior puede comenzar en un
recorrido y terminar en el siguiente. Sus eventos se asignarán al intervalo
en que ocurran y se conservará esa limitación al interpretar los resultados.

La primera vuelta incluye accesos obligatorios a líneas del arreglo que aún
no se habían traído. Los aciertos dentro de una línea siguen siendo posibles
en esa misma vuelta. No se etiquetarán automáticamente todos los fallos de
las vueltas posteriores como fallos de capacidad, porque también puede haber
conflictos entre conjuntos. La traza permitirá identificar el primer acceso
a cada línea.

### Escritura secuencial

Se añadirá `programs/bench_escritura.asm`. Visitará todas las palabras del
arreglo en orden y calculará el dato que debe guardar usando registros, sin
leer el contenido previo. En la vuelta p, numerada de uno a cuatro, escribirá
el valor i+1+p en la posición i. Por tanto, cada vuelta tendrá N escrituras
útiles y ninguna lectura útil del arreglo.

Esto permitirá observar asignaciones por fallo de escritura, aciertos al
escribir las palabras siguientes de una línea, reutilización entre vueltas
y expulsión de líneas modificadas cuando el arreglo no quepa en caché.

### Lectura, modificación y escritura

Se añadirá `programs/bench_lectura_escritura.asm`. En cada vuelta leerá cada
palabra, le sumará uno y guardará el nuevo valor en la misma posición. Cada
vuelta tendrá N lecturas útiles y N escrituras útiles. No consultará la tabla
de índices.

La escritura que sigue a una lectura normalmente encontrará su línea en L1.
Por ello esta prueba es especialmente útil para medir reutilización y cambios
de datos. No se usará por sí sola para medir fallos de escritura, que se
provocarán con la prueba de escritura pura y los casos controlados.

### Datos esperados de las pruebas nuevas

Ambas pruebas comenzarán con i+1 en la palabra i. Después de la vuelta p,
cada palabra debe contener i+1+p. Al terminar cuatro vueltas debe contener
i+5. Los archivos esperados comprobarán todas las palabras del arreglo,
además de los resultados finales. La comprobación de cada recorrido verificará
su secuencia de accesos y los valores escritos.

Si S es N multiplicado por N+1 y dividido entre dos, la suma de valores escritos
en la vuelta p será S+pN. La suma de todos los valores escritos en cuatro
vueltas será 4S+10N. La suma del contenido final del arreglo será S+4N.
Son cantidades distintas y se validarán como tales.

Las dos pruebas conservarán las cuatro posiciones de salida. Su significado
se identificará por el programa para distinguirlo de las salidas de lectura.

| Dirección | Resultado de las pruebas de escritura |
|---|---|
| `0x0020` | Suma acumulada de los valores escritos, igual a 4S+10N |
| `0x0024` | Cantidad de escrituras útiles del arreglo, igual a 4N |
| `0x0028` | Lecturas útiles del arreglo, cero en escritura pura y 4N en lectura y escritura |
| `0x002C` | Recorridos completados, igual a 4 |

Sin añadir otras operaciones de memoria, la escritura pura realizará cuatro
lecturas de configuración y 4N+4 escrituras. La prueba de lectura y escritura
realizará 4N+4 lecturas y 4N+4 escrituras. Las cuatro escrituras adicionales
son los resultados de cierre y se informarán fuera de los recorridos.

### Costos que se medirán por separado

El tiempo hasta que el procesador puede continuar y el tiempo hasta que una
línea termina de escribirse en memoria son mediciones diferentes. La política
write-back conserva primero la modificación en caché y la escribe en el nivel
inferior al expulsar esa línea. Por ello, un acierto de escritura en L1 puede
completarse sin esperar una escritura de memoria principal.

También se utiliza write-allocate. Ante un fallo de escritura de una palabra
en L1, primero se trae su línea y después se aplica el cambio. Así se conservan
las otras palabras que el programa no está escribiendo en ese acceso.

Los programas no escriben directamente en L2 cuando L1 está activa. Un fallo
de escritura de L1 puede provocar una lectura de llenado que acierte o falle
en L2. En cambio, las escrituras que recibe L2 vienen del drenaje de líneas
completas del buffer de L1. Esos dos tipos de operación se medirán por separado.

| Caso | Qué se observará |
|---|---|
| Escritura sin caché | Pausa del procesador y latencia del acceso a memoria |
| Escritura con acierto en L1 | Confirmación de la palabra y ausencia de llenado inferior |
| Escritura con fallo en L1 y llenado desde L2 | Pausa hasta traer la línea y aplicar la palabra |
| Escritura con fallo en L1 y L2 | Lectura de llenado desde memoria y confirmación de la palabra |
| Escritura con llenado desde un buffer | Entrega de la copia pendiente y aplicación de la palabra |
| Drenaje que acierta en L2 | Aceptación y terminación de la escritura de línea completa |
| Drenaje que falla en L2 | Instalación de la línea completa y posible desalojo de una víctima modificada |
| Escritura de línea en memoria | Aceptación, terminación y ciclos consumidos por la transferencia |

Con el nivel inferior libre, un acierto de escritura en L1 tiene cero ciclos
de pausa. El llenado que acierta en L2 tiene la latencia nominal de ocho
ciclos. Un llenado que también falla en L2 añade el tiempo de memoria. Un
pedido de escritura de línea completa en L2 tarda nominalmente ocho ciclos,
acierte o falle, porque ya trae todos los datos y no necesita leer esa línea
desde memoria. Las esperas por buffers llenos o accesos en curso se añadirán
al costo observado y no se ocultarán dentro de una latencia ideal.

Los tamaños y los recorridos producen mezclas de aciertos y fallos, pero no
permiten atribuir por sí solos una latencia a cada caso. Se añadirán mediciones
controladas, fuera de la matriz general, preparando las líneas antes del acceso
medido y comprobando que el acierto o fallo realmente ocurrió. Su preparación
no se incluirá en la latencia del acceso bajo estudio. Los casos controlados
actuales cubren memoria directa y L1. La matriz integrada sí mide L2; no se
añadieron casos controlados específicos de L2 en esta actualización.

### Comprobación de datos modificados y persistencia

El monitor actual conserva una referencia de las escrituras confirmadas al
procesador. Esa referencia permite comprobar el resultado del programa aunque
la copia más reciente todavía esté en una caché o en un buffer. No demuestra
por sí sola que la memoria principal ya tenga ese contenido.

Se distinguirá esa comprobación del programa de la validación de las líneas
que efectivamente terminan de escribirse en memoria. Para cada transferencia
inferior observada se guardarán su dirección, datos y máscara, y se comprobará
su terminación. Una versión más reciente que permanezca en L1 no se confundirá
con la versión que se estaba drenando.

Al terminar se informará si quedan líneas modificadas en caché o escrituras
pendientes en los buffers. Esperar únicamente a que se vacíen los buffers no
vacía las líneas modificadas de las cachés. Una medición que exija persistencia
de todo el arreglo necesitará un mecanismo de vaciado completo definido en
la integración y su costo se informará aparte del tiempo del programa.

### Criterios adicionales de aceptación

- Cada ejecución informa cuatro filas de recorridos y un resumen global.
- La preparación y el cierre quedan separados de las cifras de los recorridos.
- Las diferencias de contadores reconstruyen los totales de ejecución.
- Los contadores de máximos se calculan observando cada intervalo.
- Cada prueba nueva produce el contenido esperado de todas las palabras.
- Se distinguen escrituras útiles, escrituras finales y escrituras de líneas inferiores.
- Los casos de latencia tienen su acierto o fallo comprobado y no incluyen la preparación.
- No se presenta una confirmación en L1 como prueba de escritura terminada en memoria.
- Los resultados de L2 se obtienen con CACHE=2 y deben pasar la validación integrada.

## Implementación del paso 3

`tools/bench_data.py` genera las entradas y los resultados esperados de los cinco
programas para 1, 8 y 32 KiB. Usa únicamente Python estándar y el analizador del
ensamblador existente para localizar las etiquetas de medición. No genera las
instrucciones. Las dos fuentes nuevas se escribieron a mano y cumplen la misma
separación entre dependencias que los programas de lectura.

```console
make datos_bench
python3 tools/bench_data.py generate --sizes 1 --check
make test_benchmarks
```

`make datos_bench` regenera los quince pares de entrada y resultado esperado.
La opción `--check` comprueba que los archivos guardados coincidan con el
contenido reproducible. El ejemplo comprueba únicamente los casos de 1 KiB,
que se conservan junto al ensamblador. Para comprobar también los tamaños
grandes se ejecuta primero `make datos_bench` y después se omite `--sizes 1`. Cambiar `RECORRIDOS` permite preparar otra cantidad de
vueltas. Los archivos entregados usan cuatro.

### Ejecución de las mediciones

`make metricas` ejecuta las 135 combinaciones de la matriz. Para comprobar primero
los cinco programas con el tamaño pequeño y un solo divisor se puede usar el
primer comando siguiente. Los otros ejemplos permiten seleccionar patrones,
tamaños, configuraciones y una carpeta distinta para conservar los resultados.

```console
make metricas TAMANOS=1 DIVISORES=4
make metricas PATRONES="escritura lectura_escritura" TAMANOS="8 32" CACHES=1
make metricas RECORRIDOS=2 METRICAS_OUT=build/metricas-dos-vueltas
```

Las opciones disponibles son `PATRONES`, `TAMANOS`, `DIVISORES`, `CACHES`,
`RECORRIDOS`, `METRICAS_MAX_CYCLES` y `METRICAS_OUT`. La herramienta admite
`CACHE=0`, `1` y `2`, y `CACHES` usa las tres selecciones por defecto.

Cada combinación comienza desde reset y utiliza un proceso de simulación nuevo.
La configuración y los datos son iguales al comparar las tres selecciones de
caché. Las cuatro vueltas ocurren en una sola ejecución sin reset intermedio.
La entrada de cada medición se genera en su carpeta, por lo que seleccionar otra
cantidad de vueltas no modifica los archivos de ejemplo de `programs/`.

### Archivos obtenidos

La carpeta predeterminada es `build/metricas`. Sus archivos principales son los
siguientes.

| Archivo | Contenido |
|---|---|
| `metricas.csv` | Una fila global por ejecución comprobada |
| `recorridos.csv` | Una fila por vuelta, con ciclos, pausas, accesos y tasas |
| `segmentos.csv` | Preparación, recorridos y cierre separados |
| `costos_escritura.csv` | Cantidad, mínimo, promedio y máximo de los casos observados |
| `metricas.md` | Tabla de lectura rápida con los resultados globales |

Cada combinación conserva además su entrada, resultado esperado, configuración,
registro de simulación, volcado del monitor y traza completa de transacciones.
La ruta sigue el orden programa, tamaño, caché y divisor. Por ejemplo,
`build/metricas/escritura/8k/cache1/div4/`. La configuración conserva la semilla
y las huellas SHA-256 del ensamblador y de la entrada. Una huella identifica el
contenido exacto de un archivo y permite detectar cambios entre mediciones.

En cada carpeta también se guardan `recorridos.csv`, `escrituras.csv` y
`memoria_escrituras.csv`. El primero contiene los contadores sin procesar.
El segundo registra cada escritura confirmada al procesador, su recorrido,
dirección, clasificación y ciclos de pausa. El tercero registra las escrituras
inferiores terminadas, sus ciclos de inicio y fin, recorridos de inicio y fin,
número de línea, máscara y datos aceptados.

Las columnas de L1 se conservan en cero cuando se ejecuta sin caché y sus tasas
se dejan vacías. No son cifras medidas de una L1 activa. Los ciclos por acceso
útil incluyen el trabajo del programa y deben compararse manteniendo el mismo
patrón. En lectura y escritura, cada carga y cada store cuentan como un acceso
útil distinto. Los accesos a la tabla aleatoria tienen una columna propia.

Los resúmenes se actualizan después de cada ejecución comprobada. Si una
simulación falla, la herramienta termina con error e indica su registro. El
resumen puede contener las combinaciones anteriores que sí terminaron, pero
no incluye la ejecución fallida. Una nueva invocación reemplaza los resúmenes
de la carpeta elegida. Conviene usar otra carpeta para conservar una campaña
anterior.

### Observación y comprobaciones automáticas

`tb/benchmark_monitor.sv` observa el inicio del primer recorrido y el final de
cada vuelta mediante las etiquetas `.VUELTA` y `.FIN_RECORRIDO`. Recibe la
confirmación del paquete en ejecución y sus contadores. No introduce operaciones
en el programa ni modifica las cachés. La preparación termina antes de confirmar
el primer paquete de la primera vuelta. El final de cada vuelta se toma después
de actualizar sus contadores en ese mismo flanco.

El observador comprueba que las diferencias reconstruyan cada contador aditivo.
También mide la ocupación máxima del buffer en cada intervalo y conserva la
ocupación, las líneas modificadas en L1 y el estado ocupado de memoria al inicio
y al final. El estado ocupado indica una transferencia aceptada todavía activa,
no una cantidad de pedidos pendientes. Las transferencias pueden cruzar los
límites de una vuelta sin que el observador espere a su terminación.

El script compara cada carga y escritura con la secuencia completa esperada.
Comprueba dirección, tipo, dato, cantidad de operaciones, contenido final,
accesos por recorrido, aciertos y fallos, discrepancias del monitor e identidad
de ciclos. Por tanto, una suma final correcta no basta para aceptar una ejecución.

La clasificación de un store conserva su condición de acierto o fallo al
presentarse el pedido. Un llenado posterior no puede convertir ese fallo
original en un acierto medido. El script comprueba que un acierto de escritura
en L1 no agregue pausas y que una escritura directa tenga el costo nominal de
memoria para su divisor.

Para cada escritura inferior terminada se comparan los bytes habilitados por
su máscara con el contenido de la memoria física. La comparación usa los datos
capturados al aceptar la transferencia, porque la caché puede conservar después
una versión más reciente. También se comprueba su duración nominal. Las
transferencias todavía activas al terminar quedan indicadas en el estado final
y no se presentan como escrituras terminadas.

Esta comprobación no equivale a vaciar toda la jerarquía. El volcado `dump.mem`
representa la referencia del monitor de CPU. Puede ser correcto aunque queden
líneas modificadas en L1. Los casos controlados de L2 y un mecanismo de vaciado
completo siguen dependiendo de la integración.

### Límite de ciclos y ondas

La ejecución habitual conserva `MAX_CYCLES=2000000` y genera ondas. La matriz
usa `METRICAS_MAX_CYCLES=10000000` y desactiva las ondas para evitar archivos
muy grandes. Estas dos opciones también se pueden elegir al ejecutar un
programa directamente.

```console
make sim PROG=bench_aleatorio CACHE=0 DATA=data/benchmarks/32k/bench_aleatorio.mem EXP=data/benchmarks/32k/bench_aleatorio.exp.mem MAX_CYCLES=10000000 WAVES=0
```

Un límite insuficiente hace fallar la simulación y la herramienta de métricas.
No se reemplazan los ciclos observados por estimaciones ni se acepta una
ejecución incompleta como resultado.

### Validación realizada en el paso 3

Pasaron 29 combinaciones de cuatro recorridos y cuatro comprobaciones adicionales
con dos vueltas. Las combinaciones incluyen los cinco programas de 1 KiB con
ambas selecciones de caché y divisor 4, los cinco programas de 8 y 32 KiB con L1
y divisor 4, ambas pruebas de escritura de 8 KiB con y sin L1 y divisores 2 y 5,
y el aleatorio de 32 KiB sin caché y divisor 5.

En todos esos casos coincidieron las trazas completas, las salidas, los accesos
por vuelta, la identidad de ciclos y la reconstrucción de los contadores. Las
pruebas de escritura también comprobaron todas las palabras del arreglo.
Las transferencias observadas con la comprobación de bytes físicos no
presentaron diferencias y conservaron sus duraciones nominales.

El caso aleatorio de 32 KiB sin caché y divisor 5 terminó en 4 194 976 ciclos.
Esto comprueba que el límite ampliado permite ejecutar un caso que supera los
dos millones de ciclos habituales. También se comprobaron dos errores
intencionales. La herramienta rechazó `CACHE=2` y una simulación con límite
de veinte ciclos terminó con error sin producir una fila de medición válida.

Los 28 testbenches existentes pasaron con `make all`. Las cinco pruebas de
`make test_benchmarks` comprobaron regiones y resultados de los quince casos,
reproducibilidad, entradas inválidas, etiquetas que no cambian instrucciones
y rechazo de trazas con valores, orden o longitud incorrectos.

La siguiente tabla muestra la escritura pura de 1 KiB con L1 y divisor 4.
La primera vuelta presenta los fallos obligatorios de las líneas del arreglo,
pero sus palabras siguientes ya pueden acertar. Las otras tres vueltas
reutilizan esas líneas sin reiniciar la caché.

| Vuelta | Ciclos | Aciertos de escritura L1 | Fallos de escritura L1 |
|---|---|---|---|
| 1 | 2723 | 224 | 32 |
| 2 | 1030 | 256 | 0 |
| 3 | 1030 | 256 | 0 |
| 4 | 1030 | 256 | 0 |

La preparación costó 59 ciclos y el cierre 61. Su suma con las cuatro vueltas
reconstruye los 5933 ciclos del programa completo. Un store que acertó en L1
no agregó pausas. Una escritura directa a memoria con ese divisor requirió
53 ciclos de pausa. En el caso de 8 KiB con L1, los fallos de escritura también
incluyeron esperas por el tráfico de expulsión y llegaron a 76 ciclos. Esas
esperas observadas se conservan en la tabla de costos y no se reemplazan por
los 53 ciclos nominales de una transferencia aislada.

Esta sección conserva la evidencia del paso 3. La validación completa y los
casos controlados del paso 4 se describen a continuación. Ninguna de estas
cifras corresponde a L2 integrada.

## Implementación del paso 4

La comparación mantiene fijos el programa, los datos y las cuatro vueltas.
La base del procesador es `fae20aa`, con los cambios locales de esta rama.
La matriz completa ejecuta los cinco programas con tres tamaños, tres divisores
y dos selecciones de caché. Los resultados incluyen preparación, cuatro
recorridos y cierre, además de la muestra global.

```console
make test_benchmarks
make all
make costos_bench
make metricas METRICAS_OUT=build/metricas-final
```

Los resultados de esta validación se guardan en `build/metricas-final`. Esa
carpeta queda fuera del control de versiones. Una ejecución nueva puede usar
otra carpeta para conservar la evidencia anterior.

### Casos controlados de escritura

`make costos_bench` ejecuta `tb_bench_escritura` y guarda las muestras en
`build/costos_controlados.csv`. El testbench conecta los mismos módulos de
memoria que `top`, sin ejecutar las instrucciones del procesador. Cada instancia
tiene memoria, caché y reloj propios. Se prueban los divisores 2, 4 y 5 con el
adaptador directo y con L1, en seis instancias independientes.

La pausa cuenta los flancos en que el pedido de palabra permanece activo sin
`listo`. Por eso un acierto inmediato mide cero pausas, aunque la escritura se
confirma en un flanco. El tiempo de reset y los accesos que preparan un caso
quedan fuera de la muestra correspondiente.

| Caso preparado | MEM_DIV 2 | MEM_DIV 4 | MEM_DIV 5 |
|---|---|---|---|
| Escritura directa a memoria | 39 | 53 | 60 |
| Escritura directa repetida en la misma palabra | 39 | 53 | 60 |
| Fallo de L1 con memoria libre | 39 | 53 | 60 |
| Acierto de L1 en la misma palabra | 0 | 0 | 0 |
| Acierto de L1 en otra palabra de la misma línea | 0 | 0 | 0 |
| Fallo de L1 que expulsa una víctima modificada | 39 | 53 | 60 |
| Fallo de L1 resuelto desde el buffer | 0 | 0 | 0 |

La tabla expresa pausas del pedido de palabra. Los aciertos y fallos se
comprueban con los contadores originales de L1. Un fallo servido por memoria
acepta una lectura inferior. El caso servido por el buffer aumenta su contador
de forwarding y no acepta una lectura de memoria para ese pedido.

Para provocar las expulsiones se usan `0x1000`, `0x1800` y `0x2000`. Las tres
direcciones tienen el mismo índice de conjunto y etiquetas distintas. Al ocupar
las dos vías y pedir la tercera línea se expulsa la primera, cuyos datos fueron
modificados previamente. Volver a su dirección mientras el buffer conserva la
copia pendiente permite comprobar el llenado desde ese buffer.

Al recibir la primera víctima desde el buffer se modifica otra vez su palabra
en L1. La lectura posterior comprueba esa nueva versión. Después de las
muestras se espera al drenaje de las dos víctimas y se compara
su contenido en la memoria física. Se comprueban las palabras modificadas y
las otras palabras de la primera línea. Esta espera pertenece a la comprobación
de datos y no se añade a la pausa del store medido. La primera víctima debe
conservar en memoria la versión aceptada antes de esa última modificación.
La versión más reciente sigue en L1 y no se presenta como persistida.

La expulsión de una víctima modificada no agrega necesariamente la duración de
su escritura a la pausa del pedido actual. En este caso el buffer dispone de
espacio y desacopla ambas operaciones. La matriz general también observa otros
estados de ocupación, por lo que un fallo puede costar más que en este caso
controlado. Los contadores de lecturas y escrituras del CSV son diferencias del
intervalo medido. Un drenaje iniciado durante ese intervalo puede corresponder
a un pedido anterior.

### Archivos que se conservan en el repositorio

Las fuentes `.asm`, las herramientas, los testbenches y la documentación forman
la implementación. Los cinco `.hex` se conservan siguiendo la organización
existente del proyecto. Los `.mem` y `.exp.mem` de 1 KiB acompañan a las fuentes
para permitir `make sim PROG=bench_escritura` y los comandos equivalentes.

Las entradas de 8 y 32 KiB quedan en la carpeta ignorada `data/benchmarks/` y se
regeneran con `make datos_bench`. No hace falta incluir sus veinte archivos en
el commit. `make metricas` genera los datos de cada combinación en su carpeta
de resultados, por lo que no depende de que existan esas entradas grandes.
Los archivos bajo `build/`, las ondas y los binarios de simulación también
quedan fuera del control de versiones.

### Integración de la jerarquía completa

El observador usa `dut.g_cache` para `CACHE=1` y `dut.g_cache2` para `CACHE=2`.
Los contadores de memoria física siguen viniendo de `dut.u_memory`, después de
todos los niveles. Los programas, etiquetas, entradas y esperados se conservan.
El origen de llenado de L1 se toma de `l1_resp_src` en la jerarquía completa:
0 identifica memoria, 1 L2 y 2 un buffer. Con CACHE=2, el origen 2 puede
propagarse desde el eviction buffer o provenir del write buffer; la categoría
`l1_miss_buffer` reúne ambos y los contadores de forwarding los distinguen.

La comprobación de drenajes conserva el orden estricto de versiones consecutivas
con `CACHE=1`. Con `CACHE=2` acepta versiones posteriores en orden creciente:
L2 puede conservar varias actualizaciones antes de escribir una línea a RAM.
Cada transferencia debe seguir siendo una línea completa con todas sus palabras
de la misma versión válida; se rechazan versiones repetidas, regresivas o fuera
de los recorridos ejecutados. El monitor de CPU y los esperados verifican los
valores finales aunque todavía existan líneas sucias en caché.

Conviene registrar también la política de reemplazo y el estado inicial de su
generador. La L2 de partida elige víctimas con un generador de ocho bits que
se inicia en `0xA5`. Mantener su configuración permite repetir la misma prueba.

La latencia nominal de búsqueda de L2 en la versión de partida es ocho ciclos.
La escritura de una línea completa no necesita leer primero esa línea desde
memoria. Los tiempos del pedido completo también pueden incluir esperas por
ocupación, expulsiones y transferencias inferiores. Los ocho ciclos no deben
imponerse como duración total a todos los pedidos.

Si se conserva el reemplazo pseudoaleatorio de L2, se debe registrar su estado
inicial. La versión de partida reinicia su LFSR, que es el registro generador
de esa secuencia, con `0xA5`. También deben conservarse la política NINE y las
capacidades de buffers declaradas para poder repetir las mediciones.

Si hace falta demostrar que todo el arreglo quedó escrito en memoria principal,
la integración debe definir un vaciado completo de líneas modificadas. Esperar
solo al vaciado de buffers deja posibles modificaciones en las cachés. El tiempo
de ese vaciado completo se informará aparte del tiempo del programa.

### Comprobación final de los datos físicos

Además de comparar cada byte terminado con los datos aceptados por memoria,
el script comprueba el contenido de esas transferencias frente al programa.
Sin caché, cada escritura terminada debe corresponder al store previsto, con
su dirección, máscara y palabra correctas.

Con L1, las pruebas de escritura recorren y modifican líneas completas en orden.
Cada línea drenada debe contener las ocho palabras de la misma vuelta y sus
versiones deben avanzar en orden. Los programas de lectura no deben drenar
líneas modificadas antes de terminar. Esta comprobación se aplica a la conexión
actual de L1 con memoria y deberá adaptarse si un nivel adicional conserva o
combina versiones durante varias vueltas.

Las pruebas automáticas también rechazan una palabra alterada, una máscara
incorrecta, una dirección ajena al arreglo y una versión repetida. La validez
de los datos que ya llegaron a memoria se comprueba de forma separada del
contenido más reciente que todavía pueda permanecer en L1.

### Resultados de la matriz completa

Pasaron las 90 ejecuciones previstas, con 360 filas de recorridos, 540 segmentos
que separan preparación, vueltas y cierre, y 90 resúmenes globales. Coincidieron
las entradas y el volcado completo del monitor entre las seis configuraciones
de cada combinación de programa y tamaño. Se comprobaron todas las trazas,
resultados, versiones drenadas, aciertos, fallos e identidades de ciclos.
Los contadores de máximos y los estados en límites de intervalos también fueron
coherentes. Las ejecuciones de métricas no generaron archivos de ondas.

La siguiente tabla resume el divisor 4. El factor divide los ciclos sin caché
entre los ciclos con L1, manteniendo el programa y la entrada. Las cifras de
los divisores 2 y 5 y cada una de las cuatro vueltas están en los CSV completos.

| Programa | KiB | Sin caché | Con L1 | Factor |
|---|---|---|---|---|
| secuencial | 1 | 58823 | 5929 | 9.921 |
| secuencial | 8 | 467399 | 87177 | 5.361 |
| secuencial | 32 | 1868231 | 348297 | 5.364 |
| stride | 1 | 58984 | 6090 | 9.685 |
| stride | 8 | 467560 | 467242 | 1.001 |
| stride | 32 | 1868392 | 1868074 | 1.000 |
| aleatorio | 1 | 117352 | 10398 | 11.286 |
| aleatorio | 8 | 934504 | 554282 | 1.686 |
| aleatorio | 32 | 3736168 | 2216234 | 1.686 |
| escritura | 1 | 58827 | 5933 | 9.915 |
| escritura | 8 | 467403 | 107769 | 4.337 |
| escritura | 32 | 1868235 | 439545 | 4.250 |
| lectura_escritura | 1 | 117191 | 10025 | 11.690 |
| lectura_escritura | 8 | 934343 | 119945 | 7.790 |
| lectura_escritura | 32 | 3736007 | 479369 | 7.794 |

El arreglo de 1 KiB permite reutilizar las líneas entre vueltas. En el
secuencial grande todavía se aprovechan las ocho palabras consecutivas de cada
línea, aunque el arreglo completo supere L1. En stride, los casos de 8 y 32 KiB
vuelven a cada línea después de recorrer un arreglo que no cabe en esa caché.
Por ello sus ciclos cambian muy poco al activar L1.

El aleatorio también lee la tabla de índices y su tasa general de L1 incluye
esos accesos. La tasa general combina lecturas y escrituras en el programa
mixto. No se debe interpretar cualquiera de esas tasas como una medición
exclusiva de los accesos de lectura al arreglo. Los contadores conservan por
separado los tipos de operación y sus aciertos y fallos.

Los tiempos terminan con el programa y pueden dejar líneas modificadas en L1.
Por tanto, los factores de las pruebas de escritura comparan el tiempo hasta
la terminación del programa. No equivalen a medir el tiempo necesario para
persistir todo el arreglo en memoria principal.

La regresión final aprobó los 29 testbenches, incluido el nuevo testbench de
costos controlados. Pasaron las siete pruebas de las herramientas de Python.
También se ejecutaron ambas pruebas de escritura de 8 KiB después de retirar
las entradas grandes del directorio de trabajo temporal. La generación por
combinación permitió medirlas sin depender de esos archivos ignorados.

La evidencia de esta campaña incluye `comparaciones.csv`, con las 45 parejas
de configuraciones, y `verificacion.json`, con las cantidades comprobadas y las
huellas de fuentes y resúmenes. Son archivos de esta validación guardados bajo
`build/metricas-final`. Los cuatro CSV habituales y el resumen Markdown se
regeneran con `make metricas`.

Las cifras de la jerarquía completa, con L2, están en `rendimiento.md`. No se
cambiaron los módulos RTL del procesador ni de las cachés.

### Mostrar los resultados en la terminal

Al terminar `make metricas`, el resumen se imprime con columnas alineadas.
El archivo `metricas.md` también conserva esa alineación al leerlo con `cat`.
Para mostrar mediciones que ya existen sin repetir las simulaciones se usa el
siguiente comando, indicando la carpeta donde se guardaron.

```console
python3 tools/metricas.py --show build/metricas-l1
```

### Resumen histórico de comparación de L1

El resumen presenta los ciclos sin caché y con L1 en columnas contiguas, junto
con el factor de mejora. Una segunda tabla conserva las pausas de memoria y
el IPC de ambas configuraciones. Los nombres identifican las configuraciones
sin usar cero y uno como etiquetas visibles.

Las tablas se agrupan por latencia nominal de memoria y cantidad de recorridos.
El parámetro `MEM_DIV` se conserva en el encabezado para repetir la medición,
pero no ocupa una columna en cada fila. Los CSV conservan sus columnas técnicas.
Si se selecciona únicamente L1, el resumen indica que falta medir la ejecución
sin caché y no calcula un factor de mejora.

```console
make metricas CACHES="0 1" TAMANOS=1 DIVISORES=4 METRICAS_OUT=build/comparacion-l1
python3 tools/metricas.py --show build/comparacion-l1
```

Para ver directamente la comparación completa ya medida durante la validación
se puede usar `python3 tools/metricas.py --show build/metricas-final`.
