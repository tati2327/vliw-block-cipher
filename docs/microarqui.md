## 9. Jerarquía de caché: decisiones y contratos

Diseño de la jerarquía de datos de P2 §3.2–§3.4. Esta sección fija las políticas y
los contratos entre módulos para que cada parte se implemente y pruebe por separado.
La caché reemplaza a `mem_adapter` (§8): el núcleo y `main_memory` no cambian.

### 9.1 Organización

```text
core (EX) ──palabra──▶ l1_cache ──línea──▶ line_buffer (escritura, 4) ──línea──▶ l2_cache
                          │ push de línea sucia ──▲
l2_cache ──línea──▶ line_buffer (desalojo, 8) ──línea──▶ main_memory (u_memory)
    │ push de línea sucia ──▲
```

- `l1_cache`: L1-D, 4 KB, 2 vías, líneas de 32 B (P2 §3.2.2).
- `l2_cache`: L2 unificada, 16 KB, 4 vías, líneas de 32 B, write-back (P2 §3.2.3).
- `line_buffer`: un solo módulo FIFO de líneas, instanciado dos veces: como write
  buffer L1→L2 y como eviction buffer L2→memoria (P2 §3.4). Recibe líneas sucias,
  las drena en segundo plano y deja pasar las lecturas del nivel de arriba,
  respondiéndolas desde sus entradas si las tiene (store-to-load forwarding).
- L1 y L2 son módulos separados con los mismos contratos, para implementarlos y
  probarlos en paralelo.
- Jerarquía bloqueante: un solo fallo en curso por nivel (notas §6.3.4).

### 9.2 Decisiones

| Tema | Elegido | Justificación |
|---|---|---|
| L1-D: escritura y asignación | Write-back + write-allocate | Misma política que L2 (obligatoria write-back); el write buffer recibe líneas completas, igual que el eviction buffer; menos tráfico hacia L2 |
| L1-D: reemplazo | LRU, 1 bit por conjunto | Con 2 vías es exacto y casi tan barato como FIFO |
| Write buffer L1→L2 | 4 entradas (parámetro `DEPTH`); RAW por store-to-load forwarding | Ocurre en el camino del fallo y no toca el acierto de L1 |
| L2: reemplazo | Aleatorio con LFSR (parámetro `REPL`; pseudo-LRU opcional) | L2 solo ve los fallos de L1, donde el aleatorio compite bien; el LFSR avanza en cada reemplazo y antes se elige una vía inválida |
| L2: escritura de una línea que no tiene | Se instala sin traer de memoria | La línea llega completa desde L1 |
| L2: duración de cualquier acceso | 8 ciclos, lectura o escritura, acierto o instalación | Tiempo de acceso de L2 de P2 §3.2.3; mientras escribe está ocupada |
| Inclusión L1/L2 | NINE (no inclusiva, no exclusiva) | Un solo núcleo: la ventaja de la inclusiva (filtrar el snooping entre varias L1) no aplica (P2 §3.2.4); evita la invalidación hacia atrás y su costo en el hit rate de L1 |
| Llenado tras fallo de L2 | La línea se instala en L2 y en L1 | L2 conserva la copia cuando L1 la desaloja; un segundo recorrido de datos que caben en L2 acierta en L2 en vez de ir a memoria |
| Eviction buffer L2→memoria | 8 entradas (parámetro `DEPTH`); misma regla de RAW (forwarding) | Mismo módulo que el write buffer; cada entrada esconde un acceso de `Tmem` |
| Forwarding desde un buffer | 0 ciclos: la lectura se responde en el mismo ciclo | Forwarding ideal; costo: ruta combinacional larga (búsqueda en L1, comparación en el buffer y línea de vuelta en un ciclo) |
| Prioridad hacia el nivel inferior | El llenado (lectura) va antes que el drenaje (escritura); un drenaje ya aceptado no se interrumpe | El llenado detiene al pipeline; el drenaje no |
| Escritura de línea en memoria | Cuesta `Tmem`, igual que la lectura | Conservador; P2 §3.2.5 solo define la lectura |
| Orden de búsqueda en un fallo de L1 | Write buffer → L2 → eviction buffer → memoria | Sale de la estructura: cada buffer deja pasar la lectura y la responde si tiene la línea, de lo más nuevo a lo más viejo |

