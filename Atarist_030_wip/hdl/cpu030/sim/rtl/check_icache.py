#!/usr/bin/env python3
# [IC] prog_icache.s checker: program-space bus cycles inside loop A's / loop B's 16-byte line,
# (cases 6/23-25: loop B, 16/18: loop C, 17: loop D), per case (case = last value written to $3600), and the result writes at $5000.
# Usage: check_icache.py <bench log> <lpa hex> <lpb hex>  -> one line: "c1:n c2:n ... | results"
import re, sys
log, lpa, lpb = sys.argv[1], int(sys.argv[2], 16), int(sys.argv[3], 16)
lpc, lpd = lpa + 0x40, lpa + 0x80   # prog_icache.s: lines 4 and 8 of the $FD0000 block
case, cnt, res = 0, {}, []
for l in open(log):
    m = re.match(r'\s*\d+\s+(\S+)\s+A=([0-9A-F]{8}) FC=\d SIZ=\d (?:W|D)=([0-9A-F]+)', l)
    if not m: continue
    k, a, d = m.group(1), int(m.group(2), 16) & 0xFFFFFF, m.group(3)
    if k == 'WR' and a == 0x3600: case = int(d[0:4], 16); cnt.setdefault(case, 0); continue
    if k == 'WR' and 0x5000 <= a < 0x5100: res.append('%04x:%s' % (a, d[0:4])); continue
    if k == 'PROG' and case:
        base = lpb if case in (6, 23, 24, 25) else lpc if case in (16, 18) else lpd if case == 17 else lpa
        if base <= a < base + 16: cnt[case] += 1
print(' '.join('c%d:%d' % (c, cnt[c]) for c in sorted(cnt)) + ' | ' + ' '.join(res))
