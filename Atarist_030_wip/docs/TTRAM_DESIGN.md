# TT-RAM for the 030 ST core — design (preliminary, branch `tt-ram`)

Status: first HDL implementation behind `` `define TTRAM ``, simulated (unit bench), **not built, not on
the board**. Default builds (no `TTRAM` define) are bit-for-bit the same source paths as before.

## 1. Decisions (David)
- One SDRAM chip only (the one already used, one CS); keep the controller simple.
- 16 MB TT-RAM at `$01000000-$01FFFFFF` (8 MB acceptable), in SDRAM banks 1-2 (ST uses bank 0).
- 32-bit port to the 030 (DSACK1:0 = 00), made of two 16-bit SDRAM words; first version at the
  existing 32 MHz SDRAM clock; zero-wait / faster clock / bursts are the tuning phase.
- CIIN negated (cachable) in TT-RAM, asserted for everything on the ST side (unchanged).
- On/off switch; off = plain ST, A31:24 ignored, 24-bit wrap (aliasing software). Later in the helper OSD.
- EmuTOS first; the TF-patched TOS 2.06 should then work.
- CPU core timing is not touched (only the bridge front end and sdram.v).

## 2. Memory map (030 addresses, FC != 7)

| A31:24 | switch on | switch off |
|---|---|---|
| `$00` | ST bus (as now) | ST bus |
| `$01`, A23:0 < 16 MB | **TT-RAM**, 32-bit, cachable | ST bus (wraps to `$00xxxxxx`) |
| `$FF` | ST bus (short `.w` I/O addressing `$FFFF8xxx`) | ST bus |
| anything else | **bus error** | ST bus (wrap) |

The bus error above TT-RAM is required by EmuTOS (section 7); a wrap there would make its size probe
write into ST-RAM. `TT_BYTES` in `cpu030_st_bridge.v` selects 16 MB (`25'h1000000`) or 8 MB.

## 3. SDRAM layout (W9825G6KH, 4 banks x 8192 rows x 512 cols x 16 bit = 8 MB per bank)

| bank | use | address |
|---|---|---|
| 0 | ST-RAM (8 MB window, 4 MB used), unchanged | ST word addr A22:1 (scrambled A4:3 as before) |
| 1 | TT-RAM `$01000000-$017FFFFF` | row = A22:10, col = {A9:2, word} |
| 2 | TT-RAM `$01800000-$01FFFFFF` | bank = 1 + A23 |
| 3 | free (8 MB spare) | — |

A long word = two adjacent columns in one row (col even = D31:16, col odd = D15:0), so a 32-bit access
is one ACTIVE + two column commands.

## 4. Controller (`tang/mega138kpro/sdram.v`, `ifdef TTRAM`)
The ST side is untouched: it still starts on the GSTMCU RAS edge (or the F63 early start), ACTIVE at
g0 (g7), CAS at g1 (g0), read data captured at state 4, auto-precharge, refresh on the RAS edge.

**Slot grid.** GSTMCU RAS starts come from its time0..7 Johnson counter: video RAS when time0 rises,
CPU RAS when time0 falls, exactly 8 clk32 (250 ns) apart; the F63 early start (`ecs`) is one clock
earlier. So every ST SDRAM start lands on g0 (or g7) of a fixed 8-clock grid. `tg` follows that grid,
re-synchronised on every ST start (`tg_ok` once seen).

**TT slot.** A TT access starts only at g2, and only if the ST state machine is idle or at state 2/3
(i.e. in phase with the grid). Each 250 ns slot can carry one TT long word, whether or not the ST used
the slot:

```
clk32 edge (registered cmd)  g0    g1    g2    g3    g4    g5    g6    g7  | g0' (next ST)
ST cmd   (normal start)      ACT0  CAS0  .     .     .     .     .     .   | ACT0
ST cmd   (ecs start)         CAS0  .     .     .     .     .     .     ACT0|
ST read data on bus                     (g2-g3 ecs / g3-g4 normal)
TT read  cmd                             ACT1  RD w0 RD w1+AP
TT read  data on bus                                        w0    w1        (captured g6/g7, ack g7)
TT write cmd                             ACT1  .     WR w0 WR w1+AP         (ack g5)
TT write data on bus (FPGA)                          w0    w1
DQM owner                    ST    ST    TT .........................  TT  | ST
```
- TT never issues a command when the ST can (g7, g0, g1); data-bus use never overlaps an ST read
  (g2-g4) or an ST write (sampled at g2).
- While a TT read is on the bus, the ST write-data driver (`cs && we`, normally held for the whole
  RAS) is switched off; the ST write has already been taken at g2. DQM is driven by the TT engine from
  g2 to the end of its access (read DQM = 00, write DQM = lane masks); the ST's write DQM at g1-g2 is
  untouched.
