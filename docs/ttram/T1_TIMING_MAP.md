# T1 loop timing map (TTM1, TT-RAM, caches on, CACR $3919)

T1 readback loop (TTM1 text linked at $01000104, buffer R=$01008000):

```
010001C0 2010        move.l (a0),d0
010001C2 B088        cmp.l  a0,d0
010001C4 6708        beq.s  010001CE
010001C6 2A08        move.l a0,d5        ; mismatch path
010001C8 2C08 6100.. bsr    report
010001CE 5888        addq.l #4,a0
010001D0 5387        subq.l #1,d7
010001D2 6AEC        bpl.s  010001C0
```

I-cache index: line = A7:4, long = A3:2. The body is line $C (1C0..1CF); 1D0.. is line $D.
`beq` targets 1CE = line C, long 3, word 1 (a 4n+2 target inside the last long of the line).

## 1. The real 68030 (MC68030UM section 11, cache case) vs RTL vs board

| Instruction | UM cache case (clk, approx.) | RTL / board |
|---|---|---|
| move.l (a0),d0 (D-cache hit) | 2 + FEA(An) 2 ≈ 4 | see section 2 |
| cmp.l a0,d0 | 2 | |
| beq.s taken | 6 | board first pass: Q_MISS, PF_DONE +4, IC_TAKE +1 |
| addq.l #4,a0 | 2 | |
| subq.l #1,d7 | 2 | |
| bpl.s taken | 6 | |
| **Iteration** | **≈ 22** | **RTL 39 clk** (steady, all hits); board: fails on the first pass |

Per-instruction RTL counts are not separable from the queue trace (the decoder overlaps queue refills), so only the
iteration total is given.
The RTL is slower than a real 030 (no pipelined decode overlap), which is a performance note, not a fault.
The board and RTL agree clock-for-clock on the first pass up to 1CE (ring stamps vs mon_t1.log 38464–38489).
The only difference is the data returned by the hit at 1CE.

## 2. Clock-by-clock RTL steady iteration (mon_t1.log clk 38589–38627)

QF = Q_HIT, IC_TAKE, PF_DONE, Q_MISS. LK = lookup A7:0, FL = fill A7:0. AS/DS active low.
No bus cycle in the steady loop: every fetch and the (a0) read hit the caches. SDRAM g-states stay idle (refresh only).

