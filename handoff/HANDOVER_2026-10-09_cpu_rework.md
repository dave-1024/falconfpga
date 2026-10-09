# HANDOVER 2026-10-09: WF68K30L bus request handoff rework (for Grok chat and David)

This file is self-contained. You (Grok chat) cannot see David's box, laptop or
board. You only see this GitHub repo and whatever David pastes. David is new to
Git, so every command below is given in full. Paths are relative to the repo
root unless they start with `C:\` (David's Windows laptop).

---------------------------------------------------------------------------
## 1. Overview

### 1.1 Project
An Atari ST (MiSTery/MiSTeryNano-derived) in an FPGA, where the 68000 has been
replaced by a 68030 soft core (WF68K30L, by Wolfgang Foerster) running TOS 2.06
on a real-ST-timed bus. The goal is "a real 68030 accelerator board (like a
TF536) on an ST bus": no compatibility hacks, no posted writes, ST timing
faithful (GSTMCU/shifter slot timing untouched).

### 1.2 Hardware
- Sipeed **Tang Console 138K** (Gowin GW5AST-138B, device string `GW5AST-138B`).
- **AE350** RISC-V hard core in the FPGA = the "helper" (SD card, floppy images,
  loader). Its firmware is in `Atarist_030_wip/helper_fw/` and lives in flash at
  0x600000. TOS lives in flash at 0x500000.
- **BL616** (on-board USB/JTAG MCU): has **never been reflashed**. Do not touch it.
- Output via HDMI; keyboard/mouse via the helper; David controls the board from
  his laptop (TeraTerm on COM4, capture card screenshots).

### 1.3 Repo layout (after the 2026-10-09 hdl/ move, commit 902480d)
```
Atarist_030_wip/
  build_st_helper.tcl        main build (Gowin gw_sh); writes the `defines
  build_tc138k.tcl, build_ae350_serial.tcl   other builds
  hdl/atarist  hdl/cpu030  hdl/fdc1772  hdl/fx68k  hdl/gstmcu  hdl/hdmi
  hdl/helper   hdl/ikbd    hdl/jt49     hdl/misc   hdl/tang  hdl/misterynano.sv
  hdl/tang/console138k/build_sel.vh   generated `define file (do not edit by hand)
  hdl/cpu030/wf68k30L_*.vhd           the 68030 core (VHDL)
  hdl/cpu030/cpu030_st_bridge.v       030 bus -> 68000-style ST bus bridge
  hdl/cpu030/sim/rtl/                 GHDL core bench (run_rtl.sh)
  hdl/cpu030/sim/st/                  Icarus whole-ST bus bench (run_bus.sh)
  hdl/cpu030/sim/wf030_syn.tcl        netlist synthesis for run_bus.sh
  helper_fw/                          AE350 firmware
  docs/                               see 1.4
