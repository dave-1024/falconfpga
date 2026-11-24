#!/bin/bash
# FAL_01: iverilog check that a mount pulse during or after helper_hold
# starts tos_loader and copies 1024 sectors to $E00000.
set -euo pipefail
IV=${IVERILOG:-/workspace/tools/iverilog/bin/iverilog}
VVP=${VVP:-/workspace/tools/iverilog/bin/vvp}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${OUT:-/tmp/fal_tos_loader}
mkdir -p "$OUT"
"$IV" -g2012 -o "$OUT/tb_tos_loader.vvp"   "$ROOT/Falcon030_rtl/hdl/top/tos_mount_latch.v"   "$ROOT/Falcon030_rtl/hdl/top/tos_loader.v"   "$ROOT/Falcon030_rtl/sim/tb_tos_loader.v"
"$VVP" "$OUT/tb_tos_loader.vvp"