Los tamaños 4 y 8 son valores por defecto, no óptimos medidos; el análisis de
rendimiento los compara con `DEPTH` = 2, 4, 8 y 16.

### 9.3 Direcciones

Espacio de datos de 64 KB (16 bits de dirección de byte).

| Nivel | Conjuntos | Desplazamiento | Índice | Etiqueta |
|---|---|---|---|---|
| L1-D | 4 KB / (2 × 32 B) = 64 | `addr[4:0]` | `addr[10:5]` (6 bits) | `addr[15:11]` (5 bits) |
| L2 | 16 KB / (4 × 32 B) = 128 | `addr[4:0]` | `addr[11:5]` (7 bits) | `addr[15:12]` (4 bits) |

La palabra dentro de la línea es `addr[4:2]`; la línea completa es `addr[15:5]`.

### 9.4 Contrato A: núcleo ↔ L1 (palabra)

Es la interfaz de §8.1, sin cambios: `req`, `we`, `addr[31:0]`, `wdata[31:0]`,
`be[3:0]` → `rdata[31:0]`, `listo`.

- El núcleo pide una sola vez por bundle, solo con el bundle válido en EX, y guarda
  el resultado hasta el commit (§8.2). Mientras `req && !listo`, el bundle completo
  se detiene (P2 §3.3).
- Acierto: `listo = 1` en el mismo ciclo del pedido (lectura combinacional, P2 §3.3),
  sin pausa. Un store que acierta se escribe en L1 en ese mismo flanco y marca la
  línea sucia.
- Fallo: L1 baja `listo`, resuelve el fallo (desalojo y llenado) y da `listo` cuando
  la palabra está disponible o el store aplicado.
- L1 aplica cada store una sola vez: el núcleo no repite el pedido después de `listo`.

### 9.5 Contrato B: interfaz de línea

Una sola interfaz para todas las fronteras de línea (L1→write buffer, write
buffer→L2, L2→eviction buffer, eviction buffer→memoria). Es la de `main_memory`
(§6.1), así que cualquier módulo se puede probar contra `main_memory`.

| Señal | Sentido | Bits | Significado |
|---|---|---|---|
| `req`, `we` | maestro → esclavo | 1, 1 | Pedido válido; escritura si `we = 1` |
| `line_addr` | maestro → esclavo | 11 | `addr[15:5]` |
| `wdata`, `wmask` | maestro → esclavo | 256, 32 | Línea y máscara de bytes; las cachés siempre escriben la línea completa (`wmask` en unos) |
| `accepted` | esclavo → maestro | 1 | Pulso registrado al aceptar |
| `ready` | esclavo → maestro | 1 | El flanco actual termina el acceso (se consume en ese mismo flanco) |
| `ready_rdata` | esclavo → maestro | 256 | Línea leída, estable con `ready` |
| `resp_src` | esclavo → maestro | 2 | Con `ready`: de dónde salió la línea (0 memoria, 1 L2, 2 buffer). `main_memory` lo deja en 0 |

Reglas:
- El maestro mantiene `req` y el bus hasta ver `accepted`, y entonces baja `req`. Si
  no lo baja, se acepta otro acceso.
- Un esclavo atiende un pedido a la vez.
- `resp_src` viaja hacia arriba para que L1 cuente los ciclos perdidos por tipo de fallo.
- Un esclavo puede dar `ready` en el mismo ciclo del pedido (forwarding); el maestro
  debe aceptarlo y no esperar a `accepted` en ese caso.

### 9.6 Contrato C: `line_buffer`

Puertos:
- Lado de arriba: un puerto de **lectura** con la interfaz de línea (esclavo, solo
  `we = 0`) y un puerto de **push**: `push`, `push_addr[10:0]`, `push_data[255:0]` →
  `full`.
- Lado de abajo: la interfaz de línea (maestro).

Comportamiento:
- `push` con `full = 0` guarda la línea en el flanco. Con `full = 1` no se guarda y el
  que empuja debe esperar (cuenta como pausa por buffer lleno).
- Lectura que coincide con una entrada: se responde en el mismo ciclo, con `ready = 1`,
  la línea de la entrada más nueva con esa dirección y `resp_src = 2`. La entrada sigue
  en la cola y se drena igual.
