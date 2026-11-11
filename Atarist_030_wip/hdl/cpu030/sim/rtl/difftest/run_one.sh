#!/bin/bash
# Assemble one .s, run F156 and F157q, compare architectural WR + dump + exceptions.
set -e
AS=/workspace/tools/m68k-binutils/usr/bin/m68k-linux-gnu-as
LD=/workspace/tools/m68k-binutils/usr/bin/m68k-linux-gnu-ld
OC=/workspace/tools/m68k-binutils/usr/bin/m68k-linux-gnu-objcopy
GHDL=/workspace/tools/ghdl/bin/ghdl
SPEED=/workspace/speed/Atarist_030_wip/hdl/cpu030/sim/speed
SRC=$1
TAG=$2
OUT=${3:-/tmp/difftest}
MAXCLK=${MAXCLK:-120000}
mkdir -p "$OUT"
$AS -m68030 --register-prefix-optional -o "$OUT/$TAG.o" "$SRC"
$LD -Ttext=0xfc0000 -o "$OUT/$TAG.elf" "$OUT/$TAG.o"
$OC -O binary "$OUT/$TAG.elf" "$OUT/$TAG.bin"
python3 -c "
import sys
d=open(sys.argv[1],'rb').read()
open(sys.argv[2],'w').write('\n'.join('%04X'%(d[i]*256+d[i+1]) for i in range(0,len(d)-1,2))+'\n')
" "$OUT/$TAG.bin" "$OUT/$TAG.hex"
run_core() {
  local WD=$1 LOG=$2
  ( cd "$WD" && $GHDL -r --std=08 -fsynopsys -frelaxed --workdir=work tb030       -gROMFILE="$OUT/$TAG.hex" -gCIMODE=1 -gWS=0 -gMAXCLK=$MAXCLK -gSTOPDONE=1 -gQUIET=1       ${GHDL_EXTRA:-} --ieee-asserts=disable-at-0 > "$LOG" 2>&1 )
}
run_core ${REF_W:-/tmp/w_f156} "$OUT/${TAG}_f156.log" &
P1=$!
run_core ${DUT_W:-/tmp/w_f157ot} "$OUT/${TAG}_f157q.log" &
P2=$!
wait $P1 || true
wait $P2 || true
python3 - "$OUT/${TAG}_f156.log" "$OUT/${TAG}_f157q.log" "$OUT/${TAG}.diff" << 'PY'
import os, re, sys
IRQ_ARCH = os.environ.get("IRQ_ARCH", "0") != "0"
IRQ_IGN = {0x2600, 0x2604, 0x2610, 0x3200, 0x3204}
def arch(path):
    wr, dump, exc, done, timeout = [], {}, [], False, False
    for line in open(path, errors="replace"):
        if "TIMEOUT" in line:
            timeout = True
        if re.search(r"\bWR\b", line) and "A=" in line:
            m = re.search(r"A=([0-9A-Fa-f]+).*SIZ=(\d+).*W=([0-9A-Fa-f]+)", line)
            if not m:
                continue
            a, s, w = int(m.group(1), 16), int(m.group(2)), m.group(3).upper()
            fc = re.search(r"FC=(\d+)", line)
            rec = (a & 0xFFFFFFFF, int(fc.group(1)) if fc else -1, s, w)
            wr.append(rec)
            if 0x5000 <= (a & 0xFFFFFF) <= 0x5080:
                dump[a & 0xFFFFFF] = w
            if (a & 0xFFFFFF) == 0x3400:
                done = True
        if line.startswith("EXC "):
            exc.append(line.strip())
    return wr, dump, exc, done, timeout

a, b = sys.argv[1], sys.argv[2]
wr1, d1, e1, done1, t1 = arch(a)
wr2, d2, e2, done2, t2 = arch(b)
if IRQ_ARCH:
    def irq_keep(rec):
        a = rec[0] & 0xFFFFFF
        if a in IRQ_IGN:
            return False
        # Ignore SSP/USP exception frames (IRQs land at different PCs because F157u is faster).
        # Keep scratch data, the dump area, DONE markers, and the vector table.
        return ((0x2000 <= a < 0x2600) or (0x5000 <= a <= 0x5100)
                or a in (0x3300, 0x3400) or (0x0008 <= a < 0x0100))
    wr1 = [r for r in wr1 if irq_keep(r)]
    wr2 = [r for r in wr2 if irq_keep(r)]
out = open(sys.argv[3], "w")
ok = True
def w(msg):
    global ok
    ok = False
    out.write(msg + "\n")
    print(msg)
if (t1 or t2) and not (done1 and done2):
    w(f"TIMEOUT f156={t1} f157q={t2} done f156={done1} f157q={done2}")
if done1 != done2:
    w(f"DONE mismatch f156={done1} f157q={done2}")
if e1 != e2 and not IRQ_ARCH:
    w(f"EXC mismatch\n  f156={e1}\n  f157q={e2}")
if wr1 != wr2:
    n = min(len(wr1), len(wr2))
    first = None
    for i in range(n):
        if wr1[i] != wr2[i]:
            first = i
            break
    if first is None and len(wr1) != len(wr2):
        first = n
    w(f"WR mismatch count f156={len(wr1)} f157q={len(wr2)} first_idx={first}")
    if first is not None:
        lo = max(0, first - 2)
        hi = min(max(len(wr1), len(wr2)), first + 6)
        for i in range(lo, hi):
            x = wr1[i] if i < len(wr1) else None
            y = wr2[i] if i < len(wr2) else None
            mark = " <<<" if x != y else ""
            w(f"  [{i}] f156={x} f157q={y}{mark}")
if d1 != d2:
    keys = sorted(set(d1) | set(d2))
    w("DUMP mismatch:")
    for k in keys:
        if d1.get(k) != d2.get(k):
            w(f"  @{k:04X} f156={d1.get(k)} f157q={d2.get(k)}")
if ok:
    print("MATCH")
    out.write("MATCH\n")
    sys.exit(0)
sys.exit(1)
PY
