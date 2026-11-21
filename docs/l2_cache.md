# Caché L2 — Diseño, funcionamiento e integración

**Módulo:** `rtl/l2_cache.sv`  
**Verificación:** `tb/tb_l2_cache.sv`  
**Destino sugerido:** `docs/l2_cache.md`

## 1. Objetivo y ubicación

L2 es una caché de líneas entre L1 / el buffer de escrituras y el buffer de desalojos / memoria principal. Atiende **una transacción a la vez**. El esquema lógico es:

```text
Core (palabras) → L1
                   ├─ lecturas de línea ────────────┐
                   └─ líneas sucias → write buffer ┤
                                                    ▼
                                                  L2
                                                    ├─ lectura de línea → eviction buffer → main_memory
                                                    └─ push de línea sucia → eviction buffer
```

Los módulos de buffers pueden hacer *forwarding*: si la línea solicitada ya está en el buffer, responden sin acceder al siguiente nivel. La política de inclusión es **NINE**: L2 no envía invalidaciones hacia L1.

## 2. Organización y direcciones

| Característica | Valor |
|---|---|
| Capacidad de datos | 16 KiB |
| Asociatividad | 4 vías |
| Tamaño de línea | 32 bytes = 256 bits |
| Conjuntos | 128 |
| Líneas totales | 512 |
| Política de escritura | Write-back |
| Reemplazo | LFSR pseudoaleatorio, con prioridad a vías inválidas |
| Dirección de byte | 16 bits, espacio de 64 KiB |

```text
Dirección de byte: [15:12] etiqueta (4) | [11:5] conjunto (7) | [4:0] desplazamiento (5)
Dirección de línea: [10:7] etiqueta (4) | [6:0] conjunto (7)
```

En el RTL: `idx = saved_addr[6:0]` y `tag = saved_addr[10:7]`. Cada entrada almacena `data[255:0]`, `tags[3:0]`, `valid` y `dirty`. El almacenamiento total de datos y metadatos por línea es 262 bits; 512 × 262 = **134 144 bits**, sin contar lógica de control.

## 3. Interfaces y señales

### 3.1 Lado superior: esclavo de línea (contrato B)

| Señal | Dirección respecto de L2 | Función |
|---|---|---|
| `clk`, `rst` | Entrada | Reloj y reinicio activo alto |
| `req`, `we` | Entrada | Solicitud y tipo (0 lectura, 1 escritura) |
| `line_addr[10:0]` | Entrada | Dirección de línea, sin desplazamiento |
| `wdata[255:0]`, `wmask[31:0]` | Entrada | Datos y máscara por byte |
| `accepted` | Salida | Pulso registrado que confirma aceptación |
| `ready` | Salida | Completa la operación en el flanco actual |
| `ready_rdata[255:0]` | Salida | Línea devuelta junto con `ready` |
| `resp_src[1:0]` | Salida | Procedencia: 0 memoria, 1 L2, 2 buffer |

El parámetro REPL se conserva en la interfaz del módulo para permitir futuras políticas de reemplazo. Actualmente, todos sus valores utilizan reemplazo pseudoaleatorio mediante un LFSR de 8 bits. Las vías inválidas tienen prioridad sobre la selección del LFSR.

**Regla de protocolo:** el maestro mantiene `req` y el bus estables hasta observar `accepted`, luego desactiva `req`. No debe esperar `accepted` para consumir una respuesta `ready` que llegue en el mismo ciclo (forwarding).

### 3.2 Lado inferior: maestro de lectura

| Señales | Función |
|---|---|
| `line_req`, `line_we` | Solicitud inferior; `line_we` es siempre 0 |
| `line_line_addr[10:0]` | Dirección de línea solicitada |
| `line_wdata[255:0]`, `line_wmask[31:0]` | Sin uso en lecturas, fijadas en 0 |
| `line_accepted` | Confirmación de aceptación inferior |
| `line_ready`, `line_rdata[255:0]` | Terminación y datos de llenado |
| `line_resp_src[1:0]` | Origen de la línea recibido desde abajo |

