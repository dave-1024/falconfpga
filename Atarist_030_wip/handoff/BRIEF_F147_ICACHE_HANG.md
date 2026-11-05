# Brief: F147 hangs on the first I-cache-on delay loop (board only)

Repo `falconfpga`, branch `speed`, commit **a8dd216** (F147). Core `Atarist_030_wip/hdl/cpu030`.
David pastes this into Grok chat. **Ask David to attach these five files from a8dd216** (do not invent surrounding code):
`wf68k30L_bus_interface.vhd`, `wf68k30L_opcode_decoder.vhd`, `wf68k30L_pkg.vhd`, `wf68k30L_top.vhd`, `wf68k30L_icache.vhd`.

## Goal of F147
Save 1 clock on change-of-flow refill after F144 `IC_MTAKE`: when the prefetch queue already holds two words, deliver both in one `OPCODE_RDY` clock (`OPCODE_RDY_2`). Never faster than MC68030UM §11. Restart-only (first queue hit after `IC_MTAKE`).

## What a8dd216 actually does (not Grok v3 as-submitted)
Deviations from Grok chat's v3 patch, applied on speed:

1. **`RESTART_PEND` own process** (`bus_interface`): set by `IC_MTAKE`, cleared by any `OPCODE_RDY_I` or `RESET_CPU_I`. Grok v3 used a non-existent `IPIPE_FLUSH` in the bus interface and only cleared after a two-word delivery.
2. **`Q_HIT2`**: `Q_HIT and OPCODE_RDY_I='0' and RESTART_PEND and Q_CNT>=2 and Q_C(1)='1'`. Two-word pop: `CNT-2`, `Q_ADR+2`, shift by two; `OPCODE_RDY_2_I <= Q_HIT2` with `OBUFFER_2` / `OPCODE_VALID_2_I`.
3. **Fetch address in the decoder, not address_registers**: Grok's `PC_L <= PC_L+4` was wrong (`PC_L` is `PC + PC_ADR_OFFSET`). a8dd216 advances `ADR_OFFSET` by `"10"` when `OPCODE_RDY_2_I` (with/without `PC_INC_I`).
4. **`OPCODE_FLUSH` gate**: `OPCODE_RDY_2_I <= '0' when OPCODE_FLUSH else OPCODE_RDY_2`. `OPC_RD_NEXT` blocked when `OPCODE_RDY_2='1'`.
5. Pipe fill only in the plain-fill case: `IPIPE_PNTR` 0→2 / 1→3. Ports wired in pkg/top. EARLY_ISSUE (F145) untouched. `expect_mmut.txt` re-pinned (DBF overhead ~0.5–0.9 clk faster).

## Board symptom (F147 flashed at address 0)
AUTO LOOPTEST (`lta1.st`), two cold boots:

| Mode | F147 | F145 |
|---|---|---|
| ST-RAM (all cache modes) | 216684 | 216684 |
| TT-RAM caches off | 557103 | 557103 |
| **TT-RAM I-cache on** | **hangs** (blank after colon, 4+ min) | 1307189 |
| TT-RAM I+D | never reached | 1307189 |

Cache-off path matches F145 → F147 path only fires with a real I-cache hit (`IC_MTAKE` / `Q_C`). The hang is the Linux `__delay` loop (`subq.l #1,d0; bne.s`) running from TT-RAM with I-cache on — every taken Bcc is a COF refill.

Board recovered: re-flashed `st_helper_f131.fs` at 0. F147 `.fs` kept as `~/st_helper_147.fs`.

## Sims all pass (hang not reproduced)
- Speed table: bra.w taken unchanged (7); bsr_rts 29→28; jsr_rts 29→28.5; dbf_loop8 72→69.5; delay_loop8 94→90.5. Not-taken Bcc also 9→7 (unexpected). Nothing below manual.
- grpb SAME (seeds 11/22, WS 0/3, CIMODE 0/1; seed 33 user-mode).
- irq: irqchk / smc_tt / smc_st / loopmode identical to F145 (CIMODE 0/1).
- `run_rtl.sh` pass after expect_mmut re-pin.
- Build: clk_cpu030 **19.515 MHz** (F145 ~21.3; floor 16), 46380 LUT + 5330 ALU, timing_pairs clean.

## Suspects (ranked examination order)
1. **`IC_MTAKE` / `RESTART_PEND` vs a real I-cache hit stream** — flag set every `IC_MTAKE`, cleared on first `OPCODE_RDY`; wrong if a second restart or a non-restart `IC_MTAKE` overlaps a Q_HIT2.
2. **Second word when the cache line / long ends** — F144 loads 1 or 2 words by `OPC_ADR(1)`; `Q_C(1)` gates Q_HIT2, but after a two-word pop does the next fill see stale `Q_W(1)` / wrong `Q_ADR`?
3. **`ADR_OFFSET` +2 vs `OPC_ADR`/`PC_L` with F140 `OPC_RD_NEXT`** — blocked in the RDY_2 clock, but the clock after?
4. **Loop-mode / DBcc / delay-loop Bcc path** — `LOOP_BSY` / `LOOP_ATN` leave the plain-fill branch; a Q_HIT2 that the decoder ignores drops a word.
5. **Interaction with F144 `IC_MISS_LK` / `COF_BLK` and F145 `EARLY_ISSUE`** — should be untouched; confirm no accidental enable of two-word on early OW_REQ.
6. **Fmax / placement** — clk_cpu030 dropped 21.3→19.5; board-only like F141/F146.
7. **Bench vs board cache timing** — sim `CIMODE=1` may not model the board's TT-RAM I-cache refill cadence that trips the bug.

## Deliverable
1. Most likely root cause, with reasoning tied to **specific lines** in the attached files.
2. A **complete unified diff against a8dd216** that compiles (`ghdl -a` order: pkg → bus_interface → address_registers → opcode_decoder → top). Tag `[F148]` (or a corrected F147), keep licence headers, complete sensitivity lists, leave EARLY_ISSUE alone.
3. A **sim test** (tb030 program or speed-harness variant) that would reproduce the hang — ideally the `__delay` loop from TT-RAM-like cached space with CIMODE=1, or a tighter COF+I-cache stress. Say what to look for (lock-up, wrong PC, dropped word).
4. State assumptions explicitly; do not invent signals.

Ask David to attach the five VHDL files before you patch.
