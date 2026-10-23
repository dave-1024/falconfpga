# Bugs: fixed and still open

Plain-English list for the 68030 ST core (`Atarist_030_wip`). Sources: `Atarist_030_wip/docs/FALCON_LESSONS.md`,
`HISTORY.md`, `TODO.md`, `docs/history/investigations/float_panic/FLOAT_PANIC.md` and the TT-RAM work log (21 Oct 2026). Where a source does not
say something, it is marked **TODO** or **(unsure)**.

## Fixed

| ID | What it did | Cause | Fix | Commit | Date |
|---|---|---|---|---|---|
| [C10] I-cache block-RAM read-during-write (**the caches-on TT-RAM crash**) | TT-RAM, caches on: wrong opword at a 4n+2 branch target in the long just filled (TTM1 SP -2 slip, EXC 2 at PC `$FFC60100`; FrontBench prgflags 7 black screen) | Gowin mapped DATA_RAM to SDPB (synchronous read, no write-through); the lookup one clock after a fill of the same long returned the old long (`3F3C` instead of `5888` at `$010001CE`). RTL sim cannot show it (asynchronous read in RTL) | Write-to-read forwarding register in WF68K30L_ICACHE, no switch. Release build tt20: TTM1 caches on/off pass, FrontBench prgflags 7 caches on runs 900 s, lastcount **1362** (caches off 1169, ST-RAM 990) | 71624aa | 21 Oct 2026 |
| [C8] ST DSACK/AVEC/BERR registered | Failing timing path in every build (half-cycle s_tag -> DSACKn -> MOVEM_INH_WR -> AR_IN(SP) -> ADR_EFF_I) | Raw ST terminations fed the CPU combinationally | ST terminations go through clk_cpu flops cleared by AS (like the TT ones, C5). Correctness/timing fix; not the TT-RAM cause | 58f15a5 | 21 Oct 2026 |
| CHK2_RN sensitivity list (+ audit) | `wf68k30L_alu.vhd:1371` COND_CODES: CHK2/CMP2 Z flag. RTL simulation could differ from the synthesized netlist (Gowin EX4749) | `CHK2_RN` missing from the combinational process's sensitivity list. The audit also found `OPC_ADR` missing in BUS_IF BUS_CTRL_DEC and `MOVEM_FIRST_RD` in CONTROL FETCH_DEC (MOVEM memory-to-register) | Added the signals to the sensitivity lists. Hardware unchanged (synthesis already builds them combinationally). **Not** the TT-RAM cause for CHK2_RN: no test uses CHK2/CMP2 | d626164 | 21 Oct 2026 |
| [C2] CMPA.W | EmuTOS found no TT-RAM (it stopped sizing at once, ramtop 0) | `CMPA.W` set its flags from bit 15 instead of the full 32-bit address register. EmuTOS's loop `cmpa.w #0,a2; bgt` with a2 = `$010FFFFF` failed | Flags now from all 32 bits (`wf68k30L_alu.vhd`) | `f73d42d` | 21 Oct 2026 |
| TT_RV_MASK ($5A8) | EmuTOS skipped its TT-RAM probe | `_ramvalid` ($5A8) / `_ramtop` ($5A4) still looked valid, so EmuTOS took the warm path and didn't probe | `TT_RV_MASK=1` hides $5A8 after each load so EmuTOS always probes. With [C2], the boot screen shows "Alt-RAM 16 MB" (5/5 loads) | `f73d42d` (with C2) | 21 Oct 2026 |
| [C3] false address error | Code running from TT-RAM with caches on got a false "address error" (vector 3) on an odd data address | The odd-address check used the data address instead of the instruction address when a D-cache hit dropped the read request | Use `OPC_ADR(0)` in `wf68k30L_bus_interface.vhd`; RTL regression PASS | `af5930a` | 21 Oct 2026 |
| [C4] BUS_WIDTH | Suspected of causing the caches-on TT-RAM crash | Bus width was taken from the raw DSACK input (a −2.6 ns timing path) | Registered. Built as tt13 (clk_cpu030 22.02 MHz). **Did NOT fix the board crash**: the TTM result was identical. Kept as a correctness fix | `a96f3aa` | 21 Oct 2026 |
| JSR SP writeback (F62d) | Crash when a program quits; GEMBENCH menu freeze | In `ADDA.W #16,SP; JSR (d16,PC)` both changes to A7 landed in the same clock and one was lost | JSR waits for a pending A7 write, like BSR already did | `79f5951` / `75bfc8c` | TODO (date not in source) |
| CHK operand (F60) | Spurious CHK traps (GEMBENCH 6 "Subscript out of range") | CHK compared against A0 instead of the data register | CHK reads Dn | `87fac46` | TODO |
| Reset synchronisers | Timing failures (recovery/removal −5 to −8 ns); one placement gave a dead helper | Raw power-on reset went straight into other clock domains | 3-flop synchronisers; clk_osc loads on a global buffer | `382524f` | TODO |
| GEMBENCH Float Math panic (gb403) | Float Math crashed (looked like a CPU bug for days) | **Not the core.** The floppy image on the SD card was corrupt (desktop INF text written into AUTOFPU.BIN) by the runtime disk-swap bug | Clean image + `ST_FLOPPY_MEDIACH` (`7df7f29`). Float Math passes | `7df7f29` | closed 15 Oct 2026 |
| Mailbox lost byte (helper) | Lost characters in the cartridge/helper mailbox | RX ring not drained while transmitting | Drain while sending | `3e0d6b8` | TODO |

