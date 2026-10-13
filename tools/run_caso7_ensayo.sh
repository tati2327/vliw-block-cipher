#!/usr/bin/env bash
# Ida y vuelta del ensayo del caso 7 (sin CRYPTO). Correr desde la raiz del repo.
set -e
paso="inicio"
trap 'echo "FAIL run_caso7_ensayo (paso: $paso)"' ERR

paso="1 load_file"
python3 tools/load_file.py --input data/caso7_ensayo.txt --output data/caso7_ensayo.mem --address 0x1000
paso="2 make tb_caso7_ensayo"
make tb_caso7_ensayo
paso="3 tamano"
size=$(stat -c %s data/caso7_ensayo.txt)
paso="4 extract_data"
python3 tools/extract_data.py --memory build/tb_caso7_ensayo_dump.mem --address 0x3000 --size "$size" --output build/caso7_ensayo_descifrado.txt
python3 tools/extract_data.py --memory build/tb_caso7_ensayo_dump.mem --address 0x2000 --size "$size" --output build/caso7_ensayo_cifrado.bin
paso="5 cmp descifrado identico"
cmp data/caso7_ensayo.txt build/caso7_ensayo_descifrado.txt
paso="6 cifrado distinto"
if cmp -s data/caso7_ensayo.txt build/caso7_ensayo_cifrado.bin; then
    echo "el cifrado es igual al original"
    false
fi
trap - ERR
echo "PASS run_caso7_ensayo"
