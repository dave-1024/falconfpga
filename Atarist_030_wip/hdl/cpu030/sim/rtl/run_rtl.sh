#!/bin/bash
# RTL bench (GHDL) for the WF68K30L alone: 16-bit port, DSACK1, AVEC on IACK.
# Checks that a level-4 interrupt is never taken with mask 7 (F55, MOVE to SR),
# and that prog_chk.s / prog_branch.s (F62: branches to 4n/4n+2, jumps, traps,
# prefetch bus errors, code written ahead of the PC, user mode) write the
# results in expect_*.txt with 0, 1, 3 and 7 wait states, and that the TOS
# vblank-sync loop (prog_loop.s) is not slower than with the original core.
# [F97] prog_fidx.s: indexed EA whose index Dn was written by the previous instruction (full format,
# brief, memory indirect), expect_fidx.txt.
# [SL1] prog_slmmu.s: MiNT xaaes env loop (jsr strlen; lea (1,a2,d0.l),a2), PMMU on, ATC/cache flush, empty string.
# prog_irqwb.s (not in this loop, slow): same tail under periodic level-4 interrupts, run by hand.
# Usage: run_rtl.sh [scratch dir, default /tmp/sim030rtl]. Needs GHDL >= 4 and m68k binutils.
set -e
H=$(cd "$(dirname "$0")" && pwd); S=${WF_SRC:-$H/../..}; W=${1:-/tmp/sim030rtl}; mkdir -p $W/work; cd $W
G=${GHDL:-ghdl}; O="--std=08 -fsynopsys -frelaxed --workdir=work"
for f in pkg exception_handler opcode_decoder address_registers data_registers alu bus_interface control icache dcache mmu top; do
  $G -a $O $S/wf68k30L_$f.vhd 2>/dev/null; done
echo ffff > prog.hex; $G -a $O $H/tb030.vhd 2>/dev/null && $G -e $O tb030
fail=0
for p in a b; do
  m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_srmask_$p.s -o p.o
  m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
  python3 -c "d=open('p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('prog.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
  for d in $(seq 0 3 ${MAXD:-150}); do
    $G -r $O tb030 -gIPL_MODE=2 -gIRQ_DLY=$d -gMAXCLK=1500 2>/dev/null > r.log || true
    sr=$(awk '/IACK/{f=1} f&&/WR/{n++; if(n==3){print substr($0,index($0,"W=")+2,4); exit}}' r.log)
    grep -q DONE r.log || { echo "FAIL prog $p dly $d: no DONE"; fail=1; }
    [ "$sr" = "2700" ] && { echo "FAIL prog $p dly $d: level 4 taken with SR mask 7"; fail=1; }
  done