- Auto-precharge closes banks 1/2 before the next slot; a refresh at g0 finds all banks idle
  (TT write: last WR at g5, tWR 2 clk + tRP < 1 clk -> idle by g0').
- Bank 0 timing, addresses and data paths are unchanged, so ST/video/DMA/blitter timing is unchanged.

Port (clk32): `tt_req` (level, until `tt_ack`), `tt_we`, `tt_la[21:0]` = A23:2, `tt_be[3:0]` ([3] =
D31:24), `tt_din[31:0]`, `tt_ack` (one clock), `tt_dout[31:0]`.

## 5. Bridge (`cpu030/cpu030_st_bridge.v`, `ifdef TTRAM`)
- Decode from the 030's own A31:0/FC on the first clk32 edge with AS low (same related-clock paths
  the ST front end already uses). A TT cycle never opens `c_open`/`live`, so the ST bus never sees it.
- Byte lanes of a 32-bit port (MC68030UM 7.2.1): lanes A1:0 .. min(3, A1:0+size-1); misaligned
  operands are split by the 030 itself.
- Termination: `t_dsack` -> DSACK1:0 = 00 with `t_rdata` (registered, valid from the same edge, held
  until AS negates); BERR for the decoded bus-error ranges. Cleared on the first clk32 edge with AS high.
- `CIINn` negated only for TT-RAM **with the switch on** (before, `$01xxxxxx` was always cachable
  although it wrapped to the ST side; now off = cache-inhibited like any ST cycle).
- Switch: `tt_en` input; `misterynano` parameter `TTRAM_ON` (default 1 when `TTRAM` is defined).
  Later an OSD bit from the helper menu; it should only change while the CPU is in reset.

## 6. Speed
### 6a. First version (2bcc13c)
Bench: AS-to-DSACK about 13 clk32 average (406 ns), 15 max: wait for g2 (0-7 clk), 5 clk of SDRAM
work, one clk to DSACK, plus the 030's sampling. At a 16 MHz CPU that is about 4 wait states on a
32-bit access (two 16-bit ST cycles would take about 1000 ns). Still ~2.5x ST-RAM per long word, no
video contention, and the I/D caches hit on top. Tuning phase options: SDRAM clock 2-4x (TT slot then
fits several times per ST slot), start at more grid points, read bursts for cache line fills
(CBACK), STERM synchronous termination.

### 6b. Latency cuts without a new SDRAM clock (this branch, after 2bcc13c)
- **L1 request from the pins:** `tt_req/tt_la/tt_be/tt_we/tt_wdata` are driven straight from the 030's
  A/SIZE/RW/D outputs (valid with AS, the same assumption the ST front end makes), so sdram.v sees
  the request on the first clk32 edge with AS low instead of one edge later. Timing path: cpu_adr ->
  decode -> `tt_go` / sdram.v registers (clk_cpu -> clk32 related path, like the ST front end).
- **L2 early read ack, posted writes:** sdram.v acks a read on the edge it issues READ w1 (3 clk32
  before `tt_dout` is complete); the bridge's DSACK follows one edge later. The 030 samples DSACK on a
  clk_cpu falling edge and latches D one clk_cpu (2 clk32) later, so the data latch is never before the
  `tt_dout` load edge + 1. `cpu_din` takes `tt_dout` directly. Writes are acked when sdram.v takes
  them (data held in `tt_d`); a following TT access waits for `tt_busy`, so order is kept.
- Unit bench: AS->DSACK 13 -> 9 clk32 average (max 15 -> 13). Whole-ST bench, real core, whole TT
  cycle (AS low -> AS negated): 13.4 -> 11.6 clk32 average (prog_tt, 340 TT cycles); about 5.8 clk_cpu
  at 16 MHz, i.e. ~4 wait states per 32-bit access (was ~5). The many 15-clock cycles are reads that
  wait one slot behind a posted write.

### 6c. Further cheap options (not implemented)
- **CPU-half slots while the 030 is in a TT cycle:** the GSTMCU CPU-half RAS only comes from a
  bridge ST cycle or a DMA/blitter master. While the 030 waits for TT-RAM and no BR/BGACK is active,
  the CPU half is provably free, so a TT access could start at any of its first ~5 clocks (not just
  g2), and refresh stays in the video half. Needs the 16-clock phase (time0) and a "bridge idle, no
  grant" signal into sdram.v. Gain about 1-2 clk32 average; needs care with a BR that arrives
  mid-access (grant takes >= 4 clk32, so there is warning).
- **Start the row early on decode (like F63):** A31:24 = $01 is known one clk32 before AS from the
  030's address phase only if the core exported its S0 address early; it does not (pins only). No gain
  without touching the core.
- **Sequential reads:** keep the TT row open between accesses (no auto-precharge) when the next
  access hits the same row; needs precharge before every refresh/ST slot. Tuning phase.

## 7. EmuTOS requirements (emutos master, bios/memory.S, bios/memory2.c, bios/machine.c)
1. `detect_32bit_address_bus`: writes `$0000000C`, compares `$0100000C`. Must NOT mirror -> needs the
   switch on (off: it mirrors, EmuTOS says 24-bit and ignores TT-RAM — correct for the off case).