- Lectura sin coincidencia: pasa al nivel de abajo en el mismo ciclo, y `ready`,
  `ready_rdata` y `resp_src` vuelven desde abajo.
- Drenaje: con la cola no vacía y el nivel de abajo libre, escribe la entrada más vieja.
  Si una lectura y un drenaje quieren salir a la vez, sale primero la lectura. Un
  drenaje ya aceptado no se interrumpe.

### 9.7 Temporización exigida

Ciclos de pausa del bundle en EX para un `lw` o `sw`, con el nivel de abajo libre y
`MEM_DIV = 4` (`Tmem` = 53):

| Caso | Pausa | Origen |
|---|---|---|
| Acierto en L1 | 0 | P2 §3.3 |
| Fallo en L1, línea en el write buffer | 0 | Forwarding en el mismo ciclo |
| Fallo en L1, acierto en L2 | 8 | P2 §3.3 |
| Fallo en L1 y L2, línea en el eviction buffer | 8 | Tiempo de L2 más forwarding en el mismo ciclo |
| Fallo en L1 y L2 | 8 + `Tmem` = 61 | P2 §3.3 |

Para lograrlo:
- L2 da `ready` exactamente 8 ciclos después del ciclo del pedido en un acierto. En
  un fallo, pide abajo en el ciclo 8, y `main_memory` responde `Tmem` ciclos después.
- Toda escritura en L2 ocupa 8 ciclos.
- El desalojo de una línea sucia se hace con `push` en el mismo ciclo en que sale el
  pedido de llenado: no suma ciclos salvo que el buffer esté lleno.
- Si el nivel de abajo está ocupado (por ejemplo, con un drenaje ya aceptado), el
  llenado espera. Por ejemplo, si un drenaje a L2 empieza en el ciclo 0 y L1 falla en
  el ciclo 3 con la línea en L2, L2 queda libre en el ciclo 8 y el llenado está listo
  en el 16: 13 ciclos de pausa. Esos ciclos son costo real y se cuentan.

### 9.8 Contadores (P2 §5.2)

| Módulo | Contadores |
|---|---|
| `l1_cache` | Lecturas y escrituras; aciertos y fallos de lectura y de escritura; ciclos de pausa por tipo según `resp_src` (buffer, L2, memoria) y por write buffer lleno |
| `l2_cache` | Lecturas (llenados de L1) y escrituras (drenajes del write buffer); aciertos y fallos de cada una; ciclos de pausa por eviction buffer lleno |
| `line_buffer` | Líneas recibidas, aciertos de forwarding, ciclos con `full = 1` y ocupación máxima |
| `main_memory` | Los de §6.3 |

Hit rate y miss rate se calculan en el testbench a partir de los contadores. Con NINE
no hay invalidaciones hacia atrás que contar.

### 9.9 Pruebas mínimas de cada módulo

Para trabajar en paralelo, cada módulo se prueba solo, contra `main_memory` o contra
un modelo de testbench que cumpla el contrato B:

- `l1_cache`: acierto y fallo de lectura y de escritura; desalojo de una línea sucia
  con `push`; LRU en los dos órdenes de acceso; store aplicado una sola vez; buffer
  lleno; respuesta en el mismo ciclo desde abajo.
- `l2_cache`: acierto con `ready` a los 8 ciclos; fallo con pedido abajo en el ciclo
  8; escritura de una línea ausente sin leer memoria; toda escritura en 8 ciclos;
  LFSR con prioridad a la vía inválida; desalojo de una línea sucia.
- `line_buffer`: push hasta llenarse; drenaje en orden FIFO; forwarding en el mismo
  ciclo desde la entrada más nueva; prioridad de la lectura sobre el drenaje; drenaje
  en curso no interrumpido.
- Integración: los mismos programas de §8 con la identidad de ciclos de §7.

### 9.10 Pendiente

- **Volcado final con write-back:** al terminar un programa, los datos más nuevos
  pueden estar en L1, en un buffer o en L2, y no en `main_memory`. Opciones: vaciar la
  jerarquía antes de volcar, o leer por puerta trasera en el orden L1 → write buffer
  → L2 → eviction buffer → memoria. Se decide al integrar L1.