El buffer inferior debe permitir respuesta combinacional en el mismo ciclo del pedido. La interfaz de L2 mantiene `line_req` mientras no se haya registrado la aceptación; revisar la temporización de `line_accepted` con el buffer real.

### 3.3 Desalojo (*push*)

`push`, `push_addr[10:0]`, `push_data[255:0]` salen de L2; `full` entra desde el eviction buffer. Un `push` solo debe consumirse en un flanco con `full=0`. `push_addr` se forma como `{tags[idx][victim_way], idx}`: **usa la etiqueta de la víctima, no la dirección nueva**.

### 3.4 Contadores de 64 bits

`read_count`, `write_count`, `read_hits`, `read_misses`, `write_hits`, `write_misses`, `stall_full_cycles`. Se reinician con `rst`. Los conteos de acceso se incrementan al aceptar solicitudes; hits/misses, al resolver la búsqueda; `stall_full_cycles`, por ciclo bloqueado por el buffer lleno. Al terminar todas las operaciones, se espera:

```text
read_count  = read_hits  + read_misses
write_count = write_hits + write_misses
```

## 4. Estructura interna del RTL

- **Arreglos** `data[0:127][0:3]`, `tags`, `valid`, `dirty`: cuatro vías por conjunto.
- **Solicitud retenida** `saved_we`, `saved_addr`, `saved_data`, `saved_mask`: permiten que el maestro cambie el bus después de `accepted`.
- **Comparación paralela**: se buscan coincidencias válidas de etiqueta entre las cuatro vías; `hit_way` identifica la vía coincidente.
- **Selección de víctima**: se elige primero la vía inválida de menor índice; si todas son válidas, `lfsr[1:0]`. La secuencia LFSR parte de `8'hA5` y avanza al instalar una línea en un fallo.
- **Fusión de bytes** `merged_data`: en un *write hit*, conserva bytes cuyo bit de `saved_mask` es cero y reemplaza los seleccionados. Según el contrato, los buffers de caché envían escrituras completas (`wmask = '1`).
- **Control** `state`, `age`, `sent`, `pushed`: implementa la latencia y evita repetir una operación aceptada o un push ya realizado.

**Parámetro `REPL`:** aparece declarado en el módulo entregado, pero el RTL inspeccionado no lo utiliza para seleccionar otra política. No documentar pseudo-LRU como implementado sin añadirlo y verificarlo.

## 5. Máquina de estados

| Estado | Comportamiento |
|---|---|
| `IDLE` | Acepta `req`, captura dirección/datos/máscara, cuenta lectura o escritura, inicia `age` |
| `LOOKUP` | Espera el tiempo fijo de búsqueda; determina hit/miss y actualiza contadores |
| `MISS` | Espera espacio para desalojar una víctima sucia; continúa cuando `full=0` |
| `WAIT_LINE` | Espera respuesta del nivel inferior; instala línea limpia y termina |

La señal `ready` se genera de forma combinacional para evitar una etapa extra: en hit, en escritura que falla y puede instalarse, o al recibir `line_ready` (incluso si este llega en el mismo ciclo en que sale `line_req`). `resp_src=1` en hit o escritura completada localmente; en un llenado se propaga `line_resp_src`.

## 6. Casos de operación

### Lectura con hit

Tras el tiempo de búsqueda, entrega `data[idx][hit_way]`, activa `ready` y marca `resp_src=1`. No consulta el nivel inferior.

### Lectura con miss

Selecciona una vía, expulsa su contenido si está válido y sucio, y emite `line_req` con la dirección solicitada. Si el nivel inferior responde inmediatamente, instala los datos y propaga `ready` sin esperar otro estado. En caso contrario espera en `WAIT_LINE`; al recibir `line_ready`, instala la línea con `valid=1`, `dirty=0` y etiqueta nueva.

