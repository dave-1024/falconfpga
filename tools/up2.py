# up2.py <local> <sdname>: same protocol as up.py (put / h <hex> / pend), but polls for the ack
# instead of sp.read(200) blocking to its 2 s timeout on every line (31 B/s -> ~KB/s).
import serial,sys,time,zlib
f=sys.argv[1]; name=sys.argv[2]; d=open(f,'rb').read()
sp=serial.Serial('/dev/ttyUSB1',115200,timeout=0.02)
def cmd(s,exp):
    sp.reset_input_buffer(); sp.write((s+'\r').encode())
    t=time.time(); buf=b''
    while time.time()-t<5:
        buf+=sp.read(max(1,sp.in_waiting))
        if exp.encode() in buf: return buf.decode(errors='replace')
    raise SystemExit('timeout on %r: %r'%(s,buf))
cmd('put '+name,'k 0')
t0=time.time()
for i in range(0,len(d),64):
    ch=d[i:i+64]; cmd('h '+ch.hex(),'k %d\r'%(i+len(ch)) if False else 'k %d'%(i+len(ch)))
    if i%65536==0: print(i,'/',len(d),int(time.time()-t0),'s',flush=True)
r=cmd('pend','crc32'); time.sleep(0.3); r+=sp.read(100).decode(errors='replace')
print(r.strip(), 'local crc32 %08x'%zlib.crc32(d), int(time.time()-t0),'s')
