#!/bin/bash
# usage: hc.sh "cmd1" "cmd2" ... ; sends helper commands, prints output
ARGS=$(printf '%s\n' "$@" | base64 -w0)
ssh -o ProxyCommand='nc -X 5 -x localhost:1055 %h %p' -i ~/.ssh/id_ed25519 dave@100.97.139.11 "python3 -c '
import serial,time,base64,sys
cmds=base64.b64decode(\"$ARGS\").decode().splitlines()
s=serial.Serial(\"/dev/ttyUSB1\",115200,timeout=0.3)
s.reset_input_buffer()
for c in cmds:
    if c.startswith(\"sleep \"): time.sleep(float(c[6:])); continue
    s.write((c+\"\\r\").encode()); time.sleep(0.8)
time.sleep(0.5)
sys.stdout.write(s.read(20000).decode(errors=\"replace\"))
'"
