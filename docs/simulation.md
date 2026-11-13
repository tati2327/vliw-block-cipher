# Modelo de simulación

La simulación ejecuta el procesador SystemVerilog con Icarus Verilog. El módulo
`top` conecta `core`, la memoria de instrucciones y la memoria de datos. Los
testbenches generan reloj y reset, cargan programas y datos mediante parámetros,
comprueban resultados y producen ondas VCD. No se necesita una placa FPGA.

Los comandos de este documento se ejecutan desde la raíz del repositorio.
La codificación está definida en [isa.md](isa.md) y las conexiones y la
organización del pipeline en [microarchitecture.md](microarchitecture.md).

## Herramientas

| Herramienta | Uso |
|---|---|
| Icarus Verilog (`iverilog`, `vvp`) | Compila SystemVerilog con `-g2012` y ejecuta la simulación. |
| GNU Make | Selecciona y ejecuta testbenches. |
| Python 3 | Genera tokens y convierte archivos a imágenes de memoria y viceversa. |
| GTKWave | Muestra las ondas VCD; es opcional para las comprobaciones automáticas. |
| GCC | Compila la referencia C usada por `tools/run_ref.sh`. |
| Bash, `cmp`, `stat`, `head` | Ejecutan los scripts de validación de archivos en Linux. |
| `tools/asm.py` | Ensamblador propio: traduce un `.asm` a `.hex` (`python3 tools/asm.py programa.asm -o programa.hex`). |
| `ccom` | Compila programas Calser (`.cls`) del proyecto de la contraparte; no es necesario para ensamblar ni simular. |

`ccom` es una dependencia externa y no se compila con este Makefile. Solo hace falta
para compilar `.cls`; si no está en `PATH`, se invoca mediante la ruta de su ejecutable.

## Representación del procesador

El procesador usa palabras de 32 bits y bundles de 128 bits con cuatro slots:
ALU0, ALU1/CRYPTO, BRU y LSU. El slot 1 selecciona ALU1 o CRYPTO. El pipeline
tiene etapas IF, ID, EX y WB; la memoria de datos permite lectura combinacional y la de
instrucciones es una ROM síncrona cuyo registro de salida hace de IF/ID, sin
una etapa MEM separada.

| Componente | Comportamiento del modelo |
|---|---|
| `fetch` | El PC cuenta bundles, avanza de uno en uno y empieza en cero tras reset. |
| `dispatch` | Decodifica los cuatro slots y obtiene los operandos del banco de registros. |
| `regfile` | Contiene 16 registros de 32 bits, ocho lecturas combinacionales y hasta cuatro escrituras en bajada de reloj. `r0` permanece en cero. |
| Registros de pipeline | Capturan en subida; los bits de validez distinguen instrucciones de burbujas. |
| ALU y BRU | Calculan combinacionalmente operaciones aritméticas, condiciones y destinos de salto. La redirección se resuelve en ID y descarta la instrucción de IF. |
| LSU | Calcula la dirección y selecciona palabras o bytes; la escritura externa se habilita únicamente cuando el bundle se confirma. |
| CRYPTO | Ejecuta Feistel combinacionalmente y autentica mediante el motor secuencial Ascon. |

El programa respeta las separaciones entre instrucciones dependientes definidas
en la ISA; la simulación no inserta automáticamente instrucciones vacías.
`tb_programa` y los casos completos usan un reloj de período 10 ns (`always
#5 clk = ~clk`). La directiva `timescale 1ns/1ps` establece la unidad de los
retardos y su precisión. Este período permite ordenar eventos en simulación;
no constituye una medición de frecuencia máxima del circuito.

## Memorias y archivos de entrada

`top` recibe `IMEM_INIT` y `DMEM_INIT`, rutas de los archivos que las memorias
leen mediante `$readmemh` al comenzar la simulación. Las rutas relativas se
resuelven desde la carpeta donde se ejecuta `vvp`.

| Memoria | Configuración predeterminada | Formato |
|---|---|---|
| Instrucciones (`imem`) | 4096 bundles de 128 bits; dirección de 22 bits en bundles. | `.hex`: un bundle por línea, en orden `slot3_slot2_slot1_slot0`, ocho dígitos hexadecimales por slot. |
| Datos (`memory`) | 16384 palabras de 32 bits, equivalentes a 64 KiB; dirección en bytes. | `.mem`: una palabra hexadecimal por entrada; `@` selecciona un índice de palabra hexadecimal. |

