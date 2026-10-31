# fidx.sh <srcdir cpu030> <scratch>
S=$1; W=$2; PATH=/workspace/tools/ghdl/bin:/workspace/tools/bin:$PATH; rm -rf $W; mkdir -p $W/work; cd $W; O="--std=08 -fsynopsys -frelaxed --workdir=work"
for f in pkg exception_handler opcode_decoder address_registers data_registers alu bus_interface control icache dcache mmu top; do ghdl -a $O $S/wf68k30L_$f.vhd 2>&1 | grep -i "error" ; done
echo ffff > prog.hex; ghdl -a $O $S/sim/rtl/tb030.vhd 2>&1 | grep -i error; ghdl -e $O tb030 || exit 1
R=$S/sim/rtl
m68k-linux-gnu-as -m68030 --register-prefix-optional $R/prog_dw2.s -o p.o && m68k-linux-gnu-ld -Ttext=0xfc0000 -o p.elf p.o 2>/dev/null && m68k-linux-gnu-objcopy -O binary p.elf p.bin
python3 -c "d=open('p.bin','rb').read(); d+=b'\xff'*(len(d)%2); open('pf.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
for ci in 0 1; do for fh in 1 0; do for ws in 0 1 3 7; do
ghdl -r $O tb030 -gROMFILE=pf.hex -gWS=$ws -gCIMODE=$ci -gFASTH=$fh -gMAXCLK=150000 2>/dev/null > r.log || true
r=$(python3 -c "
import re
s=[]
for l in open('r.log'):
    m=re.match(r'\s*\d+\s+WR\s+A=([0-9A-F]{8}) FC=\d SIZ=(\d) W=([0-9A-F]{8})',l)
    if m and 0x5000<=int(m.group(1),16)<0x5100:
        a=int(m.group(1),16); w=m.group(3)
        s.append('%04x:%s'%(a,(w[0:2] if a%2==0 else w[2:4]) if m.group(2)=='1' else w[0:4]))
print(' '.join(s))")
if [ "$r" = "$(cat $R/expect_dw2.txt)" ]; then echo "ok CI=$ci FH=$fh WS=$ws"; else echo "FAIL CI=$ci FH=$fh WS=$ws: $(echo $r | cut -c1-400)"; fi
done; done; done
