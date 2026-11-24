#!/usr/bin/env python3
"""STE/Falcon blitter reference (Hatari blitter.c behaviour, word level) + tb generator/checker.
Usage: blit_model.py gen | check"""
import sys, random
random.seed(1234)
MEM = 65536
def sx(v):  # 16-bit signed, even
    v &= 0xFFFF; return v - 0x10000 if v & 0x8000 else v
OPS = [lambda s,d:0, lambda s,d:s&d, lambda s,d:s&~d, lambda s,d:s, lambda s,d:~s&d, lambda s,d:d,
       lambda s,d:s^d, lambda s,d:s|d, lambda s,d:~s&~d, lambda s,d:~s^d, lambda s,d:~d, lambda s,d:s|~d,
       lambda s,d:~s, lambda s,d:~s|d, lambda s,d:~s|~d, lambda s,d:0xFFFF]
class Blt:
    def __init__(s): s.buf = 0
    def run(s, mem, t):
        src, dst = t['src'], t['dst']; sxi, syi, dxi, dyi = map(sx, (t['sxi'], t['syi'], t['dxi'], t['dyi']))
        hop, op, skew, fxsr, nfsr, smudge = t['hop'], t['op'], t['skew'], t['fxsr'], t['nfsr'], t['smudge']
        line = t['line']; ht = t['ht']; m1, m2, m3 = t['m1'], t['m2'], t['m3']
        xs = t['xc']; back = sxi < 0
        s.last = getattr(s, 'last', 0)
        def rd(a):
            s.last = mem[(a >> 1) & 0xFFFF]; return s.last
        def shin(w):
            if not back: s.buf = ((s.buf << 16) | w) & 0xFFFFFFFF
            else: s.buf = ((w << 16) | (s.buf >> 16)) & 0xFFFFFFFF
        # source rules from the board-proven BLTTEST.S STE model (Atarist_030_wip/tests/blitter):
        # FXSR: extra fetch on the first word (+sxi). NFSR: set when x goes 2 -> 1; the fetch at x=2 (stBlitter: x=1 shifts in the last bus word, dest read included)
        # then adds syi, and x=1 neither fetches nor shifts. Ops 0,5,A,F and HOP 0/1 (no smudge) read no source.
        opsrc = op not in (0, 5, 10, 15)
        hopsrc = (hop & 2) or smudge
        for y in range(t['yc']):
            nf = False
            for x in range(xs, 0, -1):
                first, last = x == xs, x == 1
                fetched = False
                if opsrc and hopsrc:
                    if first and fxsr:
                        shin(rd(src)); src += sxi
                    if not nf:
                        shin(rd(src)); fetched = True
                    else:
                        shin(s.last)   # NFSR: no read, latch shifts in the last bus word
                sw = (s.buf >> skew) & 0xFFFF
                idx = (sw & 15) if smudge else line
                h = ht[idx]
                hw = [0xFFFF, h, sw, sw & h][hop]
                mask = m1 if first else (m3 if last else m2)
                d = rd(dst)
                r = (d & ~mask | OPS[op](hw, d) & mask) & 0xFFFF
                mem[(dst >> 1) & 0xFFFF] = r
                if x == 2 and nfsr: nf = True
                if fetched:
                    src += syi if (last or nf) else sxi
                dst += dyi if last else dxi
            line = (line + (-1 if dyi < 0 else 1)) & 15
        return src, dst
