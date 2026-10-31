#!/bin/bash
# flash_fs.sh <fs file> : rescan cable, flash core (op53) + reload
F=$1; [ -f "$F" ] || { echo NOFILE; exit 1; }
echo "$F $(sha256sum $F | cut -c1-16)"
pgrep -x programmer_cli && { echo BUSY; exit 1; }
cd /opt/gowin/Programmer/bin
timeout -k 10 60 ./programmer_cli --scan-cables 2>&1 | tee /tmp/ffs_scan_$$.log
L=$(grep -o "A/0/[0-9]*" /tmp/ffs_scan_$$.log | sort -u)
[ $(echo "$L" | grep -c .) -eq 1 ] || { echo LOCS=$L; modprobe ftdi_sio; exit 1; }
LOC=${L##*/}; echo LOC=$LOC
timeout -k 10 400 ./programmer_cli -d GW5AST-138C --location $LOC --run 53 --fsFile $F 2>&1 | tail -n 3
echo "core rc=${PIPESTATUS[0]}"
sleep 5; timeout -k 10 120 ./programmer_cli -d GW5AST-138C --location $LOC --run 1 2>&1 | tail -n 2
modprobe ftdi_sio
echo ALLDONE
