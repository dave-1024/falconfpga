#!/bin/bash
# FAL_01 blitter bench: sim copy of the local stBlitter.sv (iverilog: packed struct, enums -> localparams)
set -e
cd "$(dirname "$0")"
IV=${IV:-/workspace/tools/iverilog-13/bin}
R=../../..
sed -e 's/^typedef struct {/typedef struct packed {/' \
    -e 's/enum int unsigned { S0 = 0, S2, S4, S6} busState;/localparam [1:0] S0=0, S2=1, S4=2, S6=3; logic [1:0] busState;/' \
    -e 's/enum bit\[1:0\] { DMAST_IDLE = 0, DMAST_REQ, DMAST_ACTIVE1, DMAST_ACTIVE2} dmaState, next;/localparam [1:0] DMAST_IDLE=0, DMAST_REQ=1, DMAST_ACTIVE1=2, DMAST_ACTIVE2=3; logic [1:0] dmaState, next;/' \
    -e 's/enum int unsigned { ST_IDLE = 0, ST_FXSR1, ST_RDSRC, ST_RDEST, ST_WDEST} bltState, next, first;/localparam [2:0] ST_IDLE=0, ST_FXSR1=1, ST_RDSRC=2, ST_RDEST=3, ST_WDEST=4; logic [2:0] bltState, next, first;/' \
    $R/Falcon030_rtl/hdl/atarist/stBlitter.sv > /tmp/stBlitter_sim.sv
python3 blit_model.py gen
$IV/iverilog -g2012 -o /tmp/tb_blitter.vvp tb_blitter.v ../../hdl/peri/falcon_blitter.v /tmp/stBlitter_sim.sv
$IV/vvp -n /tmp/tb_blitter.vvp | tail -25
python3 blit_model.py check
