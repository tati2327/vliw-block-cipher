# Buffer de líneas

`rtl/line_buffer.sv` implementa el buffer definido en los contratos B y C de
[microarqui.md](microarqui.md). Recibe líneas sucias completas mediante una FIFO,
responde lecturas por forwarding y drena la entrada más antigua hacia el nivel
inferior. No instala ni modifica líneas como resultado de una lectura.

## Parámetro y almacenamiento

`DEPTH` es un entero positivo y vale 4 por defecto. Las instancias previstas son
el write buffer entre L1 y L2 con `DEPTH=4` y el eviction buffer entre L2 y memoria
con `DEPTH=8`. También admite profundidad 1 y profundidades que no sean potencias
de dos; los punteros vuelven explícitamente a cero al alcanzar `DEPTH-1`.

Cada entrada guarda una dirección de línea de 11 bits (`addr[15:5]`) y 256 bits de
datos (32 bytes). Dos punteros y una ocupación interna identifican las entradas
vigentes; no se fusionan entradas con la misma dirección.

## Puertos para integración

Los sentidos se expresan desde `line_buffer`. Todas las señales usan `clk`.

| Grupo | Señales | Sentido | Ancho |
|---|---|---|---|
| Control | `clk`, `rst` | Entrada | 1 cada una |
| Lectura superior | `req`, `we` | Entrada | 1 cada una |
| Lectura superior | `line_addr` | Entrada | 11 |
| Lectura superior | `wdata`, `wmask` | Entrada | 256, 32 |
| Lectura superior | `accepted`, `ready` | Salida | 1 cada una |
| Lectura superior | `ready_rdata`, `resp_src` | Salida | 256, 2 |
| Push | `push`, `push_addr`, `push_data` | Entrada | 1, 11, 256 |
| Push | `full` | Salida | 1 |
| Nivel inferior | `down_req`, `down_we` | Salida | 1 cada una |
| Nivel inferior | `down_line_addr` | Salida | 11 |
| Nivel inferior | `down_wdata`, `down_wmask` | Salida | 256, 32 |
| Nivel inferior | `down_accepted`, `down_ready` | Entrada | 1 cada una |
| Nivel inferior | `down_ready_rdata`, `down_resp_src` | Entrada | 256, 2 |
| Métricas | `received_count`, `forwarding_count`, `full_cycles`, `max_occupancy` | Salida | 64 cada una |

El puerto superior conserva los campos de la interfaz de línea, pero únicamente
admite `we=0`: `wdata` y `wmask` no se utilizan. Un pedido con `we=1` no se atiende
ni recibe confirmación. Las escrituras entran exclusivamente por `push`.

El prefijo `down_` identifica la misma interfaz de línea como maestro. Puede
conectarse con L2, otro buffer o un modelo compatible con el contrato B. No se
requieren señales `busy` ni `done`: la aceptación se observa con `down_accepted`
y la terminación con `down_ready`. El origen recibido viaja sin recodificar;
los valores acordados son 0 para memoria, 1 para L2 y 2 para un buffer.

## Handshake y temporización

### Push y retiro

En cada flanco ascendente, `push && !full` incorpora una línea. Si `full=1`, el
push no se guarda y el emisor debe mantenerlo pendiente. `full` refleja la
ocupación anterior al flanco: un buffer lleno rechaza el push aunque termine
un drenaje en ese mismo flanco.

La entrada que se está drenando sigue contando en la ocupación y participando
en forwarding hasta el flanco con `down_ready=1`. Retirarla en `down_accepted`
permitiría perder una copia que todavía no terminó de escribirse abajo.

Un push y un retiro pueden ocurrir en el mismo flanco cuando había espacio;
ambos punteros avanzan y la ocupación permanece igual. Una línea nueva entra
en la búsqueda después de ese flanco; no hay bypass desde `push_data` antes
de almacenarla.

### Lectura con forwarding

Para una lectura nueva, se comparan combinacionalmente las direcciones de todas
las entradas vigentes, incluida la que se esté drenando. Si hay varias
coincidencias, se entrega la más reciente según el orden de inserción.

