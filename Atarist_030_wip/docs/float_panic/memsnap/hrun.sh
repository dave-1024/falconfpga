#!/bin/bash
# hrun.sh tag cpulevel : Hatari STE, AUTO MEMSNAP, GEMBENCH Float Math, dump $3E0000+$B000
tag=$1; cpu=${2:-3}; export DISPLAY=:5
F=/tmp/hf_$tag; rm -f $F; rm -rf sh_$tag; mkdir -p sh_$tag; cp gbsnap.st h_$tag.st
SDL_AUDIODRIVER=dummy hatari --confirm-quit no --sound off --tos /tmp/hat/emutos-256k-1.4/etos256uk.img --machine ste --cpulevel $cpu --cpuclock 16 --memsize 4 --fpu none --mmu off --compatible yes --monitor rgb --tos-res med --borders off --statusbar off --zoom 1 --disk-a h_$tag.st --auto 'A:\GEMBENCH.PRG' --screenshot-dir sh_$tag --cmd-fifo $F > log_$tag.txt 2>&1 &
echo $! > /tmp/h_$tag.pid
sleep 12; echo "hatari-shortcut screenshot" > $F
sleep 20; echo "hatari-shortcut screenshot" > $F; sleep 1
W=$(xdotool search --pid $(cat /tmp/h_$tag.pid) | tail -1)
xdotool mousemove --window $W 152 68 sleep 0.3 mousedown 1 sleep 0.15 mouseup 1 sleep 1.5
xdotool mousemove --window $W 155 95 sleep 0.3 mousemove --window $W 160 103 sleep 0.5 mousedown 1 sleep 0.15 mouseup 1
sleep 40; echo "hatari-shortcut screenshot" > $F; sleep 1
echo "hatari-debug savebin /workspace/gb/snap/dump_$tag.bin \$3e0000 \$b000" > $F; sleep 2
ls -l sh_$tag dump_$tag.bin
