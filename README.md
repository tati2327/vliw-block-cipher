<p align="center">
  <img src="docs/img/logo.png" width="300">
</p>

<h1 align="center"> Arquitectura VLIW para Cifrado de Bloques </h1>

<p align="center">
  Diseño e implementación de una arquitectura VLIW orientada al cifrado de bloques.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Architecture-VLIW-blue" alt="Architecture VLIW">
  <img src="https://img.shields.io/badge/Language-SystemVerilog-orange" alt="Language SystemVerilog">
  <img src="https://img.shields.io/badge/Course-CE4301-green" alt="Course CE4301">
</p>

---

## Arquitectura del ISA

El proyecto implementa en SystemVerilog un procesador VLIW con un conjunto de
instrucciones propio, orientado al cifrado por bloques tipo Feistel. El pipeline
tiene cuatro etapas, `IF → ID → EX → WB`, e integra la unidad CRYPTO y una
jerarquía de memoria de datos con L1, L2 y buffers de líneas.

La memoria de instrucciones es una ROM síncrona independiente. La configuración
por defecto usa la jerarquía completa de datos. También se puede ejecutar con
L1 o sin caché para comparar los resultados y los ciclos de ejecución.

### Resumen de la arquitectura

| Parámetro     | Valor         |
| ------------- | ------------- |
| Tamaño de instrucción  | 	32 bits  |
| Tamaño Bundle  | 	128 bits |
| Cantidad registros generales	 | 16  |
| Tamaño inmediatos	 | 18 bits con signo (formatos I y B); 22 bits con signo (J) |
| Endian  | 	Little  |

### Tipos de instrucciones

Las codificaciones y formatos vigentes se describen en [docs/isa.md](docs/isa.md).
El bundle contiene ALU0, ALU1/CRYPTO, BRU y LSU; el slot 1 selecciona ALU1 o CRYPTO.

### Formato de las instrucciones VLIW

Cada bundle contiene cuatro instrucciones de 32 bits, con una unidad asignada a
cada slot. Las unidades de EX trabajan en paralelo, mientras que la BRU resuelve
los saltos en ID. El bundle avanza como una unidad y se retiene si memoria o
CRYPTO necesitan esperar.

```
            [                                Bundle	 128 bits                                 ]
            [ [ slot 32 bits] [ slot 32 bits] [ slot 32 bits] [ slot 32 bits] ]
```

### Registros

