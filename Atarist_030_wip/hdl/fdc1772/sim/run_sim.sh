#!/bin/bash
# FDC SD-error bench. Makes sim-only copies of fdc1772.v/floppy.v (always begin -> always @*,
# module-level regs zeroed as on the FPGA) and runs tb_fdc_sderr.v with Icarus.
set -e; cd "$(dirname "$0")"
sed 's/^always begin/always @* begin/' ../fdc1772.v > /tmp/f0.v
python3 zinit.py /tmp/f0.v /tmp/fdc_sim.v; python3 zinit.py ../floppy.v /tmp/floppy_sim.v
iverilog -g2012 -DVERILATOR -o /tmp/tbf tb_fdc_sderr.v /tmp/fdc_sim.v /tmp/floppy_sim.v
vvp -n /tmp/tbf | grep -v "^  t="