done
for p in chk branch cas2 memind shift fidx slmmu; do
  m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_$p.s -o p.o
  m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
  python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_$p.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
  for ws in 0 1 3 7; do
    $G -r $O tb030 -gROMFILE=prog_$p.hex -gWS=$ws -gMAXCLK=$([ $p = shift -o $p = fidx -o $p = slmmu ] && echo 150000 || echo 20000) 2>/dev/null > r.log || true
    r=$(python3 -c "
import re
s=[]
for l in open('r.log'):
    m=re.match(r'\\s*\\d+\\s+WR\\s+A=([0-9A-F]{8}) FC=\\d SIZ=(\\d) W=([0-9A-F]{8})',l)
    if m and 0x5000<=int(m.group(1),16)<0x5100:
        a=int(m.group(1),16); w=m.group(3)
        s.append('%04x:%s'%(a,(w[0:2] if a%2==0 else w[2:4]) if m.group(2)=='1' else w[0:4]))
print(' '.join(s))")
    [ "$r" = "$(cat $H/expect_$p.txt)" ] && grep -q DONE r.log || { echo "FAIL prog_$p WS=$ws"; fail=1; }
  done
done
# F66: reads that bus-error ($FFFA40) must leave Dn/An/MOVEM destinations unchanged
# (prog_berrwb.s, expect_berrwb.txt).
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_berrwb.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_berrwb.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
bwres() { python3 -c "
import re
s=[]
for l in open('r.log'):
    m=re.match(r'\\s*\\d+\\s+WR\\s+A=([0-9A-F]{8}) FC=\\d SIZ=(\\d) W=([0-9A-F]{8})',l)
    if m and 0x5000<=int(m.group(1),16)<0x5100:
        a=int(m.group(1),16); w=m.group(3)
        s.append('%04x:%s'%(a,(w[0:2] if a%2==0 else w[2:4]) if m.group(2)=='1' else w[0:4]))
print(' '.join(s))"; }
for ws in 0 1 3 7; do
  $G -r $O tb030 -gROMFILE=prog_berrwb.hex -gWS=$ws -gMAXCLK=20000 2>/dev/null > r.log || true
  [ "$(bwres)" = "$(cat $H/expect_berrwb.txt)" ] && grep -q DONE r.log || { echo "FAIL prog_berrwb WS=$ws: $(bwres)"; fail=1; }
done
# [FRM] Bus-error frame contents (prog_frame.s, expect_frame.txt): SSW FC/FB/RC/RB/DF and the stage C/B images
# (words at PC+2/PC+4) for prefetch faults on stage C, stage B and the opcode word, data read and write faults,
# and the RTE re-run of each repaired fault; the same with random wait states and the cacheable mode.
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_frame.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_frame.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
for g in "-gWS=0" "-gWS=1" "-gWS=3" "-gWS=7" "-gWS=0 -gCIMODE=1" "-gWS=1 -gWSRND=3 -gIRQ_DLY=7"; do
  $G -r $O tb030 -gROMFILE=prog_frame.hex $g -gMAXCLK=20000 2>/dev/null > r.log || true
  [ "$(bwres)" = "$(cat $H/expect_frame.txt)" ] && grep -q DONE r.log || { echo "FAIL prog_frame $g: $(bwres)"; fail=1; }
done
# F62d: A7 written back by the previous instruction while JSR/BSR/PEA/-(SP) decrements it
# (prog_spwb.s); $600DC0DE at $3300 = every case saw the right SP.
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_spwb.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_spwb.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
for ws in 0 1 3 7; do
  $G -r $O tb030 -gROMFILE=prog_spwb.hex -gWS=$ws -gMAXCLK=60000 2>/dev/null > r.log || true
  grep -q "A=00003300 FC=5 SIZ=0 W=600DC0DE" r.log || { echo "FAIL prog_spwb WS=$ws: $(grep -o 'A=00003300 FC=5 SIZ=0 W=[0-9A-F]*' r.log | head -1)"; fail=1; }
done
# F62: TOS 2.06 vblank-sync loop (prog_loop.s, target at 4n+2) must not be slower than
# the original core (45885 clocks at WS=5), else TOS UK hangs before the palette.
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_loop.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_loop.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
$G -r $O tb030 -gROMFILE=prog_loop.hex -gWS=5 -gMAXCLK=200000 2>/dev/null > r.log || true
lc=$(awk '/DONE/{print $NF}' r.log); echo "prog_loop WS=5: DONE at clk ${lc:-none}"
[ -n "$lc" ] && [ "$lc" -le 45885 ] || { echo "FAIL prog_loop slower than the original core"; fail=1; }
# [IC] Instruction cache unit test (prog_icache.s, CIMODE 1 and 0, expect_icache_ci*.txt).
ic=$(bash $H/run_icache.sh $W || true); echo "$ic" | grep FAIL || true
echo "$ic" | grep -q "^PASS" || { echo "FAIL run_icache"; fail=1; }
# [DC] Data cache unit test (prog_dcache.s, 16 configs, expect_dcache_ci*.txt).
dc=$(bash $H/run_dcache.sh $W || true); echo "$dc" | grep FAIL || true
echo "$dc" | grep -q "^PASS" || { echo "FAIL run_dcache"; fail=1; }
# [PMMU1] Stage 1 PMMU (prog_pmmu.s, expect_pmmu.txt): PMOVE to/from TC, TT0, TT1, MMUSR with the field masks and
# the TC consistency check, PMOVE addressing modes, CpID 0 F-line / privilege violation, and TT0 cache inhibit: with
# CACR ED a second read of $8000 hits, a TT0 CI block makes both reads of $8010 go to the bus, an FC-masked TT0
# that does not match supervisor data lets $8020 hit again (bus reads of $8000/$8010/$8020 must be 1/2/1).
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_pmmu.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_pmmu.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
for g in "-gWS=0" "-gWS=1" "-gWS=3" "-gWS=7" "-gWS=1 -gWSRND=3"; do
  $G -r $O tb030 -gROMFILE=prog_pmmu.hex -gCIMODE=1 $g -gMAXCLK=20000 2>/dev/null > r.log || true
  rd=$(for a in 8000 8010 8020; do grep -c "RD   A=0000$a " r.log; done | tr '\n' ' ')
  [ "$(bwres)" = "$(cat $H/expect_pmmu.txt)" ] && [ "$rd" = "1 2 1 " ] && grep -q DONE r.log || { echo "FAIL prog_pmmu $g: $(bwres) reads $rd"; fail=1; }
done
# [PMMU2] MMU configuration exception (prog_mmucfg.s, expect_mmucfg.txt, MC68030UM 8.1.10): invalid TC (E=1), CRP and
# SRP with DT=0 take vector 56 after the PMOVE: format $2, SR, next PC, $20E0, PMOVE address; the next instruction has not run.
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_mmucfg.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_mmucfg.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
for g in "-gWS=0" "-gWS=1" "-gWS=3" "-gWS=7" "-gWS=1 -gWSRND=3"; do
  $G -r $O tb030 -gROMFILE=prog_mmucfg.hex $g -gMAXCLK=20000 2>/dev/null > r.log || true
  [ "$(bwres)" = "$(cat $H/expect_mmucfg.txt)" ] && grep -q DONE r.log || { echo "FAIL prog_mmucfg $g: $(bwres)"; fail=1; }
done
# [PMMU2b] Address translation (prog_xlate.s, expect_xlate.txt, MC68030UM 9.4/9.5): short two-level tree with early
# termination, remapped page, U/M updates written back, ATC hit after a table change, flush by PMOVE (FD=0) and not by
# PMOVEFD, invalid descriptor and write-protect bus errors with the fault address, 40-page ATC replacement.
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_xlate.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_xlate.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
for g in "-gWS=0" "-gWS=1" "-gWS=3" "-gWS=7" "-gWS=1 -gWSRND=3" "-gWS=0 -gCIMODE=1"; do
  $G -r $O tb030 -gROMFILE=prog_xlate.hex $g -gMAXCLK=100000 2>/dev/null > r.log || true
  [ "$(bwres)" = "$(cat $H/expect_xlate.txt)" ] && grep -q DONE r.log || { echo "FAIL prog_xlate $g: $(bwres)"; fail=1; }
done
# [PMMU2b] PFLUSHA/PFLUSH/PLOAD/PTEST (prog_pmop.s, expect_pmop.txt, MC68030UM 9.8, Table 9-3): PTEST levels 0, 1, 7
# (I, W, M, T, N), PFLUSHA, PFLUSH by FC and by FC+EA, PLOADR/PLOADW, no history-bit change by PTEST.
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_pmop.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_pmop.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
for g in "-gWS=0" "-gWS=1" "-gWS=3" "-gWS=7" "-gWS=1 -gWSRND=3" "-gWS=0 -gCIMODE=1"; do
  $G -r $O tb030 -gROMFILE=prog_pmop.hex $g -gMAXCLK=100000 2>/dev/null > r.log || true
  [ "$(bwres)" = "$(cat $H/expect_pmop.txt)" ] && grep -q DONE r.log || { echo "FAIL prog_pmop $g: $(bwres)"; fail=1; }
done
# [PMMU2c] Long tables, limit, indirect, S page with SRE (prog_xlate2.s, expect_xlate2.txt, ST=1): MC68030UM 9.5.1-9.5.5.
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_xlate2.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_xlate2.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
for g in "-gWS=0" "-gWS=1" "-gWS=3" "-gWS=7" "-gWS=1 -gWSRND=3"; do
  $G -r $O tb030 -gROMFILE=prog_xlate2.hex -gST=1 $g -gMAXCLK=150000 2>/dev/null > r.log || true
  [ "$(bwres)" = "$(cat $H/expect_xlate2.txt)" ] && grep -q DONE r.log || { echo "FAIL prog_xlate2 $g: $(bwres)"; fail=1; }
done
# [PMMU3] Short indirect descriptors (prog_xlate3.s, expect_xlate3.txt): MC68030UM 9.5.1.4.
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_xlate3.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_xlate3.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
for g in "-gWS=0" "-gWS=1" "-gWS=3" "-gWS=7" "-gWS=1 -gWSRND=3"; do
  $G -r $O tb030 -gROMFILE=prog_xlate3.hex $g -gMAXCLK=150000 2>/dev/null > r.log || true
  [ "$(bwres)" = "$(cat $H/expect_xlate3.txt)" ] && grep -q DONE r.log || { echo "FAIL prog_xlate3 $g: $(bwres)"; fail=1; }
done
# [PMMU3] RTE reruns a faulted write (prog_df.s, expect_df.txt): MC68030UM 8.1.2, 8.2.1.
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_df.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_df.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
for g in "-gWS=0" "-gWS=1" "-gWS=3" "-gWS=7" "-gWS=1 -gWSRND=3"; do
  $G -r $O tb030 -gROMFILE=prog_df.hex $g -gMAXCLK=150000 2>/dev/null > r.log || true
  [ "$(bwres)" = "$(cat $H/expect_df.txt)" ] && grep -q DONE r.log || { echo "FAIL prog_df $g: $(bwres)"; fail=1; }
done
# [PMMU3] PRM ch. 6 forms that must take the F-line (prog_prm.s, expect_prm.txt): PMOVE (An)+ / -(An), PTEST #0,An,
# PFLUSH mode 010 (M68000PRM pp. 6-34, 6-48, 6-66); A0 and TC unchanged.
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_prm.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_prm.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
for g in "-gWS=0" "-gWS=1" "-gWS=3" "-gWS=1 -gWSRND=3" "-gWS=0 -gCIMODE=1"; do
  $G -r $O tb030 -gROMFILE=prog_prm.hex $g -gMAXCLK=100000 2>/dev/null > r.log || true
  [ "$(bwres)" = "$(cat $H/expect_prm.txt)" ] && grep -q DONE r.log || { echo "FAIL prog_prm $g: $(bwres)"; fail=1; }
done
# [PMMU3] 11.7.2 MMU instruction clocks (prog_mmut.s, expect_mmut.txt): loops of 8 from the I-cache, clocks per
# block / 8 between marker writes; PFLUSH 16, PFLUSH SFC 20, PTEST #0 22 (+ EA 4), PLOAD 8 + EA 4 + 11.7 search.
m68k-linux-gnu-as -m68030 --register-prefix-optional $H/prog_mmut.s -o p.o
m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null; m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\\xff'*(len(d)%2); open('prog_mmut.hex','w').write('\\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\\n')"
$G -r $O tb030 -gROMFILE=prog_mmut.hex -gWS=0 -gCIMODE=1 -gSTOPDONE=1 -gMAXCLK=100000 2>/dev/null > r.log || true
mt=$(grep "WR   A=00003400 " r.log | awk '{print $1}' | awk 'NR>1{printf "blk%d %.2f ", NR-1, ($1-p)/8} {p=$1}' | sed 's/ $//')
[ "$mt" = "$(cat $H/expect_mmut.txt)" ] || { echo "FAIL prog_mmut: $mt"; fail=1; }
[ $fail = 0 ] && echo "PASS: no interrupt taken above the SR mask, all runs finished, chk/branch results match, SP writeback/push ok, BERR no-writeback ok, loop timing ok, instruction cache ok, data cache ok, PMMU stage 1 ok, MMU configuration exception ok, PMMU translation ok, PFLUSH/PLOAD/PTEST ok, long/limit/indirect/S ok, short indirect ok, write rerun ok, MMU instruction clocks ok, PRM F-line forms ok"
