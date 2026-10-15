#!/usr/bin/env bash
# Compara la referencia en C (Fig. 1) con los esperados y con el procesador. Correr desde la raiz del repo.
set -e
paso="inicio"
trap 'echo "FAIL run_ref (paso: $paso)"' ERR

REF=build/feistel4_ref
K0=0x0F1E2D3C,0x4B5A6978,0x8796A5B4,0xC3D2E1F0
KA=19114957,-1985229329,324508639,610839776
KB=286331153,572662306,858993459,1145324612

paso="1 compilar"
mkdir -p build
gcc -std=c99 -Wall -Wextra -Werror -O2 -o "$REF" tools/feistel4_ref.c

paso="2 pruebas"
salida=$("$REF" --pruebas)
echo "$salida"
echo "$salida" | grep -q "^Casos: 9; Fallos: 0$"

paso="3 caso 7 contra la Fig. 1"
./tools/run_caso7.sh
"$REF" --llave "$K0" data/caso7_ensayo.txt build/caso7_ref.bin
cmp build/caso7_cifrado.bin build/caso7_ref.bin

paso="4 ida y vuelta con 903 bytes"
head -c 903 /dev/urandom > build/ref_in.bin
"$REF" --completo --llave "$K0" build/ref_in.bin build/ref_enc.bin
"$REF" -d --completo --llave "$K0" build/ref_enc.bin build/ref_dec.bin
head -c 903 build/ref_dec.bin > build/ref_dec903.bin
cmp build/ref_in.bin build/ref_dec903.bin

paso="5 segmentos"
head -c 1024 /dev/urandom > build/ref_seg_in.bin
"$REF" --llave "$KA" --llave2 "$KB" --segmento 16 build/ref_seg_in.bin build/ref_seg_enc.bin
"$REF" -d --llave "$KA" --llave2 "$KB" --segmento 16 build/ref_seg_enc.bin build/ref_seg_dec.bin
cmp build/ref_seg_in.bin build/ref_seg_dec.bin
"$REF" --llave "$KA" build/ref_seg_in.bin build/ref_seg_una.bin
if cmp -s build/ref_seg_enc.bin build/ref_seg_una.bin; then
    echo "el cifrado por segmentos es igual al de una sola llave"
    false
fi

trap - ERR
echo "PASS run_ref"
