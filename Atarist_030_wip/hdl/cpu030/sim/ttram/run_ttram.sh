#!/bin/bash
# TT-RAM bench (no Gowin netlist needed): ./run_ttram.sh  -> prints TTRAM BENCH PASS/FAIL
set -e
H=$(cd "$(dirname "$0")" && pwd); R=$(cd $H/../../.. && pwd)
iverilog -g2012 -DTTRAM -DWF030_NETLIST ${OFFGRID:+-DOFFGRID} -o /tmp/tb_ttram.vvp -s tb_ttram $H/tb_ttram.v $H/wf030_stub.v $H/sdram_model.v \
  $R/cpu030/cpu030_st_bridge.v $R/tang/mega138kpro/sdram.v
# OFFGRID=1 ./run_ttram.sh: ST slot gaps 8..15 clk (arbiter phase randomised)
vvp -n /tmp/tb_ttram.vvp | grep -v "^VCD"
