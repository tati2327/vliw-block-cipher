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

En este proyecto se desarrollará una Arquitectura VLIW Propia para Aplicaciones de Cifrado por Bloques
aplicando los conceptos de arquitectura de computadores en el diseño e implementación en SystemVerilog
de un procesador VLIW con una arquitectura del set de instrucciones (ISA) propia, orientada a la
aceleración de un algoritmo de cifrado por bloques tipo Feistel.

### Resumen de la arquitectura

| Parámetro     | Valor         |
| ------------- | ------------- |
| Tamaño de intrucción  | 	32 bits  |
| Tamaño Bundle  | 	128 bits |
| Cantidad registros generales	 | 16  |
| Tamaño inmediatos	 |   |
| Endian  | 	Little  |

### Tipos de instrucciones

Las codificaciones y formatos vigentes se describen en [docs/isa.md](docs/isa.md).
El bundle contiene ALU0, ALU1/CRYPTO, BRU y LSU; el slot 1 selecciona ALU1 o CRYPTO.

### Formato de las instrucciones VLIW

Cada instrucción VLIW (bundle) estará compuesta por 4 slots, cada uno dedicado
a una unidad funcional específica y ejecutado en paralelo durante el mismo ciclo de reloj.
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

Las unidades funcionales a utilizar para desarrollar un procesador VLIW son las siguientes:

- ALU0
- ALU1
- Crypto
- LSU
- BRU

---

## ⚙️ Tecnologías utilizadas

| Tecnología | Uso |
| --- | --- |
| `Verilog/SystemVerilog` | Diseño hardware |
| `Git/GitHub` | Control de versiones |

---

## Estructura del proyecto

```text
rtl/        Módulos SystemVerilog del procesador y de CRYPTO (rtl/prov/: provisionales)
tb/         Testbenches por módulo, subsistema y caso (tb_programa.sv: genérico, por macros)
tb/reference/ Generador en C de los vectores de auth_hash32
tools/      asm.py (ensamblador), load_file.py, extract_data.py, lamport.py,
            feistel4_ref.c (referencia en C) y scripts de validación
programs/   Programas en ensamblador (.s/.asm) y su .hex; .mem de datos y .exp.mem esperados
data/       Datos de prueba (.mem, .txt) y cadena Lamport de demostración
docs/       isa.md, microarchitecture.md, simulation.md, compiler-integration.md, img/, diagrams/
build/      Simulaciones y ondas generadas (ignorado por Git)
```

---

## 🚀 Instalación

Clona el repositorio:

```bash
git clone https://github.com/tati2327/vliw-block-cipher.git
```

---

## Cómo simular

Requisitos: make, Python 3, Icarus Verilog (`iverilog` y `vvp`, con soporte de `-g2012`) y GTKWave para ver ondas.

```bash
make tb_icarus      # comprueba la version de Icarus
make tb_<nombre>    # corre un testbench
make all           # corre todos
make crypto        # corre las ocho pruebas de CRYPTO
make waves_crypto_unit # corre el TB del subsistema y abre sus ondas
make clean          # borra lo generado
make help           # guía de targets, variables y ejemplos
```

Los nuevos TB de CRYPTO generan `build/tb_<nombre>.vcd`; los anteriores pueden
generar `tb_<nombre>.vcd` en la raíz. Se abren con GTKWave usando la ruta
correspondiente. `make sim` equivale a `make all`.

### Ensamblador y ejecución de programas

`tools/asm.py` es el ensamblador propio: traduce un programa `.asm` (un bundle por
línea, cuatro slots entre llaves) al `.hex` que carga el procesador.

```bash
python3 tools/asm.py programa.asm -o programa.hex
```

`make sim PROG=...` ejecuta cualquier programa en el testbench genérico
`tb/tb_programa.sv`, sin editarlo. Si falta el `.hex`, ensambla el `.asm`.

```bash
make sim PROG=ej1                                   # programs/ej1.hex
make sim PROG=programs/ejercicio3 DATA=build/cifrado_datos.mem
make sim PROG=programs/mi_prueba DESDE=0x40 HASTA=0x60
```

`PROG` es un nombre (`ej1` equivale a `programs/ej1`) o una ruta, con o sin
extensión. Variables opcionales: `DATA` (memoria de datos; por defecto
`<base>.mem`), `EXP` (memoria esperada; por defecto `<base>.exp.mem`), `DESDE` y
`HASTA` (rango de memoria a listar, en bytes) y `ASM` (ensamblador). Las ondas y
el volcado quedan en `build/<nombre>/ondas.vcd` y `build/<nombre>/dump.mem`
(`make waves_prog PROG=...` abre las ondas). Los detalles y el flujo de cifrado de
archivos están en [docs/simulation.md](docs/simulation.md).

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

(El volcado `build/ejercicio3/dump.mem` lo genera `make sim PROG=programs/ejercicio3`; ver abajo.)

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

La unidad pasa sus pruebas aisladas. El core y dispatch de esta rama todavía
mantienen la variante sin CRYPTO; Luis integra las conexiones y el arranque.
Los casos del procesador completo con CRYPTO todavía no se han validado.

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

<p align="center">
  ⭐ Proyecto académico de Arquitectura de Computadores 1 ⭐
</p>

---