Las memorias se inicializan en cero antes de cargar sus archivos. Las posiciones
sin programa contienen bundles cero. Una lectura de instrucciones fuera de la
profundidad devuelve cero. La lectura de instrucciones es síncrona: el bundle
llega un flanco después de presentar el PC. La memoria de datos lee combinacionalmente y escribe
en subida, con una habilitación por cada byte; el reset no borra su contenido.
El hardware indexa datos con los bits bajos de la dirección de palabra; las
herramientas comprueban el rango de 64 KiB para evitar direcciones que se solapen.

Los datos usan little endian. Por ejemplo, los bytes `48 6F 6C 61` (`Hola`)
se representan mediante la palabra `616C6F48`. La dirección de byte `0x1000`
corresponde a la marca `@400` en un `.mem`.

## Ensamblado y ejecución de un programa

`tools/asm.py` ensambla un programa en la sintaxis de la ISA (un bundle por línea,
cuatro slots entre llaves) y genera el `.hex` que carga el procesador:

```bash
python3 tools/asm.py programs/ejercicio1.asm -o programs/ejercicio1.hex
```

El `.hex` no incluye datos iniciales; los datos de entrada se preparan aparte
cuando el programa los necesita (`PROG_MEM`). Un `.asm` generado por `ccom`
(`ccom -s programa.cls`) también se puede reensamblar con `asm.py`.

`make sim PROG=...` ejecuta el testbench genérico `tb_programa` sin editarlo:

```bash
make sim PROG=ejercicio1                            # programs/ejercicio1.hex, datos y esperados por defecto
make sim PROG=programs/ejercicio3 DATA=build/cifrado_datos.mem
make sim PROG=programs/mi_prueba DESDE=0x40 HASTA=0x60
make help                                           # lista de variables y ejemplos
```

`PROG` es un nombre (`ejercicio1` equivale a `programs/ejercicio1`) o una ruta, con o sin
extensión `.hex` o `.asm`. Si existe el `.asm` y el `.hex` no existe o es más antiguo que el `.asm`, se
ensambla con `asm.py` (se cambia con `ASM=...`); si solo existe el `.hex`, se usa tal cual; si no existe ninguno, termina con el error
`No existe <base>.hex ni <base>.asm`. Las demás variables son:

| Variable | Significado | Por defecto |
|---|---|---|
| `DATA` | Memoria de datos (`PROG_MEM`) | `<base>.mem` si existe; si no, ninguna |
| `EXP` | Memoria esperada (`EXP_MEM`) | `<base>.exp.mem` si existe; si no, no se compara la memoria |
| `DESDE`, `HASTA` | Rango de la lista de memoria, en bytes (decimal o `0x..`) | `0` y `4095` |

Detrás, `make sim` compila `tb/tb_programa.sv` con las macros `PROG_HEX`,
`PROG_MEM`, `EXP_MEM`, `MEM_DESDE` y `MEM_HASTA`. Sin `EXP`, el TB solo
comprueba la finalización y la ausencia de valores desconocidos en las señales
que observa; no valida por sí solo el resultado del algoritmo. Al terminar copia
las salidas a `build/<nombre>/ondas.vcd` y `build/<nombre>/dump.mem`, e imprime
esas rutas; `make waves_prog PROG=...` abre las ondas en GTKWave.

El TB reconoce el final mediante `jef 0`, espera cinco ciclos adicionales y
limita la ejecución a 50000 ciclos antes de declarar fallo. No existe una
instrucción de apagado del simulador en el procesador: el TB llama a `$finish`.
Guarda el volcado completo en `build/tb_programa_dump.mem` (que `make sim` copia a `build/<nombre>/dump.mem`), imprime los registros
(`r4 = 120 (0x00000078)`: decimal con signo y hexadecimal), lista las palabras de
datos distintas de cero (`0x0044: 120 (0x00000078)`) y genera `build/tb_programa.vcd` (copiado a `build/<nombre>/ondas.vcd`). Un resultado `PASS` termina sin error;
una comprobación fallida termina mediante `$fatal`.

