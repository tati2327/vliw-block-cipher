# Implementación de CRYPTO

La referencia de diseño es [diseno_crypto_ascon.md](diseno_crypto_ascon.md).

## Ejecución

Desde la raíz del repositorio, con Python 3, Icarus Verilog, make y GTKWave disponibles:

```bash
make crypto
make tb_crypto_unit
make waves_crypto_unit
```

`make crypto` ejecuta las ocho pruebas de CRYPTO; `make sim` ejecuta todos los TB del repositorio. Los objetivos `tb_nombre`
compilan y ejecutan una prueba; `waves_nombre` también abre sus ondas. No es
necesario ejecutar ambos consecutivamente. Los archivos compilados y VCD
se guardan en `build/`.

## Módulos implementados

| Archivo | Función |
|---|---|
| `rtl/auth_hash32.sv` | Calcula H de un token de 32 bits en doce rondas después de la carga. |
| `rtl/key_vault.sv` | Guarda cuatro llaves con cuatro palabras cada una. |
| `rtl/crypto_state.sv` | Guarda autenticación, sello, excepción y ancla. |
| `rtl/crypto_control.sv` | Calcula permisos, control del hash y estado siguiente. |
| `rtl/crypto_datapath.sv` | Calcula la ronda Feistel y compara el hash con el ancla. |
| `rtl/crypto_dec.sv` | Traduce los cinco bits de funct; pertenece a dispatch. |
| `rtl/crypto_unit.sv` | Conecta control, estado, bóveda y datapath. |

Cada módulo tiene un testbench en `tb/`. `tb_lamport` compara los 100 tokens
generados por Python con el motor RTL. La generación y procedencia de los
vectores se documentan en `tools/README.md` y `tb/reference/README.md`.

## Ancla de demostración

`make lamport` genera la cadena con semilla `0xCAFEDECE` y longitud 100 en
`data/lamport_demo/`. El ancla es `0xFEFF95FF`; los dos primeros tokens son
`0xF47BD70B` y `0xA45326BA`. Los parámetros por defecto de `crypto_state` y
`crypto_unit` coinciden con esa cadena. Sus pruebas comprueban la coincidencia
con la configuración generada, sin sobrescribir dichos parámetros.

## Conexión con el procesador

`crypto_dec` se instancia en dispatch y sus salidas viajan por ID/EX.
`crypto_unit` se instancia en EX y recibe `en`, `crypto_op`, `a`, `b`, `k`,
`i`, `ex_valid` y `ex_commit`. Entrega `result`, `allowed` y `crypto_stall`.
Las llaves y el estado no tienen puertos de lectura hacia el programa.

El arranque mantiene `rst = 1` e `init_anchor = 1` durante al menos una
subida de reloj. Después desactiva `init_anchor` antes de liberar `rst`.
Un reset normal usa `init_anchor = 0`: borra llaves, banderas y hash pendiente,
pero conserva el ancla. Sin arranque protegido, el ancla no está inicializada.

Mientras `crypto_stall = 1`, el core conserva ID/EX y sus operandos, impide
stores y emite burbujas hacia EX/WB. El motor Ascon sigue recibiendo reloj.
Sin otras fuentes de espera, el contrato del diseño es:

```text
ex_commit = ex_valid AND NOT crypto_stall AND NOT rst
```

La instrucción auth emplea una carga, doce rondas y un flanco de finalización:
14 ciclos. El core retira el bundle al finalizar; si conserva auth después de
su aceptación, el motor puede iniciar otro cálculo en la siguiente subida.
El TB retira el bundle y también verifica que un resultado terminado espere
si ex_commit permanece deshabilitado por otra causa.

`allowed` indica permiso, no habilitación de escritura por sí sola. La escritura
del resultado CRYPTO debe combinar el `we` decodificado con `allowed` y la
validez de EX/WB. `allowed = 1` para auth permite el intento; el token puede fallar.

## Alcance de las pruebas

`tb_crypto_unit` verifica autenticación válida e inválida, tokens sucesivos y
reutilizados, carga de las 16 palabras, ronda Feistel, sello, sanc, logout,
ausencia de efectos sin commit o validez, conservación del ancla y cancelación
del hash por reset. Observa registros internos por jerarquía sin puertos de debug.

Estas pruebas validan el subsistema CRYPTO. Todavía falta conectarlo con el core
y ejecutar los programas de los casos del enunciado sobre el procesador completo.
La microarquitectura y la ISA documentan la conservación del ancla y `init_anchor`.
En esta rama, `rtl/core.sv` y `rtl/dispatch.sv` todavía mantienen la variante sin
CRYPTO. Luis debe conectar `crypto_dec`, `u_crypto`, la selección del resultado
y la escritura autorizada; también debe llevar la señal de arranque protegida
`init_anchor` hasta `u_crypto`, sin activarla en los resets normales.
