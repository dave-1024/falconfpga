#!/bin/bash
# try2.sh <tag>: flash, check serial, grab WITHOUT cold boot
T=$1
printf '%s\n' "$LINSERVER_PASSWORD" | ssh linserver "sudo -S -p '' bash ~/flash_fs.sh /home/dave/fpga_bitstreams/st_helper_hdn_$T.fs" 2>&1 | grep -E "LOC=|rc=|ALLDONE|NOFILE|BUSY|LOCS"
sleep 30
/workspace/hcx.sh "?" 2>&1 | grep -q "this help" && echo SERIAL_OK || echo SERIAL_DEAD
printf '%s\n' "$LINSERVER_PASSWORD" | ssh linserver 'sudo -S -p "" usbreset 345f:2130 >/dev/null; sleep 10'
bash /workspace/lg2.sh /workspace/sd64b/${T}_noc.png