`ready=1`, `ready_rdata` y `resp_src=2` están disponibles en el mismo ciclo del
pedido, sin esperar al nivel inferior. La entrada permanece en la FIFO.
Este acceso no genera un pulso adicional de `accepted`: el maestro debe consumir
`ready` en el flanco actual y retirar el pedido, tal como permite el contrato B.

Un forwarding puede coincidir con un drenaje, incluso si este ya fue aceptado.
Si una lectura ya se presentó abajo, conserva esa ruta hasta completarse: un
push posterior con la misma dirección no sustituye una transacción en curso.
El puerto superior admite una sola lectura pendiente.

### Lectura sin coincidencia

Si el canal inferior está libre dentro del buffer, el pedido de lectura sale
combinacionalmente en el mismo ciclo, con `down_we=0`. También se propagan sin
un registro adicional `accepted`, `ready`, `ready_rdata` y `resp_src` desde
las señales correspondientes del nivel inferior.

El buffer conserva la dirección y mantiene `down_req` hasta observar
`down_accepted`. Entonces baja `down_req` y espera `down_ready`. Si el nivel
inferior da `down_ready` en el ciclo del pedido, la lectura termina directamente,
aunque no haya pulso de aceptación. `ready` tiene prioridad sobre `accepted`.

El emisor superior mantiene su pedido y dirección hasta ver `accepted` o
consumir una respuesta inmediata con `ready`; después retira `req`. No debe
presentar otra lectura hasta que termine la anterior.

### Arbitraje y drenaje

Al elegir un nuevo pedido inferior, una lectura sin coincidencia tiene prioridad
sobre el drenaje. Una lectura resuelta por forwarding no usa ese canal y permite
que el drenaje avance simultáneamente.

El drenaje presenta la entrada más antigua con `down_we=1` y
`down_wmask=32'hFFFFFFFF`. Se mantiene el pedido hasta `down_accepted`, luego se
espera `down_ready` y se retira la entrada en ese flanco. No se transmite hacia
arriba la aceptación ni la respuesta de una escritura de drenaje.

**Decisión de arbitraje para integración:** la prioridad se aplica al seleccionar
un pedido nuevo. Una vez presentado abajo, se conserva el bus incluso si aún
no llegó `down_accepted`; esto cumple la regla del contrato B de mantener el
pedido hasta la aceptación. Una lectura que llegue después espera, salvo que
pueda resolverse por forwarding. Un drenaje aceptado tampoco se interrumpe.
No se agrega un puerto `busy` ni se presupone una latencia del nivel inferior.

## Estado interno

| Estado | Función |
|---|---|
| `IDLE` | Seleccionar una lectura pendiente o el drenaje más antiguo |
| `READ_REQ` | Mantener una lectura hasta su aceptación o respuesta inmediata |
| `READ_WAIT` | Esperar la respuesta de una lectura aceptada |
| `DRAIN_REQ` | Mantener un drenaje hasta su aceptación o terminación |
| `DRAIN_WAIT` | Esperar que termine la escritura aceptada |

El estado vuelve a `IDLE` al consumir la respuesta. El siguiente pedido se
selecciona combinacionalmente después de ese flanco. Las respuestas de lectura
no atraviesan una etapa de registro adicional dentro del buffer.

## Reset y contadores

`rst` es asíncrono y activo en alto. Vacía la cola, cancela el estado local del
pedido pendiente y pone a cero los contadores. Durante reset se suprimen
`down_req`, `accepted`, `ready` y `full`. No se borran los arreglos de datos:
la ocupación cero impide utilizar su contenido anterior.

Al integrar, el reset de una transacción debe coordinarse con el otro extremo;
el buffer no cancela por sí solo una operación ya aceptada por otro módulo.

