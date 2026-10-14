# Integración con el compilador de CE1108

**Grupo 6 · Contrato de interfaz y validación · 14 de octubre de 2026**

Este documento describe la interfaz entre el compilador Calser (`ccom`) de
CE1108 y el procesador VLIW de CE4301. Fija los archivos intercambiados, la
interpretación de los bundles y las reglas que debe respetar el código generado.
Incluye una ejecución reproducible de un programa del compilador sobre el RTL.

La especificación normativa es [isa.md](isa.md). La organización del hardware
está en [microarchitecture.md](microarchitecture.md), y el procedimiento de
simulación en [simulation.md](simulation.md). Una diferencia entre herramientas
y hardware se resuelve contra la ISA antes de modificar la codificación.

## Proyectos y responsabilidades

| Proyecto | Responsabilidad |
|---|---|
| [vliw-block-cipher](https://github.com/tati2327/vliw-block-cipher) · CE4301 | Implementa la ISA, carga instrucciones y datos, ejecuta los bundles y comprueba sus resultados mediante testbenches. |
| [calser_compiler](https://github.com/Kevnrz/calser_compiler) · CE1108 | Traduce Calser a bundles, organiza las operaciones y ensambla sus codificaciones; genera las imágenes que consume la simulación. |

El compilador es una dependencia externa: este repositorio no contiene su
código ni lo construye con `make all`. Para repetir las pruebas se necesita su
ejecutable `ccom` y, para compilar el ejemplo desde Calser, su archivo fuente.

El contrato coincide con `fase4_contrato_comun.md`, `docs/ccom_banderas.md` y
`docs/crypto_para_ccom.md` del repositorio del compilador. Las convenciones de
llamada y distribución de variables son decisiones del compilador; el hardware
solo observa registros, direcciones y operaciones de la ISA.

## Archivos de intercambio

```bash
ccom -s programa.cls -o programa.bin
ccom -x archivo.s -o archivo.bin
```

El primer comando compila Calser y conserva el ensamblador generado. El segundo
ensambla directamente una entrada textual con la sintaxis de la ISA; no ejecuta
las fases de compilación de Calser. Los ejemplos del compilador también usan la
extensión `.asm`. El modo de ensamblado se selecciona con `-x`.

| Archivo | Contrato |
|---|---|
| `.asm` o `.s` de entrada | Un bundle por línea, cuatro slots entre llaves y separados por `|`, en orden `slot0 | slot1 | slot2 | slot3`. Admite etiquetas, comentarios con `#` y líneas vacías. |
| `.hex` de salida | Una línea por bundle de 128 bits, `slot3_slot2_slot1_slot0`, ocho dígitos hexadecimales por slot. Es la entrada de `imem` mediante `$readmemh`. |
| `.mem` de salida | Imagen inicial de datos: `@0` seguido de palabras de 32 bits en hexadecimal. Se carga en `memory`. Con `-x` no hay datos iniciales y el archivo contiene solo `@0`. |
| `.bin` de salida | Encabezado de cuatro palabras de 32 bits little endian: cantidad de bundles, punto de entrada, tamaño de datos en bytes y dirección inicial de datos. Luego bundles de 16 bytes, slot 0 primero, cada slot little endian; al final, datos iniciales. |
| `.asm` generado con `-s` | Ensamblador anotado con etiquetas y comentarios. Puede reensamblarse con `-x` para obtener el mismo `.hex`. |

La simulación actual carga `.hex` y `.mem` por separado. No interpreta el
encabezado del `.bin`. El punto de entrada es el bundle 0 y el PC cuenta bundles,
no bytes. La memoria de instrucciones predeterminada admite 4096 bundles;
los programas deben caber en la profundidad configurada.

Los comandos válidos terminan con código 0; los errores se notifican por stderr
y con código distinto de cero. Antes de usar un archivo generado se comprueba
que el comando terminó correctamente, para evitar ejecutar una salida anterior.

## Slots, registros y codificación

| Slot | Operaciones admitidas |
|---|---|
| 0 | ALU0. |
| 1 | ALU1 con `sel = 0`, o CRYPTO con `sel = 1`. |
| 2 | BRU: saltos condicionales, saltos directos y con enlace. |
| 3 | LSU: `lw`, `lb`, `sw` y `sb`. |

`nopi` puede ocupar cualquier slot. Las instrucciones son de 32 bits y los
campos, inmediatos y desplazamientos se codifican según las tablas de la ISA.
La selección de CRYPTO corresponde al ensamblador, no a una transformación
posterior del archivo `.hex`.

El banco contiene `r0` a `r15`, de 32 bits. Los alias son `rz = r0`, `rl = r1`,
`rx = r2`, `rg = r3` y `t0` a `t11 = r4` a `r15`. `rz` devuelve cero y descarta
escrituras. Los papeles de enlace, punteros y temporales son convenciones de
software, no restricciones adicionales del circuito.

Los inmediatos de 18 bits con signo abarcan de -131072 a 131071. Una constante
de 32 bits que no cabe se construye con la secuencia de la ISA; no se trunca
para hacerla caber en `mov`. Las comparaciones relacionales de la ISA son con
signo. Las operaciones aritméticas trabajan con palabras de 32 bits.

El ensamblador rechaza bundles con una cantidad incorrecta de slots,
operaciones en unidades incompatibles, operandos fuera de rango, etiquetas
indefinidas o duplicadas, mnemónicos desconocidos y escrituras simultáneas de
varios slots al mismo registro destino, salvo `rz`.

## Dependencias, saltos y finalización

El hardware no inserta bundles para resolver dependencias de datos. El
compilador, o quien escribe ensamblador manual, respeta estas reglas:

- Entre la escritura de un registro y una lectura dependiente deja al menos
  un bundle intermedio. Puede contener operaciones independientes. La regla
  también aplica a registros producidos por cargas y a operandos de saltos.
- Todos los slots de un bundle leen los valores anteriores de los registros.
  Un slot no consume el resultado producido por otro slot del mismo bundle.
- Un store seguido por una carga de la misma dirección no exige por sí solo
  un bundle intermedio; las dependencias de registros siguen aplicando.
- Una etiqueta identifica el índice de su bundle. Un salto relativo calcula
  `destino - PC`, usando el PC del bundle que contiene el salto.
- Un salto tomado descarta la instrucción de IF. No hay un delay slot que el
  software deba ejecutar después del salto.
- El bundle que contiene el salto se ejecuta completo: las operaciones de los
  otros slots conservan sus efectos aunque el salto sea tomado.

El compilador termina `main` con un salto a su propio bundle (`jef 0`, o una
etiqueta equivalente). No hay una instrucción de apagado. `tb_programa`
reconoce ese salto, deja avanzar cinco ciclos y finaliza la simulación. Por
esta convención, un bucle intencional con `jef 0` también se interpretaría como
fin por este TB.

## Memoria de datos

La configuración predeterminada ofrece 64 KiB con direcciones en bytes y
palabras de 32 bits little endian. Las cargas y stores de palabra usan
direcciones alineadas a cuatro bytes. `lb` y `sb` seleccionan el byte
correspondiente dentro de la palabra.

Las marcas `@` de un `.mem` usan índices de palabra: `@400` corresponde a la
dirección de byte `0x1000`. No se multiplica el PC por cuatro para obtener una
dirección de instrucción: instrucciones y datos tienen espacios separados.

El compilador determina las direcciones de globales, parámetros, locales,
retornos y temporales. Las globales constantes se incluyen en la imagen `.mem`;
los inicializadores que requieren cálculo se ejecutan como instrucciones.
El RTL no implementa esas estructuras de lenguaje ni detecta solapamientos.
El programa y sus archivos deben respetar el tamaño de memoria configurado y
mantener separadas sus áreas de trabajo y los archivos que procesa.

Para datos externos se usa `tools/load_file.py` y se selecciona su imagen como
`DMEM_INIT` o `PROG_MEM`. Si el programa necesita además la imagen del compilador,
se prepara una imagen conjunta con zonas sin solapamiento: `top` recibe una
sola imagen inicial de datos, no mezcla automáticamente dos archivos.

## Contrato de CRYPTO

Las operaciones `auth`, `logout`, `kv_write`, `kv_lock`, `sanc` y `feis` ocupan
solo el slot 1. `k`, `i` y `w` son campos constantes de dos bits (0 a 3), no
registros. Una llave tiene cuatro palabras de 32 bits; existen cuatro llaves.

| Operación | Condición y efecto relevantes para el programa |
|---|---|
| `auth rs1` | Compara H del token con el ancla. Si coincide, autentica y sustituye el ancla por el token; si falla, quita la autenticación y activa la excepción. |
| `kv_write rs1, k, w` | Requiere autenticación y bóveda desbloqueada; guarda una palabra. |
| `kv_lock` | Requiere autenticación; bloquea escrituras hasta reset. |
| `feis rd, rs1, rs2, k, i` | Requiere autenticación; calcula una ronda usando la subllave seleccionada. Solo esta operación CRYPTO escribe un registro general. |
| `sanc rs1` | Requiere autenticación; establece una nueva ancla. |
| `logout` | Cierra la sesión; no desbloquea la bóveda. |

`F(x, K) = (ROL32(x, 5) + K) XOR ROL32(x, 13)`, con suma de 32 bits.
`feis` produce `rs1 XOR F(rs2, subllave[k][i])`; el programa organiza las cuatro
rondas, los intercambios y el orden de subllaves para cifrar y descifrar.
La bóveda no proporciona instrucciones de lectura hacia registros o memoria.

`auth` ocupa 14 ciclos de EX y pausa el pipeline por hardware. El compilador
no inserta 13 bundles vacíos para esperar: el bundle siguiente observa el
estado actualizado. Sigue respetando la separación entre registros para cargar
el token antes de `auth`. Una escritura de bóveda puede ir seguida por `feis`
en el bundle siguiente. Los resultados de rondas Feistel que se usan como
operandos mantienen la separación normal de un bundle.

La cadena inicial usa semilla `0xCAFEDECE`, ancla `0xFEFF95FF`, primer token
`0xF47BD70B` y segundo token `0xA45326BA`. Los tokens se generan fuera del
procesador mediante `tools/lamport.py`. El reset normal conserva el ancla;
una simulación nueva inicializa la cadena mediante el arranque de `top`.
Generar otra lista no actualiza el hardware en ejecución.

El programa no puede leer `AUTH`, `KVLOCK` ni `EXC` mediante registros generales.
Los TB observan esos estados por jerarquía para comprobar aceptación y rechazo.

## Validación conjunta reproducible

Se comprobó el flujo completo con el factorial de cinco, fuente
`pruebas/p02_factorial.cls` del compilador. El programa llama a una función,
usa saltos, aritmética y memoria. El repositorio del procesador contiene su
ensamblador e imagen de ejemplo en `programs/ej1.asm` y `programs/ej1.hex`, junto
con los resultados esperados `programs/ej1.exp.mem`.

Suponiendo ambos repositorios como carpetas hermanas, desde la raíz del
repositorio del procesador:

```bash
CCOM_REPO=../calser_compiler
mkdir -p build
"$CCOM_REPO/ccom" -s "$CCOM_REPO/pruebas/p02_factorial.cls" \
  -o build/factorial.bin
"$CCOM_REPO/ccom" -x build/factorial.asm \
  -o build/factorial_reassembled.bin
cmp build/factorial.hex build/factorial_reassembled.hex

iverilog -g2012 -Wall -I data/lamport_demo -s tb_programa \
  '-DPROG_HEX="build/factorial.hex"' \
  '-DPROG_MEM="build/factorial.mem"' \
  '-DEXP_MEM="programs/ej1.exp.mem"' \
  -o build/tb_factorial rtl/*.sv tb/tb_programa.sv
vvp build/tb_factorial
```

Se adapta `CCOM_REPO` si los proyectos están en otra ubicación. La prueba usa
el `.hex` recién compilado y su `.mem`; no depende de que coincidan byte a byte
con una salida de una versión anterior del generador.

### Evidencia obtenida

Validación realizada el 14 de octubre de 2026 con el procesador en `6bf55f0`
y el compilador en `aa2d3b1`. Se ejecutó sobre una copia temporal del RTL y los
datos del procesador, sin modificar sus programas versionados.

| Comprobación | Resultado |
|---|---|
| Compilación de `p02_factorial.cls` con `ccom -s` | Código de salida 0. |
| Reensamblado de su `.asm` con `ccom -x` | Código de salida 0; `.hex` idéntico al generado desde Calser. |
| Ejecución del `.hex` recién generado en `tb_programa` | Final reconocido en el ciclo 230; 7 comprobaciones y 0 fallos. |
| Valores desconocidos en PC, bundle o datos escritos en WB | Ningún ciclo detectado por los monitores del TB. |
| Resultado de factorial en dirección `0x0004` | `0x00000078` = 120. |
| Entrada y variable resultado de `main`, direcciones `0x0040` y `0x0044` | 5 y 120, respectivamente. |

Salida resumida del testbench:

```text
Llegada al fin en el ciclo 230
Casos: 7; Fallos: 0
PASS tb_programa
```

También se ejecutó `python3 pruebas/ensamblador/probar.py` desde el repositorio
del compilador: pasaron los cinco vectores de codificación, el ejemplo exacto
de la ISA, el formato binario, las banderas, once casos de error, las pruebas
de sintaxis y el reensamblado de diez programas.

Esta evidencia demuestra compilación y ejecución conjunta para factorial y
compatibilidad de ensamblado en los casos indicados. Las pruebas de Feistel y
bóveda del procesador se ejecutan con `make tb_caso4_feis`,
`make tb_caso5_feistel4`, `make tb_caso6_boveda` y `make tb_caso7_mixto`; no se
presentan aquí como ejecución de un fuente Calser de cifrado. Si se añade esa
validación, se registra su fuente, comandos y resultados específicos.
