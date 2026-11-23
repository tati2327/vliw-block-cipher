# Caché L1 de datos

`rtl/l1_cache.sv` implementa la L1 con las interfaces de
[la microarquitectura](microarchitecture.md#213-interfaces-de-la-jerarquía). Tiene 4 KiB, dos vías, 64 conjuntos y líneas de
32 bytes (ocho palabras). Usa write-back, write-allocate y un bit por conjunto para seleccionar la próxima víctima. `REPL=0` usa LRU exacto por defecto y `REPL=1` usa FIFO. No tiene parámetros de capacidad ni latencia.

## Direcciones y almacenamiento

| Campo | Bits de dirección de byte | Función |
|---|---|---|
| Etiqueta | `addr[15:11]` | Cinco bits por vía |
| Conjunto | `addr[10:5]` | Selecciona uno de 64 conjuntos |
| Palabra | `addr[4:2]` | Selecciona una de ocho palabras |
| Byte | `addr[1:0]` | La LSU prepara el carril y `be` |
| Línea inferior | `addr[15:5]` | Dirección de línea de 11 bits |

Cada vía conserva `data[255:0]`, `tags[4:0]`, `valid` y `dirty`. Los bits altos
de dirección no intervienen en la selección, igual que en la memoria de 64 KiB.
Se prefiere una vía inválida. Con ambas válidas, `replacement_way` indica la próxima víctima. LRU deja la otra vía como víctima en cada acierto o llenado. FIFO solo cambia ese bit al llenar, por lo que un acierto de lectura o escritura no altera el orden de entrada. En ambas políticas, la víctima se conserva mientras el fallo está pendiente.

## Puertos para integración

Todos los sentidos se expresan desde L1. Todas las señales usan `clk`.

| Grupo | Señales | Sentido | Ancho |
|---|---|---|---|
| Control | `clk`, `rst` | Entrada | 1 cada una |
| Palabra | `req`, `we` | Entrada | 1 cada una |
| Palabra | `addr`, `wdata`, `be` | Entrada | 32, 32, 4 |
| Palabra | `rdata`, `listo` | Salida | 32, 1 |
| Lectura de línea | `line_req`, `line_we`, `line_addr` | Salida | 1, 1, 11 |
| Lectura de línea | `line_wdata`, `line_mask` | Salida | 256, 32 |
| Lectura de línea | `line_accepted`, `line_ready` | Entrada | 1 cada una |
| Lectura de línea | `line_rdata`, `resp_src` | Entrada | 256, 2 |
| Víctima sucia | `push`, `push_addr`, `push_data` | Salida | 1, 11, 256 |
| Víctima sucia | `full` | Entrada | 1 |
| Métricas | Diez contadores descritos abajo | Salida | 64 cada uno |

El puerto de palabra cumple la interfaz de palabra. `rdata` contiene la palabra completa,
incluso para `lb`; la LSU selecciona el byte y extiende su signo. Un store aplica
únicamente los carriles habilitados por `be`; una máscara vacía conserva los
datos, pero sigue contando como escritura y marca la línea sucia.

El puerto inferior cumple la interfaz de línea y solo lee: `line_we`, `line_wdata` y
`line_mask` siempre valen cero. Los desalojos salen exclusivamente por el puerto
de *push*, conectado al [buffer de líneas](line_buffer.md).

## Acierto, fallo y víctima

En un acierto, `listo=1` y la palabra están disponibles combinacionalmente en
el mismo ciclo del pedido. En el flanco de consumo solo LRU actualiza la víctima. Un store
fusiona los bytes habilitados y marca la vía sucia. No hay pausa ni acceso inferior.
Los pedidos en flancos consecutivos se consideran accesos distintos.

En un fallo se elige víctima una sola vez. Si no termina inmediatamente, se
guardan dirección, operación, dato, máscara y vía elegida. Es un diseño
bloqueante: atiende un solo fallo pendiente, aunque cambie el bus de entrada.
El núcleo no debe enviar una segunda operación hasta completar la primera.

Una víctima inválida o limpia no genera push. Una víctima válida y sucia se
presenta como línea completa por `push_addr={tag,conjunto}` y `push_data`,
en el mismo ciclo que `line_req` solicita el llenado. Este solape no añade una
etapa de desalojo. El bit `evicted` evita volver a empujar la víctima mientras
se espera la lectura. Que el pedido salga no implica que ya haya sido aceptado
por el nivel inferior: el buffer puede estar drenando otra línea.

Si la víctima es sucia y `full=1`, se inhiben tanto push como llenado hasta
que haya espacio. Se cuenta una pausa por buffer lleno en cada flanco bloqueado.
Con víctima limpia o inválida, `full` no bloquea la lectura. La decisión usa el
espacio previo al flanco; un retiro simultáneo de una cola llena libera espacio
para el siguiente ciclo.

## Llenado y forwarding

El pedido inferior se mantiene hasta observar `line_accepted`; entonces baja
`line_req` y se espera `line_ready`. Una respuesta inmediata con `line_ready`
no necesita aceptación previa. En ese flanco se instala la línea, etiqueta y
validez, se actualiza la próxima víctima con ambas políticas y se confirma la operación superior. Si era un store,
se fusionan sus bytes sobre la línea recibida y queda sucia; si era un load,
se entrega la palabra recibida y queda limpia.

El forwarding lo resuelve el buffer: si la línea está en su FIFO, devuelve
`line_ready=1`, datos y `resp_src=2` sin pausa adicional. L1 puede instalarla y
hacer push de otra víctima sucia en el mismo flanco. No se agrega un estado
para respuestas inmediatas. El buffer selecciona la copia más nueva cuando
hay entradas duplicadas y conserva la entrada drenándose hasta su terminación.

## Reset y contadores

El reset es asíncrono, activo alto. Invalida las vías, borra datos, etiquetas,
suciedad y estado de reemplazo, cancela el fallo pendiente y reinicia todos los contadores.
Durante reset no hay pedido ni push ni `listo`. No vacía las líneas sucias hacia
abajo: un reset no sirve para persistir su contenido.

| Contador | Evento |
|---|---|
| `read_count`, `write_count` | Primer flanco de cada pedido nuevo, según `we` |
| `read_hits`, `write_hits` | Pedido nuevo que encuentra la línea residente |
| `read_misses`, `write_misses` | Pedido nuevo sin coincidencia |
| `stall_buffer_cycles` | Pausas de un fallo que termina con `resp_src=2` |
| `stall_l2_cycles` | Pausas de un fallo que termina con `resp_src=1` |
| `stall_memory_cycles` | Pausas de un fallo que termina con origen 0 u otro valor |
| `stall_full_cycles` | Flancos bloqueados por víctima sucia y buffer lleno |

Los contadores usan 64 bits sin saturación. Los accesos se cuentan al entrar;
las pausas de origen se acumulan en `pending_stalls` y se atribuyen al terminar
el fallo. El flanco de terminación no suma pausa. Las pausas por buffer lleno
se cuentan separadamente y no se duplican en el origen. La espera de un drenaje
inferior también forma parte del costo del fallo y se atribuye al origen de la
respuesta final. Por eso un forwarding inmediato sin espera suma cero pausas
de buffer, aunque sí incrementa el contador de forwarding del buffer.

Se cumplen `read_count=read_hits+read_misses` y su equivalente de escritura.
La tasa global de aciertos es `(read_hits+write_hits)/(read_count+write_count)`;
con cero accesos se reporta cero. En un corte sin fallo pendiente, la suma de
las cuatro clases de pausa coincide con `pausa_memoria` del núcleo.

## Pruebas y ejecución

```bash
make tb_l1_cache
make sim PROG=ejercicio1 CACHE=2 MEM_DIV=4 L1_REPL=1 WAVES=0
make tb_line_buffer
make sim PROG=ejercicio1 CACHE=1 MEM_DIV=4 VVP_ARGS=+LOG_MEM
make sim PROG=ejercicio3 CACHE=1 MEM_DIV=4 DATA=build/cifrado_datos.mem VVP_ARGS=+TRACE_L1
```

`tb_l1_cache` ejecuta el modelo inferior controlable con LRU y FIFO, y tres instancias de memoria
principal real con divisores 2, 4 y 5. Comprueba las ocho palabras, máscaras de
cada byte, write-allocate, ausencia de write-through, preferencia de vías inválidas,
LRU en ambos sentidos, víctimas limpias y sucias, push único y llenado simultáneo,
cuatro ciclos de buffer lleno, víctimas que no se bloquean por full, forwarding
inmediato, aceptación demorada, origen de pausas, retención del pedido y accesos
consecutivos. Un tráfico reproducible de 600 operaciones y un recorrido posterior
contrastan datos contra una referencia por palabra. Las esperas tienen límites.

Las instancias reales comprueban latencias exactas `25+7*MEM_DIV`, datos de los
extremos de memoria, bytes de víctimas y contadores sin pedidos duplicados.
`tb_line_buffer` prueba por separado presión, FIFO y forwarding. `tb_programa`
ejercita la conexión completa con un monitor independiente, valida esperados,
identidad de ciclos e igualdad de pausas. Los resultados y la matriz completa
están en [el informe de rendimiento](rendimiento.md).

La secuencia A, B, A, C usa líneas del mismo conjunto. LRU conserva A y expulsa B. FIFO expulsa A aunque se haya leído y escrito recientemente. Las pruebas también comprueban el siguiente reemplazo FIFO y recuperan los bytes modificados desde el nivel inferior. `make tb_l1_cache` pasó 16686 comprobaciones y `make all` pasó los 41 testbenches. La comparación de rendimiento incluye los cinco patrones originales y el caso dirigido de reutilización descrito en [el análisis de rendimiento](rendimiento.md#410-lru-contra-fifo-en-l1).