| clk | Q_HEAD | word0 | QF | BIW | LK FL HIT | PF_DONE | AS DS | A |
|---|---|---|---|---|---|---|---|---|
| 0 | 010001C0 | 015A | 0100 | 0100 | 0C0 D8 1 | 0 | 1 11 | 010001C0 |
| 1 | 010001C0 | 2010 | 1100 | 0100 | 0C4 D8 1 | 0 | 1 11 | 010001C0 |
| 2 | 010001C2 | B088 | 0000 | 0100 | 0C8 D8 1 | 0 | 1 11 | 010001C0 |
| 3 | 010001C2 | B088 | 0000 | 0100 | 0C8 D8 1 | 0 | 1 11 | 010001C0 |
| 4 | 010001C2 | B088 | 1000 | 0100 | 0C8 D8 1 | 0 | 1 11 | 010001C2 |
| 5 | 010001C4 | 6708 | 0000 | 0100 | 0C8 D8 1 | 0 | 1 11 | 010001C2 |
| 6 | 010001C4 | 6708 | 0000 | 0100 | 0C8 D8 1 | 0 | 1 11 | 010001C2 |
| 7 | 010001C4 | 6708 | 1000 | 2010 | 0C8 D8 1 | 0 | 1 11 | 010001C4 |
| 8 | 010001C6 | 2A08 | 0100 | 2010 | 0C8 D8 1 | 0 | 1 11 | 010001C4 |
| 9 | 010001C6 | 2A08 | 0000 | 2010 | 0CC D8 1 | 0 | 1 11 | 0100800C |
| 10 | 010001C6 | 2A08 | 1000 | 2010 | 0CC D8 1 | 0 | 1 11 | 0100800C |
| 11 | 010001C8 | 2C08 | 0000 | 2010 | 0CC D8 1 | 0 | 1 11 | 010001C6 |
| 12 | 010001C8 | 2C08 | 0000 | 2010 | 0CC D8 1 | 0 | 1 11 | 010001C6 |
| 13 | 010001C8 | 2C08 | 0000 | B088 | 0CC D8 1 | 0 | 1 11 | 010001C8 |
| 14 | 010001C8 | 2C08 | 1000 | B088 | 0CC D8 1 | 0 | 1 11 | 010001C8 |
| 15 | 010001CA | 6100 | 0100 | B088 | 0CC D8 1 | 0 | 1 11 | 010001C8 |
| 16 | 010001CA | 6100 | 0000 | B088 | 0D0 D8 1 | 0 | 1 11 | 010001C8 |
| 17 | 010001CA | 6100 | 0000 | 6708 | 0D0 D8 1 | 0 | 1 11 | 010001CA |
| 18 | 010001CA | 6100 | 1000 | 6708 | 0D0 D8 1 | 0 | 1 11 | 010001CA |
| 19 | 010001CC | 0158 | 0000 | 6708 | 0D0 D8 1 | 0 | 1 11 | 010001CA |
| 20 | 010001CC | 0158 | 0100 | 0100 | 0D0 D8 1 | 0 | 1 11 | 010001CA |
| 21 | 010001CC | 0158 | 0001 | 0100 | 0D4 D8 1 | 0 | 1 11 | 010001CE |
| 22 | 010001CE | 0158 | 0100 | 0100 | 0CE D8 1 | 0 | 1 11 | 010001CE |
| 23 | 010001CE | 5888 | 1100 | 0100 | 0D0 D8 1 | 0 | 1 11 | 010001CE |
| 24 | 010001D0 | 5387 | 0000 | 0100 | 0D4 D8 1 | 0 | 1 11 | 010001CE |
| 25 | 010001D0 | 5387 | 0000 | 0100 | 0D4 D8 1 | 0 | 1 11 | 010001CE |
| 26 | 010001D0 | 5387 | 1000 | 0100 | 0D4 D8 1 | 0 | 1 11 | 010001D0 |
| 27 | 010001D2 | 6AEC | 0100 | 0100 | 0D4 D8 1 | 0 | 1 11 | 010001D0 |
| 28 | 010001D2 | 6AEC | 0000 | 0100 | 0D8 D8 1 | 0 | 1 11 | 010001D0 |
| 29 | 010001D2 | 6AEC | 1000 | 5888 | 0D8 D8 1 | 0 | 1 11 | 010001D2 |
| 30 | 010001D4 | 7001 | 0000 | 5888 | 0D8 D8 1 | 0 | 1 11 | 010001D2 |
| 31 | 010001D4 | 7001 | 0000 | 5888 | 0D8 D8 1 | 0 | 1 11 | 010001D2 |
| 32 | 010001D4 | 7001 | 1000 | 5387 | 0D8 D8 1 | 0 | 1 11 | 010001D4 |
| 33 | 010001D6 | 6100 | 0100 | 5387 | 0D8 D8 1 | 0 | 1 11 | 010001D4 |
| 34 | 010001D6 | 6100 | 0000 | 5387 | 0DC D8 0 | 0 | 1 11 | 010001D4 |
| 35 | 010001D6 | 6100 | 1000 | 6AEC | 0DC D8 0 | 0 | 1 11 | 010001D6 |
| 36 | 010001D8 | 015A | 0000 | 6AEC | 0DC D8 0 | 0 | 1 11 | 010001D6 |
| 37 | 010001D8 | 015A | 0000 | 6AEC | 0DC D8 0 | 0 | 1 11 | 010001D6 |
| 38 | 010001D8 | 015A | 0001 | 0100 | 0DC D8 0 | 0 | 1 11 | 010001D8 |

## 3. First pass on the board vs RTL (the fault)

RTL (mon_t1.log): 38487 the prefetch of long 1CC ends (DS 00) → 38488 PF_DONE + Q_MISS (beq taken), the fill writes
slot C3 at the edge → 38489 IC_TAKE, HIT, LK=0CE reads slot C3 → word 5888 (correct, asynchronous read).

Board (TTXD3 STR ring, tt17s, `/workspace/sw/xg1.png`):

| Q_HEAD | w1 | meaning | IC16 |
|---|---|---|---|
| 010001CC | FFFF 100C | Q_MISS (beq taken), stamp 3 | D198 |
| 010001CE | FFFF 2010 | PF_DONE: fill F_CUR=1CC, stamp 4 | CF9A (F_ADR CE, F_CUR CC, PFD) |
| 010001CE | FFFF 4004 | IC_TAKE, stamp 1 (next clock) | CF9C (HIT=1) |
| 010001CE | **3F3C** 8104 | decoder gets 3F3C instead of 5888 | D198 |

3F3C0002 is TTM1's `move.w #2,-(sp)` at 010003CC/CE: the same slot C3 under the old tag.
Why: Gowin maps DATA_RAM to a block RAM (SDPB, READ_MODE 0) and retimes the read address onto the F_ADR
register input, so the read is sampled at the same edge as the fill write. SDPB has no write-through, so the
lookup sees the old long while VALID and TAG already say hit. Fix [C10]: a write-to-read forwarding register.
