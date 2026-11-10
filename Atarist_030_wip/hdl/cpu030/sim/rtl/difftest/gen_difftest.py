#!/usr/bin/env python3
"""Generate dense m68k sequences for F156 vs F157q architectural diffs."""
import argparse
import random
import sys

DUMP = 0x5000
DONE = 0x3400
SCRATCH = (0x2000, 0x2100, 0x2200, 0x2300, 0x2400, 0x2500)

HEADER = """\
        .text
        .long 0x00002F00
        .long 0x00FC0008
start:  moveq #1,d7
        movec d7,cacr
        move.w #0x2700,sr
        lea 0x2000,a0
        lea 0x2100,a1
        lea 0x2200,a2
        lea 0x2300,a3
        lea 0x2400,a4
        lea 0x2500,a5
        move.l #0x12345678,d0
        move.l #0x9ABCDEF0,d1
        move.l #0x0F0F0F0F,d2
        move.l #0xF0F0F0F0,d3
        move.l #0x00FF00FF,d4
        move.l #0xFF00FF00,d5
        move.l #0xA5A5A5A5,d6
        move.l #0x00000007,d7
        move.l #0x11111111,(a0)
        move.l #0x22222222,4(a0)
        move.l #0x33333333,8(a0)
        move.l #0x44444444,12(a0)
        move.l #0x55555555,(a1)
        move.l #0x66666666,4(a1)
        move.l #0x77777777,(a2)
        move.l #0x88888888,(a3)
        move.l #0x99999999,(a4)
        move.l #0xAAAAAAAA,(a5)
"""

FOOTER = f"""\
        movem.l d0-d7/a0-a6,0x{DUMP:04X}
        move.l a7,0x{DUMP+60:04X}
        move.w sr,0x{DUMP+64:04X}
        move.w #0xFFFF,0x{DONE:04X}
hang:   bra.s hang
"""


def refresh_an(rng):
    i = rng.randrange(6)
    return [f"        lea 0x{SCRATCH[i]:04X},a{i}"]


