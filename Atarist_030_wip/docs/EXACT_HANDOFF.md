# Exact bus hand-off vs MC68030UM (19 Oct 2026, branch exact-handoff)

Bench: tb030 16-bit port, DSACK 2+WS clocks after AS (4-clock cycles at WS0), uncached (CIIN, ST side).
Reference = worst case (no overlap) of UM 11.6 tables, NCC + n16*(4+ws) - n32*2 (UM 11.3 2-clock 32-bit basis, 11.5 wait states). It is an upper bound: below it is allowed, above it is too slow.

## Before (F3a 7919eb3)
```
test       | ours ws0 | 030 worst ws0 | delta | ours ws1 | 030 worst ws1 | delta | our idle ws0/ws1
wr_rd      |   24.34 |   17.0 |   +7.3 |   23.50 |   21.0 |   +2.5 | 8.3/3.5
wr_wr      |   16.00 |   16.0 |   +0.0 |   20.00 |   20.0 |   +0.0 | 0.0/0.0
rd_rd      |   19.50 |   18.0 |   +1.5 |   23.50 |   22.0 |   +1.5 | 3.5/3.5
rd1        |    8.00 |    9.0 |   -1.0 |   10.00 |   11.0 |   -1.0 | 0.0/0.0
wr1        |    8.00 |    8.0 |   +0.0 |   10.00 |   10.0 |   +0.0 | 0.0/0.0
rmw_or     |   12.00 |   13.0 |   -1.0 |   15.00 |   16.0 |   -1.0 | 0.0/0.0
rmw_addq   |   12.00 |   13.0 |   -1.0 |   15.00 |   16.0 |   -1.0 | 0.0/0.0
rmw_bclr   |   16.00 |   19.0 |   -3.0 |   20.00 |   23.0 |   -3.0 | 0.0/0.0
mvm_rd4    |   40.00 |   54.0 |  -14.0 |   50.00 |   64.0 |  -14.0 | 0.0/0.0
mvm_wr4    |   40.00 |   42.0 |   -2.0 |   50.00 |   52.0 |   -2.0 | 0.0/0.0
mvm_rdw4   |   34.50 |   38.0 |   -3.5 |   30.00 |   44.0 |  -14.0 | 10.5/0.0
mvm_wrw4   |   24.00 |   26.0 |   -2.0 |   30.00 |   32.0 |   -2.0 | 0.0/0.0
pop_l      |   34.89 |   30.0 |   +4.9 |   35.00 |   37.0 |   -2.0 | 6.9/0.0
push_l     |   34.89 |   30.0 |   +4.9 |   35.00 |   37.0 |   -2.0 | 6.9/0.0
jsr_rts    |   55.80 |   57.5 |   -1.7 |   68.75 |   70.4 |   -1.6 | 4.3/3.9
link_unlk  |   31.98 |   34.0 |   -2.0 |   40.03 |   42.0 |   -2.0 | -0.0/0.0
trap_rte   |  108.17 |   94.1 |  +14.0 |  129.38 |  115.2 |  +14.2 | 24.0/23.9
```

## After XH1
```
test       | ours ws0 | 030 worst ws0 | delta | ours ws1 | 030 worst ws1 | delta | our idle ws0/ws1
wr_rd      |   19.39 |   17.0 |   +2.4 |   20.00 |   21.0 |   -1.0 | 3.4/0.0
wr_wr      |   16.00 |   16.0 |   +0.0 |   20.00 |   20.0 |   +0.0 | 0.0/0.0
rd_rd      |   16.00 |   18.0 |   -2.0 |   20.00 |   22.0 |   -2.0 | 0.0/0.0
rd1        |    8.00 |    9.0 |   -1.0 |   10.00 |   11.0 |   -1.0 | 0.0/0.0
wr1        |    8.00 |    8.0 |   +0.0 |   10.00 |   10.0 |   +0.0 | 0.0/0.0
rmw_or     |   12.00 |   13.0 |   -1.0 |   15.00 |   16.0 |   -1.0 | 0.0/0.0
rmw_addq   |   12.00 |   13.0 |   -1.0 |   15.00 |   16.0 |   -1.0 | 0.0/0.0
rmw_bclr   |   16.00 |   19.0 |   -3.0 |   20.00 |   23.0 |   -3.0 | 0.0/0.0
mvm_rd4    |   40.00 |   54.0 |  -14.0 |   50.00 |   64.0 |  -14.0 | 0.0/0.0
mvm_wr4    |   40.00 |   42.0 |   -2.0 |   50.00 |   52.0 |   -2.0 | 0.0/0.0
mvm_rdw4   |   29.50 |   38.0 |   -8.5 |   30.00 |   44.0 |  -14.0 | 5.5/0.0
mvm_wrw4   |   24.00 |   26.0 |   -2.0 |   30.00 |   32.0 |   -2.0 | 0.0/0.0
pop_l      |   28.00 |   30.0 |   -2.0 |   35.00 |   37.0 |   -2.0 | 0.0/0.0
push_l     |   28.00 |   30.0 |   -2.0 |   35.00 |   37.0 |   -2.0 | 0.0/0.0
jsr_rts    |   55.75 |   57.5 |   -1.8 |   68.28 |   70.4 |   -2.1 | 4.2/3.9
link_unlk  |   32.00 |   34.0 |   -2.0 |   40.19 |   42.0 |   -1.8 | 0.0/0.0
trap_rte   |  108.12 |   94.1 |  +14.0 |  128.91 |  115.2 |  +13.8 | 24.0/23.9
```