handoff/                              patches + notes exchanged with chat AIs (this file)
misterynano_tc138k/                   older non-030 project, reference only
```

### 1.4 Docs map
| File | What |
|---|---|
| `Atarist_030_wip/README.md` | status, results, known issues, doc map |
| `Atarist_030_wip/docs/BUILD.md` | how to build and flash |
| `Atarist_030_wip/docs/HISTORY.md` | F-number history (what each fix did) |
| `Atarist_030_wip/docs/TODO.md` | open work; this task is at the top |
| `Atarist_030_wip/docs/ST_HELPER.md` | helper design, URGENT TODO block at top |
| `Atarist_030_wip/docs/DIAG_OVERLAY.md` | on-screen debug overlay |
| `Atarist_030_wip/docs/notes/RAM_PATH.md` | **the analysis behind this task** |
| `Atarist_030_wip/docs/notes/TF536_NOTES.md` | how a real TF536 behaves |
| `Atarist_030_wip/docs/notes/DEBUG2.md` | board debug notes |
| `Atarist_030_wip/docs/notes/SPI_SDC.md` | SD/SPI notes |

---------------------------------------------------------------------------
## 2. Current state

- **main = 3ae221e**, tagged **`rollback-2026-10-09-eas`** (annotated, pushed).
- Board runs **`st_helper_eas_d43f5fd_p3.fs`**
  SHA256 `cb7a96320e1e4f18921a297309b2b66e3ae22c7871e23f53a049e7a39aca14eb`
  (built from d43f5fd, same HDL as 3ae221e; a fresh 3ae221e build has a
  different hash but identical timing).
- Fallback: `st_helper_f62d_rb_75bfc8c_p3.fs`
  SHA256 `2d4c2a1031d2f677c5825ea9de11e9fdc6a7ddbc4c43797f28bb533a438a780c`.
- Older reference: `st_helper_main_382524f.fs` (SHA256 starts d4f19cfda54d11b2).
- Copies + `SHA256SUMS.txt` in `C:\Users\dave_\fpga_rollback_20261009\`.
- Timing of the board build (place_option 3): TNS 0 on all clocks; worst slack
  clk32 32.037 MHz-path ok, cpu030 16.985 ok, recovery +7.974 ns, removal +0.256 ns.

### 2.1 GEMBENCH history (100% = real ST 8 MHz 68000)
| Build | RAM | ROM | Display | CPU | Avg |
|---|---|---|---|---|---|
| F60 | 48 | 60 | 31 | 120 | 61 |
| F63 | 61 | 69 | 37 | 137 | 71 |
| F62d (fallback) | 76 | 85 | 72 | 225 | 112 |
| **early AS d43f5fd (now)** | **86** | **86** | **74** | **230** | **115** |

RAM/ROM < 100% means the 030 at 16 MHz is still slower than a 68000 at memory
access. That is this task.

Rollback point and HISTORY row for F62d: commit 75bfc8c (bench 76/85/72/225/112).

### 2.2 Known issues
- GEM dialog OK/Cancel mouse clicks sometimes lost (keyboard Return works).
- Blitter disabled under TOS 2.06.
- Helper SD write timeout (writes to SD image unreliable).
- Gowin place_option sensitivity: 3 is good, 1 is ok, **2 fails/unstable - avoid**.
- PR1014 warning on the pad->DCE hop (understood, harmless).
- MISO pad constraint warning (understood).

---------------------------------------------------------------------------
## 3. THE TASK: let the WF68K30L issue the next bus request without idle clocks

### 3.1 The finding (2026-10-09 13:35)
Between two bus transfers the core's bus interface FSM goes
`DATA_C1C4 -> IDLE -> START_CYCLE` (`wf68k30L_bus_interface.vhd:530-568`, back to IDLE at `:565-566`), costing 2 extra clk_cpu (16 MHz, 62.5 ns
each). AS->AS gap between separate transfers: **156 ns** (5 clk32). Inside one
dynamically sized long (two 16-bit halves) it is only **31 ns**. Why:

1. `hdl/cpu030/wf68k30L_top.vhd:744-764` (process P_BUSREQ): RD_REQ / WR_REQ /
   OPCODE_REQ to the bus interface are forced to 0 while BUS_BSY = 1
   ("We need these flip flops to avoid combinatorial loops").
2. `hdl/cpu030/wf68k30L_bus_interface.vhd:908-923`: DATA_RDY (and opcode RDY)
   is registered on the same edge that ends the cycle; BUS_CYC_RDY comes at
   T_SLICE S5 (`:1018-1020`). So the control unit only sees "done" after the
   cycle, then issues the next request, then the FSM passes IDLE, then
   START_CYCLE.
3. Logic keyed on BUS_CTRL_STATE = START_CYCLE (all must keep working if
   START_CYCLE is entered directly from DATA_C1C4 or skipped):
   - `:287` ACCESSTYPE latch
   - `:414` WP_BUFFER (write data buffer)
   - `:455` SIZE_N
   - `:604` ADR_OFFSET
   - `:622` AERR_I (address error)
   - `:645` PF_START (prefetch start)
   - `:692` instruction-queue write flush
   - DSACK_MEM, SLICES `:948-960`
   - T_SLICE S0..S5, ASn low in S0..S4 (`:1006`).

### 3.2 Why only removing IDLE gives 0 gain: the 62.5 ns window
- The bridge (`hdl/cpu030/cpu030_st_bridge.v`) starts a 68000 S0 only on
  `enPhi1` (mhz8_en1), `:541` "accept the 030 request: 68000 S0"; AS at S2
  (or at the S0 en2 for ST RAM with BRIDGE_EARLY_AS, `:476-481`).
- The GSTMCU grants the CPU a RAM slot once per 500 ns, latched at cycsel_en
  (`hdl/gstmcu/hdl/mcucontrol.v:182-188`, DTACK in `gstmcu.v:554`). This is
  faithful to the real ST and must not be changed. Video never steals CPU
  slots; video on/off timing is identical.
- Result: the next request must reach the bridge **within 62.5 ns after the ST
  AS rises** to catch the next slot. Today it arrives 156 ns after; skipping
  only IDLE makes it 94 ns: still too late, same slot, **0 gain**. It must be
  ~31 ns (like inside a long), i.e. remove **both** clocks.

### 3.3 What a real 68030 does
A real MC68030 starts S0 of the next cycle directly after S5 when a request is
pending; AS is negated only about one clock between cycles (MC68030UM ch. 7).
So removing both clocks is the real behaviour, not a hack.

### 3.4 Numbers (RAM_PATH.md, slot model slotsim.py, code in ST RAM, µs)
| Test | base (F62d) | early AS measured | core -2clk (model) | core -2clk + early AS (model) | 68000 ideal |
|---|---|---|---|---|---|
| rd.l loop | 363 | 315 | 276 (+32%) | 267 (+36%) | 216 |
| wr.l loop | 384 | 328 | 281 | 273 | 216 |
| copy | 579 | 523 | 475 | 443 | 344 |
| dbra loop | 387 | 323 | 291 | 275 | 192 |
ROM code: +10-15% from the core change. The model reproduced all
measurements exactly. David expects the CPU fix **alone** (BRIDGE_EARLY_AS off)
to reach about 100% GEMBENCH RAM.

Other limiters (not this task): no I-cache (CACHES=0, `wf68k30L_top.vhd:167`),
the prefetch queue over-fetches past taken branches, real CPU idle 9-15%.

### 3.5 Constraints
- **No combinational loops** (the reason for the P_BUSREQ masking). New paths
  must be registered or provably acyclic; Gowin must report no loops.
- Keep F62/F62b/F62d prefetch behaviour (see glossary), including the
  documented F62b deviation (in HISTORY.md / ST_HELPER.md).
- Keep the JSR fix and the CHK fix (both covered by run_rtl.sh).
- cpu030 clock must still meet timing (16 MHz, currently 16.985 MHz worst).
- Must be a `define switch (e.g. `` `define WF030_FAST_HANDOFF ``) with the
  old behaviour kept, so it can be A/B tested; BRIDGE_EARLY_AS stays switchable
  independently so the CPU fix can be measured alone.

### 3.6 Suggested approach
1. Let the control unit see "cycle will end" one clock earlier: generate an
   early ready (e.g. from T_SLICE = S3/S4 with DSACK seen) as a registered
   signal, instead of DATA_RDY at S5. Data itself must still be latched at the
   real end.
2. Let P_BUSREQ pass a request while BUS_BSY if the current cycle is in its
   last slice (registered, no loop), and let the FSM go DATA_C1C4 ->
   START_CYCLE (or directly to S0 with START_CYCLE work done in parallel).
3. Make every START_CYCLE-keyed latch (list 3.1) also fire on the direct path.

Pitfalls:
- Freeze history: when the pipeline stalls, latched operands/addresses must not
  move ahead of the bus.
- Stale state on prefetch restarts (branches, F62 restarts) and on interrupts /
  exceptions / bus errors: a speculatively issued request must be cancelable
  or must be one that would have happened anyway.
- SP writeback hazards (stack pushes, exception frames): prog_spwb covers it;
  an earlier early-AS attempt lost stack writes because write DS was too late.
- Read-modify-write (TAS/CAS) must stay locked.
- **Test after every small change** (section 5), not at the end.

---------------------------------------------------------------------------
## 4. Rules (from David)
- No compatibility hacks: behave like a real 68030 / TF board on an ST bus.
- No posted writes.
- Document every deviation from real 68030 behaviour (HISTORY.md + comments).
- Keep credits: Wolfgang Foerster (WF68K30L), the MiSTery/MiSTeryNano/GSTMCU
  authors, all existing headers.
- A "switch" means a Verilog `define written by build_st_helper.tcl into
  build_sel.vh (VHDL: a generic set from it).
- Do not hack timing constraints to pass.
- Do not commit with DIAG_OVERLAY enabled.

---------------------------------------------------------------------------
## 5. Verification ladder (in order; stop at the first failure)

### 5.1 RTL bench: `Atarist_030_wip/hdl/cpu030/sim/rtl/run_rtl.sh`
GHDL 6.0.0 + m68k-linux-gnu binutils. Ends with `PASS: ...` or `FAIL ...`.
- `prog_srmask_a/b.s`: level-4 interrupt never taken with SR mask 7 (F55, MOVE to SR), several delays.
- `prog_chk.s`, `prog_branch.s` at WS 0/1/3/7: results must equal `expect_chk.txt` / `expect_branch.txt`
  (CHK, branches to 4n/4n+2, jumps, traps, prefetch bus errors, code written ahead of PC, user mode).
- `prog_spwb.s` at WS 0/1/3/7: SP writeback/push; must write $600DC0DE at $3300.
- `prog_loop.s` at WS 5: TOS vblank-sync loop must finish at clock **<= 45885**
  (original core; currently 44627). Slower = TOS UK hangs before palette.
  With the fix this number should drop clearly.
- Also in the folder (F64 TOS idioms, run by hand like the others): `prog_linea`
  (Line-A init), `prog_pushrts` (move.l x,-(sp); rts), `prog_smcstack` (VDI
  self-modifying fill loop), `prog_tas` (AES semaphore), `prog_trapirq`
  (TRAP polling with level 4/6 interrupts).

### 5.2 Whole-ST bus bench: `hdl/cpu030/sim/st/run_bus.sh <wf030.vg>`
Synthesize the core netlist with `hdl/cpu030/sim/wf030_syn.tcl` (gw_sh), then
run with Icarus 12 + Gowin simlib. Check: AS->AS gap statistics (target ~31 ns
class gaps between transfers, not 156), register dump at the end identical to
the old core (prog_bus.s).

### 5.3 RAM-loop slot measurement
rd.l / wr.l / copy / dbra loops from ST RAM (prog_ram.s style): compare with
the table in 3.4 (model predictions).

### 5.4 Build
`gw_sh build_st_helper.tcl` (from `Atarist_030_wip/`). Required before any flash:
TNS 0 on **all** rows of the timing summary, and recovery/removal slack positive
in the detailed report. place_option 3 first, then 1; **avoid 2**.

### 5.5 Board
Cold boot and warm boot to the GEM desktop, medium resolution, GEMBENCH:
6 menu passes plus both test groups. Numbers to beat: **86/86/74/230/115**.
If anything fails: reflash the rollback bitstream (section 6) immediately.

---------------------------------------------------------------------------
## 6. Exact commands

Tools on David's box: GHDL 6.0.0, Icarus Verilog 12.0 (`/workspace/tools/iverilog/bin`),
m68k binutils and gw_sh in `/workspace/tools/bin`. Laptop: Gowin
`C:\Dev\Gowin\Gowin_V1.9.12.03_x64`.

Build:
```
cd Atarist_030_wip
gw_sh build_st_helper.tcl
```
Flash (laptop, PowerShell) - check the hash first, find the cable location
with `--scan` (it changed from 417 to 289 once):
```
Get-FileHash C:\Users\dave_\fpga_rollback_20261009\st_helper_eas_d43f5fd_p3.fs
programmer_cli --scan
programmer_cli --device GW5AST-138B --operation_index 53 --location 289 --fsFile <file.fs>
```
**Never bulk erase. Never write flash 0x500000 (TOS) or 0x600000 (helper firmware).**
Never reflash the BL616.

Git basics for David:
```
git checkout main && git pull           # latest
git checkout -b f65-handoff             # new branch for the work
git apply handoff/<patch>.patch         # apply a patch from chat
git checkout rollback-2026-10-09-eas    # look at the rollback point (read-only)
git checkout main                       # back
```
Reset main to the rollback point (only if main is broken; this throws away
later commits, so ask first):
```
git checkout main && git reset --hard rollback-2026-10-09-eas
```

---------------------------------------------------------------------------
## 7. Debug tools
- **DIAG_OVERLAY** (`docs/DIAG_OVERLAY.md`): on-screen bus/CPU state; enable
  via `define for a debug build only, never commit enabled.
- **WF030_TRACE** (branch `diag-trace`): in-fabric trace ring of 030 bus cycles
  shown as a bit-dump on HDMI. Build: `git checkout diag-trace`, then
  `gw_sh build_trace.tcl`. Trigger is set in
  `Atarist_030_wip/cpu030/trace/wf030_trace_cap.v`. Decode capture-card frames:
  `python3 Atarist_030_wip/cpu030/trace/gao_decode.py OUT img1.png [img2...]`
  -> OUT.txt listing. `opcheck.py` (same folder) checks the delivered opwords
  against the TOS ROM image. (diag-trace predates the hdl/ move, so paths there
  are `Atarist_030_wip/cpu030/...`.)

---------------------------------------------------------------------------
## 8. Handing code back
- Put the change as a patch + a short .md in `handoff/` named
  `YYYYMMDD-HHMM-<topic>.patch/.md` (existing convention, see `handoff/README.md`).
  Make patches with `git diff` against main 3ae221e so `git apply` works.
- Work branch name: `f65-handoff` (next F-number).
- Rollback: `git checkout rollback-2026-10-09-eas` (or reset main as above) and
  reflash `st_helper_eas_d43f5fd_p3.fs` from `C:\Users\dave_\fpga_rollback_20261009\`
  (check against `SHA256SUMS.txt` first).

---------------------------------------------------------------------------
## 9. Glossary
| Term | Meaning |
|---|---|
| F60 | CHK operand fix (87fac46); bench row 6c706f0 |
| F61 | synchronous bridge start from the 030's AS (0104f1b..6611246) |
| F62 | opcode prefetch queue with aligned long fetches, like a cache-off 68030 (8f104b3) |
| F62b | restart the stream with a long fetch at the requested word (fixes the 4n+2 branch-target black screen, 9e612d5); documented deviation, see HISTORY.md item 3 |
| F62c | queue uses the decoder's OPCODE_FLUSH (ef56b11) |
| F62d | JSR SP writeback fix (79f5951 on main, 75bfc8c on the queue); the fallback bitstream |
| F63 | bridge + gstmcu RAM_EARLY: SDRAM row opened one clk32 earlier (f484271) |
| F64 | TOS-idiom benches (prog_linea etc.) and BRIDGE_EARLY_AS (d43f5fd) |
| F65 | this task (fast request handoff) |
| early AS | `BRIDGE_EARLY_AS`: for ST RAM, AS + read DS at S0 en2, write DS at S2 en2 (d43f5fd) |
| WS | wait states in the RTL bench |
| slot | the 500 ns ST RAM CPU access window granted by the GSTMCU |
See `Atarist_030_wip/docs/HISTORY.md` for the exact per-F details.
