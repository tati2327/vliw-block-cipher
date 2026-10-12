#!/usr/bin/env bash
set -euo pipefail
task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$task_repo_root"
mkdir -p build
iverilog -g2012 -Wall -s tb_bru_dec -o build/tb_bru_dec.vvp \
    rtl/bru_dec.sv tb/tb_bru_dec.sv
vvp build/tb_bru_dec.vvp | tee build/tb_bru_dec.log
iverilog -g2012 -Wall -s tb_bru -o build/tb_bru.vvp \
    rtl/bru_dec.sv rtl/bru.sv tb/tb_bru.sv
vvp build/tb_bru.vvp | tee build/tb_bru.log
