import re,sys
out=[]
for line in open(sys.argv[1]).read().split('\n'):
    out.append(line)
    m=re.match(r'^reg\s*(\[[^\]]+\])?\s*([A-Za-z_]\w*)\s*(/\*.*\*/)?\s*;',line)
    if m: out.append('initial %s = 0;'%m.group(2))
open(sys.argv[2],'w').write('\n'.join(out))