La lista de memoria es solo informativa (no es una comprobación). Su rango, en
direcciones de byte, se elige con las macros `MEM_DESDE` (por defecto `0`) y
`MEM_HASTA` (por defecto `4095`, `0x0FFF`); con `make sim` se pasan como `DESDE` y
`HASTA`, por ejemplo `DESDE=0x2000 HASTA=0x2010`.

## Reset, autenticación y pausa

Los testbenches mantienen `rst` activo durante al menos una subida de reloj y
lo liberan fuera de esa subida. El reset borra PC, registros generales,
validez del pipeline, llaves, banderas CRYPTO y el hash pendiente.

En `top`, `por_done` comienza en cero y permite que `init_anchor` esté activo
en la primera subida con reset. Así se carga el ancla de fábrica `0xFEFF95FF`.
Los resets posteriores conservan el ancla vigente. Una ejecución nueva de `vvp`
crea un estado inicial nuevo; un reset dentro de esa ejecución conserva el
ancla y el contenido de las memorias.

La cadena de demostración usa la semilla `0xCAFEDECE` y 100 tokens. La primera
autenticación presenta `0xF47BD70B` (x99) y la segunda `0xA45326BA` (x98).
El token aceptado pasa a ser el ancla. `make lamport` regenera la lista, pero
no cambia los registros de una simulación en ejecución.

`auth` ocupa 14 ciclos de EX: carga el token, ejecuta 12 rondas y confirma el
resultado. Durante la espera, `crypto_stall` congela el PC y los registros
IF/ID e ID/EX. EX/WB recibe burbujas y los stores quedan deshabilitados.
La condición `ex_commit = ex_valid & ~crypto_stall & ~rst` confirma los efectos
del bundle una sola vez cuando termina la espera. La bóveda, el ancla y las
banderas no se exponen mediante puertos de lectura al programa; los TB las
observan por jerarquía para verificar su funcionamiento.

## Comprobaciones automáticas

```bash
make all                  # todos los testbenches; make sim sin PROG equivale a make all;
                          # con PROG=... ejecuta un solo programa (ver «Ensamblado y ejecución»)
make crypto               # ocho testbenches del subsistema CRYPTO
make tb_top               # procesador integrado, incluida la pausa de auth
make tb_programa          # programa ejercicio1 y resultados predeterminados
make tb_caso4_feis
make tb_caso5_feistel4
make tb_caso6_boveda
make tb_caso7_mixto
python3 tools/test_file_tools.py
bash tools/run_ref.sh
```

El Makefile compila cada TB con `-s tb_nombre`, seleccionándolo como única
raíz, y ejecuta el binario mediante `vvp`. Genera los ejecutables en `build/`.
Las pruebas abarcan componentes, subsistemas, el procesador y los siete casos:
paralelismo de ALU, memoria, saltos, una ronda Feistel, Feistel4 completo,
bóveda y procesamiento mixto de un archivo. La cobertura funcional se basa
en comprobaciones de resultados y escenarios; no se presenta como cobertura
formal ni como porcentaje de líneas ejecutadas.

`run_ref.sh` compila la referencia C, comprueba sus nueve casos, compara el
cifrado del procesador contra esa referencia y prueba ida y vuelta y segmentos
en la referencia. Las pruebas de segmentos de este script corresponden al
programa C, no a una ejecución adicional del procesador.

## Carga, cifrado y recuperación de un archivo

El flujo reproducible del caso 7 se ejecuta con:

```bash
bash tools/run_caso7.sh
```

El script carga `data/caso7_ensayo.txt` en `0x1000`, ejecuta el programa
`programs/feistel4.hex`, extrae el cifrado de `0x2000` y el descifrado de `0x3000`.
Compara el descifrado byte a byte con el archivo original y exige que el
cifrado sea distinto. Es un caso con tamaño y programa acordados; sustituir
el archivo requiere ajustar la cantidad de bloques y las zonas usadas.

Las herramientas también se pueden usar por separado:

```bash
mkdir -p build
python3 tools/load_file.py --input data/caso7_ensayo.txt \
  --output build/entrada.mem --address 0x1000
python3 tools/extract_data.py --memory build/tb_caso7_mixto_dump.mem \
  --address 0x3000 --size 903 --output build/recuperado.txt
```