## XH1
PF_REQ_RAW asked for the next prefetch long only at Q_CNT<=1; after an operand cycle the 4-word queue often held 2-3 words while the control unit drained it, so the bus idled (W->R 8 clocks, MOVEM.W read 10.5, push/pop 6.9 at WS0, R->R 3.5). Now Q_CNT<=2 (a long still fits: 2+2=4), except during exception processing (BUSY_EXH), where the extra long is fetched and thrown away (trap_rte +12 clocks when tried).

## Cache case (I-cache on, 4 copies x 64, CIMODE=1)
```
test       f3a ws0  x1 ws0 f3a ws1  x1 ws1
wr_rd        15.11   15.04   17.10   17.05
wr_wr         9.11    9.12   11.15   11.15
rd_rd        18.02   17.97   20.05   20.00
rd1           8.00    8.00    9.02    9.02
wr1           2.10    2.10    3.12    3.12
rmw_or        9.05    9.05   11.07   11.07
rmw_addq      9.05    9.05   11.07   11.07
rmw_bclr      9.11    9.12   11.15   11.15
mvm_rd4      40.98   40.98   49.02   49.02
mvm_wr4      35.08   35.09   43.12   43.12
mvm_rdw4     30.07   29.99   29.02   29.02
mvm_wrw4     19.08   19.09   23.12   23.12
pop_l        26.11   26.03   30.08   30.08
push_l       26.11   26.03   30.08   30.08
jsr_rts      48.05   48.00   54.03   53.97
link_unlk    29.05   29.05   33.11   33.11
trap_rte     93.08   93.04  103.12  103.07
```
XH1 does not change the cache case (no idle to remove; prefetch comes from the cache).

## Open
- TRAP/RTE: +14 over the bound. Gaps: 3 clocks between stack longs, 3 before the vector read, 4 between RTE frame reads, 5 before the refill. Cause: the exception handler drops DATA_WR/RD in the DATA_RDY clock and re-requests one clock after ISP_DEC because ADR_EFF is registered (P_D). Fix needs the SP step one clock earlier (at WP_GO / cycle start), which touches the DSACK->WR_EARLY path (Fmax) and the SP value after a fault while stacking. Not done.
- W->R residual +2.4 at WS0 in one of two alignments: queue full while the control unit executes LEA (about 5 clocks per instruction), not a hand-off.
- MOVEM.L reads 14 below the 8+4n bound: internal clocks hidden behind the bus; flagged for the A1200/ACA1230 oracle.

## XH2 (19 Oct night, shelved, branch exact-handoff-xh2)
Exception handler: ISP-4 taken into the registered effective address in the ISP_DEC clock (address section,
M = 0 only), P_D as a plain flip flop masked by DATA_RDY, next stack long / vector read / RTE frame reads
requested in the DATA_RDY clock. The SP still steps only on DATA_RDY. TRAP/RTE 108.12 -> 104.12 (WS0),
128.91 -> 124.91 (WS1); everything else unchanged. Sim: run_rtl, dcache, icache PASS, cmpall = XH1,
FILT 36/36, audit identical to XH1, prog_stkflt (fault while stacking) identical to F3a WS0/1/3/7.
Build clk_cpu030 20.356 MHz. Board: 2 of 6 cold boots halted (black 4/5); XH1 6/6. Not accepted: the cause
is not reproduced in RTL (candidates: an early request meeting bus arbitration (floppy DMA) or a DATA_RDY
of another cycle in BUILD_STACK on the real ST bus).
