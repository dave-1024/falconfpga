# WF68K30L speed overhaul: cycle counts against MC68030UM section 11

Branch `speed` (from main 528aea1). Goal: the instruction-cache-case clock counts and bus-cycle placement of the
MC68030 User's Manual section 11, as near cycle-exact as possible. The core must never be faster than the manual.
ST-RAM stays cache-inhibited (TF536-style accelerated STE).

## Harness (`hdl/cpu030/sim/speed/`)

- `tests.txt` lists the tests: name | one copy of the instruction(s) (`;` = new line) | K | manual I-cache-case clocks per copy | note.
- `gen.py` builds the test program at $FD0000, which is cacheable with `CIMODE=1`, using the bench `tb030.vhd`.
  It sets up the registers, enables the I-cache, and runs the block twice: pass 1 fills the cache.
  It writes a marker to $3400 before each pass and after the end.
- `one.sh` runs one program at WS0.
- `runall.sh <built bench> <out>` runs every test with K and K/2 copies. Result = (T(K) - T(K/2)) / (K/2), so loop and
  marker overhead cancel. The figure is the clocks per copy with the instruction stream hitting the cache.
- `build.sh <cpu030 dir> <workdir>` builds the bench (GHDL, set `GHDL=`).
- Usage: `GHDL=... ./build.sh $PWD/../.. /tmp/w && GHDL=... ./runall.sh /tmp/w out.txt` (about 1 minute with 8 cores).

Limits:
- The bench bus is 16 bit with DSACK1, about 4 clocks per cycle at WS0. The manual assumes two-clock 32-bit reads
  and writes, so rows with operand cycles (memory EA, stack, MOVEM) are not directly comparable.
  The register-only and branch rows are comparable.
- MUL/DIV rows are maximum times in the manual. The harness operands are data dependent.
- `delay_loop8` is the Linux `__delay` loop: moveq, then 8 passes of subq.l/bcc.s, then the exit. The manual figure is 72.

## Baseline (main 528aea1) and the F140 prototype