El volcado `build/tb_caso7_mixto_dump.mem` lo genera `make tb_caso7_mixto` (o `bash tools/run_caso7.sh`),
que debe correrse antes de esa extracción.

`load_file.py` agrupa bytes en palabras, completa la última palabra con ceros
y requiere una dirección inicial múltiplo de cuatro. Para ejecutar ese archivo
se pasa `build/entrada.mem` como `DATA` a `make sim`. El procesamiento Feistel de
bloques de 64 bits requiere además que el programa maneje el relleno y la
cantidad de bloques apropiados. `extract_data.py` recibe la longitud original
en bytes (903 en este ejemplo) para recuperar el archivo sin relleno. Ambos
scripts comprueban rangos; la extracción rechaza palabras ausentes o desconocidas.

## Ejercicio 3 (cifrado) con el compilador

`ccom` compila el ejercicio 3 (`ejercicio3.cls`) a tres archivos que están en
`programs/`:

| Archivo | Contenido | Destino |
|---|---|---|
| `programs/ejercicio3.hex` | Programa | Memoria de instrucciones (`PROG_HEX`) |
| `programs/ejercicio3.mem` | Variables `origen = 0x1000`, `cifrado = 0x2000`, `vuelta = 0x3000` | Memoria de datos (`PROG_MEM`) |
| Archivo a cifrar | Los 1024 bytes de entrada, convertidos con `load_file.py` | Memoria de datos desde `0x1000` |
| `programs/ejercicio3.asm` | Listado del programa, solo para consulta | No se carga |

El programa del compilador no carga el archivo: solo recibe direcciones. Lee de
`0x1000`, escribe el cifrado en `0x2000` y el descifrado en `0x3000`, por lo que el
archivo debe cargarse en memoria antes de ejecutar (paso 2 de abajo). Hoy está
compilado para exactamente 1024 bytes.

El programa procesa siempre 1024 bytes fijos: `main` llama a
`cifrar_archivo [origen, cifrado, 128, 16]` y a
`descifrar_archivo [cifrado, vuelta, 128, 16]`, es decir, 128 bloques de 8 bytes
en segmentos de 16 bloques (8 segmentos; los pares usan la llave 0 y los impares
la llave 1). Cambiar el tamaño exige modificar y recompilar el `.cls`. Se
autentica con el token `-193210613` (`0xF47BD70B`), el primer token de la cadena
de Lamport de `data/lamport_demo`, carga las llaves de la bóveda, las bloquea con
`kv_lock` y termina con `cerrar_sesion`. Por eso, al terminar, `auth = 0`,
`kvlock = 1` y `exc = 0`.

El archivo de prueba de 1024 bytes se arma de forma reproducible con el ensayo
del caso 7 (903 bytes) más sus primeros 121 bytes. Los comandos, en orden, desde
la raíz del repositorio:

```bash
mkdir -p build
# 1. Archivo de prueba de exactamente 1024 bytes
(cat data/caso7_ensayo.txt; head -c 121 data/caso7_ensayo.txt) > build/cifrado_1024.txt
wc -c build/cifrado_1024.txt

# 2. Conversión a .mem desde 0x1000 y unión con las variables del programa
python3 tools/load_file.py --input build/cifrado_1024.txt \
  --output build/cifrado_archivo.mem --address 0x1000
cat programs/ejercicio3.mem build/cifrado_archivo.mem > build/cifrado_datos.mem

# 3. Ejecutar el programa (el volcado queda en build/ejercicio3/dump.mem)
make sim PROG=programs/ejercicio3 DATA=build/cifrado_datos.mem

# 4. Extraer el cifrado (0x2000) y el descifrado (0x3000), 1024 bytes cada uno
python3 tools/extract_data.py --memory build/ejercicio3/dump.mem \
  --address 0x2000 --size 1024 --output build/cifrado_enc_hw.bin
python3 tools/extract_data.py --memory build/ejercicio3/dump.mem \
  --address 0x3000 --size 1024 --output build/cifrado_dec_hw.bin

# 5a. El descifrado debe ser idéntico al original
cmp build/cifrado_dec_hw.bin build/cifrado_1024.txt && echo "PASS (a)"

# 5b. El cifrado debe ser idéntico al de la referencia en C (tools/feistel4_ref.c)
gcc -std=c99 -O2 -o build/feistel4_ref tools/feistel4_ref.c
build/feistel4_ref \
  --llave 19114957,-1985229329,324508639,610839776 \
  --llave2 286331153,572662306,858993459,1145324612 \
  --segmento 16 build/cifrado_1024.txt build/cifrado_enc_ref.bin
cmp build/cifrado_enc_hw.bin build/cifrado_enc_ref.bin && echo "PASS (b)"
```

