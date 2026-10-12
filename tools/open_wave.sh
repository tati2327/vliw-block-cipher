#!/usr/bin/env bash
set -euo pipefail
task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$task_repo_root"
wave_path="${1:-build/tb_lsu.vcd}"
if [[ ! -f "$wave_path" ]]; then
    printf 'No existe el VCD: %s. Ejecuta primero su testbench.\n' "$wave_path" >&2
    exit 1
fi
# Evita cargar módulos GTK y bibliotecas de Snap heredados de VS Code.
# Solo afecta al proceso del visor; conserva DISPLAY, WAYLAND_DISPLAY y sesión.
exec env -u GTK_PATH -u LD_LIBRARY_PATH -u LD_PRELOAD gtkwave "$wave_path"
