#!/bin/bash
tag=$1; export DISPLAY=:5
F=/tmp/hf_$tag; rm -f $F; rm -rf sh_$tag; mkdir -p sh_$tag; cp gbtest.st h_$tag.st
SDL_AUDIODRIVER=dummy hatari --confirm-quit no --sound off --tos /tmp/hat/emutos-256k-1.4/etos256uk.img --machine ste --cpulevel 3 --cpuclock 16 --memsize 4 --fpu none --mmu off --compatible yes --monitor rgb --tos-res med --borders off --statusbar off --zoom 1 --disk-a h_$tag.st --auto 'A:\TESTCR.PRG' --screenshot-dir sh_$tag --cmd-fifo $F > log_$tag.txt 2>&1 &
echo $! > /tmp/h_$tag.pid
sleep 25; echo "hatari-shortcut screenshot" > $F; sleep 1
echo "hatari-debug savebin /workspace/gb/snap/dump_$tag.bin \$3e0000 \$b000" > $F; sleep 1
echo "hatari-debug loadbin /workspace/gb/snap/ld_only.bin \$3e1000" > $F; sleep 1
echo "hatari-debug loadbin /workspace/gb/snap/ld_regs.bin \$3e0030" > $F; sleep 1
echo "hatari-shortcut warmreset" > $F
sleep 30; echo "hatari-shortcut screenshot" > $F; sleep 2
kill $(cat /tmp/h_$tag.pid); sleep 1
mcopy -n -o -i h_$tag.st ::SNAP_HD.BIN ::SNAP_LD.BIN ::SNAP_CR.BIN out_$tag/ 2>&1 || (mkdir -p out_$tag; mcopy -n -o -i h_$tag.st ::SNAP_HD.BIN ::SNAP_LD.BIN ::SNAP_CR.BIN out_$tag/)
ls -l sh_$tag out_$tag