El mismo flujo sirve para cualquier archivo de exactamente 1024 bytes; por ejemplo,
`data/imagen_1024.ppm` (imagen PPM de 22×15 píxeles) en lugar de `build/cifrado_1024.txt`.

Dónde queda cada cosa:

| Dirección | Contenido | Archivo extraído |
|---|---|---|
| `0x1000` | Archivo original (1024 bytes), cargado antes de ejecutar | `build/cifrado_1024.txt` (entrada) |
| `0x2000` | Cifrado producido por el procesador | `build/cifrado_enc_hw.bin` |
| `0x3000` | Descifrado producido por el procesador | `build/cifrado_dec_hw.bin` |

`make sim` no compara la memoria porque no existe `programs/ejercicio3.exp.mem`
(sin `EXP`, desactiva el esperado por defecto de `ejercicio1`). Las llaves de `feistel4_ref` son las mismas que carga el programa
(KA para la llave 0 y KB para la llave 1; ver `tools/run_ref.sh`).

Resultado esperado con memoria principal y divisor 4: el TB imprime
`Llegada al fin en el ciclo 139832` y
`PASS tb_programa`, y las dos comparaciones `cmp` terminan sin diferencias. El
límite de 2000000 ciclos del TB es suficiente.

**Advertencia.** Si `auth` falla (un token distinto del de la cadena de
Lamport), queda `EXC = 1` y las escrituras de bóveda y `feis` no se ejecutan.
En ese caso `0x2000` queda con el texto plano y el descifrado de `0x3000`
"pasa" aunque no se cifró nada. Por eso la comparación (b) con `feistel4_ref`
es la que valida el cifrado; (a) sola no basta. El token provisional
`1234567` de versiones anteriores del ejercicio producía exactamente esta falla.

`tb_programa` imprime al final una línea informativa con el estado de CRYPTO
(`auth=… kvlock=… exc=…`), sin comprobarla. En el ejercicio 3 se espera
`auth=0 kvlock=1 exc=0`.

## Ver la memoria después de simular

`tools/ver_mem.py` lee el volcado `build/<nombre>/dump.mem` (una palabra de 32 bits por
línea; la línea n corresponde a la dirección `4n`) y `make mem` lo invoca con la misma
resolución de `PROG` que `make sim`. Las variables son `DESDE` y `HASTA` (byte, decimal
o `0x..`; por defecto `0x0000`-`0x00FF`), `FORMATO` (`palabras` o `bytes`) y `EXP`.

```bash
# Palabras distintas de cero: dirección, hexadecimal y decimal con signo
make mem PROG=ejercicio1 DESDE=0 HASTA=0x48

# Hexdump: 16 bytes por línea en orden de memoria (little endian) y su texto ASCII
make mem PROG=programs/ejercicio3 FORMATO=bytes DESDE=0x1000 HASTA=0x103F   # texto original
make mem PROG=programs/ejercicio3 FORMATO=bytes DESDE=0x2000 HASTA=0x203F   # cifrado (ilegible)
make mem PROG=programs/ejercicio3 FORMATO=bytes DESDE=0x3000 HASTA=0x303F   # descifrado (igual al original)

# Comparar con un archivo de esperados: OK/FALLA por palabra, resumen y código de salida 1 si falla
make mem PROG=ejercicio1 EXP=programs/ejercicio1.exp.mem
```

Sin `make`, el script admite además `--todas` (incluye las palabras en cero) y
`--contra otro_dump.mem` (imprime solo las palabras que difieren en el rango):

```bash
python3 tools/ver_mem.py build/ejercicio3/dump.mem --desde 0x1000 --hasta 0x13FF \
  --contra build/ejercicio3/dump.mem
```

Si no existe el volcado, `make mem` indica `Primero corre make sim PROG=<nombre>`. Un rango
fuera de `0x0000`-`0xFFFF` o un archivo inexistente terminan con un mensaje de error.

