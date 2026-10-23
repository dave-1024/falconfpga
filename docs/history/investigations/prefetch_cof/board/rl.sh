#!/bin/bash
# rl.sh tag : c + 10 reloads; halt = all 5 grabs (10 s apart) black/non-desk
cd /workspace/gb/pf; T=$1
tty() { printf '%s\n' "$LINSERVER_PASSWORD" | timeout 30 ssh -o "ProxyCommand=nc -X 5 -x localhost:1055 %h %p" dave@100.97.139.11 'ls /dev/ttyUSB1 >/dev/null 2>&1 || { sudo -S -p "" modprobe ftdi_sio; sleep 2; }' >/dev/null 2>&1; }
shot() { for t in 1 2 3 4 5; do ./grab2.sh $1 >/dev/null 2>&1; r=$(python3 cls.py $1.png 2>/dev/null); case "$r" in DESK*) echo "$1 $r try$t"; return;; esac; sleep 10; done; echo "$1 HALT? last=$r"; }
timeout 30 ../hc.sh c >/dev/null 2>&1; sleep 60; shot ${T}c0
for n in $(seq 1 10); do
  timeout 120 ssh -o "ProxyCommand=nc -X 5 -x localhost:1055 %h %p" dave@100.97.139.11 'cd /opt/gowin/Programmer/bin && timeout 90 ./programmer_cli -d GW5AST-138C --location 4193 --run 1 >/dev/null 2>&1; echo -n "reload rc=$? "'; tty
  sleep 50; shot ${T}r$n
done
echo ALLDONE
