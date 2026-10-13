# Cadena Lamport de 32 bits

`lamport.py` implementa la H del diseño: Ascon-Hash256 de cuatro bytes
little-endian, con salida truncada a los primeros cuatro bytes, interpretados
como entero little-endian. Usa solo la biblioteca estándar de Python.

Desde la raíz del repositorio, estos comandos generan la cadena de demostración y
comprueban todos sus hashes contra `auth_hash32.sv`:

```bash
make lamport
make tb_lamport
```

`make tb_lamport` ya incluye la generación. La cadena reproducible usa
semilla `0xCAFEDECE` (Café de CE) y longitud 100. Estos valores se usan para las pruebas
del proyecto:

```text
Ancla inicial: x100 = 0xFEFF95FF
Primer token:  x99  = 0xF47BD70B
Segundo token: x98  = 0xA45326BA

H(0xF47BD70B) = 0xFEFF95FF
H(0xA45326BA) = 0xF47BD70B
```

El hardware acepta x99 y lo guarda como ancla; entonces necesita x98.
La generación construye x0..x100, pero los tokens se presentan de x99 a x0.
Una longitud N produce N tokens y N+1 eslabones, incluido el ancla final.

## Archivos generados

En `data/lamport_demo/`:

- `chain.json` contiene la semilla, el ancla, la cadena y los tokens en orden de uso.
- `tokens.mem` contiene los tokens desde x99 hasta x0, uno por línea.
- `hash_vectors.mem` contiene pares de entrada/hash para contrastar Python con RTL.
- `lamport_config.svh` define `LAMPORT_RESET_ANCHOR` y `LAMPORT_TOKEN_COUNT`.

`crypto_state` usa `32'hFEFF95FF` como valor por defecto de su parámetro
`RESET_ANCHOR`, correspondiente a esta cadena. Su TB verifica que el valor
coincide con la configuración generada. Si cambia la cadena, la instancia
recibe el nuevo ancla mediante el parámetro, o se actualiza su valor por defecto.
El hardware carga el registro con `rst = 1` e `init_anchor = 1` en una subida
de reloj. Generar archivos por sí solo no actualiza un registro del hardware
en ejecución. La conexión de la unidad completa queda para `crypto_unit`.

## Otras cadenas

```bash
python3 tools/lamport.py --seed 0xCAFEDECE --length 10 --out build/otra_cadena
python3 tools/lamport.py --self-test
```

Sin `--out`, el script imprime el ancla y todos los tokens. Requiere una
semilla explícita. Rechaza entradas fuera de 32 bits, longitudes menores que
uno y repeticiones dentro de la cadena.

## Validación realizada

Los ocho vectores fijos coinciden con la referencia de `ascon/ascon-c`
documentada en `tb/reference/README.md`. Los 100 eslabones de la cadena de
demostración se contrastaron además con esa implementación C externa y con
el motor RTL. El autocheck de Python comprueba el orden inverso y que un
token consumido no verifica contra sí mismo como nueva ancla.

`tb_crypto_unit` comprueba la autenticación de tokens sucesivos y el rechazo
de reutilización con el control y los registros reales conectados. También
verifica que el reset normal conserve el ancla y no habilite un token consumido.
