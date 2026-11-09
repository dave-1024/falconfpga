# F155: TT-RAM I-cache hang of the two-word path reproduced in sim (root cause)

**Date:** 2026-11-09. **Base:** speed F155 (tree = 0f101e0, F147_TWO_WORD := false). Sim only, no HDL change.

## Bench
`hdl/cpu030/sim/speed/irq/run_lt_tt.sh` + `lt_tt.s`: tb030 (GHDL RTL), LOOPTEST's `subq.l #1,d0 / bcc.s`
loop copied to the cacheable 32-bit TT port ($01000010), CACR 0808 / 0809 / 0909 / 0809, periodic
level 4 + level 6 interrupts (IPL_MODE=3, IRQ_PER=900, IRQ_PER6=500). The scratch copy with
F147_TWO_WORD := true hangs exactly like the board; the as-is (F155) core passes.

    asis WS=0 done=1 iack=175   (all four passes, d0 = FFFFFFFF)
    tw   WS=0 done=0 TIMEOUT iack=74   (caches-off pass OK, hangs in the first I-cache-on pass)
    tw   WS=1 done=0 TIMEOUT iack=116

What the older benches missed: an exception (here the timer interrupt) taken while the loop runs
from the I-cache, and its RTE back into cached code. f147_icache_stress.s has no interrupts;
irqchk.s has interrupts but never enables the I-cache.

## Root cause (VCD, tw WS=0, wall clock c = 23711..23722, t ~ 2.984 ms)
RTE to $01000010 -> exception handler EX_STATE = REFILL_PIPE (IPIPE_FILL = 1), IPIPE_FLUSH, decoder IPIPE_PNTR = 0.
- c 23712: IC_MTAKE = 1 (restart hit on the cached loop), RESTART_PEND = 1.
- c 23713: Q_HIT2 = 1 (Q_ADR = $01000010, Q_CNT = 2).
- c 23714: OPCODE_RDY = 1 **and** OPCODE_RDY_2 = 1 (5380, 64FC). Decoder IPIPE_PNTR 0 -> 2.
- c 23717: OPCODE_RDY = 1 (4E75). IPIPE_PNTR 2 -> 3 = pipe full.
- From then on: no further OPCODE_RDY, because the pipe is full. The exception handler's PIPE_STATUS
  counter (PIPE_CNT) has counted only **2** OPCODE_RDY strobes, but it needs **3** before PIPE_FULL goes true.
  EX_STATE stays in REFILL_PIPE for good. BUSY_EXH = 1, IPIPE_FILL = 1, OW_REQ = 0. Nothing executes
  and no interrupt is taken (no IACK). No bus cycles: silent hang.

File:line (speed F155):
- `wf68k30L_exception_handler.vhd:850-866` PIPE_STATUS counts OPCODE_RDY pulses (CNT < "10" then PIPE_FULL),
  one per word. It knows nothing about OPCODE_RDY_2, which delivers two words in one pulse.
- `wf68k30L_exception_handler.vhd:1105-1112` REFILL_PIPE leaves only on PIPE_FULL (or ACCESS_ERR / DOUBLE_BUSFLT).
- `wf68k30L_bus_interface.vhd:938` Q_HIT2 (two-word pop), `:1668` OPCODE_RDY_2_I <= Q_HIT2.
- `wf68k30L_opcode_decoder.vhd:502-510` pipe fill 0 -> 2 on OPCODE_RDY_2.

So it is not the address skew: the addresses are right. It is an under-count in the exception handler's
refill. It fires after any exception whose refill gets the restart two-word hit (cached code), and the 200 Hz
timer interrupt during LOOPTEST's cached TT-RAM loop is exactly that. ST-RAM is cache-inhibited, so it never fires there.
No fix written (per brief).

Debug: `VCD=1 run_lt_tt.sh` writes tw.vcd. `vcdt.py tw.vcd 23706 23722 i_exc_handler.pipe_cnt[1:0] i_exc_handler.pipe_full i_bus_if.opcode_rdy_i i_bus_if.opcode_rdy_2_i i_opcode_decoder.ipipe_pntr`
