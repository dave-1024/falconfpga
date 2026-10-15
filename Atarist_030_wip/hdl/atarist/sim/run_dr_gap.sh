#!/bin/bash
# Reset-sequence check (iverilog): atarist.v reset_cnt/DR_GAP + the bridge's cpu_rst_n hold.
# tb_dr_gap_gen.v is generated from the sources (copies of those blocks; regenerate if they change).
# Expect: rigsdram timing = 2 CPU releases (the CPU runs, then is reset again); ST_DR_PRECPU = 1 release.
cd "$(dirname "$0")"; IV=${IVERILOG:-iverilog}; VVP=${VVP:-vvp}
$IV -g2012 -o /tmp/drg tb_dr_gap_gen.v && a=$($VVP -n /tmp/drg | grep -o "releases=[0-9]*")
$IV -g2012 -DST_DR_PRECPU -o /tmp/drg tb_dr_gap_gen.v && b=$($VVP -n /tmp/drg | grep -o "releases=[0-9]*")
echo "rigsdram $a, ST_DR_PRECPU $b"; [ "$a" = releases=2 ] && [ "$b" = releases=1 ] && echo PASS || { echo FAIL; exit 1; }
