#!/bin/bash
# [F155] LOOPTEST TT-RAM + I-cache bench (sim only). Builds tb030 for the core in $1 (default: this tree)
# twice, as-is and with F147_TWO_WORD forced true in a scratch copy, then runs lt_tt.s (Linux __delay loop
# copied into the cacheable 32-bit TT port, CACR 0808 / 0809 / 0909 / 0809, periodic level 4 + 6 IRQs).
# Pass: done=1 and every pass d0 = FFFFFFFF. The board hang shows as TIMEOUT with no IACK after the first
# I-cache-on pass starts. VCD=1 also writes $W/tw.vcd (bus_if, decoder, icache, exception handler).
# Usage: run_lt_tt.sh [core src dir] [scratch dir]. Needs GHDL >= 4 (GHDL=...) and m68k binutils.
H=$(cd "$(dirname "$0")" && pwd); S=$(cd ${1:-$H/../../..} && pwd); W=${2:-/tmp/lt_tt}; G=${GHDL:-ghdl}
O="--std=08 -fsynopsys -frelaxed --workdir=work"; mkdir -p $W
for v in asis tw; do
  rm -rf $W/src_$v $W/w_$v; mkdir -p $W/src_$v $W/w_$v/work; cp $S/wf68k30L_*.vhd $W/src_$v/
  [ $v = tw ] && sed -i 's/\(constant F147_TWO_WORD *: boolean := \)false;/\1true;/' $W/src_$v/wf68k30L_bus_interface.vhd
  (cd $W/w_$v; for f in pkg exception_handler opcode_decoder address_registers data_registers alu bus_interface control icache dcache mmu top; do
     $G -a $O ../src_$v/wf68k30L_$f.vhd 2>/dev/null || echo "GHDL ERROR $v $f"; done
   $G -a $O $S/sim/rtl/tb030.vhd 2>/dev/null && $G -e $O tb030 2>/dev/null)
done
m68k-linux-gnu-as -m68030 --defsym LOFS=${LOFS:-0x10} --defsym NLOOP=${NLOOP:-300} $H/lt_tt.s -o $W/p.o && m68k-linux-gnu-ld -Ttext=0xfc0000 -o $W/p.elf $W/p.o 2>/dev/null && m68k-linux-gnu-objcopy -O binary $W/p.elf $W/p.bin
python3 -c "d=open('$W/p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('$W/p.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
printf '$ version 1.1\n/tb030/clk\n/tb030/dut/i_bus_if/*\n/tb030/dut/i_opcode_decoder/*\n/tb030/dut/i_icache/*\n/tb030/dut/i_exc_handler/*\n' > $W/w.opt
for v in asis tw; do for ws in ${WSL:-0 1}; do
  vc=""; [ -n "$VCD" ] && [ $v = tw ] && [ $ws = 0 ] && vc="--read-wave-opt=$W/w.opt --vcd=$W/tw.vcd"
  (cd $W/w_$v && $G -r $O tb030 -gROMFILE=$W/p.hex -gSTOPDONE=1 -gIPL_MODE=3 -gIRQ_PER=900 -gIRQ_PER6=500 -gWS=$ws -gMAXCLK=${MAXCLK:-150000} $vc 2>/dev/null | grep -v "assertion\|^\.\./" > $W/r_${v}_$ws.log)
  r=$W/r_${v}_$ws.log; p=$(grep -E "WR +A=000033(0[4-9A-F]|1[0-9A-F]|2[0-3]) .*SIZ=0" $r | grep -o "W=[0-9A-F]*" | tr '\n' ' ')
  echo "$v WS=$ws done=$(grep -c DONE $r) $(grep -o 'TIMEOUT' $r) iack=$(grep -c IACK $r) pass(d0,ticks): $p"
done; done