## Ondas y diagnóstico

```bash
make waves_crypto_unit
bash tools/open_wave.sh build/tb_top.vcd
```

Los TB actuales de CRYPTO y del procesador guardan sus VCD en `build/`;
algunos TB anteriores los guardan en la raíz. La ruta exacta aparece en la
salida de `$dumpfile`. `waves_nombre` supone `build/tb_nombre.vcd`; para otra
ruta se usa `open_wave.sh` con el archivo correspondiente.

En GTKWave se agregan las señales de interés y se ajusta el zoom al intervalo
completo. Para estudiar `auth` se observan `crypto_stall`, `ex_valid`,
`ex_commit`, PC y las habilitaciones de escritura. Los estados internos también
pueden consultarse por la jerarquía del TB.

Un aviso de `$readmemh` por menos palabras que la profundidad indica que el
archivo no llena toda la memoria; el resto ya fue inicializado en cero. En
cambio, un archivo que no se puede abrir debe corregirse antes de interpretar
los resultados. Los valores `X` o `Z`, los mensajes `FAIL` y `$fatal` requieren
revisar reset, rutas, operandos y resultados esperados. `make clean` elimina
`build/` y los VCD de la raíz, incluidos resultados que se quieran conservar.

## Memoria principal por líneas

`make tb_main_memory` compila y corre únicamente `tb/tb_main_memory.sv` como
raíz; `make all` lo descubre sin modificar el Makefile. Instancia simultáneamente
`MEM_DIV=2,4,5`, con latencias de 39, 53 y 60 ciclos del procesador
(P2 §§3.2.5, 3.4, 5.3; decisión M-10 de `microarchitecture.md` §6).

Carga `data/main_memory/lines.mem` mediante índices de palabra; comprueba una
línea conocida, el extremo superior de RAM y palabras no cargadas en cero.
Prueba escritura completa, máscara parcial repartida entre palabras y carriles,
máscara cero, lecturas posteriores, latencia exacta de lectura/escritura en
TODAS las fases del divisor, pedidos consecutivos y un válido sostenido durante
busy. Un monitor cuenta independientemente aceptaciones, finalizaciones,
lecturas, escrituras y ciclos; verifica cada pulso de fin, busy bajo junto con
done, handshake recuperado, estabilidad de la salida pública y ausencia de
timeouts. Un monitor en cada subida lenta compara RAM y response antes y
después del flanco: solo puede cambiar la palabra transferida (y sus bytes
habilitados en escritura). Comprueba ocho palabras en ocho flancos consecutivos,
sin huecos ni duplicados, con la última anterior a TMEM. Para cada fase del
divisor prueba un par escritura→lectura: el segundo pedido se acepta en el
flanco inmediatamente posterior a done. Además comprueba la aceptación
inmediata de un pedido presentado antes de done y sostenido durante busy. También verifica
reset asíncrono y persistencia de RAM. La secuencia previa al reset tiene
`6+MEM_DIV` lecturas, `4+MEM_DIV` escrituras y `(10+2*MEM_DIV)*TMEM` ciclos de
transferencia. Un límite global de simulación evita esperas infinitas.
Cada instancia y el total imprimen `Casos: N; Fallos: N`; fallos terminan en
`$fatal`. Los casos incluyen comprobaciones por ciclo, no solo transacciones.

Para ver la traza por ciclo del primer acceso de divisor 4 (incluye también
una lectura después del reset):

```bash
make tb_main_memory
vvp build/tb_main_memory +TRACE_MEMORY
```

Prueba explícita del vigilante, separada de la regresión normal:

```bash
vvp build/tb_main_memory +TEST_TIMEOUT
```

Fuerza `dut.req_sync=0` en la instancia de divisor 4, sin cambiar el diseño.
Antes del ciclo 106 el contador permanece en cero; al llegar a 106 aparece
UN `$error` esperado, se registra una vez aunque siga colgado y, al liberar
el force, se comprueba la recuperación. Esa línea `ERROR` es intencional
exclusivamente en este modo; la corrida normal no contiene errores. Icarus
puede devolver cero aun cuando `$error` imprime un diagnóstico: deben
inspeccionarse el mensaje esperado y `Fallos: 0` además del código de salida.
El `$error` del vigilante está en un proceso de simulación separado del
`always_ff`: la compilación normal con Icarus no genera avisos nuevos.


