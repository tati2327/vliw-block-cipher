# Referencia de auth_hash32

Los ocho valores esperados del testbench se obtuvieron el 12 de octubre de
2026 mediante `crypto_hash/asconhash256/ref/hash.c` de
[ascon/ascon-c](https://github.com/ascon/ascon-c), rama `main`, implementación
del equipo de Ascon para NIST SP 800-232. El generador de esta carpeta llama
a esa referencia C; no calcula el hash mediante una copia del RTL.

SHA-256 del archivo `hash.c` usado:

```text
336045b5329f52f48807390c0e8ac2f0b0fb8fae3b92715ffcae74fb919cd5a8
```

Cada token se entrega como cuatro bytes little-endian. La referencia realiza
el relleno y produce 32 bytes de hash. El esperado del RTL corresponde a los
primeros cuatro bytes interpretados como un entero little-endian.

| Token | hash32 esperado |
|---|---|
| `03020100` | `EDC7E4D7` |
| `00000000` | `8F28B790` |
| `00000001` | `EC267D58` |
| `80000000` | `F5C202DC` |
| `80000001` | `FEFEC6C6` |
| `12345678` | `88035407` |
| `FFFFFFFF` | `8A6AD37E` |
| `A5A55A5A` | `D020C92A` |

El primer caso coincide con Count=5 del
[KAT publicado](https://github.com/ascon/ascon-c/blob/main/crypto_hash/asconhash256/LWC_HASH_KAT_128_256.txt):
Msg=`00010203`, MD=`D7E4C7ED9B8A325CD08B9EF259F8877054ECD8304FE1B2D7FD847137DF6727EE`.
Ese mensaje equivale al token `03020100`, y su prefijo corresponde al entero
`EDC7E4D7`. El mensaje de entrada tiene cuatro bytes; el relleno no constituye
otros cuatro bytes de datos.

## Reproducción de los valores

Con la referencia descargada en `/tmp/ascon-c-main`, desde la raíz del repositorio:

```bash
cc -std=c99 -Wall -Wextra \
  -I/tmp/ascon-c-main/crypto_hash/asconhash256/ref \
  -I/tmp/ascon-c-main/tests \
  tb/reference/generate_auth_hash32_vectors.c \
  /tmp/ascon-c-main/crypto_hash/asconhash256/ref/hash.c \
  -o /tmp/generate_auth_hash32_vectors
/tmp/generate_auth_hash32_vectors
```

El testbench usa valores fijos: ejecutarlo no requiere la referencia C ni
acceso a Internet.

## Simulación

Desde la raíz del repositorio:

```bash
make tb_auth_hash32
make waves_auth_hash32
```

El testbench verifica los ocho vectores, cálculos consecutivos, las doce
rondas exactas después del flanco de carga, cambios de entrada durante el
cálculo, retención de todo el estado hasta `accept`, aceptación simultánea
con `start` y reset antes de cada ronda y con resultado pendiente.

Los catorce ciclos de la instrucción `auth` incluyen la finalización en la
unidad CRYPTO. Este testbench comprueba el motor: una carga y doce rondas,
seguidas de un resultado retenido hasta su aceptación.

En GTKWave, las señales `clk`, `rst`, `start`, `accept`, `busy`, `done`,
`token_cargado`, `hash32` y `esperado` permiten revisar la interfaz.
`u_auth_hash32.round_idx` muestra el avance de las rondas. `esperado` solo
se compara con `hash32` cuando `done = 1`.
