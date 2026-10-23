#!/bin/bash
# gembench.sh tag : drive GEMBENCH "All Tests" (ST Medium, STE ref) on the board from a freshly booted
# low-res TOS 2.06 desktop with gbref.st in drive A. Run from /workspace/gb/pf (needs ../hc.sh, go.sh, gg.sh,
# grab2.sh). Results image -> gb_<tag>_result.png (1080p). Takes ~20 min. Learned 16 Oct 2026:
#  - clicks appended after mouse moves in one hc.sh call get lost: move with go.sh, then click separately;
#  - single "click" does not press alert buttons reliably: use "key ret" for the default button;
#  - after a resolution change the capture is black ~20 s (gg.sh retries).
#  - go.sh coords are in the 960x540 preview; XS=30 in low res, 15 (default) in medium.
set -e; T=${1:-run}; H=../hc.sh
timeout 25 $H s | grep -q "link OK" || { echo "serial link not OK"; exit 1; }
timeout 25 $H "key ctrl+r" >/dev/null; sleep 4; timeout 25 $H "key ret" >/dev/null   # low -> medium
sleep 20; ./gg.sh ${T}_med
./go.sh 50 110; timeout 25 $H "click 2" >/dev/null; sleep 8          # open DISK A
./go.sh 80 322; timeout 25 $H "click 2" >/dev/null; sleep 20         # GEMBENCH.PRG (2nd row, 1st icon)
./gg.sh ${T}_start
./go.sh 225 122; timeout 25 $H "click" >/dev/null; sleep 3           # window menu Test
./go.sh 265 181; timeout 25 $H "click" >/dev/null                    # All Tests
echo "started $(date +%T)"; sleep 1080
for i in 1 2 3 4 5 6; do ./gg.sh gb_${T}_result; sleep 60; done     # last grabs; inspect by eye