class Gen:
    def __init__(self, rng):
        self.rng = rng
        self.lab = 0

    def L(self):
        self.lab += 1
        return self.lab

    def dn(self):
        return self.rng.randrange(8)

    def an(self):
        return self.rng.randrange(6)

    def q(self):
        return self.rng.choice([1, 2, 3, 4, 5, 6, 7, 8])

    def two_clock(self):
        d, s = self.dn(), self.dn()
        return self.rng.choice([
            f"        add.l d{s},d{d}",
            f"        sub.l d{s},d{d}",
            f"        and.l d{s},d{d}",
            f"        or.l d{s},d{d}",
            f"        eor.l d{s},d{d}",
            f"        addq.l #{self.q()},d{d}",
            f"        subq.l #{self.q()},d{d}",
            f"        not.l d{d}",
            f"        neg.l d{d}",
            f"        clr.l d{d}",
            f"        move.l d{s},d{d}",
            f"        addi.l #0x{self.rng.randrange(0x10000):04X},d{d}",
            f"        subi.l #0x{self.rng.randrange(0x100):02X},d{d}",
            f"        andi.l #0x{self.rng.choice([0xFFFFFFFF, 0x00FF00FF, 0xFF00FF00, 0x0F0F0F0F, 0]):08X},d{d}",
            f"        ori.l #0x{self.rng.choice([1, 0x80000000, 0xFF, 0xFFFF]):08X},d{d}",
            f"        eori.l #0x{self.rng.choice([0xFFFFFFFF, 1, 0x80000000]):08X},d{d}",
        ])

    def follow_ccr(self):
        d, s = self.dn(), self.dn()
        n = self.L()
        return self.rng.choice([
            [f"        bcc.s .L{n}", f"        addq.l #1,d6", f".L{n}:"],
            [f"        bcs.s .L{n}", f"        addq.l #1,d6", f".L{n}:"],
            [f"        beq.s .L{n}", f"        addq.l #1,d6", f".L{n}:"],
            [f"        bne.s .L{n}", f"        addq.l #1,d6", f".L{n}:"],
            [f"        bpl.s .L{n}", f"        addq.l #1,d6", f".L{n}:"],
            [f"        bmi.s .L{n}", f"        addq.l #1,d6", f".L{n}:"],
            [f"        bge.s .L{n}", f"        addq.l #1,d6", f".L{n}:"],
            [f"        blt.s .L{n}", f"        addq.l #1,d6", f".L{n}:"],
            [f"        bhi.s .L{n}", f"        addq.l #1,d6", f".L{n}:"],
            [f"        bls.s .L{n}", f"        addq.l #1,d6", f".L{n}:"],
            [f"        bvc.s .L{n}", f"        addq.l #1,d6", f".L{n}:"],
            [f"        bvs.s .L{n}", f"        addq.l #1,d6", f".L{n}:"],
            [f"        scc d{d}"],
            [f"        scs d{d}"],
            [f"        seq d{d}"],
            [f"        sne d{d}"],
            [f"        smi d{d}"],
            [f"        spl d{d}"],
            [f"        sge d{d}"],
            [f"        slt d{d}"],
            [f"        shi d{d}"],
            [f"        sls d{d}"],
            [f"        svc d{d}"],
            [f"        svs d{d}"],
            [f"        addx.l d{s},d{d}"],
            [f"        subx.l d{s},d{d}"],
            [f"        negx.l d{d}"],
        ])

    def shift(self):
        d = self.dn()
        amt = self.rng.choice([1, 2, 3, 4, 5, 8])
        return self.rng.choice([
            f"        lsl.l #{amt},d{d}",
            f"        lsr.l #{amt},d{d}",
            f"        asl.l #{amt},d{d}",
            f"        asr.l #{amt},d{d}",
            f"        rol.l #{amt},d{d}",
            f"        ror.l #{amt},d{d}",
            f"        roxl.l #1,d{d}",
            f"        roxr.l #1,d{d}",
            f"        lsl.w #{amt},d{d}",
            f"        lsr.w #{amt},d{d}",
            f"        lsl.b #1,d{d}",
            f"        lsr.b #1,d{d}",
        ])

    def mem(self):
        a, b = self.an(), self.an()
        d, s = self.dn(), self.dn()
        disp = self.rng.choice([0, 4, 8, 12])
        return self.rng.choice([
            [f"        move.l (a{a}),d{d}"],
            [f"        move.l d{d},(a{a})"],
            [f"        move.l {disp}(a{a}),d{d}"],
            [f"        move.l d{d},{disp}(a{a})"],
            [f"        lea 0x{SCRATCH[a]:04X},a{a}", f"        move.l (a{a})+,d{d}"],
            [f"        lea 0x{SCRATCH[a]:04X},a{a}", f"        move.l d{d},(a{a})+"],
            [f"        and.l (a{a}),d{d}"],
            [f"        or.l (a{a}),d{d}"],
            [f"        eor.l d{d},(a{a})"],
            [f"        add.l (a{a}),d{d}"],
            [f"        sub.l (a{a}),d{d}"],
            [f"        cmp.l (a{a}),d{d}"],
            [f"        not.l (a{a})"],
            [f"        lea 0x{SCRATCH[a]:04X},a{a}", f"        and.l d{s},d{d}", f"        or.l d{d},(a{a})"],
            [f"        lea 0x{SCRATCH[a]:04X},a{a}", f"        move.l (a{a})+,d{d}",
             self.shift(), f"        and.l d{s},d{d}", f"        or.l d{d},(a{b})"],
        ])

    def an_use(self):
        a = self.an()
        d = self.dn()
        return self.rng.choice([
            [f"        lea 0x{SCRATCH[a]:04X},a{a}", f"        addq.l #4,a{a}", f"        move.l (a{a}),d{d}"],
            [f"        lea 0x{SCRATCH[a]:04X},a{a}", f"        adda.w #4,a{a}", f"        move.l d{d},(a{a})"],
            [f"        lea 0x{SCRATCH[a]:04X},a{a}", f"        move.l a{a},d{d}", f"        addq.l #8,d{d}",
             f"        movea.l d{d},a{a}", f"        move.l (a{a}),d{d}"],
            [f"        lea 0x{SCRATCH[a]:04X},a{a}", f"        lea 4(a{a}),a{a}", f"        move.l d{d},(a{a})"],
            [f"        lea 0x{SCRATCH[a]:04X},a{a}", f"        exg d{d},a{a}", f"        move.l a{a},d{d}",
             f"        lea 0x{SCRATCH[a]:04X},a{a}", f"        move.l (a{a}),d{d}"],
        ])

    def movem_dbf(self):
        n = self.L()
        a = self.an()
        cnt = self.rng.choice([1, 2, 3])
        return [
            f"        lea 0x{SCRATCH[a]:04X},a{a}",
            f"        movem.l d0-d3,(a{a})",
            f"        movem.l (a{a}),d4-d7",
            f"        moveq #{cnt},d7",
            f".L{n}:",
            f"        add.l d0,d1",
            f"        lsr.l #1,d2",
            f"        and.l d3,d4",
            f"        dbf d7,.L{n}",
        ]

    def chunk(self):
        k = self.rng.choice(
            ["alu"] * 4 + ["alu_ccr"] * 5 + ["shift"] * 2 + ["shift_ccr"] * 3
            + ["mem"] * 3 + ["an"] * 2 + ["movem"] + ["mixed"] * 2
        )
        if k == "alu":
            return [self.two_clock() for _ in range(self.rng.randint(2, 6))]
        if k == "alu_ccr":
            lines = [self.two_clock()]
            lines += self.follow_ccr()
            if self.rng.random() < 0.5:
                lines.append(self.two_clock())
                lines += self.follow_ccr()
            return lines
        if k == "shift":
            return [self.shift() for _ in range(self.rng.randint(1, 4))]
        if k == "shift_ccr":
            lines = [self.shift()]
            lines += self.follow_ccr()
            return lines
        if k == "mem":
            out = []
            for _ in range(self.rng.randint(1, 3)):
                m = self.mem()
                out.extend(m if isinstance(m, list) else [m])
            return out
        if k == "an":
            return self.an_use()
        if k == "movem":
            return self.movem_dbf()
        # mixed dense
        out = [self.two_clock(), self.shift()]
        out += self.follow_ccr()
        m = self.mem()
        out.extend(m if isinstance(m, list) else [m])
        return out


