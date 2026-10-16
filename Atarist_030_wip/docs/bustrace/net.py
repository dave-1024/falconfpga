#!/usr/bin/env python3
# net.py: per-test counters minus the idle baseline scaled to the non-test time
import json,subprocess,sys
def L(n):
    subprocess.run(['python3','parse.py',n+'.txt'],capture_output=True); return json.load(open(n+'.txt.json'))
idle=L('idle20'); it=idle[0]/32e6
tests=[('vdigfx','VDI Graphics',26.105,72),('dialog','GEM Dialog',9.995,79),('gemwin','GEM Window',4.070,80),
       ('blit','Blitting (no blitter)',9.635,91),('vditext','VDI Text',14.175,99),('romacc','ROM Access',5.485,115)]
print(f"{'test':22s} {'s':>7} {'ratio':>5} {'STcyc/s':>9} {'busy%':>6} {'noreq%':>6} {'ROM%':>5} {'pf%':>5} {'RAMr%':>5} {'RAMw%':>5} {'IO%':>4} {'ws/cyc':>6} {'wait/c':>6} {'S6->S0%':>7} {'long%':>5} {'STE-equiv cyc':>13}")
for n,name,t,r in tests:
    c=L(n); dt=c[0]/32e6-t; k=dt/it
    d=[x-y*k for x,y in zip(c,idle)]
    cyc=d[7]; ws=d[8]
    busy=(cyc*4+ws)*4/(t*32e6)   # ST cycle = 4 en1 periods (16 clk32) + waits (4 clk32 each)
    rom=sum(d[24+i] for i in range(8,16)); ram_r=sum(d[24+i] for i in range(0,4)); ram_w=sum(d[24+i] for i in range(4,8))
    io=sum(d[24+i] for i in range(16,32)); lng=sum(d[24+i] for i in range(32) if (i&3)==0)
    # STE 68000 doing the same work in t*r/100 s can do at most that/500ns bus cycles
    ste=t*r/100/500e-9
    print(f"{name:22s} {t:7.3f} {r:5d} {cyc/t:9.0f} {100*busy:6.1f} {100*d[2]/(t*32e6):6.1f} {100*rom/cyc:5.1f} {100*d[22]/cyc:5.1f} {100*ram_r/cyc:5.1f} {100*ram_w/cyc:5.1f} {100*io/cyc:4.1f} {ws/cyc:6.3f} {sum(d[56:88])/cyc:6.2f} {100*d[14]/cyc:7.1f} {100*lng/cyc:5.1f} {cyc/ste:13.2f}")
    json.dump({'name':name,'t':t,'ratio':r,'net':d},open(n+'.net.json','w'))
