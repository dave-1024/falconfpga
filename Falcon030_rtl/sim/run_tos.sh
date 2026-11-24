#!/bin/bash
# FAL_01: GHDL run of TOS 4.04 on the shared WF68K30L with the behavioural Falcon bus (tb_falcon.vhd).
# Usage: run_tos.sh <tos404.img> [scratch dir, default /tmp/falsim] [extra -g generics]
# The CPU sources come from ../../Atarist_030_wip/hdl/cpu030 (shared, never copied). ROM images are not in git.
set -e
H=$(cd "$(dirname "$0")" && pwd); S=$H/../../Atarist_030_wip/hdl/cpu030
IMG=$(readlink -f "$1"); W=${2:-/tmp/falsim}; shift 2 || shift $#; mkdir -p $W/work; cd $W
G=${GHDL:-ghdl}; O="--std=08 -fsynopsys -frelaxed --workdir=work"
python3 -c "d=open('$IMG','rb').read(); open('tos404.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
for f in pkg exception_handler opcode_decoder address_registers data_registers alu bus_interface control icache dcache mmu top; do
  $G -a $O $S/wf68k30L_$f.vhd 2>/dev/null; done
$G -a $O $H/tb_falcon.vhd && $G -e $O tb_falcon
$G -r $O tb_falcon "$@" 2>&1 | grep -v "^.*:(assertion\|NUMERIC_STD\|metavalue" > tos.log || true
tail -5 tos.log