def tests():
    T = []
    def mk(**k):
        t = dict(src=0x2000, dst=0x10000, sxi=2, syi=2, dxi=2, dyi=160, xc=8, yc=6, hop=2, op=3, skew=0,
                 fxsr=0, nfsr=0, smudge=0, line=0, ht=[random.randrange(65536) for _ in range(16)],
                 m1=0xFFFF, m2=0xFFFF, m3=0xFFFF, hog=1)
        k.setdefault('dst', 0x10000 + 0x800 * len(T)); t.update(k); T.append(t)
    mk(hop=0, op=15, xc=20, yc=10, dxi=2, dyi=160 - 38, m1=0x0FFF, m3=0xFFF0)                      # fill ones
    mk(hop=1, op=3, xc=20, yc=10, dxi=2, dyi=160 - 38, m1=0x00FF, m3=0xFF00, line=3)               # halftone desktop fill
    mk(hop=0, op=0, xc=12, yc=5, dxi=8, dyi=160 - 88, hog=0)                                         # clear, plane stride, shared
    mk(hop=2, op=3, xc=7, yc=9, sxi=2, syi=160 - 12, dxi=2, dyi=160 - 12, skew=5, fxsr=1, m1=0x07FF, m3=0xF800)
    mk(hop=2, op=7, xc=6, yc=8, sxi=2, syi=160 - 10, dxi=2, dyi=160 - 10, skew=11, nfsr=1, fxsr=1, m1=0x001F, m3=0xFFE0)
    mk(hop=2, op=1, xc=5, yc=7, sxi=2, syi=160 - 8, dxi=2, dyi=160 - 8, skew=3, fxsr=1, nfsr=1, m1=0x1FFF, m2=0xF0F0, m3=0xE000, hog=0)
    mk(hop=2, op=3, xc=6, yc=6, src=0x2000 + 160 * 6, sxi=0xFFFE, syi=(-(160 - 10)) & 0xFFFF, dxi=0xFFFE, dyi=(-(160 - 10)) & 0xFFFF, skew=4, fxsr=1)
    mk(hop=3, op=6, xc=9, yc=5, sxi=2, syi=160 - 16, dxi=2, dyi=160 - 16, skew=0, line=7)
    mk(hop=2, op=4, xc=1, yc=16, sxi=2, syi=256, dxi=2, dyi=160, skew=7, fxsr=1, m1=0x01FE)        # glyph column
    mk(hop=2, op=7, xc=2, yc=16, sxi=2, syi=254, dxi=8, dyi=152, skew=9, fxsr=1, m1=0x007F, m3=0xFF80, hog=0)  # 2-word text
    mk(hop=2, op=12, xc=4, yc=4, sxi=2, syi=160 - 6, dxi=2, dyi=160 - 6, skew=0, fxsr=0, nfsr=0, hog=0)  # inverse copy
    return T
def gen():
    mem = [random.randrange(65536) for _ in range(MEM)]
    open('mem_init.hex', 'w').write('\n'.join('%04x' % w for w in mem) + '\n')
    b = Blt(); L = []
    for n, t in enumerate(tests()):
        regs = [(0x00, t['ht'][i]) for i in range(16)]
        L.append('// test %d' % n)
        for i in range(16): L.append("wr(6'h%02x, 16'h%04x, 1, 1);" % (i * 2, t['ht'][i]))
        for off, v in ((0x20, t['sxi']), (0x22, t['syi']), (0x24, t['src'] >> 16), (0x26, t['src'] & 0xFFFF),
                       (0x28, t['m1']), (0x2A, t['m2']), (0x2C, t['m3']), (0x2E, t['dxi']), (0x30, t['dyi']),
                       (0x32, t['dst'] >> 16), (0x34, t['dst'] & 0xFFFF), (0x36, t['xc']), (0x38, t['yc']),
                       (0x3A, t['hop'] << 8 | t['op'])):
            L.append("wr(6'h%02x, 16'h%04x, 1, 1);" % (off, v & 0xFFFF))
        L.append("wr(6'h3C, 16'h%04x, 0, 1);" % ((t['fxsr'] << 7) | (t['nfsr'] << 6) | t['skew']))
        ctl = 0x80 | (0x40 if t['hog'] else 0) | (0x20 if t['smudge'] else 0) | t['line']
        L.append("wr(6'h3C, 16'h%04x, 1, 0);" % (ctl << 8))
        if not t['hog']:   # TOS shared-mode loop: restart until done (tas $ff8a3c / bmi)
            L.append("polls = 0; st = 16'h8000; while (st[15]) begin rdw(6'h3C, st); if (st[15]) wr(6'h3C, {st[15:8], 8'h00}, 1, 0); polls = polls + 1; end")
        L.append("wait_idle; $display(\"test %d done\");" % n)
        b.run(mem, t)
    open('tests.vh', 'w').write('\n'.join(L) + '\n')
    open('mem_exp.hex', 'w').write('\n'.join('%04x' % w for w in mem) + '\n')
def check():
    e = [int(x, 16) for x in open('mem_exp.hex').read().split()]
    o = [int(x, 16) if 'x' not in x else -1 for ln in open('mem_out.hex') for x in ln.split('//')[0].split()]
    bad = [i for i in range(MEM) if e[i] != o[i]]
    T = tests(); 
    print('mismatch words:', len(bad))
    for i in bad[:20]: print('  word %05x (byte %06x) exp %04x got %s' % (i, i * 2, e[i], '%04x' % o[i] if o[i] >= 0 else 'xxxx'))
    for n in range(len(T)):
        lo, hi = 0x10000 + 0x800 * n - 0x400, 0x10000 + 0x800 * (n + 1) + 0x400
        nb = sum(1 for i in bad if lo <= i * 2 < hi)
        print('test %d: %s' % (n, 'PASS' if nb == 0 else 'FAIL %d' % nb))
    print('ALL PASS' if not bad else 'FAIL')
{'gen': gen, 'check': check}[sys.argv[1]]()