def flatten(xs):
    out = []
    for x in xs:
        if isinstance(x, list):
            out.extend(flatten(x))
        else:
            out.append(x)
    return out


def hand_flags():
    return """\
        add.l d0,d1
        beq.s .Hf0
        addq.l #1,d6
.Hf0:   add.l d0,d0
        bne.s .Hf1
        addq.l #1,d6
.Hf1:   sub.l d1,d2
        scs d5
        and.l d3,d4
        seq d5
        add.l d0,d1
        addx.l d2,d3
        sub.l d4,d5
        subx.l d0,d1
        or.l d2,d3
        scc d4
        eor.l d0,d1
        smi d5
        not.l d2
        spl d4
        neg.l d3
        addx.l d1,d0
        clr.l d7
        seq d5
        addq.l #1,d0
        bcc.s .Hf2
        addq.l #1,d6
.Hf2:   subi.l #1,d0
        bcs.s .Hf3
        addq.l #1,d6
.Hf3:
"""


def hand_icon():
    return """\
        lea 0x2000,a0
        lea 0x2100,a1
        move.l #0xFF00FF00,d2
        move.l #0x00FF00FF,d3
        moveq #7,d7
.Hi0:   move.l (a0)+,d0
        lsr.l #1,d0
        and.l d2,d0
        move.l (a1),d1
        and.l d3,d1
        or.l d0,d1
        eor.l d2,d1
        not.l d1
        move.l d1,(a1)+
        dbf d7,.Hi0
        lea 0x2000,a0
        movem.l d0-d3/a0-a1,-(sp)
        movem.l (sp)+,d0-d3/a0-a1
"""


def hand_an():
    return """\
        lea 0x2000,a0
        addq.l #4,a0
        move.l (a0),d0
        lea 0x2100,a1
        move.l a1,d1
        addq.l #8,d1
        move.l d1,a1
        move.l d0,(a1)
        lea 0x2200,a2
        adda.w #4,a2
        move.l (a2),d2
        lea 4(a0),a3
        move.l d2,(a3)
        exg d3,a4
        lea 0x2400,a4
        move.l (a4),d3
"""


def hand_shiftx():
    return """\
        move.l #0x80000001,d0
        lsl.l #1,d0
        addx.l d1,d2
        lsr.l #1,d0
        subx.l d3,d4
        roxl.l #1,d5
        roxr.l #1,d6
        asl.l #2,d1
        addx.l d0,d1
        asr.l #3,d2
        scs d7
        rol.l #4,d3
        ror.l #1,d4
        add.l d0,d1
        roxl.l #1,d2
"""


def emit(kind, seed, nchunks):
    rng = random.Random(seed)
    g = Gen(rng)
    if kind == "hand_flags":
        body = hand_flags()
    elif kind == "hand_icon":
        body = hand_icon()
    elif kind == "hand_an":
        body = hand_an()
    elif kind == "hand_shiftx":
        body = hand_shiftx()
    else:
        lines = []
        for i in range(nchunks):
            if i % 8 == 7:
                lines.extend(refresh_an(rng))
            lines.extend(flatten(g.chunk()))
        body = "\n".join(lines) + "\n"
    return HEADER + body + FOOTER


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kind", default="random")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--nchunks", type=int, default=40)
    ap.add_argument("-o", required=True)
    args = ap.parse_args()
    open(args.o, "w").write(emit(args.kind, args.seed, args.nchunks))


if __name__ == "__main__":
    main()
