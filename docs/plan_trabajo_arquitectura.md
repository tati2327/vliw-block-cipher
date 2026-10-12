# Plan de trabajo — CE 4301

**Grupo 6 · 11 de octubre de 2026 · Entrega: 14 de octubre de 2026**

Lista ordenada de todas las tareas de arquitectura, con responsable y fecha. El
detalle de cada módulo y de sus casos de prueba está en
`plan_implementacion_modulos.md`; la especificación, en `microarchitecture.md`
(oficial desde el 11 de octubre).

---

## 1. Reglas

- **Un módulo, un testbench.** El testbench imprime `PASS` o `FAIL` por caso y
  el total de fallos al final, y genera su `.vcd`.
- **Los casos salen de la sección del módulo** en `microarchitecture.md`, con
  el resultado esperado escrito antes de correr.
- **No se sube de nivel con fallos pendientes.** Si falta un módulo, se integra
  con un provisional de la misma cabecera (`microarchitecture.md` §4.3).
- **Git:** una rama y un *issue* por tarea; PR cuando el testbench pasa; un
  *milestone* por bloque. Esto cubre de paso el 11 % del repositorio
  (enunciado §8.2.2).
- **Hora límite de Tatiana:** 12 oct a las 12:00, con revisión a las 10:00 de
  las tareas 4, 5 y 6. Lo que no pase a esa hora lo toma Luis.

---

## 2. Tareas

### Bloque 0 — Preparación · 11 oct en la noche

| # | Tarea | Quién | Terminado cuando |
|---|---|---|---|
| 1 | Arreglos empaquetados en Icarus (F-03) | Luis | Imprime `PASS`; si falla, se cambian las cabeceras antes de seguir |
| 2 | Repositorio: carpetas, ramas, *issues*, *milestones* | Luis | Cada tarea de este plan tiene su *issue* |
| 3 | `Makefile` mínimo | Luis | `make tb_x` funciona para cualquiera |

### Bloque 1 — Componentes · 12 oct

| # | Tarea | Quién | Testbench |
|---|---|---|---|
| 4 | `pipe_reg` | Tatiana | `tb_pipe_reg` |
| 5 | `regfile` | Tatiana | `tb_regfile` |
| 6 | `fetch` | Tatiana | `tb_fetch` |
| 7 | `alu_dec` + `alu` | Tatiana | `tb_alu` |
| 8 | `memory` | Tatiana | `tb_memory` |
| 9 | `imem` | Tatiana | `tb_imem` |
| 10 | `lsu_dec` + `lsu` | Gabriel | `tb_lsu` |
| 11 | `bru_dec` + `bru` | Gabriel | `tb_bru` |
| 12 | `key_vault` | Saddy | `tb_key_vault` |
| 13 | `auth_hash32` | Saddy | `tb_auth_hash32` |
| 14 | `crypto_state`, `crypto_control`, `crypto_datapath`, `crypto_dec` | Saddy | Uno por módulo |
| 15 | `dispatch` | Tatiana | `tb_dispatch` |

### Bloque 2 — Herramientas · 12 oct

| # | Tarea | Quién | Terminado cuando |
|---|---|---|---|
| 16 | Ensamblador propio | Kevin | Vectores de `isa.md` §6.5 bit a bit, `.hex` de §11 idéntico, rechaza los errores de §11.4 |
| 17 | Referencia en C de la Fig. 1 | Kevin | Compila e imprime cifrado y descifrado de bloques y llaves conocidos |
| 18 | Script de la cadena de Lamport | Saddy | `RESET_ANCHOR` y tokens; su `H` coincide con `tb_auth_hash32` |
| 19 | `load_file.py` y `extract_data.py` | Gabriel | Ida y vuelta de un `.txt` y un `.bin`: idénticos; informa tamaño y zona |

**Orden de cada persona en los bloques 1 y 2**

| Persona | Orden |
|---|---|
| Tatiana | 4 → 5 → 6 → 9 → 15 → 8 → 7 |
| Gabriel | 10 → 11 → 19 |
| Saddy | 13 → 12 → 14 → 18 |
| Kevin | 16 → 17 |
| Luis | Revisa los PR y cubre a Tatiana |

### Bloque 3 — Subsistemas · 12 oct en la noche

| # | Tarea | Quién | Testbench |
|---|---|---|---|
| 20 | IF + ID | Luis | `tb_front` |
| 21 | WB | Luis | `tb_wb` |
| 22 | `crypto_unit` armada | Saddy | `tb_crypto_unit` |
| 23 | `lsu` + `memory` | Gabriel | `tb_lsu_mem` |

