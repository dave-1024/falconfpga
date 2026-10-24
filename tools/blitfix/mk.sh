# mk.sh name.s OUT.PRG [prgflags]
P=/workspace/tools/bin/m68k-linux-gnu-; ${P}as -m68030 -o $1.o $1 && ${P}ld -Ttext 0 -o $1.elf $1.o 2>/dev/null && ${P}objcopy -O binary -j .text -j .data $1.elf $1.bin && python3 - $1 $2 ${3:-0} <<'P'
import struct,sys,subprocess
src,out,fl=sys.argv[1],sys.argv[2],int(sys.argv[3],0)
b=open(src+'.bin','rb').read()
# bss size from symbol table
nm=subprocess.run(['/workspace/tools/bin/m68k-linux-gnu-objdump','-t',src+'.elf'],capture_output=True,text=True).stdout
sy={l.split()[-1]:int(l.split()[0],16) for l in nm.splitlines() if len(l)>8 and all(c in '0123456789abcdef' for c in l[:8]) and len(l.split())>=4}
r=subprocess.run(['/workspace/tools/bin/m68k-linux-gnu-objdump','-r',src+'.o'],capture_output=True,text=True).stdout
assert 'R_68K_32' not in r, 'absolute relocations:\n'+r
bss=sy.get('_end',len(b))-len(b) if '_end' in sy else 0
if len(b)%2:b+=b'\0'
# relocation: none (PC-relative code only)
open(out,'wb').write(struct.pack('>HIIIIIIH',0x601a,len(b),0,max(bss,0),0,0,fl,1)+b)
print(out,len(b),'bss',bss)
P