### Escritura con hit

Actualiza los bytes seleccionados mediante `merged_data` y marca `dirty=1`. Completa tras la latencia fija, sin lectura inferior.

### Escritura con miss

La línea nueva se instala directamente, sin solicitar la anterior a memoria. La vía queda válida y sucia. Si debe reemplazar una víctima sucia, primero realiza el push (o espera espacio).

### Buffer de desalojos lleno

Si la víctima está sucia y `full=1`, no puede sobrescribirse todavía. L2 pasa a `MISS` y cuenta los ciclos de espera. Cuando `full=0`, hace el push y continúa. Es indispensable comprobar que el buffer capture **una sola vez** la víctima.

## 7. Temporización y significado de los ciclos

| Operación | Latencia requerida sin contención |
|---|---|
| Lectura hit L2 | 8 ciclos |
| Escritura hit L2 | 8 ciclos |
| Escritura miss con instalación completa | 8 ciclos |
| Lectura miss con forwarding inferior | 8 ciclos |
| Lectura miss hasta memoria (`MEM_DIV=4`) | 8 + 53 = 61 ciclos |

En el **ciclo 8** de un fallo de lectura, L2 debe presentar el pedido inferior. El desalojo sucio debe coincidir con ese ciclo si hay espacio. La memoria real usa `Tmem = 25 + 7 × MEM_DIV`, por lo que `MEM_DIV=2,4,5` corresponde a 39, 53 y 60 ciclos, respectivamente. Si el buffer inferior está ocupado, la latencia aumenta.

**Convención para las pruebas:** definir explícitamente el flanco que acepta la solicitud como ciclo 0 y muestrear `ready` antes del flanco que consume la respuesta. La versión del RTL recibida aquí contiene `age <= 1` y una condición `age == 7`; el usuario informó que corrigió los fallos de conteo en su versión local. **La temporización de la rama corregida prevalece; no copiar literalmente el contador de la versión antigua.**

## 8. Verificación

El testbench compartido `tb_l2_cache.sv` utiliza un modelo controlado de memoria inferior (`TMEM=53`) y un indicador `full` para forzar bloqueos. Incluye comprobaciones automáticas de aceptación, latencia, datos, `resp_src`, solicitudes inferiores, pushes y contadores.

Las direcciones `A=0x012`, `B=0x092`, `C=0x112`, `D=0x192` y `E=0x212` comparten índice de conjunto (`0x12`) y difieren en etiqueta: permiten llenar las cuatro vías y provocar un reemplazo. El testbench también usa forwarding (`resp_src=2`) y un bloqueo temporal del eviction buffer.

Compilación independiente, suponiendo Icarus Verilog:

```bash
iverilog -g2012 -s tb_l2_cache -o tb_l2_cache.vvp rtl/l2_cache.sv tb/tb_l2_cache.sv
vvp tb_l2_cache.vvp
```

El testbench genera `tb_l2_cache.vcd` y termina con el formato `Casos: N; Fallos: N`; falla con `$fatal` si hay errores. El equipo reportó que las pruebas ya pasan tras corregir los ciclos, pero este documento **no afirma una ejecución independiente** sobre la versión corregida.

## 9. Guía práctica de integración

