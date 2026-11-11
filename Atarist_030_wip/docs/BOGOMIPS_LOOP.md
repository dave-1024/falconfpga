# Linux BogoMIPS delay loop on F157x (sim only, 11 Nov 2026)
Tree: speed eadb3a2 (RTL = F157x 3ff7c63, Phase A off). tb030 GHDL (/tmp/bmw), harness /tmp/bml/run.sh.
Loop as Linux arch/m68k `__delay` (.balignw 4,0x4a8e; `1: subq.l #1,d0; jcc 1b`), so subq+bcc.s share one longword.
Iteration count = (clocks(N=200) - clocks(N=100)) / 100, second pass (cache warm). CACR: Linux sets I+D enable
(value not checked against head.S; 1 and 0x0101 give the same result here).

## Clocks per iteration
| Config | clk/iter | Manual |
|---|---|---|
| I-cache on (CACR 1 or 0x0101), cacheable ROM/"fast" area, WS0 | **10.98** | 8 (SUBQ 2 + Bcc taken 6, cache case) |
| Caches off (CACR 0, or CIIN on every cycle), WS0 | 26.08 | - |
| Caches off, WS3 (ST-like) | 44.14 | - |
Board: lpj 10688 at HZ=100 -> 1.069 M iter/s -> ~15.0 clk/iter at 16 MHz. **Sim 11 does not explain the board's 15**
(4 clocks unaccounted; unverified causes: the real CPU clock on the board, interrupt load during calibration,
I-cache actually off/missing for the kernel loop, or TT-RAM/bridge latency on misses). Not resolved here.

## One cached iteration (clock = tb rising edge, steady state, period 11: 1403 -> 1414)
| k | Signals | Meaning |
|---|---|---|
| 0 | ALU_ACK, IPIPE_FLUSH, COF_PEND (Bcc) | Bcc condition known, pipe flushed, PC += displ |
| 1 | FLUSHED, PC=target, OPCODE_RD=0, IC_HIT=0 | **dead clock**: refill request is registered from IPIPE_FLUSH |
| 2 | OPCODE_RD=1, IC_HIT=1 | I-cache hit on target |
| 3 | OPCODE_RD=1 | **wait**: hit data not yet delivered |
| 4 | OPCODE_RDY + OPCODE_RDY_2 | both words (subq, bcc) arrive |
| 5 | IPIPE_PNTR=2, PIPE_RDY | decoder register stage |
| 6 | OPD_ACK (SUBQ issue) | SUBQ starts |
| 7 | ALU_INIT (SUBQ) | |
| 8 | ALU_ACK (SUBQ), PC_INC, PIPE_RDY | **SUBQ = 3 clocks** (manual 2; the INIT/WRITEBACK overlap is Phase A, off in F157x) |
| 9 | OPD_ACK (Bcc issue) | |
| 10 | ALU_INIT (Bcc) | **Bcc condition goes through the ALU handshake** |
| 11=0 | ALU_ACK + IPIPE_FLUSH | Bcc taken = 8 clocks issue->next issue (manual 6) |
Totals: SUBQ 3 (+1), Bcc taken 8 (+2) -> 11 vs 8.

## Likely RTL locations
- Bcc condition / flush only at FETCH_STATE->START_OP after the ALU INIT/ACK: `wf68k30L_control.vhd:1348`
  (PC_ADD_DISPL_I), `:1370-1376` (COF_PEND / IPIPE_FLUSH_I for Bcc/DBcc), `:1398` (Bcc in ALU_INIT_I list).
- Refill starts a clock late: `wf68k30L_opcode_decoder.vhd:244-246` (OPCODE_RD_I set on the clock edge *after*
  IPIPE_FLUSH), `:875-889` (FLUSHED / PC_INC_I after a flush).
- I-cache hit -> OPCODE_RDY takes 2 clocks: `wf68k30L_bus_interface.vhd:1143-1149` (PF_REQ/IC_TAKE) and the
  queue load `:1570-1630`.
- SUBQ 3 clocks: the Phase A overlap (F157a, `F157_PHASE_A` generics in control/decoder/bus interface).

## Fix plan for Monday (not implemented)
1. Fix Phase A (already planned) -> SUBQ/ADDQ 2 clocks (-1/iter).
2. Bcc: evaluate the condition from the CCR at issue when no CC update is pending (CC_UPDT=0 and the previous op
   has acked), raise COF_PEND/IPIPE_FLUSH in the first Bcc clock; keep the ALU path when a CC hazard exists (-1).
3. Refill: start the I-cache lookup in the flush clock with the target address (combinational PC+displ to the
   lookup only), as F157r tried for BSR/JSR/RTS - watch timing_pairs (F157r failed at 17.2 MHz, -10.6 ns), so
   register the displacement add early instead of a long combinational path (-1).
4. Optional: deliver an I-cache hit to OPCODE_RDY in the OPCODE_RD clock (IC_TAKE path) (-1). Steps 1-3 reach 8;
   do not go below the manual. Gate: speed harness (delay_loop8 = 72, dbf_loop8 = 54, bra.s = 6), run_rtl, difftest
   vs F156, icache expect files, then board.

## Other branches (speed harness one.sh, I-cache on, WS0; per copy incl. harness overhead)
bra.s taken 8.3 (manual 6), jmp (d16,pc) 9.3, DBcc loop8 71 (manual 54, ~+2 per taken DBcc), delay_loop8 91.9
(manual 72), 4x subq.l 11.25 (2.8 each, manual 2). Same cause: every taken change of flow pays the late refill
(k1, k3, k5); Bcc/DBcc also pay the ALU condition handshake. JMP/JSR/RTS/BSR share the refill path.
