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
| `ccom` | Ensambla programas externos con `-x`; se obtiene del proyecto de la contraparte. |

`ccom` es una dependencia externa y no se compila con este Makefile. Si no está
en `PATH`, se invoca mediante la ruta de su ejecutable.

## Representación del procesador

El procesador usa palabras de 32 bits y bundles de 128 bits con cuatro slots:
ALU0, ALU1/CRYPTO, BRU y LSU. El slot 1 selecciona ALU1 o CRYPTO. El pipeline
tiene etapas IF, ID, EX y WB; las memorias permiten lectura combinacional, sin
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
profundidad devuelve cero. La memoria de datos lee combinacionalmente y escribe
en subida, con una habilitación por cada byte; el reset no borra su contenido.
El hardware indexa datos con los bits bajos de la dirección de palabra; las
herramientas comprueban el rango de 64 KiB para evitar direcciones que se solapen.

Los datos usan little endian. Por ejemplo, los bytes `48 6F 6C 61` (`Hola`)
se representan mediante la palabra `616C6F48`. La dirección de byte `0x1000`
corresponde a la marca `@400` en un `.mem`.

## Ensamblado y ejecución de un programa

El modo `-x` de `ccom` ensambla directamente una entrada en la sintaxis de la
ISA, sin pasar por la compilación del lenguaje Calser:

```bash
mkdir -p build
ccom -x programs/ej1.asm -o build/ej1.bin
```

La salida incluye `build/ej1.hex`, `build/ej1.bin` y `build/ej1.mem`. El procesador
simulado carga el `.hex`, no el `.bin`. El modo `-x` genera un `.mem` sin datos
iniciales (solo la marca `@0`); los datos de entrada se preparan aparte cuando
el programa los necesita. El ensamblador admite el archivo `.s` usado por el
usuario; los ejemplos de `ccom` emplean la extensión `.asm`.

El testbench genérico permite seleccionar programa, datos y resultados esperados
con las macros `PROG_HEX`, `PROG_MEM` y `EXP_MEM`. Este ejemplo ejecuta el programa
ensamblado y contrasta la memoria con los resultados de `ej1`:

```bash
iverilog -g2012 -Wall -I data/lamport_demo -s tb_programa \
  '-DPROG_HEX="build/ej1.hex"' \
  '-DPROG_MEM=""' \
  '-DEXP_MEM="programs/ej1.exp.mem"' \
  -o build/tb_programa rtl/*.sv tb/tb_programa.sv
vvp build/tb_programa
```

Para otro programa se cambian esas rutas. Si no hay archivo de resultados,
`'-DEXP_MEM=""'` desactiva la comparación de memoria; en ese caso el TB solo
comprueba la finalización y la ausencia de valores desconocidos en las señales
que observa. No valida por sí solo el resultado del algoritmo.

El TB reconoce el final mediante `jef 0`, espera cinco ciclos adicionales y
limita la ejecución a 50000 ciclos antes de declarar fallo. No existe una
instrucción de apagado del simulador en el procesador: el TB llama a `$finish`.
Guarda el volcado completo en `build/tb_programa_dump.mem`, imprime los registros
(`r4 = 120 (0x00000078)`: decimal con signo y hexadecimal), lista las palabras de
datos distintas de cero (`0x0044: 120 (0x00000078)`) y genera `build/tb_programa.vcd`. Un resultado `PASS` termina sin error;
una comprobación fallida termina mediante `$fatal`.

La lista de memoria es solo informativa (no es una comprobación). Su rango, en
direcciones de byte, se elige con las macros `MEM_DESDE` (por defecto `0`) y
`MEM_HASTA` (por defecto `4095`, `0x0FFF`), por ejemplo
`-DMEM_DESDE=8192 -DMEM_HASTA=8208` en la línea de `iverilog` para `0x2000`-`0x2010`.

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
make all                  # todos los testbenches; make sim es equivalente
make crypto               # ocho testbenches del subsistema CRYPTO
make tb_top               # procesador integrado, incluida la pausa de auth
make tb_programa          # programa ej1 y resultados predeterminados
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

`load_file.py` agrupa bytes en palabras, completa la última palabra con ceros
y requiere una dirección inicial múltiplo de cuatro. Para ejecutar ese archivo
se pasa `build/entrada.mem` como `PROG_MEM` al TB. El procesamiento Feistel de
bloques de 64 bits requiere además que el programa maneje el relleno y la
cantidad de bloques apropiados. `extract_data.py` recibe la longitud original
en bytes (903 en este ejemplo) para recuperar el archivo sin relleno. Ambos
scripts comprueban rangos; la extracción rechaza palabras ausentes o desconocidas.

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