| Test | Manual (I-cache case) | Baseline 528aea1 | F140 prototype | Note |
|---|---|---|---|---|
| `nop` | 2 | 3.00 | 3.00 |   |
| `moveq` | 2 | 4.00 | 4.00 |   |
| `move.l_Dn_Dn` | 2 | 4.00 | 4.00 |   |
| `movea.l_Dn_An` | 2 | 3.00 | 3.00 |   |
| `move.w_Dn_(An)` | 3 | 7.00 | 7.00 | mem write  |
| `move.w_(An)_Dn` | 5 | 10.00 | 10.00 | fea (An) 3 + move 0..2  |
| `move.w_Dn_(An)+` | 3 | 7.00 | 7.00 | mem write  |
| `move.w_(An)+_Dn` | 5 | 10.00 | 10.00 |   |
| `move.w_Dn_-(An)` | 4 | 7.00 | 7.00 |   |
| `move.w_d16(An)_Dn` | 6 | 12.00 | 12.00 |   |
| `move.w_Dn_d16(An)` | 4 | 9.00 | 9.00 |   |
| `move.w_d8(An,Xn)_Dn` | 8 | 12.00 | 12.00 |   |
| `move.l_#imm_Dn` | 4 | 9.00 | 7.00 | fiea #.L 4  |
| `add.l_Dn_Dn` | 2 | 4.00 | 4.00 |   |
| `add.w_(An)_Dn` | 5 | 10.00 | 10.00 | fea 3 + 2  |
| `add.w_Dn_(An)` | 6 | 14.00 | 14.00 | fea 3 + 3  |
| `adda.l_Dn_An` | 2 | 4.00 | 4.00 |   |
| `adda.w_Dn_An` | 4 | 4.00 | 4.00 |   |
| `cmp.l_Dn_Dn` | 2 | 3.00 | 3.00 |   |
| `cmpa.l_Dn_An` | 4 | 3.00 | 3.00 |  FASTER than manual (bug) |
| `addq.l_Dn` | 2 | 4.00 | 4.00 |   |
| `subq.l_Dn` | 2 | 4.00 | 4.00 |   |
| `addi.l_Dn` | 6 | 10.00 | 6.00 | ADDI 2 + fiea #.L 4 (4+op head)  |
| `and.l_Dn_Dn` | 2 | 4.00 | 4.00 |   |
| `eor.l_Dn_Dn` | 2 | 4.00 | 4.00 |   |
| `or.l_Dn_Dn` | 2 | 4.00 | 4.00 |   |
| `clr.l_Dn` | 2 | 4.00 | 4.00 |   |
| `neg.l_Dn` | 2 | 4.00 | 4.00 |   |
| `not.l_Dn` | 2 | 4.00 | 4.00 |   |
| `ext.l_Dn` | 4 | 4.00 | 4.00 |   |
| `swap` | 4 | 4.00 | 4.00 |   |
| `tst.l_Dn` | 2 | 3.00 | 3.00 |   |
| `scc_Dn` | 4 | 4.00 | 4.00 |   |
| `lsl.l_#_Dn` | 4 | 6.00 | 6.00 |   |
| `asl.l_#_Dn` | 6 | 7.00 | 7.00 |   |
| `asr.l_#_Dn` | 4 | 6.00 | 6.00 |   |
| `ror.l_#_Dn` | 6 | 7.00 | 7.00 |   |
| `lsl.l_Dx_Dn` | 6 | 7.00 | 7.00 |   |
| `roxl.l_Dn` | 12 | 13.00 | 13.00 |   |
| `mulu.w_Dn_Dn` | 28 | 30.00 | 30.00 | max  |
| `muls.l_Dn_Dn` | 44 | 46.00 | 46.00 | max (fiea none: Dn)  |
| `divu.w_Dn_Dn` | 44 | 46.00 | 46.00 | max  |
| `divs.l_Dn_Dn` | 90 | 92.00 | 92.00 | max  |
| `lea_d16(An)` | 2 | 6.00 | 5.00 |   |
| `lea_d8(An,Xn)` | 4 | 6.00 | 5.00 |   |
| `bra.w_taken` | 6 | 11.00 | 10.00 |   |
| `bra.s_taken` | 6 | 11.00 | 10.00 | skipped nop not run  |
| `beq.s_not` | 6 | 11.00 | 11.00 | Z clear, incl. nop 2  |
| `beq.w_not` | 6 | 11.00 | 10.00 |   |
| `bfextu` | 10 | 13.00 | 13.00 |   |
| `btst_#_Dn` | 4 | 6.00 | 4.00 |   |
| `bset_Dn_Dn` | 6 | 7.00 | 7.00 |   |
| `bsr_rts` | 15 | 32.00 | 30.00 | BSR 6 + RTS 9 (stack long on 16-bit port)  |
| `jsr_rts` | 13 | 32.00 | 30.00 | JSR 4 + jea (An) 0 + RTS 9  |
| `pea_(An)` | 4 | 11.00 | 11.00 |   |
| `dbf_loop8` | 54 | 107.00 | 85.00 | moveq 2 + 7x DBcc taken 6 + expired 10  |
| `delay_loop8` | 72 | 110.00 | 102.00 | Linux __delay: moveq 2 + 8x(subq 2+Bcc taken 6) + subq 2 + Bcc.B not taken 4  |


Summary of the baseline:
- Every register-to-register single-word instruction takes 3 to 4 clocks; the manual gives 2.
- Taken branches take 11 clocks against 6, and the Linux delay loop takes 13.75 clocks per pass against 8 (110/8).
- Only one instruction is faster than the manual: `CMPA.L Rn,An`, 3 against 4. That is a bug by the cycle-exact rule.

## Root causes (RTL evidence, GHDL waveform of a cached MOVEQ stream at WS0)

