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
rtl/        Módulos SystemVerilog del procesador y de CRYPTO
rtl/prov/   Módulos provisionales, si se necesitan durante la integración
tb/         Testbenches por módulo, subsistema y caso
tools/      Herramientas de archivos, referencia y cadena Lamport
programs/   Programas ensamblador y archivos hex
data/       Datos de prueba y cadena Lamport de demostración
docs/       ISA, microarquitectura, diseño y guía de integración CRYPTO
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
```

Los nuevos TB de CRYPTO generan `build/tb_<nombre>.vcd`; los anteriores pueden
generar `tb_<nombre>.vcd` en la raíz. Se abren con GTKWave usando la ruta
correspondiente. `make sim` equivale a `make all`.

## CRYPTO implementada

Los siete módulos, sus ocho TB y `tools/lamport.py` están disponibles. La
cadena de demostración usa semilla `0xCAFEDECE`, 100 tokens y ancla
`0xFEFF95FF`. El reset normal conserva el ancla; el arranque protegido la
carga con `rst` e `init_anchor` activos en subida de reloj.

La unidad pasa sus pruebas aisladas. El core y dispatch de esta rama todavía
mantienen la variante sin CRYPTO; Luis integra las conexiones y el arranque.
Véanse [la guía de implementación](docs/crypto_implementation.md) y
[el diseño detallado](docs/diseno_crypto_ascon.md). Los casos del procesador
completo con CRYPTO todavía no se han validado.

## Estructura

| Carpeta | Contenido |
|---|---|
| `rtl/` | Módulos del procesador, uno por archivo |
| `rtl/prov/` | Módulos provisionales para integrar mientras falta el real |
| `tb/` | Testbenches, uno por módulo o subsistema |
| `programs/` | Programas en ensamblador (`.s`) y su `.hex` |
| `data/` | Archivos `.mem` de datos y volcados |
| `tools/` | Ensamblador, `load_file.py`, `extract_data.py`, referencia en C |
| `docs/` | Documentación técnica e imágenes |


---

---

<p align="center">
  ⭐ Proyecto académico de Arquitectura de Computadores 1 ⭐
</p>

---
