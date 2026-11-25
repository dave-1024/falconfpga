#!/bin/bash
# tb_ikbd_real: keyboard ACIA through falcon_bus/falcon_io/falcon_pbus to the ST acia.v + ikbd.sv (HD63701).
# ~2 min. Usage: bash run_ikbd_real.sh [workdir]
set -e
R=$(cd "$(dirname "$0")/../.." && pwd); H=$R/Falcon030_rtl/hdl; F=$R/Falcon030_rtl/hdl
W=${1:-/tmp/ikbdsim}; mkdir -p "$W"; cd "$W"; cp "$H/ikbd/rom/ikbd.hex" .
IV=${IVERILOG:-iverilog}; VVP=${VVP:-vvp}
$IV -g2012 -o tb -I $H/ikbd/hd63701 $R/Falcon030_rtl/sim/tb_ikbd_real.v $F/bus/falcon_bus.v $F/peri/falcon_io.v \
  $F/bus/falcon_pbus.v $H/atarist/acia.v $H/ikbd/ikbd.sv $H/ikbd/rom/MCU_BIROM.v $H/ikbd/hd63701/HD63701.v \
  $H/ikbd/hd63701/HD63701_ALU.v $H/ikbd/hd63701/HD63701_CORE.v $H/ikbd/hd63701/HD63701_EXEC.v \
  $H/ikbd/hd63701/HD63701_MCROM.v $H/ikbd/hd63701/HD63701_SEQ.v
$VVP -n tb | grep -v '^  \.\. t='
