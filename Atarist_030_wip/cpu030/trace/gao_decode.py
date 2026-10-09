#!/usr/bin/env python3
"""Decode wf030_trace_view HDMI dumps (frames or captures) into trace entries.
usage: gao_decode.py OUT_PREFIX img1 [img2 ...]
Writes OUT_PREFIX.txt (listing, oldest first) and OUT_PREFIX.json (raw)."""
import sys, json
from PIL import Image

def rows_of(fn):
    im = Image.open(fn).convert('L'); W, H = im.size; px = im.load()
    sx, sy = W / 640.0, H / 480.0
    def cellbits(row, half):
        x0 = 8 if half == 0 else 328
        y = int((row * 4 + 2) * sy)
        bits = []
        for c in range(146):
            x = int((x0 + c * 2 + 1) * sx)
            v = (px[x, y] + px[x, min(H - 1, y + 1)]) / 2
            bits.append(1 if v > 128 else 0)
        return bits
    out = {}
    for row in range(118):
        for half in (0, 1):
            b = cellbits(row, half)
            ok = b[0] == 1 and b[145] == 1
            val = 0
            for k in range(1, 145): val = (val << 1) | b[k]
            out[(row, half)] = (ok, val)
    return out

def fields(e):
    g = lambda hi, lo: (e >> lo) & ((1 << (hi - lo + 1)) - 1)
    return dict(ts=g(143, 132), fl=g(131, 125), a=g(124, 101), fc=g(100, 98), rwn=g(97, 97), siz=g(96, 95),
                dsk=g(94, 94), ber=g(93, 93), d=g(92, 77), op=g(76, 61), pcl=g(60, 38) << 1, qcnt=g(37, 35),
                opcrd=g(34, 34), ordy=g(33, 33), qdis=g(32, 32), flush=g(31, 31), qhit=g(30, 30), qmiss=g(29, 29),
                qdum=g(28, 28), bexh=g(27, 27), ipl=g(26, 24), pc=g(23, 0))

def fmt(e):
    f = fields(e)
    fl = f['fl']; tags = ''.join(ch if fl >> (6 - i) & 1 else '.' for i, ch in enumerate('BOFXDTI'))
    s = '%03x %s ' % (f['ts'], tags)
    if fl & 0x40:
        kind = 'IACK' if f['fc'] == 7 else ('RD' if f['rwn'] else 'WR')
        s += '%-4s %06x fc%d s%d %s%s d=%04x  ' % (kind, f['a'], f['fc'], f['siz'], 'K' if f['dsk'] else '-', 'E' if f['ber'] else '-', f['d'])
    else:
        s += ' ' * 33
    s += 'op=%04x pcl=%06x pc=%06x q%d %s%s%s%s%s%s%s%s ipl=%d' % (
        f['op'], f['pcl'], f['pc'], f['qcnt'], 'r' if f['opcrd'] else '.', 'Y' if f['ordy'] else '.',
        'S' if f['qdis'] else '.', 'F' if f['flush'] else '.', 'H' if f['qhit'] else '.', 'M' if f['qmiss'] else '.',
        'U' if f['qdum'] else '.', 'X' if f['bexh'] else '.', 7 - f['ipl'])
    return s

def main():
    pre, imgs = sys.argv[1], sys.argv[2:]
    pages = {}; status = None; watch = {}; bad = 0
    for fn in imgs:
        r = rows_of(fn)
        okc, cal = r[(0, 0)]
        if not okc or cal != int('01' * 72, 2):
            continue                       # not a dump frame (or torn)
        okl, stl = r[(1, 0)]; okr, strr = r[(1, 1)]
        if not (okl and okr) or ((stl >> 54) & 0xffff) != 0xC0DE:
            continue
        page = (stl >> 48) & 0x3f
        st = stl & ((1 << 48) - 1)
        if (strr & ((1 << 48) - 1)) != st or ((strr >> 48) & 0xffff) != 0x5A5A or ((strr >> 64) & 0x3f) != page:
            bad += 1; continue
        status = st
        for row in range(2, 10):
            for h in (0, 1):
                ok, v = r[(row, h)]
                if ok: watch[(row - 2) * 2 + h] = v
        ent = {}
        for row in range(10, 118):
            for h in (0, 1):
                ok, v = r[(row, h)]
                idx = page * 216 + (row - 10) * 2 + h
                if ok and idx < 4096: ent[idx] = v
        pages.setdefault(page, []).append(ent)
    if status is None:
        print('no dump frames found'); return 1
    trig = status >> 47 & 1; armed = status >> 46 & 1; stopped = status >> 45 & 1; wrapped = status >> 44 & 1
    src = status >> 38 & 0x3f; tslot = status >> 24 & 0xfff; ptr = status >> 12 & 0xfff; wcnt = status >> 7 & 0x1f; wptr = status >> 3 & 0xf
    ring = {}
    disagree = 0
    for p, lst in pages.items():
        for idx in set().union(*[set(e) for e in lst]):
            vals = [e[idx] for e in lst if idx in e]
            best = max(set(vals), key=vals.count)
            if len(set(vals)) > 1: disagree += 1
            ring[idx] = best
    order = list(range(ptr, 4096)) + list(range(0, ptr)) if wrapped else list(range(0, ptr))
    srcn = ','.join(n for i, n in enumerate(['HALT', 'AESLOOP', 'BERR', 'BADPF', 'VBLTMO', 'HELPKEY']) if src >> i & 1)
    hdr = ('status trig=%d armed=%d stopped=%d wrapped=%d src=%s trigslot=%03x next=%03x watch=%d/%x pages=%s missing=%d disagree=%d badframes=%d'
           % (trig, armed, stopped, wrapped, srcn, tslot, ptr, wcnt, wptr, sorted(pages), sum(1 for i in order if i not in ring), disagree, bad))
    lines = [hdr, '-- watch (writes to $88/$404/$6ABC-$6AC3), oldest first --']
    wo = [(wptr + k) % 16 for k in range(16)] if wcnt >= 16 else list(range(wcnt))
    for k in wo:
        if k in watch: lines.append('W%x %s' % (k, fmt(watch[k])))
    lines.append('-- ring, oldest first (rel = position relative to the trigger entry) --')
    tpos = order.index(tslot) if tslot in order else 0
    for n, idx in enumerate(order):
        if idx in ring: lines.append('%+5d %03x %s' % (n - tpos, idx, fmt(ring[idx])))
        else: lines.append('%+5d %03x ??' % (n - tpos, idx))
    open(pre + '.txt', 'w').write('\n'.join(lines) + '\n')
    json.dump({'status': status, 'ring': {str(k): '%036x' % v for k, v in ring.items()},
               'watch': {str(k): '%036x' % v for k, v in watch.items()}}, open(pre + '.json', 'w'))
    print(hdr); return 0

if __name__ == '__main__':
    sys.exit(main())