2. `detect_ttram_size` (only if 32-bit bus, `CONF_WITH_TTRAM`): for each MB, `check_read_byte` of the
   last byte (`$010FFFFF`, `$011FFFFF`, ...) — stops at a **bus error**; then writes/reads patterns and
   stops at a mirror of the first MB. With BERR from `$02000000` it finds exactly 16 MB.
   Without the BERR the probe would continue into wrapped ST-RAM (corruption).
3. `_FRB` cookie: added automatically when ramtop != 0 (`CONF_WITH_FRB` = `CONF_WITH_ALT_RAM`); a
   64 KB ST-RAM bounce buffer for ACSI/floppy DMA. No hardware needed: DMA and blitter stay 24-bit on
   the ST bus and never see TT-RAM.
4. Build variant: `TARGET_192` (192 KB ROM) has `CONF_WITH_TTRAM 0`. The 256 KB / 512 KB images keep
   it (check the image at 0x500000 before testing; do not reflash it without approval).
5. Programs flagged TT-load/TT-malloc in the header (FRNTBNCH.PRG has all three bits) go to TT-RAM.
6. TOS 2.06 (TF-patched) on a non-TT: relies on the same `_FRB`/maddalt conventions; expected to work
   once EmuTOS does.

## 8. Simulation
`cpu030/sim/ttram/run_ttram.sh` (Icarus 12, no Gowin netlist): bridge with a pin-level 030 stub +
`sdram.v` + an SDRAM model (bank state, tRC, refresh with all banks idle, read DQM, bus contention),
random ST SDRAM traffic on the 8-clock grid (reads, ecs reads, writes, refreshes) checked against a
shadow, plus:
- directed long/word/byte/3-byte/misaligned-piece writes and reads, both banks, last long of 16 MB;
- 3000 random TT reads/writes (all sizes, all A1:0) against a byte model;
- BERR at `$02000000`, `$80001234`; `$00000102` and `$FFFF0204` go to the ST bus;
- switch off: `$01000100` -> ST `$000100`, `$02000000` -> ST `$000000`, no BERR;
- CIIN checked on every cycle.
Result: `TTRAM BENCH PASS` (3219 ST reads all correct, 0 SDRAM model errors). Moving the TT start
to g1 makes it fail (the bench catches the clash).

### 8b. Whole-ST bench (`cpu030/sim/st`, real WF68K30L netlist, `run_tt.sh`)
`prog_tt.s` (ROM): the same long/word/byte/misaligned store sequence on TT-RAM and ST-RAM, 80 longs
compared, misaligned long/word/byte read sums, code copied to `$01002000` and run twice with I+D
caches on, cached TT re-read, BERR at `$02000000`, while ST video/refresh/CPU traffic runs.
Result (v1 and with L1/L2): 0 mismatches, sums equal, TT code result 0x1356 twice, 1 bus error,
0 SDRAM data-bus clashes; only 6 program-space TT bus cycles for 200 loop iterations (I-cache hits).
ST timing: `prog_bus.s` ST bus trace (4221 cycles with times, 3 ms) is byte-identical for frame-fix
(no TTRAM), TTRAM on and TTRAM off (v1 and L1/L2).
Netlist note: the box cannot run Gowin synthesis (license server unreachable), so these runs use the
existing core netlist `/tmp/gbsyn` (core ff6af03); the same netlist for every compared run.
The tb SDRAM model had a latent bug (back-to-back READs returned the second address for both);
ST never issues them, TT does; fixed in tb_bus.v.

## 9. Risks / open points
- **Grid assumption**: TT slots rely on the GSTMCU 8-clock RAS grid. If a start ever lands off-grid
  (turbo mode, a future MCU change), a TT access could clash with an ST command. Guarded by the ST
  state check; to verify on the whole-ST bench (`sim/st`, needs the netlist) and with SignalTap-style
  counters before trusting it on the board. Turbo (`cpu_16mhz_enable`) is not supported by the bridge.
- **Real SDRAM timing** (board clock is clkout2 at 338.4 deg): the model mirrors sdram.v's own ST
  capture offsets; the turnaround between an ST read (ends g4) and a TT write drive (from g4) is
  tight on the real pins. If it is a problem, the TT write moves one clock later only in slots
  without a pending refresh.
- tWR/tDAL at 32 MHz vs a refresh at g0' is within spec on paper (W9825G6KH-6), no margin to spare.
- The bench uses a pin stub, not the real WF68K30L: the 030's 32-bit-port lane/termination handling
  in `wf68k30L_bus_interface.vhd` (LONG_32 when DSACK = 00) is exercised for the first time on the
  board; `sim/st` with the netlist should run a TT-RAM program next.
- Fmax: new paths are cpu_adr -> decode -> clk32 regs (like the ST front end) and the 32-bit read
  mux into DATA_IN. Not built yet.
- Switch changes at run time must only happen in reset (no half cycles).
- `TTRAM` is not yet set by any build script.
