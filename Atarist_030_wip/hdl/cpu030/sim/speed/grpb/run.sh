#!/bin/bash
# run.sh seed N ws [extra]  -> SAME/DIFF between snap143 and snapB
s=$1; n=$2; ws=$3; shift 3; T=/tmp/grpb_$s_$ws_$$; mkdir -p $T; cd $T
python3 /workspace/grpb/gen.py $s $n p.s && m68k-linux-gnu-as -m68030 --register-prefix-optional p.s -o p.o && m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null && m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('p.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
O="--std=08 -fsynopsys -frelaxed --workdir=work"
for d in snap143 snapB; do (cd /workspace/$d/w && ghdl -r $O tb030 -gROMFILE=$T/p.hex -gWS=$ws -gSTOPDONE=1 -gMAXCLK=200000 "$@" 2>/dev/null | awk "/ WR +A=00005/{print \$3,\$5,\$6}" > $T/$d.txt); done
if cmp -s $T/snap143.txt $T/snapB.txt; then echo "seed $s ws $ws SAME $(wc -l < $T/snapB.txt)"; rm -rf $T; else echo "seed $s ws $ws DIFF $T"; fi