## Open

| Bug | Symptom | What we know | Next step |
|---|---|---|---|
| Worst timing path | Negative slack on tt20: **-4.89 ns**, path MOVEM_INH_WR -> AR_IN -> ADR_EFF_I (SP write-back) | Fmax still meets the rule (clk_cpu030 22.42 MHz >= 17 MHz; clk32 33.38 MHz) and the board passes, but the path is the worst in the design | Look at the SP write-back path |
| Tests not rerun on tt20 | I-cache-only, D-cache-only, TTW and TTE tests passed on tt19 (I/D-only) but were not rerun on the release build tt20 | tt20 = tt19 minus the debug ring | Rerun on tt20 |
| tt19 debug-ring video dropouts | With the TT_RING/STR debug logic built in (tt19) HDMI and the OSD often went black | Build-specific: tt17 (14/15 good grabs) and tt20 are stable. Debug ring stays a commented-out option in `build_st_helper.tcl` | Keep debug builds separate from release; root cause not looked at |
| Warm-reset "System halted!" | Sometimes halts after the cartridge self-test on reload (op 1) or warm reset (`w`); the helper `c` command (sysctrl reset R=3) or a power cycle clears it | Pinned since 16 Oct 2026. Rate changes with build (0/27 to ~3/10); clk32 margin only 0.04 MHz, so it looks timing-related **(unsure)**. Evidence on branch `warm-reset` @ `65e8b32`, `docs/RESET_PATHS.md` §7-9 | Pinned; no work for now |
| SD write path | (Lead left open after the float-panic hunt) | The float panic itself was the image, not the SD write path. Write jam was fixed by `ST_SD_WRITE_FIX`/`ST_SD_HARDEN` | TODO: no open SD write bug is listed in TODO.md. Confirm whether this lead is still needed |
| HDMI after flash | Picture often doesn't come up until about 3 reloads after a flash | Seen repeatedly (e.g. TT1 capture: black after reload) | Not investigated yet |
| Mailbox byte loss (again) | One lost character once on tt6 ("hello from the T") | Seen once after the `3e0d6b8` fix; the next boot was fine (17 bytes OK) | Watch for repeats |
| PMMU opcodes | PMMU instructions trap to Line F (the core has no PMMU) | **(unsure: not stated in these words in the sources)** PMMU is a planned later step, in HDL; needed for TOS 3/4 (PMOVE) | PMMU work (TODO.md item 4) |
| Operand idle clocks | Slower than a real 68030 in some instructions | E.g. memory-indirect ~10 idle clocks after the operand read (JSR ([bd,An]) 77 vs 28 clocks); CAS2 has idle clocks inside its locked sequence | Exact-timing work in TODO.md |


Release build tt20 (71624aa, 21 Oct 2026): clk32 33.38 MHz, clk_cpu030 22.42 MHz, worst slack -4.89 ns, 41127 LUT + 5036 ALU.

## Planned / later

| Item | Notes |
|---|---|
| Helper TT-RAM on/off option | TT-RAM is built in by default (`TTRAM` in the build script, no switch to set). An on/off option will be added to the helper (OSD/console) later |
