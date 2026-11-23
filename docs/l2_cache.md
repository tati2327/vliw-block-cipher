# Caché L2 de datos

`rtl/l2_cache.sv` implementa una caché L2 bloqueante, de cuatro vías y 16 KiB, situada entre el *write buffer* de L1 y el *eviction buffer* de memoria principal. Cada línea contiene 256 bits (ocho palabras de 32 bits). La política es *write-back*; los pedidos de escritura recibidos son líneas completas. El módulo acepta el parámetro `REPL`, pero **su valor no cambia la política**: el reemplazo efectivo usa un LFSR de ocho bits.

## Organización y direcciones

| Recurso | Cantidad | Detalle |
|---|---:|---|
| Capacidad | 16 KiB | 128 conjuntos × 4 vías × 32 bytes |
| Línea | 32 bytes | 8 palabras de 32 bits |
| Etiqueta | 4 bits | `line_addr[10:7]` |
| Conjunto | 7 bits | `line_addr[6:0]` |
| Dirección de línea | 11 bits | Equivale a `addr[15:5]` |
| Metadatos por vía | `valid`, `dirty`, `tags[3:0]` | Se reinician con `rst` |
| Datos por vía | `data[255:0]` | 32 bytes |

El LFSR arranca en `8'hA5`. En ausencia de vías inválidas, `lfsr[1:0]` selecciona la víctima. Se prefiere siempre la vía inválida de menor índice: el recorrido descendente sobrescribe la selección hasta llegar a la primera vía. El LFSR avanza al instalar una línea nueva, no en cada acierto.

## Puertos para integración

Todos los sentidos se indican desde L2 y las operaciones secuenciales usan `clk`.

| Grupo | Señales | Sentido | Ancho |
|---|---|---|---|
| Control | `clk`, `rst` | Entrada | 1 |
| Pedido superior | `req`, `we`, `line_addr` | Entrada | 1, 1, 11 |
| Escritura superior | `wdata`, `wmask` | Entrada | 256, 32 |
| Respuesta superior | `accepted`, `ready`, `ready_rdata`, `resp_src` | Salida | 1, 1, 256, 2 |
| Pedido inferior | `line_req`, `line_we`, `line_line_addr` | Salida | 1, 1, 11 |
| Datos inferiores | `line_wdata`, `line_wmask` | Salida | 256, 32 |
| Respuesta inferior | `line_accepted`, `line_ready`, `line_rdata`, `line_resp_src` | Entrada | 1, 1, 256, 2 |
| Desalojo | `push`, `push_addr`, `push_data` | Salida | 1, 11, 256 |
| Capacidad de desalojo | `full` | Entrada | 1 |
| Métricas | `read_count`, `write_count`, `read_hits`, `read_misses`, `write_hits`, `write_misses`, `stall_full_cycles` | Salida | 64 cada una |

El puerto inferior de L2 es exclusivamente de lectura: `line_we=0`, `line_wdata=0` y `line_wmask=0`. Las líneas sucias salen por `push` al *eviction buffer*. En la jerarquía `CACHE=2`, el *write buffer* de L1 alimenta el puerto superior y el *eviction buffer* conecta el puerto inferior con `main_memory`.

## Secuencia de acceso y temporización

La máquina de estados tiene `IDLE`, `LOOKUP`, `MISS` y `WAIT_LINE`.

1. **Recepción:** en `IDLE`, un pedido `req` se captura en `saved_we`, `saved_addr`, `saved_data` y `saved_mask`. `accepted` se registra y se presenta como pulso después del flanco de captura. Solo se atiende un pedido pendiente.
2. **Búsqueda:** `age` empieza en 1 y avanza hasta 8. La decisión se toma cuando `state==LOOKUP && age==8`. La búsqueda introduce ocho ciclos de conteo antes de resolver el pedido; no es un acierto combinacional como L1.
3. **Acierto de lectura:** `ready` se activa al completar la búsqueda y `ready_rdata` devuelve la línea residente. `resp_src=1` identifica la respuesta de L2.
4. **Acierto de escritura:** se combinan los bytes habilitados por `wmask` con la línea residente, se marca `dirty` y se confirma el pedido sin escribir inmediatamente a memoria.
5. **Fallo de escritura:** después de liberar la víctima, se instala `saved_data` como línea válida y sucia, sin lectura del nivel inferior. El código actual instala `saved_data` completo en este caso; por tanto, el emisor debe entregar una línea completa válida. La máscara solo se aplica en los aciertos.
6. **Fallo de lectura:** se solicita la línea al nivel inferior; al recibir `line_ready`, se instala limpia y se devuelve la respuesta. Si la respuesta llega inmediatamente, no se necesita esperar en otro estado.

