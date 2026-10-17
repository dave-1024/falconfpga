#!/usr/bin/env python3
# [DC] prog_dcache.s checker: data read / write bus cycles at $8000-$FFFF and $20000-$2FFFF per case
# (case = last word written to $36C0), and the result writes at $5080-$50FF.
# Usage: check_dcache.py <bench log>  -> one line: "c1:r/w c2:r/w ... | results"
import re, sys
case, cnt, res = 0, {}, []
for l in open(sys.argv[1]):
    m = re.match(r'\s*\d+\s+(\S+)\s+A=([0-9A-F]{8}) FC=\d SIZ=\d (?:W|D)=([0-9A-F]+)', l)
    if not m: continue
    k, a, d = m.group(1), int(m.group(2), 16) & 0xFFFFFF, m.group(3)
    if k == 'WR' and a == 0x36C0: case = int(d[0:4], 16); cnt.setdefault(case, [0, 0]); continue
    if k == 'WR' and 0x5080 <= a < 0x5100: res.append('%04x:%s' % (a, d[0:4])); continue
    if case and (0x8000 <= a < 0x10000 or 0x20000 <= a < 0x30000):
        if k == 'RD': cnt[case][0] += 1
        elif k == 'WR': cnt[case][1] += 1
print(' '.join('c%d:%d/%d' % (c, cnt[c][0], cnt[c][1]) for c in sorted(cnt)) + ' | ' + ' '.join(res))