| Contador | Actualización en cada flanco fuera de reset |
|---|---|
| `received_count` | Incrementa por cada `push && !full` |
| `forwarding_count` | Incrementa por cada lectura completada localmente con forwarding |
| `full_cycles` | Incrementa por cada ciclo con `full=1`, exista o no un push |
| `max_occupancy` | Conserva la mayor ocupación alcanzada desde reset |

Una lectura con forwarding cuyo `req` siga activo en flancos consecutivos se
interpreta como accesos consecutivos y se contabiliza en cada flanco. Los
contadores de eventos usan aritmética de 64 bits sin saturación.

## Pruebas y ejecución

La prueba principal usa un modelo independiente que cumple el contrato B, con
aceptación registrada, aceptación demorada, latencia configurable y respuestas
combinacionales sin `accepted`. Una FIFO de referencia comprueba los puertos
públicos y los cuatro contadores en cada ciclo; no accede al estado interno del
módulo. Las esperas tienen un límite global que hace fallar la simulación.

```console
make tb_line_buffer
```

El Makefile existente descubre `tb/tb_line_buffer.sv` automáticamente, así que
la prueba también forma parte de `make all`. No se necesitan scripts ni cambios
en las reglas de compilación.

Se ejecutan instancias con `DEPTH=1,3,4,8`. Se comprueban llenado y rechazo,
FIFO, vuelta de punteros, duplicados con prioridad al más nuevo, forwarding en
el mismo ciclo y durante un drenaje, propagación de los orígenes 0/1/2,
prioridad de lectura al seleccionar un pedido, drenaje no interrumpido,
estabilidad del bus hasta aceptación, respuesta inmediata inferior, dirección
retenida tras aceptación, push durante una lectura, push y retiro simultáneos,
rechazo con buffer lleno aun al retirar y reset asíncrono durante un acceso.
También se verifica que un pedido superior de escritura no reciba confirmación.

### Prueba con memoria principal

La ejecución habitual también conecta el módulo con `main_memory` y `MEM_DIV=4`
después de terminar los casos contra el modelo. El origen de memoria se fija
en cero en el testbench. Para cada profundidad se escriben y se vuelven a leer
líneas completas durante dos rondas, comprobando forwarding antes del drenaje,
persistencia después del drenaje y ausencia de lecturas o escrituras duplicadas.
Las instancias de profundidad 4 y 8 cubren las dos configuraciones acordadas.
No se requiere una macro ni un comando adicional para esta prueba.

Resultado conjunto: **Casos: 28528; Fallos: 0**. El número incluye las
comprobaciones por ciclo del monitor. Como control del testbench, se
introdujeron por separado tres errores en copias temporales del módulo:
forwarding de la entrada más vieja, retiro anticipado en `accepted` y `req`
sin bajar tras aceptación. Las tres variantes fueron detectadas. Esas copias
no forman parte del proyecto.

### Compatibilidad y regresión

La revisión con Icarus Verilog 13.0 detectó dos errores previos de orden de
declaraciones que impedían compilar la memoria y las pruebas del procesador:

- En `rtl/main_memory.sv` se reubicó el bloque `initial` después de las
  declaraciones de las señales que inicializa. El contenido del bloque se
  conserva sin cambios.
- En `rtl/core.sv` se reubicó la asignación continua de `memory_bundle` después
  de las declaraciones de `idex_s3_is_load` y `idex_s3_is_store`. La expresión
  se conserva sin cambios.

Estas correcciones permiten ejecutar la prueba con los archivos del repositorio;
no se utilizan copias temporales adaptadas de memoria. No cambian interfaces,
políticas ni latencias de los módulos existentes.

La regresión `make all` ejecuta **37 testbenches** y termina correctamente,
incluidos `tb_line_buffer`, `tb_main_memory`, `tb_mem_adapter` y los casos del
procesador. Persisten avisos de `$readmemh` porque los programas ocupan menos
palabras que la ROM; las pruebas terminan sin fallos.

El módulo, las pruebas independientes y esta documentación quedan listos para
la integración posterior con L1 y L2. La conexión de esas cachés y el mecanismo
de volcado final de la jerarquía siguen correspondiendo a la fase de integración.