El banco contiene 16 registros de 32 bits, `r0` a `r15`. `r0` (`rz`) devuelve
cero y descarta escrituras. `rl`, `rx` y `rg` son los alias de r1, r2 y r3;
`t0` a `t11` son los alias de r4 a r15. Los roles son convenciones del
ensamblador, descritas en [la ISA](docs/isa.md#8-banco-de-registros).

---

## 🎛️ Unidades Funcionales

El procesador integra las siguientes unidades funcionales.

- ALU0
- ALU1
- Crypto
- LSU
- BRU

---

## Jerarquía de memoria de datos

| Configuración | Componentes |
|---|---|
| `CACHE=0` | Adaptador de palabra a línea y memoria principal |
| `CACHE=1` | L1 de 4 KiB y 2 vías, write buffer de 4 líneas y memoria principal |
| `CACHE=2` por defecto | L1, write buffer, L2 de 16 KiB y 4 vías, eviction buffer de 8 líneas y memoria principal |

Las líneas tienen 32 bytes y la memoria principal almacena 64 KiB. L1 utiliza
LRU y L2 reemplazo mediante LFSR. La relación entre niveles es NINE, sin exigir
inclusión ni exclusividad. Las dos cachés usan escritura diferida, y los buffers
pueden responder una lectura con una línea pendiente de escritura.

`MEM_DIV=2`, `4` o `5` selecciona el reloj de memoria. Un acceso a memoria
principal cuesta `25 + 7*MEM_DIV` ciclos del sistema. Los aciertos de L1 no
agregan pausa y un acceso a L2 requiere ocho ciclos antes de resolver el acierto
o continuar hacia memoria. Los detalles están en [la microarquitectura](docs/microarchitecture.md).

## Documentación

| Documento | Contenido |
|---|---|
| [ISA](docs/isa.md) | Instrucciones, formatos y reglas para escribir programas |
| [Microarquitectura](docs/microarchitecture.md) | Etapas, interfaces y diagramas del procesador y la jerarquía de memoria |
| [Simulación](docs/simulation.md) | Herramientas, comandos, testbenches y flujo de cifrado de archivos |
| [Benchmarks de memoria](docs/benchmarks_memoria.md) | Recorridos, tamaños, comprobaciones y mediciones por vuelta |
| [Rendimiento](docs/rendimiento.md) | Resultados y análisis de las configuraciones y optimizaciones |

Las imágenes se guardan en [`docs/diagrams/`](docs/diagrams/) y se presentan con
sus explicaciones en el documento de microarquitectura.

## ⚙️ Tecnologías utilizadas

| Tecnología | Uso |
| --- | --- |
| `Verilog/SystemVerilog` | Diseño hardware |
| `Icarus Verilog` | Compilación y simulación (`iverilog -g2012`, `vvp`) |
| `Python 3` | Ensamblador, herramientas de carga y extracción, cadena Lamport |
| `gcc` | Referencia en C de Feistel4 (`tools/feistel4_ref.c`) |
| `GTKWave` | Visualización de ondas |
| `Git/GitHub` | Control de versiones |

---

## Estructura del proyecto

```text
rtl/        Procesador, CRYPTO, cachés, buffers y memoria principal (rtl/prov/: provisionales)
tb/         Testbenches por módulo, subsistema y caso (tb_programa.sv: genérico, por macros)
tb/reference/ Generador en C de los vectores de auth_hash32
tools/      asm.py (ensamblador), load_file.py, extract_data.py, lamport.py,
            feistel4_ref.c (referencia en C), bench_data.py, metricas.py y validación
programs/   Programas en ensamblador (.s/.asm) y su .hex; .mem de datos y .exp.mem esperados
data/       Datos de prueba (.mem, .txt) y cadena Lamport de demostración
docs/       ISA, microarquitectura, simulación, benchmarks y rendimiento
docs/diagrams/ Diagramas del diseño
docs/resultados/ Reportes y evidencias de validación
build/      Simulaciones y ondas generadas (ignorado por Git)
```

---

## 🚀 Instalación

Clona el repositorio y entra en su carpeta.

```bash
git clone https://github.com/tati2327/vliw-block-cipher.git
cd vliw-block-cipher
```

---

## Cómo simular

Requisitos: make, Python 3, Icarus Verilog (`iverilog` y `vvp`, con soporte de `-g2012`), gcc (referencia en C) y GTKWave para ver ondas.

```bash
make tb_icarus      # comprueba la version de Icarus
make tb_<nombre>    # corre un testbench
make all           # corre todos
make crypto        # corre las ocho pruebas de CRYPTO
make waves_crypto_unit # corre el TB del subsistema y abre sus ondas
make clean          # borra lo generado
make help           # guía de targets, variables y ejemplos
make mem PROG=<programa>  # muestra la memoria de la última simulación
```

Los nuevos TB de CRYPTO generan `build/tb_<nombre>.vcd`; los anteriores pueden
generar `tb_<nombre>.vcd` en la raíz. Se abren con GTKWave usando la ruta
correspondiente. `make sim` sin `PROG` equivale a `make all`; con `PROG=...` ejecuta un solo
programa (ver abajo).

### Ensamblador y ejecución de programas

`tools/asm.py` es el ensamblador propio: traduce un programa `.asm` (un bundle por
línea, cuatro slots entre llaves) al `.hex` que carga el procesador.

```bash
python3 tools/asm.py programa.asm -o programa.hex
```

`make sim PROG=...` ejecuta cualquier programa en el testbench genérico
`tb/tb_programa.sv`, sin editarlo. Si falta el `.hex`, ensambla el `.asm`.

```bash
make sim PROG=ejercicio1 CACHE=2 MEM_DIV=4          # jerarquía completa (por defecto)
make sim PROG=ejercicio1 CACHE=1 MEM_DIV=4          # L1 y write buffer, memoria a 25 MHz
make sim PROG=ejercicio1 CACHE=0 MEM_DIV=4          # línea base sin caché
make sim PROG=ejercicio1 VVP_ARGS=+LOG_MEM           # registro de accesos de palabra
make sim PROG=auth_lsu MEM_DIV=2                    # auth y LSU en el mismo bundle
make sim PROG=programs/ejercicio3 DATA=build/cifrado_datos.mem
make sim PROG=programs/mi_prueba DESDE=0x40 HASTA=0x60
```

`PROG` es un nombre (`ejercicio1` equivale a `programs/ejercicio1`) o una ruta, con o sin
extensión. `CACHE=2` (por defecto) conecta L1, write buffer, L2 y eviction buffer.
`CACHE=1` conecta L1 de 4 KiB y un write buffer de 4 líneas;
`CACHE=0` conecta el adaptador directo a memoria principal.
En las tres configuraciones, `MEM_DIV=2`, `4` o `5` selecciona 50, 25 o 20 MHz; el valor por
defecto es 4. Un acceso a memoria principal cuesta `25 + 7*MEM_DIV` ciclos;
un acierto de L1 o forwarding del write buffer no agrega pausa. El TB imprime
tablas del procesador, de los niveles de caché y buffers presentes, de memoria
y del monitor. El monitor comprueba cada load
y conserva los stores confirmados; de su copia salen los esperados y el volcado,
incluidos los datos todavía sucios en L1. `VVP_ARGS=+LOG_MEM` produce
`build/<nombre>/transacciones.txt`. Con caché se escribe `l1.txt` y con `CACHE=2`
también `l2.txt`. Variables opcionales: `DATA` (memoria de datos; por defecto
`<base>.mem`), `EXP` (memoria esperada; por defecto `<base>.exp.mem`), `DESDE` y
`HASTA` (rango de memoria a listar, en bytes) y `ASM` (ensamblador). Las ondas y
el volcado quedan en `build/<nombre>/ondas.vcd` y `build/<nombre>/dump.mem`
(`make waves_prog PROG=...` abre las ondas). Los detalles y el flujo de cifrado de
archivos están en [docs/simulation.md](docs/simulation.md).

Para ver la memoria después de simular (palabras con signo o volcado de bytes con ASCII):

```bash
make mem PROG=ejercicio1 DESDE=0 HASTA=0x48
make mem PROG=programs/ejercicio3 FORMATO=bytes DESDE=0x3000 HASTA=0x303F
```

### Herramienta de carga de archivos

`tools/load_file.py` convierte cualquier archivo (texto, imagen, binario) en un `.mem`
para la memoria de datos, desde la dirección indicada, e informa el tamaño y la
zona que ocupa. `tools/extract_data.py` extrae bytes del volcado de la simulación.

```bash
python3 tools/load_file.py --input data/caso7_ensayo.txt \
  --output build/entrada.mem --address 0x1000
python3 tools/extract_data.py --memory build/ejercicio3/dump.mem \
  --address 0x2000 --size 1024 --output build/resultado.bin
```

El `extract_data.py` de este ejemplo requiere haber corrido antes el ejercicio 3: el volcado
`build/ejercicio3/dump.mem` lo genera `make sim PROG=programs/ejercicio3` (ver abajo).

Para ese archivo de 903 bytes, `load_file.py` imprime `903 bytes, 0x1000–0x1386` y
`Archivo de memoria: build/entrada.mem`. Admite cualquier tipo de archivo; la dirección debe ser múltiplo de cuatro.

### Cifrar y descifrar un archivo (ejercicio 3)

El programa compilado `programs/ejercicio3.hex` solo recibe direcciones: lee el
archivo de `0x1000`, escribe el cifrado en `0x2000` y el descifrado en `0x3000`.
El archivo debe cargarse antes con `load_file.py` y unirse con
`programs/ejercicio3.mem` (las variables del programa). Hoy el programa está
compilado para **1024 bytes exactos**.

```bash
mkdir -p build
# Archivo de prueba de exactamente 1024 bytes
(cat data/caso7_ensayo.txt; head -c 121 data/caso7_ensayo.txt) > build/cifrado_1024.txt

# Cargar el archivo en 0x1000 y unirlo con las variables del programa
python3 tools/load_file.py --input build/cifrado_1024.txt \
  --output build/cifrado_archivo.mem --address 0x1000
cat programs/ejercicio3.mem build/cifrado_archivo.mem > build/cifrado_datos.mem

# Ejecutar y extraer cifrado (0x2000) y descifrado (0x3000)
make sim PROG=programs/ejercicio3 DATA=build/cifrado_datos.mem
python3 tools/extract_data.py --memory build/ejercicio3/dump.mem \
  --address 0x2000 --size 1024 --output build/cifrado_enc_hw.bin
python3 tools/extract_data.py --memory build/ejercicio3/dump.mem \
  --address 0x3000 --size 1024 --output build/cifrado_dec_hw.bin

# (a) el descifrado es idéntico al original
cmp build/cifrado_dec_hw.bin build/cifrado_1024.txt && echo "PASS (a)"

# (b) el cifrado es idéntico al de la referencia en C
gcc -std=c99 -O2 -o build/feistel4_ref tools/feistel4_ref.c
build/feistel4_ref \
  --llave 19114957,-1985229329,324508639,610839776 \
  --llave2 286331153,572662306,858993459,1145324612 \
  --segmento 16 build/cifrado_1024.txt build/cifrado_enc_ref.bin
cmp build/cifrado_enc_hw.bin build/cifrado_enc_ref.bin && echo "PASS (b)"
```

Al terminar, `tb_programa` imprime `auth=0 kvlock=1 exc=0` (estado de CRYPTO).

El mismo flujo cifra cualquier archivo de 1024 bytes, por ejemplo la imagen PPM
`data/imagen_1024.ppm` (22×15 píxeles, encabezado incluido):

```bash
python3 tools/load_file.py --input data/imagen_1024.ppm \
  --output build/imagen_archivo.mem --address 0x1000
cat programs/ejercicio3.mem build/imagen_archivo.mem > build/imagen_datos.mem
make sim PROG=programs/ejercicio3 DATA=build/imagen_datos.mem
python3 tools/extract_data.py --memory build/ejercicio3/dump.mem \
  --address 0x2000 --size 1024 --output build/imagen_enc_hw.ppm
python3 tools/extract_data.py --memory build/ejercicio3/dump.mem \
  --address 0x3000 --size 1024 --output build/imagen_dec_hw.ppm
cmp build/imagen_dec_hw.ppm data/imagen_1024.ppm && echo "PASS (a)"
gcc -std=c99 -O2 -o build/feistel4_ref tools/feistel4_ref.c
build/feistel4_ref \
  --llave 19114957,-1985229329,324508639,610839776 \
  --llave2 286331153,572662306,858993459,1145324612 \
  --segmento 16 data/imagen_1024.ppm build/imagen_enc_ref.ppm
cmp build/imagen_enc_hw.ppm build/imagen_enc_ref.ppm && echo "PASS (b)"
```

Validación, en dos comprobaciones:
- **(a)** el descifrado del procesador es idéntico al original.
- **(b)** el cifrado del procesador es idéntico al de la referencia en C
  `tools/feistel4_ref.c`, con las llaves `KA=19114957,-1985229329,324508639,610839776`
  y `KB=286331153,572662306,858993459,1145324612` y `--segmento 16`.

El armado del archivo de 1024 bytes, la compilación de la referencia y la tabla de
direcciones están en [docs/simulation.md](docs/simulation.md#ejercicio-3-cifrado-con-el-compilador).

## CRYPTO implementada

Los siete módulos, sus ocho TB y `tools/lamport.py` están disponibles. La
cadena de demostración usa semilla `0xCAFEDECE`, 100 tokens y ancla
`0xFEFF95FF`. El reset normal conserva el ancla; el arranque protegido la
carga con `rst` e `init_anchor` activos en subida de reloj.

La unidad está integrada en el procesador (`core` y `dispatch`, con el arranque protegido en `top`)
y validada tanto aislada (`make crypto`) como en el procesador completo (`tb_caso4_feis` a
`tb_caso7_mixto`, `tb_top` y el ejercicio 3 del compilador).

### Cadena Lamport

`tools/lamport.py` implementa la H del diseño: Ascon-Hash256 de cuatro bytes
little-endian, truncada a los primeros cuatro bytes (entero little-endian).
Solo usa la biblioteca estándar de Python.

```bash
make lamport       # regenera la cadena y comprueba los hashes contra auth_hash32.sv
make tb_lamport    # ya incluye la generación
python3 tools/lamport.py --seed 0xCAFEDECE --length 10 --out build/otra_cadena
```

Semilla `0xCAFEDECE`, longitud 100. Los tokens se presentan de x99 a x0:

```text
Ancla inicial: x100 = 0xFEFF95FF
Primer token:  x99  = 0xF47BD70B
Segundo token: x98  = 0xA45326BA
```

El hardware acepta x99 y lo guarda como ancla; luego necesita x98. Una longitud
N produce N tokens y N+1 eslabones. Archivos generados en `data/lamport_demo/`:
`chain.json` (semilla, ancla, cadena y tokens), `tokens.mem` (x99 a x0, uno por
línea), `hash_vectors.mem` (pares entrada/hash para contrastar Python con RTL) y
`lamport_config.svh` (`LAMPORT_RESET_ANCHOR` y `LAMPORT_TOKEN_COUNT`).

### Vectores de `auth_hash32`

Los ocho valores esperados de `tb_auth_hash32` se obtuvieron el 12 de octubre de
2026 con `crypto_hash/asconhash256/ref/hash.c` de
[ascon/ascon-c](https://github.com/ascon/ascon-c) (rama `main`, NIST SP 800-232;
SHA-256 de `hash.c`:
`336045b5329f52f48807390c0e8ac2f0b0fb8fae3b92715ffcae74fb919cd5a8`). Cada token
son cuatro bytes little-endian y el esperado son los primeros cuatro bytes del
hash como entero little-endian. El caso `03020100` → `EDC7E4D7` coincide con
Count=5 del
[KAT publicado](https://github.com/ascon/ascon-c/blob/main/crypto_hash/asconhash256/LWC_HASH_KAT_128_256.txt).

El testbench usa valores fijos y no necesita la referencia ni Internet
(`make tb_auth_hash32`). Para regenerarlos, con `ascon-c` descargado en
`/tmp/ascon-c-main`:

```bash
cc -std=c99 -Wall -Wextra \
  -I/tmp/ascon-c-main/crypto_hash/asconhash256/ref \
  -I/tmp/ascon-c-main/tests \
  tb/reference/generate_auth_hash32_vectors.c \
  /tmp/ascon-c-main/crypto_hash/asconhash256/ref/hash.c \
  -o /tmp/generate_auth_hash32_vectors
/tmp/generate_auth_hash32_vectors
```

---

## Mediciones de memoria

Los cinco programas de prueba permiten comparar lectura secuencial, saltos de
ocho palabras, orden aleatorio de líneas, escritura y lectura con escritura.
Cada ejecución realiza cuatro vueltas sin reiniciar la caché entre ellas.

Se puede elegir una prueba pequeña o la matriz completa.

```console
# Solo L1, con 1 KiB y divisor 4, cinco ejecuciones
make metricas TAMANOS=1 DIVISORES=4 CACHES=1 METRICAS_OUT=build/metricas-l1

# Comparación pequeña de las tres configuraciones, quince ejecuciones
make metricas TAMANOS=1 DIVISORES=4 METRICAS_OUT=build/metricas-mini

# Matriz completa, 135 ejecuciones
make metricas
```

La matriz completa combina cinco programas, tamaños de 1, 8 y 32 KiB, tres
divisores y `CACHE=0`, `1` y `2`. Conserva las métricas globales y las de cada
uno de los cuatro recorridos. La primera vuelta comienza con los datos del
arreglo sin precargar y las siguientes reutilizan el estado de la jerarquía.
Los resultados se guardan en la carpeta elegida con `METRICAS_OUT`, o en
`build/metricas` por defecto. Para comparar los tres tamaños con un solo divisor
se usa `make metricas DIVISORES=4`.

La preparación de datos, las comprobaciones y el significado de las columnas
se explican en [la metodología de los benchmarks](docs/benchmarks_memoria.md).

Los casos controlados de escritura se ejecutan con `make costos_bench`. Sus
muestras quedan en `build/costos_controlados.csv`. Las entradas grandes se
regeneran con `make datos_bench` y quedan fuera del control de versiones.

### Mostrar los resultados en la terminal

Al terminar `make metricas`, el resumen se imprime con columnas alineadas.
El archivo `metricas.md` también conserva esa alineación al leerlo con `cat`.
Para mostrar mediciones que ya existen sin repetir las simulaciones se usa el
siguiente comando, indicando la carpeta donde se guardaron.

```console
python3 tools/metricas.py --show build/metricas-l1
```

### Comparar las tres configuraciones de memoria

El resumen presenta una fila por programa, tamaño y `CACHE`, con ciclos, IPC,
hit rate y miss rate de L1 y L2, AMAT medido y AMAT de fórmula para la jerarquía
completa. Otra tabla muestra las líneas recibidas, forwarding, ciclos lleno y
ocupación máxima del write buffer y del eviction buffer, además de las pausas
de L2 por eviction buffer lleno. Las tasas se calculan con lecturas y escrituras
del intervalo; en L2 se usan las solicitudes ya clasificadas, porque la
aceptación precede a su búsqueda de ocho ciclos. Las pendientes de clasificación
se informan por separado. Las columnas no aplicables se muestran como `—`.

El AMAT medido es `1 + pausa_memoria/accesos_cpu` con caché y
`pausa_memoria/accesos_cpu` sin caché. La fórmula de referencia para `CACHE=2`
es `1 + miss_L1 * (8 + miss_L2 * (25 + 7*MEM_DIV))`; no incluye todos los efectos
de colas y solapamiento. La mejora compara contra `CACHE=0` manteniendo fijos
el programa, tamaño, divisor y cantidad de recorridos. Una selección parcial
muestra las configuraciones ausentes como `No medido`.

```console
make metricas CACHES="0 1 2" DIVISORES=4 METRICAS_OUT=build/metricas-l2
python3 tools/metricas.py --show build/metricas-l2
```

---

<p align="center">
  ⭐ Proyecto académico de Arquitectura de Computadores 1 ⭐
</p>