1. **Instruction issue loop of 3 clocks plus a hazard clock.**
   - The control unit asserts OW_REQ in START_OP. The decoder answers with a registered OPD_ACK one clock later
     (opcode_decoder HANDSHAKING).
   - The control unit then latches OW_RDY, goes to INIT_EXEC_WB, and only after that returns to START_OP and raises
     OW_REQ again (control.vhd OW_REQ, FETCH_DEC START_OP).
   - Minimum: 3 clocks per instruction.
   - For MOVEQ/EXT/SWAP/DBcc and the Dn-destination ALU group, FETCH_DEC also waits while `DR_IN_USE` is set by the
     previous instruction's writeback. This happens even when the new instruction only writes that register: MOVEQ
     has a write-after-write case only. That adds the 4th clock (MOVEQ, MOVE.L Dn,Dn, ADD, SUBQ, AND... all 4.00).
   - A 68030 issues these in 2.
2. **Opcode words reach the decoder pipe one per 2 clocks.**
   - `OPCODE_RD_I` (decoder P_BSY) is cleared asynchronously by OPCODE_RDY and set again on the next edge.
   - The bus interface serves a queue hit only when `OPCODE_RDY_I = '0'` (Q_HIT).
   - The I-cache itself delivers a whole long into the queue in one clock (IC_TAKE). So multi-word instructions and
     every refill after a change of flow pay 2 clocks per word. Examples: MOVE.L #imm 9 against 4, ADDI.L 10 against 6,
     LEA d16 6 against 2, BTST # 6 against 4.
3. **Branch restart.** BRA/Bcc taken takes 11 clocks against 6, and DBcc in a loop about 13 against 6.
   - The branch goes INIT_EXEC_WB, then SLEEP, then a flush.
   - About 3 clocks pass before the new OW_REQ.
   - Then the pipe needs two words (PIPE_RDY needs IPIPE_PNTR > 1 for level D), which at 2 clocks per word (cause 2)
     costs another 4.
4. **Single-word ALU ops in the EXEC_WB unit** (shifts, MUL/DIV, BFEXTU) are only 1-2 clocks above the manual. That is
   mostly the issue overhead of cause 1, not the ALU.

## F140 prototype (not merged; `F140_b2b_prototype.patch`, in docs/ for reference, not applied)

The prototype addresses cause 2:
- `OPC_RD_NEXT` from the decoder: in an OPCODE_RDY clock, the next word is wanted too if IPIPE_PNTR < 2 and there is
  no flush, exception or loop.
- `Q_HIT` serves it from the queue when the head matches PC_L + 2.

Results:
- MOVE.L #imm 9 → 7, ADDI.L 10 → 6 (manual), LEA d16 6 → 5, BTST # 6 → 4 (manual).
- Taken branch 11 → 10, DBF loop 107 → 85, delay loop 110 → 102.

Gates: `run_rtl.sh` fails two of them, so the prototype is not committed.
- `run_icache`, CIMODE=1: cases 2/9/10/11/21/25 fetch one more long of the loop line (prefetch count 6 → 8).
  The faster pipe drains the queue earlier, so the stream prefetches a further long past the loop's RTS.
  That is a change in bus-cycle placement.
- `prog_mmut`: some blocks get faster but block 2 gets slower (35.88 → 42.75).
- Everything else passed.

## Plan

1. Rework cause 2 so the queue refill threshold (PF_REQ_RAW, Q_CNT) is unchanged, so the bus placement stays as before.
   Reach the expected prefetch counts first, then the faster delivery.
2. Cause 1: OW_REQ for the next instruction in INIT_EXEC_WB, so ACK(N+1) arrives in the clock after INIT(N).
   - Interrupts and trace are triggered in INIT_EXEC_WB (INT_TRIG), so OW_REQ must stay off while an exception is
     about to be taken.
   - Drop the DR_IN_USE wait for pure write-after-write (MOVEQ, CLR Dn, MOVE to Dn with another source).
   - Then match the manual's 2 clocks.
3. Cause 3: start the target fetch when the branch resolves, and let PIPE_RDY take a level D instruction with one
   word when it is a single-word opcode.
