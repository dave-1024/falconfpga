#!/bin/bash
# try.sh <tag>: flash, check serial, cold boot, grab. Prints SERIAL_DEAD if one-way state.
T=$1
printf '%s\n' "$LINSERVER_PASSWORD" | ssh linserver "sudo -S -p '' bash ~/flash_fs.sh /home/dave/fpga_bitstreams/st_helper_hdn_$T.fs" 2>&1 | grep -E "LOC=|rc=|ALLDONE|NOFILE|BUSY|LOCS"
sleep 15
/workspace/hcx.sh "?" 2>&1 | grep -q "this help" || { echo SERIAL_DEAD; exit 2; }
/workspace/hcx.sh "c" "sleep 3" "key space" "sleep 25" 2>&1 | tail -n 1
printf '%s\n' "$LINSERVER_PASSWORD" | ssh linserver 'sudo -S -p "" usbreset 345f:2130 >/dev/null; sleep 10'
bash /workspace/lg2.sh /workspace/sd64b/$T.png
