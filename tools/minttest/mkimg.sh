#!/bin/bash
# Builds mint_mp.st: 720 KB floppy that boots FreeMiNT 1.19 (68030 kernel, memory protection on)
# from TOS 2.06 and runs MPTEST.PRG as INIT. Needs curl, unzip, mtools.
# Results: A:\STAGE0.TXT (AUTO reached), A:\MPTEST.TXT (test) and A:\MINT\1-19-CUR\BOOT.LOG (kernel boot messages).
set -e; cd "$(dirname "$0")"
Z=freemint-1-19-4a6b3e82-02060.zip
U=https://atari.joska.no/snapshots/freemint/cpu/$Z
SHA=$(cat zip.sha256)
D=${CACHE:-/workspace/mint}; mkdir -p $D
[ -f $D/$Z ] || curl -sL -o $D/$Z $U
echo "$SHA  $D/$Z" | sha256sum -c -
./build.sh
T=$(mktemp -d); unzip -q -o -j $D/$Z mint/1-19-cur/mint030.prg -d $T
printf "MEM_PROT=${MP:-YES}\r\nBOOT_DELAY=0\r\nINI_STEP=NO\r\nDEBUG_LEVEL=1\r\nWRITE_BOOT=${WB:-YES}\r\n" > $T/mint.ini
printf '# MPTEST: no GEM, no XaAES. KERN_MPFLAGS=1 = MPF_STRICT: a Pexec child loses access to its parent'"'"'s memory\r\nKERN_MPFLAGS=1\r\nINIT=A:\\MPTEST.PRG\r\n' > $T/mint.cnf
O=${1:-mint_mp.st}
rm -f $O; mformat -C -f 720 -i $O ::
mmd -i $O ::/AUTO ::/MINT ::/MINT/1-19-CUR
mcopy -i $O STAGE0.PRG ::/AUTO/STAGE0.PRG
[ -n "$PROBE" ] && mcopy -i $O PROBE.PRG ::/AUTO/PROBE.PRG
[ -n "$PROBE2" ] && mcopy -i $O PROBE2.PRG ::/AUTO/PROBE2.PRG
mcopy -i $O $T/mint030.prg ::/AUTO/MINT030.PRG
mcopy -i $O $T/mint.ini ::/MINT/1-19-CUR/MINT.INI; mcopy -i $O $T/mint.cnf ::/MINT/1-19-CUR/MINT.CNF
mcopy -i $O MPTEST.PRG ::/MPTEST.PRG
mdir -i $O -/ ::
rm -rf $T