## Métricas del procesador

`tb_programa` fotografía los siete contadores de
`dut.u_core.u_perf_counters` al detectar por primera vez el salto terminal en
ID. La foto corresponde al ciclo de `Llegada al fin`, antes de los cinco
ciclos de drenaje posteriores. Funciona con cualquier `PROG`, sin cambios de
código por programa. Como referencia histórica, antes de integrar la memoria
principal el flujo de ejercicio3 imprimía:

```text
Llegada al fin en el ciclo 17084
Rendimiento: ciclos=17084 bundles=14771 instrucciones=13978 IPC=0.818
Pausas: saltos=2299 crypto=13 memoria=0 total=13; auth=1
PASS foto de ciclos coincide con llegada
PASS identidad de ciclos con ajuste del salto final
Identidad: ciclos - bundles - saltos - pausa_total - 2 + 1 = 0 (cumple)
```

El IPC se calcula como instrucciones/ciclos con división real y tres decimales.
Los bundles válidos de NOP cuentan como bundles, pero no suman instrucciones.
Los códigos libres no cuentan como operaciones. Stores, saltos no tomados y
operaciones CRYPTO sin escritura a registro sí cuentan si son no-NOP y su
bundle se confirma. El salto terminal en ID todavía no está confirmado en la
foto. `auth` indica las autenticaciones confirmadas observadas por el TB.

La constante de llenado es 2. Al tomar la foto, la redirección del salto
hacia el final ya está contada, pero su burbuja aún no se consumió en EX.
Por eso se resta 1 en la identidad comprobada:

```text
ciclos == bundles + saltos + pausa_total + 2 - 1
```

La comprobación suma un caso a `Casos` y, si no coincide, suma un fallo a
`Fallos`; el testbench termina con error cuando hay fallos. La diferencia
impresa después usa esa misma identidad ajustada y es cero en los cuatro
programas de validación. La explicación del punto de corte y la tabla completa
están en `microarchitecture.md` §7. También se compara automáticamente el ciclo
fotografiado contra el de llegada. No se cambian los contadores de hardware
ni el instante de la foto.

`make tb_perf_counters` ejecuta la prueba unitaria con 167 comprobaciones:
ciclos sin confirmación, bundles de 0..4 operaciones, redirecciones, pausas de
cada causa y ambas a la vez, confirmación después de pausa, anchos de 64 bits
y reset asíncrono entre flancos. Incluye pruebas con los decodificadores reales
para los 32 códigos de los cuatro slots y ambas selecciones del slot 1, y una
prueba del transporte por ID/EX: cuatro operaciones detenidas durante tres
ciclos se suman una vez al liberar la pausa. El Makefile lo incorpora a
`make all` sin modificación. Mantiene el formato `Casos: N; Fallos: N` y termina
con `$fatal` si falla alguna comprobación.

Validación completa: `make clean`, `make all`, `make sim PROG=ejercicio1`,
`make sim PROG=ejercicio2`, `make sim PROG=salto_doble` y el flujo de ejercicio3
con 1024 bytes descrito arriba. Se conservan los ciclos 230, 382, 8 y 17084.
En el flujo de cifrado también se comprueban descifrado idéntico a la entrada
y cifrado idéntico al de la referencia C. Los contadores nuevos no introducen
avisos de compilación en Icarus; se mantienen los avisos habituales de
`$readmemh` por archivos de instrucciones que no llenan la ROM.


## Ejecución sin caché y divisor de memoria

`top` conecta la LSU mediante `mem_adapter` a `main_memory`, cuya instancia
sigue llamándose `u_memory`. Ya no se usa la RAM combinacional dentro de top.
`make sim PROG=... MEM_DIV=n` pasa n al parámetro de top a través de la macro
del TB; admite 2, 4 o 5, y usa 4 por defecto. `make all` conserva el valor por
defecto. `make help` incluye esta variable.

```bash
make sim PROG=ejercicio1 MEM_DIV=2
make sim PROG=ejercicio2 MEM_DIV=4
make sim PROG=salto_doble MEM_DIV=5
make sim PROG=auth_lsu MEM_DIV=4
make sim PROG=ejercicio3 DATA=build/cifrado_datos.mem MEM_DIV=4
```