1. **Usar las versiones actuales de la rama** de L2 y del testbench; comprobar que las correcciones de ciclos estén incorporadas.
2. **Conectar el lado superior** al arbitraje entre llenados de L1 y drenajes del write buffer. L2 solo dispone de un puerto de solicitudes; si ambos pueden solicitar simultáneamente, la integración debe arbitrar y mantener las señales estables hasta aceptación.
3. **Conectar `line_*` al puerto de lectura del eviction buffer** (`we=0`). Este buffer consulta primero sus entradas y, en ausencia de coincidencia, envía el pedido a `main_memory`.
4. **Conectar `push*` al puerto de inserción del eviction buffer** y `full` a su señal de ocupación completa. No confundir push con una escritura normal por contrato B.
5. **Conservar el handshake**: `req` hasta `accepted`; `ready` se consume en el mismo flanco, incluso si llega antes de `accepted`.
6. **Propagar `resp_src`**: 1 si L2 encuentra la línea; 2 si el eviction buffer la reenvía; 0 si viene de memoria. `main_memory.sv` no tiene puerto `resp_src`: asignar 0 en el adaptador o conexión correspondiente.
7. **Verificar reinicio y tráfico concurrente**: una solicitud superior no debe sobrescribir la transacción retenida; comprobar las esperas si el buffer inferior ya está drenando.
8. **Conectar contadores** al banco de pruebas de integración, sin inferir hit rate/AMAT directamente dentro del RTL.
9. **Verificar coherencia final de memoria**: con write-back, las líneas sucias pueden permanecer en L1, write buffer, L2 o eviction buffer. El equipo debe definir cómo drenar la jerarquía antes de comparar el contenido final de `main_memory`.
10. **Añadir `make tb_l2_cache` a `make all`** siguiendo el Makefile existente; documentar y enviar cambios por PR a `develop`.

### Conexión conceptual de puertos

```systemverilog
// Los nombres del lado izquierdo son puertos de l2_cache.
// Los del lado derecho representan señales de interconexión,
// no nombres definitivos del top.
.req(up_req), .we(up_we), .line_addr(up_line_addr),
.wdata(up_wdata), .wmask(up_wmask),
.accepted(up_accepted), .ready(up_ready),
.ready_rdata(up_rdata), .resp_src(up_resp_src),

.line_req(ev_read_req), .line_we(ev_read_we),
.line_line_addr(ev_read_addr),
.line_wdata(ev_read_wdata), .line_wmask(ev_read_wmask),
.line_accepted(ev_read_accepted), .line_ready(ev_read_ready),
.line_rdata(ev_read_rdata), .line_resp_src(ev_read_src),

.push(ev_push), .push_addr(ev_push_addr),
.push_data(ev_push_data), .full(ev_full)
```

## 10. Riesgos y comprobaciones pendientes antes del PR

- **Versión del contador:** la copia compartida puede no incluir la corrección de ciclos.
- **Protocolo de aceptación:** probar con el `line_buffer` real que un `line_req` sostenido no se acepte dos veces y que un `line_ready` inmediato no se pierda.
- **Reemplazo:** el LFSR avanza en cada instalación por miss, incluso cuando se usó una vía inválida; verificar que esto coincide con la política acordada. El parámetro `REPL` aún no selecciona otra estrategia en el código inspeccionado.
- **Máscaras:** la escritura hit aplica `wmask`, pero la escritura miss instala `saved_data` completa. Es correcto bajo el contrato de escrituras de línea completa; no conectar escrituras parciales directamente a L2 sin ampliar esa lógica.
- **Colisiones y pushes:** probar las cuatro vías ocupadas, víctima limpia y sucia, buffer lleno y liberación posterior, además de direcciones y datos desalojados.
- **Cobertura:** el TB actual usa un modelo inferior; conviene agregar una prueba de integración con `main_memory.sv` y el eviction buffer real.

## 11. Referencias internas del proyecto

- `contratos_cache.md`: organización, contrato B, reglas de forwarding, temporización y contadores.
- `tarea_kevin.md`: entregables, pruebas mínimas, integración, métricas y flujo de PR.
- `rtl/l2_cache.sv`: implementación de la caché L2.
- `tb/tb_l2_cache.sv`: pruebas independientes.
- `rtl/l1_cache.sv`: interfaz de L1 hacia la jerarquía de líneas.
- `rtl/main_memory.sv`: memoria de líneas y latencia dependiente de `MEM_DIV`.
