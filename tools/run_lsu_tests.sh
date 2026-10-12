#!/usr/bin/env bash
set -euo pipefail

# Ejecutar desde cualquier carpeta; las rutas de VCD son relativas a la raíz.
task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$task_repo_root"
mkdir -p build

iverilog -g2012 -Wall -s tb_lsu_dec -o build/tb_lsu_dec.vvp \
    rtl/lsu_dec.sv tb/tb_lsu_dec.sv
vvp build/tb_lsu_dec.vvp | tee build/tb_lsu_dec.log

iverilog -g2012 -Wall -s tb_lsu -o build/tb_lsu.vvp \
    rtl/lsu_dec.sv rtl/lsu.sv tb/tb_lsu.sv
vvp build/tb_lsu.vvp | tee build/tb_lsu.log
