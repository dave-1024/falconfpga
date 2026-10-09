import json,sys
sys.path.insert(0,'/workspace/st_helper_out/fetchfix'); from gao_decode import fields
rom=open('/tmp/tos.bin','rb').read()
def romw(a): return int.from_bytes(rom[a-0xE00000:a-0xE00000+2],'big')
d=json.load(open(sys.argv[1]))
ent=[(int(k),fields(int(v,16))) for k,v in d['ring'].items()]
# order oldest first via the txt order
order=[int(l.split()[1],16) for l in open(sys.argv[1].replace('.json','.txt')) if l[:1] in ' -+' and len(l.split())>2 and l.split()[0].lstrip('+-').isdigit()]
m={k:f for k,f in ent}
ok=bad=0
for i,k in enumerate(order):
    f=m[k]
    if f['fl']&0x20 and not f['qdis'] and 0xE00000<=f['pcl']<0xE40000:
        if romw(f['pcl'])==f['op']: ok+=1
        else:
            bad+=1
            if bad<=12: print('mismatch idx',i,'slot %03x'%k,'pcl %06x op %04x rom %04x'%(f['pcl'],f['op'],romw(f['pcl'])), 'flags qhit',f['qhit'],'qcnt',f['qcnt'])
print('ok',ok,'bad',bad)
