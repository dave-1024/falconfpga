#!/bin/bash
# [F157p] IRQ arriving during INIT_EXEC_WB of an early-issuable ADD/MOVEQ stream.
# The core asserts that EX_P_INT is never taken while IRQ_HOT=0 (the EARLY_OW hold).
# Sweeps IRQ_DLY (IPL_MODE=2). F157m+Phase B fails at DLY 3/14/17/24/27; F157p must pass all.
# Usage: run_irq_window.sh [core src dir] [scratch dir]
set -e
H=$(cd "$(dirname "$0")" && pwd)
S=$(cd ${1:-$H/../../..} && pwd)
W=${2:-/tmp/irqwin}
G=${GHDL:-ghdl}
O="--std=08 -fsynopsys -frelaxed --workdir=work"
mkdir -p "$W/work"
rm -rf "$W/src" "$W/w"; mkdir -p "$W/src" "$W/w/work"
cp "$S"/wf68k30L_*.vhd "$W/src/"
( cd "$W/w"
  echo ffff > prog.hex
  for f in pkg exception_handler opcode_decoder address_registers data_registers alu bus_interface control icache dcache mmu top; do
    $G -a $O ../src/wf68k30L_$f.vhd || { echo "GHDL ERROR $f"; exit 1; }
  done
  $G -a $O "$S/sim/rtl/tb030.vhd" || { echo "GHDL ERROR tb030"; exit 1; }
  $G -e $O tb030 || { echo "GHDL ERROR elab"; exit 1; }
)
m68k-linux-gnu-as -m68030 --register-prefix-optional "$H/irqwin.s" -o "$W/p.o"
m68k-linux-gnu-ld -Ttext=0xfc0000 -o "$W/p.elf" "$W/p.o" 2>/dev/null
m68k-linux-gnu-objcopy -O binary "$W/p.elf" "$W/p.bin"
python3 -c "d=open('$W/p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('$W/p.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
fail=0
hits=0
for dly in $(seq 0 ${MAXDLY:-31}); do
  log="$W/r_$dly.log"
  # keep ghdl stderr so assertion failures are visible
  ( cd "$W/w" && $G -r $O tb030 -gROMFILE=$W/p.hex -gSTOPDONE=1 -gIPL_MODE=2 -gIRQ_DLY=$dly \
      -gWS=0 -gCIMODE=1 -gMAXCLK=${MAXCLK:-20000} ) > "$log" 2>&1 || true
  if grep -q "interrupt take while IRQ_HOT=0" "$log"; then
    echo "FAIL dly=$dly: early OW_REQ in take cycle"
    fail=1
  elif grep -q TIMEOUT "$log"; then
    echo "FAIL dly=$dly: TIMEOUT"
    fail=1
  elif ! grep -q DONE "$log"; then
    echo "FAIL dly=$dly: no DONE"
    fail=1
  else
    iack=$(grep -c IACK "$log" || true)
    echo "PASS dly=$dly iack=$iack"
    hits=$((hits+iack))
  fi
done
echo "irq_window fail=$fail iacks=$hits"
exit $fail