### Víctimas y *eviction buffer* lleno

Una víctima válida y sucia se envía mediante `push`, `push_addr={tags[idx][victim_way],idx}` y `push_data`. El bit `pushed` evita repetir el desalojo mientras el fallo está pendiente. Si `full=1` y todavía hay que expulsar una víctima sucia, se bloquea el avance y se incrementa `stall_full_cycles` en cada flanco bloqueado. Una vía inválida o una víctima limpia no requieren espacio en el buffer.

### Retención del pedido inferior

Para fallos de lectura, `line_req` se mantiene en `WAIT_LINE` mientras no se haya observado aceptación, y `sent` evita volver a emitir el pedido aceptado. La respuesta `line_ready` puede resolver la lectura inmediatamente. Esto evita perder un pedido cuando el buffer inferior está ocupado drenando otra línea.

## Reset y contadores

`rst` es asíncrono y activo alto. Reinicia el estado, los pedidos pendientes, el LFSR, datos, etiquetas, validez, suciedad y los siete contadores. No descarga las líneas sucias a memoria: un reset no equivale a un vaciado de caché.

| Contador | Evento |
|---|---|
| `read_count`, `write_count` | Pedido capturado en `IDLE` |
| `read_hits`, `read_misses` | Resultado de búsqueda para lectura |
| `write_hits`, `write_misses` | Resultado de búsqueda para escritura |
| `stall_full_cycles` | Ciclo bloqueado por víctima sucia y `full` |

En ausencia de operaciones pendientes, deben cumplirse `read_count=read_hits+read_misses` y `write_count=write_hits+write_misses`. Las tasas de acierto y fallo se calculan con estos contadores. Los contadores no saturan explícitamente.

## Diagnóstico e integración

Con `CACHE=2`, `tb_programa` puede reportar accesos y tasas de L1/L2, métricas de ambos buffers y AMAT. La fórmula de referencia usada en la integración es:

```text
AMAT_medido = 1 + pausa_memoria / (lecturas_L1 + escrituras_L1)
AMAT_formula = 1 + miss_L1 * (8 + miss_L2 * (25 + 7*MEM_DIV))
```

La fórmula es aproximada: mezcla accesos de lectura y escritura de L2, aunque los fallos de escritura de línea completa no necesitan una lectura a memoria. La ocupación y el drenaje de buffers también pueden introducir esperas adicionales.

El volcado `l2.txt` muestra las 128 × 4 vías (validez, suciedad, etiqueta, dirección y ocho palabras) y las entradas pendientes del *eviction buffer*. El monitor de memoria compara el estado arquitectónico, incluso cuando existen líneas sucias todavía residentes.

## Pruebas

```bash
make tb_l2_cache
make tb_line_buffer
make sim PROG=ejercicio1 CACHE=2 MEM_DIV=4
make sim PROG=l2_estres CACHE=2 MEM_DIV=4 > l2_estres.log 2>&1
tail -n 100 l2_estres.log
```

`l2_estres` escribe y lee 5120 palabras (20 KiB) desde `0x1000`, superando la capacidad de L2. Comprueba la suma `0x00C80A00` en `0x7000` y el indicador de verificación en `0x7004`. El tráfico provoca desalojos sucios; no garantiza que el *eviction buffer* se llene ni que ocurra forwarding. Verificar también `CACHE=0` y `CACHE=1` para comparar ciclos y comportamiento.

Las pruebas de unidad deben incluir la aceptación diferida del pedido inferior, respuesta inmediata, aciertos y fallos, reemplazo de vías, escrituras con máscara, víctimas sucias, bloqueo por buffer lleno y ausencia de pedidos duplicados. Los resultados concretos deben tomarse de las ejecuciones del repositorio, no de este documento.
