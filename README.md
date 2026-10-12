<p align="center">
  <img src="docs/images/logo.png" width="300">
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
| Tamaño Bundle  | 	160 bits | 
| Cantidad registros generales	 | 16  | 
| Tamaño inmediatos	 |   | 
| Endian  | 	Little  | 

### Tipos de instrucciones	
Se utilizarán instrucciones de los siguientes tipos

| Parámetro     | Valor         |
| ------------- | ------------- |
| R | 	Register |
| I | 	immediate |
| B | 	Branch |
| S | 	Store & Branch |
| J | 	jump |
| C | 	cifrado |
| A | 	arithmetic |
| K | 	key-vault |
| M | 	Move condicional |

### Formato de las instrucciones VLIW

Cada instrucción VLIW (bundle) estará compuesta por 5 slots, cada uno dedicado 
a una unidad funcional específica y ejecutado en paralelo durante el mismo ciclo de reloj.
```
            [                                Bundle	 160 bits                                 ]
            [ [ slot 32 bits] [ slot 32 bits] [ slot 32 bits] [ slot 32 bits] [ slot 32 bits] ]
```

### Registros

Para el desarrollo del procesador VLIW se estarán utilizando 16 registros, los cuales se describen a contiuación.

| Registers  | Descripcion   | Codificación en decimal | 
| -----------| ------------- | ----------------------- |
| rz | Constante cero cableada. Cualquier lectura retorna 0; escrituras se descartan.                | 0  |
| rl | Enlace de retorno (Return Address). JAL guarda aquí el PC de retorno; E lo usa para volver.   | 1  |
| rx |  General  | 2  |
| rg | Puntero global. Base para variables de módulo y tablas de saltos en Calser.| 3 |
| ra | Argumento 0 | 4  |
| rb |  Argumento 1 | 5 |
| rc |  Argumento 2 | 6 |
| rd |  Argumento 3 | 7 |
| ri | Iterador de ciclo I. Optimizado para la variable de control en ciclos S y L | 8 |
| rj | Iterador de ciclo J. Cálculo de índices de columnas en arreglos bidimensionales | 9 |
| rk | Buffer de llaves / Crypto. Registro de staging para cargar palabras hacia la Bóveda con KV_LOAD | 10  |
| re | Temporal de evaluación de expresiones. Cálculo intermedio de operaciones aritméticas. | 11 |
| rf | Registro dedicado de condición/flags para ifmov y resultado de slt | 12 |
| rh | Temporal general y cálculo de direcciones intermedias. | 13  |
| rs | Registro preservado (callee-saved). | 14 |
| rt | Registro preservado (callee-saved). | 15 |

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

##  Estructura del proyecto

```text

📦 vliw-block-cipher
│
├── 📄 README.md
├── 📄 LICENSE
├── 📄 .gitignore
│
├── 📁 docs
│   ├── 📄 arquitectura.md
│   ├── 📄 diseño.md
│   ├── 📄 resultados.md
│   └── 📁 images
│       ├── 🖼️ logo.png
│       ├── 🖼️ arquitectura.png
│       ├── 🖼️ diagrama.png
│       └── 🖼️ waveform.png
│
├── 📁 src
│   └── 📁 systemverilog
│       ├── 📁 processor
│       ├── 📁 crypto
│       ├── 📁 memory
│       └── 📁 common
│
├── 📁 simulations
│   └── 📁 icarus
│       ├── 🧪 tb_vliw_top.sv
│       ├── 🧪 tb_crypto.sv
│       ├── ⚙️ run.sh
│       └── 📁 results
|

```

---

## 🚀 Instalación

Clona el repositorio:

```bash
git clone https://github.com/tati2327/vliw-block-cipher.git
```

---

## Cómo simular

Requisitos: Icarus Verilog (`iverilog`, con soporte de `-g2012`) y GTKWave.

```bash
make tb_icarus      # comprueba la version de Icarus
make tb_<nombre>    # corre un testbench
make all            # corre todos
make clean          # borra lo generado
```

Las formas de onda (`.vcd`) se abren con `gtkwave tb_<nombre>.vcd`.

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