4. Slow outliers (BSR/JSR/RTS, PEA, Scc, shifts), then the fast bug: CMPA.L Rn,An 3 → 4.
Each step needs the full `run_rtl.sh`, the `/workspace/simall` process(all) variant and a Gowin V1.9.12.03 build
(clk_cpu030 >= 16 MHz, timing_pairs).

## Progress log (overnight, UK time)

- 2026-11-04 00:10: F140 (back-to-back opcode read from the queue, fetch counts preserved: stale sequential prefetch is blocked while the decoder asks for an address the queue head does not match) plus F141 (early OW_REQ in INIT_EXEC_WB for register-only ops, gated by TRACE_MODE="00" and the new IRQ_HOT; MOVEQ no longer waits on an overwrite-only DR_IN_USE hazard; in the register file, a new in-use mark now wins over a release in the same clock). Both are uncommitted while run_rtl runs. Backup: /workspace/speedh/wip_f140_f141.patch.
- Harness (clocks/instr, manual / base / now): moveq 2/4/3, cmp.l 2/3/2.38, tst.l 2/3/2.38, move.l #imm 4/9/7, addi.l 6/10/6, lea d16 2/6/5, btst # 4/6/4, bra 6/11/10, bsr+rts 15/32/30, dbf_loop8 54/107/79, delay_loop8 72/110/101.
- Open bug: cmpa.l Dn,An is 3, but the manual says 4 (faster than the manual). CMPA is excluded from early issue. Step 4 will fix it.
- 2026-11-04 01:45 UK: WIP is safe on branch speed-wip (05f1121). The Gowin V1.9.12.03 build of F140+F141 (/workspace/bld141) gives clk_cpu030 20.069 MHz (f132: 20.869), clk32_core 33.885 MHz, 45892 LUT + 5330 ALU, timing_pairs rc=0, fs md5 5734c25d. The first run_rtl had one failure, prog_mmut: every block is faster, all still slower than the manual floors. expect_mmut.txt has been updated, and run_rtl plus simall are re-running.
- 2026-11-04 01:50 UK: F140+F141 gates PASS: run_rtl.sh (bus-error/restart F122-F131 included), the simall process(all) variant, and timing_pairs. Committed to speed.
  Harness clocks/instr (manual / base / F141):
  moveq 2/4/3, cmp.l 2/3/2.38, tst.l 2/3/2.38, move.l #imm 4/9/7, addi.l 6/10/6, lea d16 2/6/5, btst # 4/6/4,
  bra 6/11/10, bsr+rts 15/32/30, dbf_loop8 54/107/79, delay_loop8 72/110/101.
  Open bug: cmpa.l is 3, the manual says 4.
- 2026-11-04 01:55 UK: board step blocked. ssh linserver fails: linserver itself is offline on the tailnet (correction: not the PC). The bld141 bitstream is ready (impl/pnr/st_helper.fs, md5 5734c25d) and has passed timing_pairs. It has not been loaded. The board is unchanged: f132 in SRAM, f131 in flash.
- 2026-11-04 02:45 UK: F142 (CMPA Rn,An gets one extra START_OP clock; 3 -> 4 = manual, which removes the faster-than-manual bug). The harness shows no other change. Regressions run on a snapshot (/workspace/snap142), so source edits can continue. WIP is on speed-wip. linserver is still offline.
- Step 3 analysis: a taken Bcc goes START_OP -> INIT_EXEC_WB (ALU) -> SLEEP (condition) -> flush/PC load -> START_OP, then the target opcode comes from the cache: 10 clocks against the manual's 6. Getting to 6 needs the condition decided and the target fetch started in START_OP/INIT_EXEC_WB (BRA/BSR unconditional, Bcc when the CCR is not pending), with trace and IRQ handled as in F141 (IRQ_HOT).
- 2026-11-04 03:08 UK: F142 gates PASS (run_rtl incl. F122-F131, simall). Committed. cmpa.l is now 4 (manual 4). No harness row is faster than the manual.
