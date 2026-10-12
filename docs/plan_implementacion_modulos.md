# Plan de implementación por módulo — CE 4301

**Grupo 6 · 11 de octubre de 2026 · Entrega: 14 de octubre de 2026**

Para cada tarea de `plan_trabajo_arquitectura.md`: qué se implementa, dónde está
la especificación, qué hay que cuidar y **los casos exactos del testbench** con
su resultado esperado. La especificación es `microarchitecture.md` (oficial
desde el 11 de octubre); ante cualquier diferencia con `isa.md`, manda `isa.md`.

**Regla:** el código se escribe a partir de `microarchitecture.md` §4. Si algo no
cuadra, se corrige primero el documento y después el código, nunca al revés en
silencio.

---

## Contenido

0. [Convenciones](#0-convenciones)
1. [Bloque 0 — Preparación](#1-bloque-0--preparación)
2. [Bloque 1 — Componentes](#2-bloque-1--componentes)
3. [Bloque 2 — Herramientas](#3-bloque-2--herramientas)
4. [Bloque 3 — Subsistemas](#4-bloque-3--subsistemas)
5. [Bloque 4 — Procesador](#5-bloque-4--procesador)
6. [Bloque 5 — Casos del enunciado](#6-bloque-5--casos-del-enunciado)
7. [Bloque 6 — Validación conjunta](#7-bloque-6--validación-conjunta)
8. [Módulos provisionales](#8-módulos-provisionales)
9. [Integración de un módulo real](#9-integración-de-un-módulo-real)
10. [Problemas típicos](#10-problemas-típicos)

---

## 0. Convenciones

### 0.1 Estructura de archivos

```
rtl/        un módulo por archivo, con el mismo nombre del módulo
rtl/prov/   provisionales (se borran al integrar el real)
tb/         un testbench por módulo o subsistema
programs/   .s y .hex de los casos de prueba
data/       .mem de entrada y volcados
tools/      ensamblador, load_file.py, extract_data.py, lamport, referencia en C
docs/       isa.md, microarchitecture.md, simulation.md, compiler-integration.md, img/
Makefile
```

Los provisionales declaran el módulo con el **nombre real** (`module alu`, no
`module alu_prov`), para que `core` no cambie al integrar. Solo el nombre del
archivo lleva `_prov`.

### 0.2 Código

| Tema | Regla |
|---|---|
| Herramienta | Icarus Verilog, `iverilog -g2012 -Wall`; formas de onda en GTKWave |
| Registros | `always_ff @(posedge clk or posedge rst)`, reset asíncrono activo alto. **Excepción:** la escritura del `regfile` usa `negedge clk` |
| Combinacional | `always_comb` con **valor por defecto** para todas las salidas al inicio; sin *latches* |
| Asignación | No bloqueante (`<=`) en `always_ff`; bloqueante (`=`) en `always_comb` |
| Puertos con varios elementos | Arreglos empaquetados: `logic [N-1:0][W-1:0]` |
| Cabeceras | Exactamente las de `microarchitecture.md` §4.3 |
| Instancias | Prefijo `u_` |
| Señales | `idex_s0_rd`, `exwb_s3_result`, `id_branch_taken` (§3.14) |
| Comentarios | Cada bloque cita la sección de `isa.md` o `microarchitecture.md` que implementa (enunciado §5.1) |

### 0.3 Testbenches

- **Autoverificables:** cada caso compara contra el valor esperado e imprime
  `PASS` o `FAIL` con su nombre; al final, el total de fallos.
- **`.vcd` siempre:** `$dumpfile("tb_x.vcd"); $dumpvars(0, tb_x);`.
- **Reloj:** `always #5 clk = ~clk;` (periodo 10). El flanco de bajada cae a
  mitad del ciclo, lo que permite comprobar la escritura del `regfile`.
- **Combinacionales:** poner entradas, esperar `#1`, comparar.
- **Estado interno:** se lee por jerarquía (`dut.u_core.u_regfile.regs[5]`); no
  se agregan puertos de depuración.
- **Esperado escrito antes de correr**, en la tabla de casos de este documento.
  Si el resultado no coincide, primero se revisa el esperado contra la
  especificación, y después el código.

Esqueleto de comprobación:

```systemverilog
int fallos = 0;
task automatic check(string nombre, logic [31:0] obtenido, logic [31:0] esperado);
  if (obtenido === esperado) $display("PASS %s", nombre);
  else begin
    $display("FAIL %s: obtenido %h, esperado %h", nombre, obtenido, esperado);
    fallos++;
  end
endtask
// al final: $display("Fallos: %0d", fallos); $finish;
```

`===` en lugar de `==` hace que un valor `X` cuente como fallo.

---

## 1. Bloque 0 — Preparación

### Tarea 1 · Arreglos empaquetados en Icarus (F-03)

Si Icarus no los acepta como puertos, cambian las cabeceras de `regfile`,
`dispatch` y `core` (`decisiones_arquitectura.md` DA-16). Se prueba antes de
escribir cualquier módulo.

```systemverilog
module m (input logic [7:0][3:0] a, output logic [7:0][3:0] y);
  assign y = a;
endmodule
module t;
  logic [7:0][3:0] a, y;
  m u (.a, .y);
  initial begin
    a = 32'h06000043; #1;
    if (y[0] == 4'd3 && y[1] == 4'd4 && y[6] == 4'd6) $display("PASS");
    else $display("FAIL");
  end
endmodule
```

**Terminado:** imprime `PASS` con la versión de Icarus de todos los integrantes.

### Tarea 2 · Repositorio

Estructura de §0.1, rama `main` protegida, una rama por tarea
(`feat/regfile`, `feat/ensamblador`…), un *issue* por tarea y un *milestone* por
bloque. Un PR se acepta cuando su testbench pasa y alguien más lo revisó.

### Tarea 3 · `Makefile` mínimo

```make
IV   = iverilog -g2012 -Wall
RTL  = $(wildcard rtl/*.sv)
PROV = $(wildcard rtl/prov/*.sv)

tb_%: tb/tb_%.sv
	@mkdir -p build
	$(IV) -o build/$@ $(RTL) $(PROV) $< && vvp build/$@

.PHONY: all clean
all: $(patsubst tb/%.sv,%,$(wildcard tb/tb_*.sv))
clean: ; rm -rf build *.vcd
```

Mientras un módulo tenga a la vez versión real y provisional, se borra el
provisional (si no, Icarus reporta el módulo duplicado).

---

## 2. Bloque 1 — Componentes

### Tarea 4 · `pipe_reg`

| | |
|---|---|
| Archivo | `rtl/pipe_reg.sv` |
| Especificación | `microarchitecture.md` §3.13, §4.3, §4.5 |
| Clave | Prioridad `rst` > `flush` > `en`. `flush` es **síncrono** (DA-17). `en = 0` conserva (pausa de `auth`) |
| Testbench | `tb_pipe_reg`, con `W = 8` |

| # | Caso | Estímulo | Esperado |
|---|---|---|---|
| 1 | Reset asíncrono | `q = 0x5A`; subir `rst` a mitad del ciclo | `q = 0` antes del siguiente flanco |
| 2 | Carga normal | `en = 1`, `d = 0x11`, flanco ↑; `d = 0x22`, flanco ↑ | `q = 0x11`, luego `0x22` |
| 3 | `flush` | `d = 0x33`, `flush = 1`, flanco ↑ | `q = 0` |
| 4 | `flush` a mitad del ciclo | `q = 0x44`; subir `flush` a mitad del ciclo | `q = 0x44` hasta el flanco ↑; después `0` |
| 5 | `rst` y `flush` | Ambos en 1 | `q = 0` |
| 6 | `en = 0` | `q = 0x55`, `en = 0`, `d = 0x66`, 3 flancos | `q = 0x55` |
| 7 | `flush` y `en = 0` | `q = 0x77`, `flush = 1`, `en = 0`, flanco ↑ | `q = 0` |

### Tarea 5 · `regfile`

| | |
|---|---|
| Archivo | `rtl/regfile.sv` |
| Especificación | §3.1, §4.1, §4.3, §4.5 |
| Clave | Escritura en `negedge`; bucle sobre los 4 slots en orden (gana el mayor); `waddr != 0`; lectura combinacional con `assign` |
| Testbench | `tb_regfile` |

```systemverilog
always_ff @(negedge clk or posedge rst)
  if (rst) regs <= '0;
  else for (int s = 0; s < NUM_SLOTS; s++)
         if (we[s] && waddr[s] != 0) regs[waddr[s]] <= wdata[s];
```

| # | Caso | Estímulo | Esperado |
|---|---|---|---|
| 1 | Reset | `rst = 1` | Los 16 registros en 0 |
| 2 | Escritura simple | `we[0] = 1`, `waddr[0] = 5`, `wdata[0] = 0xCAFE` | Tras el flanco ↓, `rdata` de un puerto con `raddr = 5` es `0xCAFE` |
| 3 | `r0` | Escribir `0x1234` en `r0` | Leer `r0` da 0 |
| 4 | 4 escrituras | Slots 0–3 escriben `r1`=1, `r2`=2, `r3`=3, `r4`=4 | Los 4 quedan |
| 5 | Prioridad | Slot 1 escribe `r6 = 0xAAAA` y slot 3 `r6 = 0xBBBB` | `r6 = 0xBBBB` |
| 6 | `we = 0` | `waddr = 7`, `wdata = 0x99`, `we = 0` | `r7` no cambia |
| 7 | 8 lecturas | `raddr` = {1,2,3,4,5,6,7,8} con valores distintos cargados | Cada `rdata[p]` es su registro |
| 8 | Mismo registro en 8 puertos | Los 8 `raddr = 7` | Los 8 iguales |
| 9 | Escribir y leer en el mismo ciclo | Escribir `r9 = 0x1111` (viejo 0); `raddr[0] = 9` | Antes del flanco ↓: 0; después: `0x1111` |
| 10 | Solo flanco ↑ | Cambiar `we`/`wdata` y comprobar justo después de un flanco ↑, antes del ↓ | El registro no cambia |

### Tarea 6 · `fetch`

| | |
|---|---|
| Archivo | `rtl/fetch.sv` |
| Especificación | §3.12, §4.3, §4.5 |
| Clave | Incrementador propio (DA-21); `stall` tiene prioridad sobre el salto |
| Testbench | `tb_fetch` |

| # | Caso | Estímulo | Esperado |
|---|---|---|---|
| 1 | Reset | `rst = 1` | `pc = 0` |
| 2 | Avance | 4 flancos sin salto | `pc` = 1, 2, 3, 4 |
| 3 | Salto adelante | `branch_taken = 1`, `branch_target = 8` | `pc = 8` tras el flanco |
| 4 | Salto atrás | Desde `pc = 8`, destino 2 | `pc = 2` |
| 5 | Reset a mitad | `pc = 5`; subir `rst` a mitad del ciclo | `pc = 0` de inmediato |
| 6 | `stall` | `stall = 1` 3 flancos; luego `stall = 0` | `pc` fijo; después `pc + 1` |
| 7 | `stall` y salto | `stall = 1`, `branch_taken = 1` | `pc` no cambia |

### Tarea 7 · `alu_dec` + `alu`

| | |
|---|---|
| Archivos | `rtl/alu_dec.sv`, `rtl/alu.sv` |
| Especificación | §3.2, §3.3, tabla `alu_dec` de §4.8 |
| Clave | `slt = N ^ V`; desplazamientos con `op2[4:0]`; `$signed` en `sra`; `cond_ok` usa `b`, nunca `imm`; `default` en el `case` |
| Testbench | `tb_alu` (nombre que exige el enunciado §7.2). Prueba `alu` sola y `alu_dec` sola |

**`alu`** (`imm` se pone con `use_imm = 1` donde corresponde)

| # | Operación | `a`, `b` / `imm` | Esperado `y` | `cond_ok` |
|---|---|---|---|---|
| 1 | `add` | `0x7FFFFFFF`, `1` | `0x80000000` | 1 |
| 2 | `sub` | `0`, `1` | `0xFFFFFFFF` | 1 |
| 3 | `slt` | `0x7FFFFFFF`, `0x80000000` | `0` | 1 |
| 4 | `slt` | `0x80000000`, `0x7FFFFFFF` | `1` | 1 |
| 5 | `slt` | `-1`, `0` | `1` | 1 |
| 6 | `slt` / `sle` | `5`, `5` | `0` / `1` | 1 |
| 7 | `seq` / `sne` | `7`, `7` | `1` / `0` | 1 |
| 8 | `sra` / `srl` | `0x80000000`, `4` | `0xF8000000` / `0x08000000` | 1 |
| 9 | `sll` | `1`, `33` | `2` | 1 |
| 10 | `and` | `0xF0F0`, `0xFF00` | `0xF000` | 1 |
| 11 | `or` | `0xF0`, `0x0F` | `0xFF` | 1 |
| 12 | `xor` | `0xFF`, `0x0F` | `0xF0` | 1 |
| 13 | `xori` | `0xFF`, imm `0x0F` | `0xF0` | 1 |
| 14 | `saddi` | `5`, imm `0xFFFFFFFF` (−1) | `4` | 1 |
| 15 | `mov` | `a = 123`, imm `0xABC` | `0xABC` | 1 |
| 16 | `ifmov` | `0xDEAD`, `b = 0` | `0xDEAD` | **0** |
| 17 | `ifmov` | `0xDEAD`, `b = 5` | `0xDEAD` | 1 |
| 18 | `add` con `b = 0` | `3`, `0` | `3` | 1 |
| 19 | `alu_op = 1110` | cualquiera | `0` | 1 |

**`alu_dec`**

| # | `funct` | Esperado |
|---|---|---|
| 1 | Los 16 válidos de la tabla §4.8 | Su `alu_op`, su `use_imm` y `we = 1` |
| 2 | `00000` (`nopi`) | `we = 0` |
| 3 | `01110`, `01111`, `10011`, `11111` | `we = 0` |

### Tarea 8 · `memory`

| | |
|---|---|
| Archivo | `rtl/memory.sv` |
| Especificación | §3.6, §1.5 |
| Clave | Arreglo de palabras; `idx = addr[AW+1:2]`; escritura en flanco ↑ por carril; inicializar en 0 y luego `$readmemh` |
| Testbench | `tb_memory`, con `INIT_FILE = "data/hola.mem"` (`@400` / `616C6F48`) |

| # | Caso | Estímulo | Esperado |
|---|---|---|---|
| 1 | Carga del `.mem` | Leer `0x1000` | `0x616C6F48` (bytes H, o, l, a) |
| 2 | Posición sin cargar | Leer `0x0000` | `0` |
| 3 | `sw` | `0x12345678` en `0x2000`, `be = 1111` | Leer `0x2000` = `0x12345678` |
| 4 | `sb` | `be = 0100`, `wdata = 0x00AA0000` en `0x2000` | `0x12AA5678` |
| 5 | `we = 0` | `be = 1111`, `wdata = 0xFFFFFFFF` | No cambia |
| 6 | `be = 0000` | `we = 1` | No cambia |
| 7 | Dirección no alineada | Leer `0x2002` | La palabra de `0x2000` |
| 8 | Reflejo | Leer `0x12000` | La palabra de `0x2000` |
| 9 | Escribir y leer en el mismo ciclo | `sw` en `0x3000` y leer `0x3000` | Viejo antes del flanco ↑; nuevo después |
| 10 | Volcado | `$writememh` y comparar con el formato del `.mem` | Mismo formato |

### Tarea 9 · `imem`

| | |
|---|---|
| Archivo | `rtl/imem.sv` |
| Especificación | §3.7, §1.5 |
| Clave | Fuera de rango entrega **cero**, no recorta la dirección |
| Testbench | `tb_imem`, con `INIT_FILE = "programs/ejemplo_isa11.hex"` |

`programs/ejemplo_isa11.hex` (de `isa.md` §11):

```
00000000_00000000_49400003_49000000
00000000_00000000_00000000_00000000
00000000_0D500000_00000000_41100001
```

| # | Caso | `addr` | Esperado |
|---|---|---|---|
| 1 | Programa | 0, 1, 2 | Las tres líneas |
| 2 | Sin programa | 3 | `0` |
| 3 | Última posición | `DEPTH − 1` | `0` (o su contenido si se cargó) |
| 4 | Fuera de rango | `DEPTH`, `DEPTH + 1` | `0`, **no** el bundle 0 |
| 5 | Máximo | `2^22 − 1` | `0` |
| 6 | `.hex` con `_` y `//` | Igual al caso 1 con comentarios | Mismo contenido |

### Tarea 10 · `lsu_dec` + `lsu`

| | |
|---|---|
| Archivos | `rtl/lsu_dec.sv`, `rtl/lsu.sv` |
| Especificación | §3.4, §3.5, tabla de §4.8 |
| Clave | *Little endian*: el carril 0 es el byte menos significativo; `lb` con signo |
| Testbench | `tb_lsu` |

`dmem_rdata` lo pone el testbench (sin `memory`).

| # | Caso | Estímulo | Esperado |
|---|---|---|---|
| 1 | `lw` no alineado | `base = 0x1000`, `imm = 2`, `rdata = 0x7F80FF01` | `dmem_addr = 0x1002`, `load_data = 0x7F80FF01`, `we = 0`, `be = 0000` |
| 2 | `sw` | `sdata = 0x12345678` | `wdata = 0x12345678`, `we = 1`, `be = 1111` |
| 3–6 | `sb` en carriles 0–3 | `sdata = 0x123456AA`, `imm` = 0..3 | `be` = `0001`, `0010`, `0100`, `1000`; `wdata` = `000000AA`, `0000AA00`, `00AA0000`, `AA000000` |
| 7 | `lb` carril 2 | `rdata = 0x7F80FF01`, `imm = 2` | `0xFFFFFF80` |
| 8 | `lb` carril 3 | ídem, `imm = 3` | `0x0000007F` |
| 9 | `lb` carriles 0 y 1 | ídem, `imm = 0`, `1` | `0x00000001`, `0xFFFFFFFF` |
| 10 | Desplazamiento negativo | `base = 0x1004`, `imm = −4` | `dmem_addr = 0x1000` |
| 11 | Sin operación | Control en 0 | `we = 0`, `be = 0000`, `wdata = 0`, `load_data = 0` |
| 12 | `lsu_dec` | Los 5 de la tabla §4.8 y `00101`, `11111` | Su fila; libres → `000` |

### Tarea 11 · `bru_dec` + `bru`

| | |
|---|---|
| Archivos | `rtl/bru_dec.sv`, `rtl/bru.sv` |
| Especificación | §3.8, §3.9, tabla de §4.8 |
| Clave | `off` extendido con signo a 22 bits; `jefR` absoluto con `a[21:0]`; comparación con signo |
| Testbench | `tb_bru` |

`instr_low` se arma con el campo que corresponda (`off` en bits 17..0,
`target` en 21..0).

| # | Caso | Estímulo | Esperado |
|---|---|---|---|
| 1 | `blt` tomado con negativo | `a = −3`, `b = 5`, `pc = 10`, `off = −2` | `taken = 1`, `target = 8`, `link = 11` |
| 2 | `bge` no tomado | `a = −1`, `b = 1` | `taken = 0` |
| 3 | `beq` adelante | `a = b = 7`, `pc = 10`, `off = +5` | `taken = 1`, `target = 15` |
| 4 | `bne` con iguales | `a = b` | `taken = 0` |
| 5 | Condiciones falsas | `beq` con `a ≠ b`, `blt` con `a > b`, `bge` con `a < b`, `bne` con `a = b` | `taken = 0` en los 4 |
| 6 | `jef` atrás | `pc = 100`, `target = −40` | `taken = 1`, `target = 60` |
| 7 | `jas` | `pc = 100`, `target = +40` | `taken = 1`, `target = 140`, `link = 101` |
| 8 | `jefR` | `a = 0x00400065` | `taken = 1`, `target = 0x65` |
| 9 | Ninguno | `br_op = 000` | `taken = 0` |
| 10 | `bru_dec` válidos | Los 8 de la tabla §4.8 | Su `br_op` y su `we` |
| 11 | `bru_dec` libres | Los 24 restantes | `br_op = 000`, `we = 0` |

### Tareas 12 a 14 · CRYPTO por partes

| | |
|---|---|
| Archivos | `rtl/key_vault.sv`, `rtl/auth_hash32.sv`, `rtl/crypto_state.sv`, `rtl/crypto_control.sv`, `rtl/crypto_datapath.sv`, `rtl/crypto_dec.sv` |
| Especificación | §3.10 y el diseño de Saddy (sus diagramas de nivel 3); tabla `crypto_dec` de §4.8 |
| Clave | El estado cambia solo con `ex_commit`; ningún puerto expone la bóveda, el ancla ni las banderas; `crypto_dec` valida los 5 bits |

Los casos internos de `crypto_state`, `crypto_control` y `crypto_datapath` los
define Saddy desde su diseño, que no está en este documento. Como mínimo:

**`tb_key_vault`** (nombre que exige el enunciado §7.2)

| # | Caso | Esperado |
|---|---|---|
| 1 | Reset | Las 16 palabras en 0 |
| 2 | Escribir las 16 palabras (`k`, `w` = 0..3) con valores distintos | Cada lectura por `k`, `i` devuelve la suya |
| 3 | Escritura con habilitación en 0 | No cambia |
| 4 | Reset después de cargar | Todo en 0 |

**`tb_auth_hash32`**

| # | Caso | Esperado |
|---|---|---|
| 1 | Vectores de NIST SP 800-232 con la codificación de §3.10 (entrada `{32'h1, token}`, bytes del token de menor a mayor peso) | Salida truncada igual al vector |
| 2 | Latencia | Termina exactamente en el ciclo 14 desde la carga |
| 3 | Dos hash seguidos | El segundo no arrastra estado del primero |

**`tb_crypto_dec`**

| # | Caso | Esperado |
|---|---|---|
| 1 | Los 7 de la tabla §4.8 | Su `crypto_op`; `we = 1` solo en `feis` |
| 2 | `00111`–`11111` | `crypto_op = 000`, `we = 0` |

### Tarea 15 · `dispatch`

| | |
|---|---|
| Archivo | `rtl/dispatch.sv` |
| Especificación | §3.11, §2.5, §4.3, §4.5 |
| Clave | Puerto B: bits 17..14 en los slots 0 y 1; bits 25..22 en los slots 2 y 3. `s1_we = sel ? we_crypto : we_alu`. `s1_crypto_op = sel ? op : 000` |
| Testbench | `tb_dispatch`. Funciona con los decodificadores reales o con provisionales; se vuelve a correr al integrar los reales |

Bundles en el orden `slot3_slot2_slot1_slot0`.

| # | Caso | Bundle | Esperado |
|---|---|---|---|
| 1 | Traza de §3.11 | `05D80000_0D0FFFFE_98100000_054D0000` | `rf_raddr` (puerto 7 a 0) = {7, 6, 4, 3, 0, 4, 4, 3}; slot 0: suma, `rd = 5`, `we = 1`; slot 1: `sel = 1`, `crypto_op = 110`, `we = 0`; slot 2: `br_op = 011`, `instr_low = 0x0FFFFE`, `we = 0`; slot 3: `is_load = 1`, `rd = 7`, `imm = 0` |
| 2 | Vectores de `isa.md` §6.5 | `add` `054D0000` (slot 0), `feis` `854D0800` y `sanc` `98100000` (slot 1), `blt` `0D0FFFFE` (slot 2), `lw` `05D80000` (slot 3) | Campos de la tabla de cada vector |
| 3 | Bundle vacío | Todo en 0 | Los 4 `we = 0`, `crypto_op = 000`, `br_op = 000`, sin carga ni almacenamiento |
| 4 | Bloqueo de CRYPTO | Slot 1 = `054D0000` (`add`, `sel = 0`) | `crypto_op = 000`, `s1_we = 1` (de `alu_dec`) |
| 5 | CRYPTO en el slot 1 | Slot 1 = `854D0000` (mismo `funct` con `sel = 1` = `feis r5, r3, r4, 0, 0`) | `crypto_op = 001`, `s1_we = 1` (de `crypto_dec`) |
| 6 | Inmediato negativo | Slot 0 = `4113FFFF` (`saddi t0, t0, −1`) | `s0_imm = 0xFFFFFFFF` |
| 7 | Inmediato máximo | Slot 0 = `4901FFFF` (`mov t0, 131071`) | `s0_imm = 0x0001FFFF` |
| 8 | `sel` en el slot 0 | Slot 0 = `C9000000` (`mov t0, 0` con bit 31 en 1) | Igual que `49000000`: `mov`, `rd = 4`, `we = 1` |
| 9 | Puerto B en los slots 2 y 3 | Slot 3 = `sw` con fuente distinta de los bits 17..14 | `rf_raddr[7]` = bits 121..118 |

---

## 3. Bloque 2 — Herramientas

### Tarea 16 · Ensamblador propio

| | |
|---|---|
| Archivo | `tools/asm.py` (o el lenguaje que elija su responsable) |
| Entrada | Sintaxis de `isa.md` §11 |
| Salida | `.hex` de `microarchitecture.md` §1.5: un bundle por línea, slot 3 a la izquierda, grupos de 8 dígitos separados por `_` |
| Uso | `./asm.py programa.s -o programa.hex` |
| Clave | Dos pasadas: la primera asigna a cada etiqueta el índice de su bundle; la segunda codifica, con `destino = etiqueta − PC`. Pone `sel = 1` en el slot 1 cuando la instrucción es de CRYPTO |

| # | Caso | Entrada | Esperado |
|---|---|---|---|
| 1 | Vectores de `isa.md` §6.5 | `add r5, r3, r4` en el slot 0, `lw r7, 0(r6)` en el 3, `blt r3, r4, -2` en el 2, `feis r5, r3, r4, 0, 2` y `sanc r4` en el 1 | `054D0000`, `05D80000`, `0D0FFFFE`, `854D0800`, `98100000` |
| 2 | Vectores de `crypto_para_ccom.md` §1 | `auth t0`, `logout`, `kv_write t1, 0, 3`, `kv_lock` | `88100000`, `8C000000`, `90140C00`, `94000000` |
| 3 | Programa de `isa.md` §11 | El programa con `inicio:` y `lazo:` | Las 3 líneas de `programs/ejemplo_isa11.hex`, idénticas |
| 4 | Etiqueta hacia adelante | `beq` a una etiqueta 3 bundles adelante | `off = +3` |
| 5 | Alias | `t0` y `r4` | Misma codificación |
| 6 | Inmediato hexadecimal y negativo | `mov t0, 0x1F`, `saddi t0, t0, -1` | `imm` = `0x1F`, `0x3FFFF` |
| 7 | Comentarios y líneas vacías | `#` al final y líneas en blanco | Se ignoran |
| 8–13 | Errores de `isa.md` §11.4 | Bundle con 3 slots · `lw` en el slot 0 · `mov t0, 200000` · etiqueta no definida y duplicada · dos slots con el mismo `rd` (salvo `rz`) · mnemónico inventado | Rechaza cada uno con un mensaje que indica la línea |

### Tarea 17 · Referencia en C de la Fig. 1

| | |
|---|---|
| Archivo | `tools/feistel4_ref.c` |
| Contenido | `ROL32`, `feistel4_F`, `feistel4_encrypt` y `feistel4_decrypt` **copiados tal cual** de la Fig. 1, más un `main` |
| Uso | `./feistel4_ref llave.txt entrada.bin salida.bin [-d]`, o con valores fijos en el código |

| # | Caso | Esperado |
|---|---|---|
| 1 | Una ronda (`feistel4_F` sola) con `x` y `K` conocidos | Imprime el valor; es el esperado del caso 4 |
| 2 | Cifrar un bloque con la llave 0 de `crypto_para_ccom.md` §6 | Imprime `L` y `R`; esperado del caso 5 |
| 3 | Cifrar y descifrar 1 KB | El descifrado es idéntico a la entrada (`cmp`) |
| 4 | Orden de bytes | Lee `L` y `R` en *little endian*, igual que `lw` |

### Tarea 18 · Script de la cadena de Lamport

| | |
|---|---|
| Archivo | `tools/lamport.py` |
| Contenido | `H(x)` = Ascon-Hash256 de 4 bytes truncado a 32 bits, con la **misma codificación** que `auth_hash32`; genera `w0 → … → wN` |
| Salida | `RESET_ANCHOR` (para el hardware) y los tokens en orden de uso (para los programas) |

| # | Caso | Esperado |
|---|---|---|
| 1 | `H` contra los vectores de NIST usados en `tb_auth_hash32` | Mismos valores |
| 2 | `H(w[N−1]) == RESET_ANCHOR` | Verdadero |
| 3 | En simulación: `auth` con `w[N−1]` y luego con `w[N−2]` | Los dos exitosos |
| 4 | Reusar `w[N−1]` | Falla |

### Tarea 19 · `load_file.py` y `extract_data.py`

| | |
|---|---|
| Archivos | `tools/load_file.py`, `tools/extract_data.py` |
| Interfaz | La del enunciado §5.4.3 |
| Formato | `.mem` de `microarchitecture.md` §1.5: `@` en palabras, 4 bytes por línea en *little endian* |

```bash
./load_file.py    --input archivo.txt --output datos.mem --address 0x1000
./extract_data.py --memory volcado.mem --address 0x3000 --size 4096 --output resultado.bin
```

| # | Caso | Entrada | Esperado |
|---|---|---|---|
| 1 | Texto corto | `Hola` en `0x1000` | `@400` y `616C6F48`; informa «4 bytes, 0x1000–0x1003» |
| 2 | Tamaño no múltiplo de 4 | 5 bytes | Última palabra completada con ceros; informa 5 bytes |
| 3 | Dirección no alineada | `--address 0x1001` | Error |
| 4 | Fuera de la memoria | Archivo que pasa de `0xFFFF` | Error |
| 5 | Ida y vuelta de texto | `.txt` → `load_file` → `extract_data` con el mismo tamaño | Idéntico (`cmp`) |
| 6 | Ida y vuelta binaria | 1 KB aleatorio y una imagen | Idénticos |
| 7 | Volcado de `$writememh` | Leer el volcado de `tb_memory` | Lo lee sin errores |

---

## 4. Bloque 3 — Subsistemas

### Tarea 20 · IF + ID (`tb_front`)

Instancia `fetch`, `u_ifid_bundle`, `u_ifid_pc`, `dispatch`, `regfile` e
`imem` con `programs/ejemplo_isa11.hex`. El testbench hace de BRU: maneja
`branch_taken` y `branch_target` a mano.

| # | Caso | Esperado |
|---|---|---|
| 1 | Arranque | El bundle 0 llega a ID en el ciclo 2 (§3.12) |
| 2 | Avance | En cada ciclo, `ifid_pc` = PC del ciclo anterior |
| 3 | Salto a 8 | En el flanco siguiente: PC = 8 e IF/ID vacío |
| 4 | Direcciones | `rf_raddr` corresponde al bundle que está en IF/ID |

### Tarea 21 · WB (`tb_wb`)

Instancia `u_exwb_s0` … `u_exwb_s3` y `regfile`. El testbench hace de EX.

| # | Caso | Esperado |
|---|---|---|
| 1 | Un resultado entra a EX/WB en el flanco ↑ | Se escribe en el flanco ↓ de ese mismo ciclo |
| 2 | Leer ese registro en la segunda mitad | Valor nuevo |
| 3 | 4 slots a la vez | Los 4 quedan |
| 4 | `we = 0` | No se escribe |

### Tarea 22 · `crypto_unit` armada (`tb_crypto_unit`)

Nombre que exige el enunciado §7.2. El testbench maneja `en`, `crypto_op`, `k`,
`i`, `a`, `b`, `ex_valid` y `ex_commit` como lo haría `core`. Necesita
`RESET_ANCHOR` y un token de la tarea 18, y los valores de F de la tarea 17.

| # | Caso | Esperado |
|---|---|---|
| 1 | Reset | `AUTH = KVLOCK = EXC = 0`, ancla = `RESET_ANCHOR`, bóveda en 0 |
| 2 | `feis` sin `AUTH` | `allowed = 0`, `EXC = 1`, `result = 0` |
| 3 | `auth` con token incorrecto | Tras 14 ciclos: `AUTH = 0`, `EXC = 1`, ancla sin cambio |
| 4 | `auth` con el token correcto | `crypto_stall = 1` durante 13 ciclos; luego `AUTH = 1`, `EXC = 0`, ancla = token |
| 5 | Reusar el mismo token | Falla como el caso 3 |
| 6 | `kv_write` de las 16 palabras con `AUTH` | Bóveda cargada (por jerarquía) |
| 7 | `feis` con `AUTH` | `result = a XOR F(b, subllave[k][i])` = tarea 17; `allowed = 1` |
| 8 | `kv_lock` y luego `kv_write` | `kv_write` rechazado, `EXC = 1`, la palabra no cambia |
| 9 | `sanc` con `AUTH` | Ancla = `a` |
| 10 | `logout` | `AUTH = 0` |
| 11 | `sanc` y `kv_lock` sin `AUTH` | Sin efecto, `EXC = 1` |
| 12 | Aislamiento | En toda operación distinta de `feis`, `result = 0` |
| 13 | `ex_commit = 0` | Ninguna operación cambia el estado |

### Tarea 23 · `lsu` + `memory` (`tb_lsu_mem`)

| # | Caso | Esperado |
|---|---|---|
| 1 | `sb` en el carril 2 de `0x7F80FF01` (cargado con `.mem`), `sdata = 0x123456AA` | La palabra queda `0x7FAAFF01` |
| 2 | `sw` y en el ciclo siguiente `lw` a la misma dirección | El `lw` lee el valor nuevo |
| 3 | `lb` sobre la palabra del caso 1, carril 2 | `0xFFFFFFAA` |

---

## 5. Bloque 4 — Procesador

### Tarea 24 · `core` + `top` (`tb_top`)

| | |
|---|---|
| Archivos | `rtl/core.sv`, `rtl/top.sv` |
| Especificación | §2, §3.14, §4.3, §4.4 (orden de bits), §4.5 (`we` final de EX), §2.11 (pausa y bits de validez) |
| Clave | Concatenar y separar cada `pipe_reg` en el **mismo orden** de §4.4; las líneas de EX de §3.14 (`ex_commit`, `dmem_we`, `id_redirect`); los 3 bits de validez |

Cada caso es un programa pequeño ensamblado con la tarea 16 (mientras no exista,
el `.hex` de `isa.md` §11 está verificado y sirve para el caso 1).

| # | Caso | Programa | Esperado |
|---|---|---|---|
| 1 | Traza de §4.6 | `ejemplo_isa11.hex` | `pc`, `ifid_pc`, `idex_pc`, `exwb_pc`, `id_branch_taken`, `r4` y `r5` iguales a la tabla en los ciclos 1 a 14; `r4 = 4` al final |
| 2 | Varios bundles en vuelo | El mismo | Desde el ciclo 4, las cuatro etapas con bundles distintos en el `.vcd` |
| 3 | Dependencia a 1 bundle | `mov t0, 5` y en el bundle siguiente `add t1, t0, rz` | `t1 = 0` (valor viejo) |
| 4 | Dependencia a 2 bundles | `mov t0, 5`, `nopi`, `add t1, t0, rz` | `t1 = 5` |
| 5 | Salto tomado | Bundle con `mov t2, 1` y `jef +2`; el siguiente con `mov t3, 1` | `t2 = 1`, `t3 = 0` |
| 6 | `ifmov` falso | `mov t0, 7`, `nopi`, `ifmov t0, t1, rz` | `t0 = 7` |
| 7 | Slot 1: ALU contra CRYPTO | `add` en el slot 1; luego `feis` sin sesión | `add` escribe; `feis` no escribe y `EXC = 1` |
| 8 | `sw` → `lw` | `sw` y en el bundle siguiente `lw` a la misma dirección | Valor nuevo |
| 9 | Fin del programa | Correr 50 ciclos más que el programa | PC sigue avanzando; ningún registro cambia; no vuelve al bundle 0 |
| 10 | Pausa de `auth` | `auth` con token válido | PC, IF/ID e ID/EX fijos 13 ciclos; WB con burbujas |
| 11 | `auth` con `sw` y `add` en el mismo bundle | — | El `sw` escribe una vez; el `add` escribe una vez |
| 12 | Salto en ID durante la pausa | `auth` seguido de un bundle con `jef` | El salto se aplica una sola vez, al reanudar |

---

## 6. Bloque 5 — Casos del enunciado

Cada caso: `programs/casoN.s` → ensamblador → `casoN.hex` → `tb_casoN` con
`top`. El testbench comprueba registros por jerarquía y memoria con
`$writememh` o por jerarquía. Los programas de abajo respetan la separación de 1
bundle; su codificación la produce el ensamblador.

### Tarea 25 · Caso 1: ALU en paralelo con otras unidades

```
  { mov t0, 5       | mov t1, 7       | nopi              | nopi }
  { nopi            | nopi            | nopi              | nopi }
  { add t2, t0, t1  | sub t3, t1, t0  | nopi              | sw t0, 64(rz) }
  { xor t4, t0, t1  | slt t5, t0, t1  | nopi              | nopi }
  { and t6, t0, t1  | or t7, t0, t1   | beq t0, t0, fin   | lw t8, 64(rz) }
  { mov t9, 99      | nopi            | nopi              | nopi }   # se descarta
fin:
  { nopi            | nopi            | nopi              | nopi }
```

| Registro o memoria | Esperado | Qué demuestra |
|---|---|---|
| `t2`, `t3` | 12, 2 | Dos ALU en el mismo bundle que un `sw` |
| `mem[64]` | 5 | LSU en paralelo |
| `t4`, `t5` | 2, 1 | |
| `t6`, `t7`, `t8` | 5, 7, 5 | 4 slots activos a la vez (ALU, ALU, BRU, LSU) |
| `t9` | 0 | El bundle siguiente al salto se descarta |

### Tarea 26 · Caso 2: `lw`, `sw`, `lb`, `sb`

`DMEM_INIT` con `0x7F80FF01` en `0x1000`.

```
  { mov t0, 4096    | mov t1, 170     | nopi | nopi }              # t1 = 0xAA
  { nopi            | nopi            | nopi | nopi }
  { mov t8, 4104    | nopi            | nopi | lw t2, 0(t0) }
  { nopi            | nopi            | nopi | lb t3, 2(t0) }
  { nopi            | nopi            | nopi | lb t4, 3(t0) }
  { nopi            | nopi            | nopi | sb t1, 2(t0) }
  { nopi            | nopi            | nopi | lw t5, 0(t0) }      # justo después del sb
  { nopi            | nopi            | nopi | sw t2, 4(t0) }
  { nopi            | nopi            | nopi | lw t6, 6(t0) }      # no alineado
  { nopi            | nopi            | nopi | lw t7, -4(t8) }     # desplazamiento negativo
```

| Registro o memoria | Esperado |
|---|---|
| `t2` | `0x7F80FF01` |
| `t3` | `0xFFFFFF80` (`lb` con signo) |
| `t4` | `0x0000007F` |
| `t5` | `0x7FAAFF01` (`sb` cambia un byte; `sw`→`lw` sin separación) |
| `t6` | `0x7F80FF01` (palabra de `0x1004`) |
| `t7` | `0x7F80FF01` |
| `mem[0x1000]`, `mem[0x1004]` | `0x7FAAFF01`, `0x7F80FF01` |

### Tarea 27 · Caso 3: saltos

```
  { mov t0, -3 | mov t1, 5 | nopi                | nopi }   # 0
  { nopi       | nopi      | nopi                | nopi }   # 1
  { nopi       | nopi      | blt t0, t1, b4      | nopi }   # 2  tomado
  { mov t2, 1  | nopi      | nopi                | nopi }   # 3  no se ejecuta
b4:
  { nopi       | nopi      | bge t0, t1, b6      | nopi }   # 4  no tomado
  { mov t3, 1  | nopi      | nopi                | nopi }   # 5  se ejecuta
b6:
  { nopi       | nopi      | beq t0, t0, b8      | nopi }   # 6  tomado
  { mov t4, 1  | nopi      | nopi                | nopi }   # 7  no se ejecuta
b8:
  { nopi       | nopi      | bne t0, t0, b10     | nopi }   # 8  no tomado
  { mov t5, 1  | nopi      | nopi                | nopi }   # 9  se ejecuta
b10:
  { nopi       | nopi      | jas rl, sub         | nopi }   # 10 llamada
  { nopi       | nopi      | jef b16             | nopi }   # 11 al volver
  { mov t6, 1  | nopi      | nopi                | nopi }   # 12 no se ejecuta
  { nopi       | nopi      | nopi                | nopi }   # 13
sub:
  { mov t7, 1  | nopi      | nopi                | nopi }   # 14
  { nopi       | nopi      | jefR rz, rl         | nopi }   # 15 retorno a 11
b16:
  { mov t8, 1  | nopi      | nopi                | nopi }   # 16
fin:
  { nopi       | nopi      | jef fin             | nopi }   # 17 salto a sí mismo
```

| Esperado | Valor |
|---|---|
| `t2`, `t4`, `t6` | 0 (saltados) |
| `t3`, `t5`, `t7`, `t8` | 1 |
| `rl` | 11 |
| Secuencia de PC en ID | 0, 1, 2, 4, 5, 6, 8, 9, 10, 14, 15, 11, 16, 17, 17… (con un bundle vacío después de cada salto tomado) |

Cubre los 4 condicionales tomados y no tomados (con signo en `blt`/`bge`),
`jef` adelante y a sí mismo, `jas` y `jefR`.

### Tarea 28 · Caso 4: una ronda `feis`

Programa: `auth` con un token de la tarea 18, cargar las 4 palabras de la llave
0 con `kv_write` (cada palabra con la secuencia de 32 bits de `isa.md` §4.3),
cargar `L` y `R` de memoria, un `feis t0, t0, t1, 0, 0` y guardar `t0`.

| Esperado | Valor |
|---|---|
| Palabra guardada | `L XOR F(R, K[0][0])` calculado por la tarea 17 con los mismos valores |
| `AUTH` (jerarquía) | 1 |

### Tarea 29 · Caso 5: cifrado y descifrado de 4 rondas

Programa: las plantillas de cifrado y descifrado de `crypto_para_ccom.md` §4
sobre 128 bloques (1 KB) cargados en `0x1000`; cifrado a `0x2000` y descifrado a
`0x3000`.

| Esperado | Valor |
|---|---|
| `0x2000` (1 KB) | Igual a la salida de la tarea 17 con la misma llave |
| `0x3000` (1 KB) | Igual a `0x1000` |
| Prueba de borde | Con 0 bloques no se escribe nada en `0x2000` |

### Tarea 30 · Caso 6: bóveda

Programa en tres partes, con el estado leído por jerarquía después de cada una:

1. `auth` con un token **falso** → `AUTH = 0`, `EXC = 1`. Un `feis` en ese
   estado no escribe su `rd`.
2. `auth` con el token correcto → `AUTH = 1`, `EXC = 0`. `kv_write` de las
   **4 llaves × 4 palabras** y `kv_lock`. Un `kv_write` después del `kv_lock` →
   rechazado, `EXC = 1`, la palabra no cambia.
3. `logout` y luego un `feis` → no escribe, `EXC = 1`.

| Esperado | Valor |
|---|---|
| Bóveda (jerarquía) | Las 16 palabras cargadas |
| Llaves no legibles | Al terminar, ningún registro ni ninguna palabra de la memoria contiene una palabra de llave (las llaves se eligen distintas de cualquier otro dato del programa) |
| Ningún camino | Revisión de `crypto_unit`: la bóveda solo llega a F (`isa.md` §7.1) |

**Para la defensa.** `F(0, K) = K`, así que `feis rd, rz, rz, k, i` deja la
subllave en `rd` **si hay sesión**. Es inherente a una instrucción de ronda que
escribe un registro (enunciado §4.4.2). Lo que el caso demuestra es que sin
`AUTH = 1` ninguna instrucción saca información de la bóveda. Conviene decidir
de antemano cómo se explica.

### Tarea 31 · Caso 7: programa mixto sobre un archivo real

Programa: el de la tarea 29 (las plantillas ya combinan `saddi`, `lw`/`sw`,
`blt` y `feis` en los mismos bundles) sobre un archivo cargado con
`load_file.py`; al terminar, `extract_data.py` de `0x2000` y `0x3000`.

| Esperado | Valor |
|---|---|
| Archivo extraído de `0x3000` | Idéntico al original (`cmp`) |
| Archivo extraído de `0x2000` | Igual a la salida de la tarea 17 |
| `.vcd` | Bundles con ALU, LSU, BRU y CRYPTO activos a la vez |

---

## 7. Bloque 6 — Validación conjunta

### Tarea 32 · `tb_conjunta`

Ejercicio 3 de `coordinacion_pendientes.md` §3, compilado por `ccom` al `.hex` y
al `.mem`, con el archivo de prueba cargado en `0x1000` y el token real de la
tarea 18.

| Esperado | Valor |
|---|---|
| `extract_data` de `0x3000` (1 KB) | Idéntico al archivo original |
| Segmentos pares e impares de `0x2000` | Iguales a la tarea 17 con las llaves 0 y 1, alternadas |
| Bundles | Bien formados: el testbench no reporta `X` y el `.vcd` muestra las dependencias respetadas |

La evidencia (comandos, salida y capturas) va a `compiler-integration.md`
(tarea 40).

---

## 8. Módulos provisionales

Para integrar sin esperar a un módulo. Misma cabecera que §4.3; se borran al
llegar el real.

| Módulo | Comportamiento mínimo |
|---|---|
| `alu_dec` | `10010` (`mov`) → `alu_op = 1101`, `use_imm = 1`, `we = 1`; `10000` (`saddi`) → `alu_op = 0000`, `use_imm = 1`, `we = 1`; otro → todo en 0 |
| `alu` | `1101`: `y = imm`; `0000`: `y = a + (use_imm ? imm : b)`; otro: `y = 0`. `cond_ok = 1` |
| `bru_dec` | `00011` (`blt`) → `br_op = 011`, `we = 0`; otro → `000` |
| `bru` | `011`: `taken = ($signed(a) < $signed(b))`, `target = pc + {{4{instr_low[17]}}, instr_low[17:0]}`; siempre `link = {10'b0, pc + 1}` |
| `lsu_dec`, `lsu` | Todo en 0 |
| `crypto_dec` | `crypto_op = 0`, `we = 0` |
| `crypto_unit` | `result = 0`, `allowed = 0`, `crypto_stall = 0`. Variante para la pausa: sube `crypto_stall` 13 ciclos ante `crypto_op = 010` con `en & ex_valid` |
| `imem` | Arreglo en cero, `$readmemh`, cero fuera de rango |
| `memory` | Arreglo de palabras; lectura combinacional; escritura por `be` en flanco ↑ |

Las codificaciones de `alu_op` y `br_op` de esta tabla ya son las **reales** de
§4.8, así que los módulos reales entran sin cambios en `core`.

---

## 9. Integración de un módulo real

1. Revisar la cabecera contra `microarchitecture.md` §4.3: nombres, anchos y
   orden de los puertos.
2. Revisar las convenciones de §4.2: `br_op = 000` y `crypto_op = 000` son
   «nada»; con `funct` libre, `we = 0`.
3. Correr su testbench y confirmar que pasa.
4. Borrar el provisional de `rtl/prov/`.
5. Volver a correr `tb_dispatch` y `tb_top`; la traza de §4.6 debe seguir
   coincidiendo.
6. Si algo no coincide con la interfaz, se acuerda y se corrige primero
   `microarchitecture.md`, no `core` en silencio.

---

## 10. Problemas típicos

| Síntoma | Causa probable |
|---|---|
| La dependencia a 2 bundles lee el valor viejo | El `regfile` escribe en `posedge` en lugar de `negedge` |
| Un salto no salta o salta dos veces | `flush` asíncrono, o conectado en ID/EX |
| Campos cruzados en EX (por ejemplo, `rd` con basura) | El orden de concatenación de `d` no coincide con el de `q` (§4.4) |
| `X` en el `.vcd` al arrancar | Falta reset en algún registro, o `imem` no inicializa en cero antes de `$readmemh` |
| El programa se repite al terminar | `imem` recorta la dirección en lugar de entregar cero |
| `r0` cambia | Falta `waddr != 0` |
| *Latch* inferido | Una salida de `always_comb` sin valor por defecto |
| `blt` o `slt` con negativos fallan | Comparación sin `$signed`, o `slt` sin corregir por `V` |
| `lb` devuelve el byte equivocado | Carriles invertidos: el carril 0 es `[7:0]` |
| Un `sw` se escribe dos veces durante `auth` | Falta `dmem_we & ex_commit` |
| `$readmemh` no carga | Ruta relativa al directorio desde donde se ejecuta `vvp` |
| Módulo duplicado al compilar | Conviven el real y su provisional |