El flujo de preparación y comparación de los 1024 bytes de ejercicio3 descrito
arriba se mantiene; solo cambia el divisor seleccionado. El límite genérico de
`tb_programa` se amplía a 2000000 ciclos. La foto de fin incluye también los
contadores de memoria, antes de los cinco ciclos finales. Por ejemplo:

```text
Llegada al fin en el ciclo 2562
Rendimiento: ciclos=2562 bundles=202 instrucciones=167 IPC=0.065
Pausas: saltos=27 crypto=0 memoria=2332 total=2332; auth=0
Memoria: MEM_DIV=4 lecturas=27 escrituras=17 transferencia=2332 totales=2562 utilizacion=0.910226
PASS foto de ciclos coincide con llegada
PASS identidad de ciclos con ajuste del salto final
```

La utilización es `real(transferencia)/real(totales)`, con denominador no nulo.
Cada operación de palabra ocupa una línea completa, incluso si dos operaciones
consecutivas usan la misma línea; no hay caché ni agrupación de stores.
Los contadores principales de lectura/escritura cuentan aceptaciones, mientras
la transferencia suma TMEM por operación. `volcar_memoria_final` concentra el
único `$writememh` del TB, para sustituir después la obtención de datos finales
cuando haya cachés. Mantiene el volcado completo indexado por palabra.

`make tb_mem_adapter` ejecuta 621 comprobaciones entre los tres divisores:
lectura/escritura de palabra, máscaras de cada byte en las ocho posiciones,
espera de aceptación y ausencia de pedidos duplicados. `make tb_auth_lsu`
ejecuta 28 comprobaciones: cuatro sistemas con el programa de coexistencia,
tres con memoria principal y uno con respuesta inmediata. Verifica que el store
ocurra una vez, el load conserve su resultado, ambos auth terminen con sesión
válida y sin excepción y no se repita el cálculo de hash durante las esperas.

Para obtener la traza ciclo a ciclo de un lw y un bundle auth+sw con divisor 4:

```bash
make tb_auth_lsu
vvp build/tb_auth_lsu +TRACE_BASELINE
```

En esa traza, EX, req, listo, mem_stall, hecho, commit y crypto son los valores
consumidos antes de la subida; accepted y done son los pulsos registrados
justo después de esa misma subida. listo usa la indicación combinacional de
finalización de main_memory, de modo que commit coincide con el flanco de done.
La indicación evita un ciclo de retorno adicional al que consumiría observar
done registrado desde otro proceso secuencial.

Los TB antiguos conservan sus resultados esperados. Las ventanas de espera se
amplían solo por TMEM multiplicado por sus accesos, restando solape de auth
cuando corresponde. Los monitores de bundles en ID excluyen `stall` para contar
un bundle retenido una sola vez; los monitores de escrituras cuentan
aceptaciones en vez de ciclos con we alto. Los casos con llegada a un PC final
no lo consideran finalizado mientras una operación anterior en EX siga
esperando memoria. No se modifican los valores de datos, banderas o paralelismo.


Resultados de la línea base sin caché (los tres divisores):

| Programa | Antes | Lecturas | Escrituras | DIV=2 | DIV=4 | DIV=5 |
|---|---|---|---|---|---|---|
| ejercicio1 | 230 | 27 | 17 | 1946 | 2562 | 2870 |
| ejercicio2 | 382 | 73 | 27 | 4282 | 5682 | 6382 |
| salto_doble | 8 | 0 | 1 | 47 | 61 | 68 |
| auth_lsu | 41 | 4 | 2 | 249 | 333 | 375 |
| ejercicio3 | 17084 | 1245 | 1071 | 107408 | 139832 | 156044 |

Todos cumplen `ciclos = antes + TMEM*(lecturas+escrituras) - solape`.
El solape es cero excepto en auth_lsu, donde es 26 ciclos (dos auth).
Ejercicio3 confirma un auth con 13 ciclos de pausa CRYPTO, sin solape con sus
2316 accesos; las comparaciones de cifrado y descifrado pasan con cada divisor.
Las 15 ejecuciones pasan la identidad de ciclos del procesador y mantienen
las cantidades de bundles e instrucciones de la RAM combinacional.