### Bloque 4 — Procesador · 13 oct en la mañana

| # | Tarea | Quién | Testbench |
|---|---|---|---|
| 24 | `core` + `top` | Luis | `tb_top` |

### Bloque 5 — Casos del enunciado §5.2 · 13 oct

Cada caso es un programa `.s` ensamblado con la tarea 16, con su testbench y su
resultado esperado escrito antes de correr.

| # | Caso | Quién | Testbench |
|---|---|---|---|
| 25 | 1. ALU en paralelo con otras unidades | Tatiana | `tb_caso1_alu_paralelo` |
| 26 | 2. `lw`, `sw`, `lb`, `sb` | Gabriel | `tb_caso2_memoria` |
| 27 | 3. Saltos condicionales e incondicionales | Gabriel | `tb_caso3_saltos` |
| 28 | 4. Una ronda `feis` | Saddy | `tb_caso4_feis` |
| 29 | 5. Cifrado y descifrado de 4 rondas | Saddy | `tb_caso5_feistel4` |
| 30 | 6. Bóveda | Saddy | `tb_caso6_boveda` |
| 31 | 7. Programa mixto sobre un archivo real | Luis | `tb_caso7_mixto` |

### Bloque 6 — Validación conjunta · 14 oct en la mañana

| # | Tarea | Quién | Testbench |
|---|---|---|---|
| 32 | Ejercicio 3 de `ccom` en el procesador | Luis + Kevin | `tb_conjunta`. Depende de que `ccom` llegue a la Fase 6 |

### Bloque 7 — Documentación y cierre

| # | Tarea | Quién | Cuándo |
|---|---|---|---|
| 33 | Diagrama de bloques gráfico (F-04) | Tatiana | 12–13 oct |
| 34 | `organizacion_procesador.png` en `docs/img/` (F-05) | Luis | 12 oct |
| 35 | Comunicar la revisión 1 de `isa.md` (F-06) | Luis | 12 oct |
| 36 | `microarchitecture.md` final, revisado contra el código | Luis | 13 oct en la noche |
| 37 | `compiler-integration.md`: contrato | Kevin | 12–13 oct |
| 38 | `simulation.md` | Gabriel | 13 oct en la noche |
| 39 | `README.md` con comandos y ejemplos reales | Saddy | 13 oct en la noche |
| 40 | Evidencia de la validación conjunta | Kevin | 14 oct, después de la 32 |
| 41 | `Makefile` final con `make sim` | Luis | 13 oct en la noche |
| 42 | Ensayo de la defensa | Todos | 14 oct |

---

## 3. Dependencias

**Camino crítico:** 1 → 4/5/6 → 15 → 20 → 24 → 25–31 → 32.

| Tarea | Necesita |
|---|---|
| 15 `dispatch` | Decodificadores de 7, 10, 11 y 14 (o provisionales) |
| 20 `tb_front` | 4, 5, 6, 9 y 15 |
| 21 `tb_wb` | 4 y 5 |
| 22 `crypto_unit` | 12, 13, 14 y 18 |
| 23 `tb_lsu_mem` | 8 y 10 |
| 24 `tb_top` | Todo el bloque 3 |
| Bloque 5 | 24 y 16 |
| 28, 29 | 17 |
| 30 | 18 |
| 31 | 19 |
| 32 | Bloque 5 y `ccom` hasta la Fase 6 |
| 38, 39 | Bloque 5 |
| 40 | 32 |

---

## 4. Riesgos

| Riesgo | Mitigación |
|---|---|
| Tatiana tiene 7 de los 12 componentes, todos en el camino crítico | Revisión a las 10:00 y hora límite a las 12:00 del 12 oct; Luis los toma |
| Kevin lleva el ensamblador junto con el compilador | El ensamblador comparte entrada y salida con la Fase 6 de `ccom` |
| `ccom` no llega a la Fase 6 a tiempo | Por decidir. Opción: correr en el nivel 4 un programa más corto de `ccom` (por ejemplo, el de `crypto_para_ccom.md` §6) en lugar del ejercicio 3 |
| `feis rd, rz, rz, k, i` deja la subllave en `rd`, porque `F(0, K) = K` | Por decidir cómo se presenta en la defensa: la fuga solo es posible con `AUTH = 1`, así que el código sin autenticar no puede leer la bóveda (ver caso 6 en `plan_implementacion_modulos.md`) |
| Icarus no acepta los arreglos empaquetados | Se prueba en la tarea 1, antes de escribir código |
