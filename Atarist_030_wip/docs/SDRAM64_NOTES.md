# SDRAM64 notes (restart from the current core)

Written 9 Nov 2026 when the unmerged `sdram64` branch was removed. This file is the record of
that work; do not rebase the old tree. Restart against current `main`.

**Old tip (deleted branch):** `dec654f8df7f3c298036133d48411a9d12ee2d76`, 31 Oct 2026 22:01 UK
(GMT). Message: "WIP 64 MHz SDRAM / TT-RAM speedup (sd64_wt tree as-is) + docs/sdram64".
One commit ahead of its base `d270586` (tt26rmc2 era). By 9 Nov 2026 that tip was about 299
commits behind `main` (PMMU, F110 `sdram.v` arbitration, flash_unstick, caches, F121-F131,
the speed overhaul through F156). Rebasing it would conflict in the very files that matter
and would replay stale CPU/RMC copies. Take the ideas below and implement them again on the
current controller and top-level.

The longer day-by-day log lived only on that commit (`docs/sdram64/PICKUP.md`,
`PROGRESS.md`, `PLL_PHASES.md`, `REBASE_NOTE.md`, plus screenshots and helper scripts).
The useful facts are copied here.

## Goal

Run the SDRAM controller and the chips at 64 MHz instead of 32 MHz, while keeping every
ST/TT memory access at the same absolute moment as before. Step 1 only had to prove the
chips would run at 64 MHz. Nothing was meant to get faster yet. After a clean desktop:

1. GEMBENCH and FrontBench against the tt26rmc2 baselines.
2. 68030 burst cache fills (STERM / CBREQ / CBACK; the core did not support them then,
   and still does not as of F156).
3. Faster TT-RAM using the extra 64 MHz slots.

**Baselines (build tt26rmc2, TOS 2.06, blitfix.st in A, ST Medium):**

- GEMBENCH 6.31: average 124% (Display 90, CPU 172, RAM Access 102, Blitting 98, ALT RAM 161,
  Text 55).
- FrontBench: steady 1375 (1385 on the first pass), `tts.st` in B, `B:\FRNTBNCH.PRG`. Without
  TTRAM.PRG it runs from ST-RAM (~990).

No 64 MHz build ever reached a clean desktop, so those benches were never re-run at 64 MHz.

## Design

### Clocking

- The 138K datasheet (DS1239-1.0.3E) allows a VCO of 650-1300 MHz and an input/PFD of at
  least 19 MHz. An older table said 800-1600. Stay inside both ranges.
- **Never use a 1600 MHz VCO.** sd64a set the main PLL (`pll_160m`) VCO to 1600 MHz. The PLL
  never locked, `por` stayed asserted, the helper serial went silent and HDMI stayed dark.
  Recovered only by reflashing tt26rmc2 after a physical re-plug. Do not flash any leftover
  `st_helper_hdn_sd64a.fs`.
- From sd64b on, the main PLL was byte-for-byte the tt26rmc2 one (50 MHz in, VCO 800 MHz,
  all seven outputs used). A second PLL, `pll_sd64`, takes `clk32` (`clk_pixel`) as its
  input: 32 MHz in, VCO 960 MHz (inside both datasheet ranges), two 64 MHz outputs.
  - CLKOUT0: `clk_sd64` for the controller (phase 0 in the committed tree).
  - CLKOUT1: `O_sdram_clk` pad clock, 327 deg = about 1.43 ns lead in the committed tree
    (`CLKOUT1` coarse/fine 13/5).
- `pll_lock` / `jtagseln` follow `pll_hdmi` only (same as tt26rmc2). Core `por` waits for
  both locks: `por = !(pll_lock && pll_lock_sd)`.
- 64 MHz cannot be made with integer dividers from the main PLL at a legal VCO. The 12.5
  fractional divider exists, but alignment with the other outputs is undocumented and was
  not used (`prim_sim` showed clkout0 not edge-aligned with clkout1).

### Controller (`sdram.v`, `SDRAM64`)

- The controller runs on `clk_sd` (64 MHz). A clock-enable `ce` is high on the 64 MHz edges
  that coincide with `clk32` edges.
- Every command is issued on the 64 MHz edge that matches the old 32 MHz edge and lasts one
  64 MHz clock (`if (!ce) sd_cmd <= CMD_NOP`). Read data is captured 3 `clk_sd` edges after
  READ (CL2 at 64 MHz, same geometry as CL2 at 32 MHz) and handed over at the old edge, so
  `dout` / `tt_dout` change at the same absolute time as before.
- `ce` generation (sd64b onward): toggle `t32` on `clk32`, sample it on the **falling**
  `clk_sd` edge (halfway between `clk32` edges, about 7.8 ns of margin against inter-PLL
  skew), then detect the edge on rising `clk_sd`. That was meant to stop `ce` depending on
  which way the two PLLs drift.
- Optional `SD64_NEGCAP` (sd64k, not board-tested): sample DQ on the falling `clk_sd` edge
  2.5 clocks after READ and hand it on at edge 3. Aimed at a marginal capture window.

### Constraints

- `atarist_st_helper.sdc`: `clk_sd64` generated from `pll_sd/.../CLKOUT0`; `O_sdram_clk`
  period set to 15.625 ns; multicycle 2/1 both ways between `clk32_core` and `clk_sd64`
  (transfers have a full `clk32` period because of `ce`).
- Trying to tell STA the true source (`clk_sd64` `-source` pll_sd CLKIN, `-master_clock
  clk32_core`) failed with TA2004 "Cannot get clock with name clk32_core". Gowin cannot
  follow a clock through one PLL into another. STA therefore treated the second PLL's output
  as arriving about 1.6 ns **before** `clk32`, when on the board it arrives later (the
  internal feedback aligns to CLKIN after the `clk32` route, estimated 1.4-3 ns lag).
  "Timing met" is not true for the handover between the two clocks.
- Workaround used on the board: shift **both** 64 MHz outputs earlier with the PLL phase
  settings (1 coarse step = 1.042 ns, fine step = 0.13 ns). A better fix, not tried, is to
  put the SDRAM data handover on the 64 MHz edge halfway between `clk32` edges, or to move
  `clk32` and the 68030 clocks onto the same PLL as the 64 MHz clock (careful with the
  100 MHz flash clock).

### Wiring

- `top.sv`: instantiate `pll_sd64`; leave main PLL clkout2 (old 32 MHz pad clock) unused;
  pass `clk_sd64` into `misterynano`.
- `misterynano.sv`: `sdram.clk_sd = clk_sd64`, `clk_sd_pad = clk_sd64` (the board pin is
  driven directly from the PLL, not from `sd_clk`).
- `build_st_helper_hdn.tcl` / `build_sel.vh`: `` `define SDRAM64 `` and add the two PLL
  files.
- Sims: `tb_bus.v` and `tb_ttram.v` gained a non-inertial pad-clock delay
  (`always @(clk) clk_pad <= #d clk`) and an optional `+sdtrace=` SDRAM command trace.

The committed tree also carried older RMC CPU patches (`wf68k30L_bus_interface.vhd`,
`wf68k30L_control.vhd`, `wf68k30L_alu.vhd`, a small `cpu030_st_bridge.v` change). Those
landed on `main` later as `[RMC1]` / `[RMC2]`. Do not re-apply the CPU files from
`dec654f`; prefer current `main` and port only the SDRAM64 ifdefs.

## Timing (STA)

All listed builds reported no negative slack and kept `clk_cpu030` well above 16 MHz.

| Build | Change | Fmax clk32 / sd64 / cpu030 (MHz) | LUTs | Notes |
|---|---|---|---|---|
| tt26rmc2 baseline | 32 MHz SDRAM | 35.24 / — / 21.86 | 40309 | no SDRAM pin I/O delays |
| sd64a | main PLL VCO 1600 | 33.28 / 144.1 / 21.83 | 40318 | do not flash |
| sd64b | 2nd PLL, no extra shift | 36.28 / 122.9 / 23.66 | 40440 | STA caveat: pll_sd CLKOUT0 insertion delay 0 |
| sd64c | SDC source = pll_sd CLKIN | build failed (TA2004) | — | SDC reverted |
| sd64e / f | phase sweep | (same family as b) | 40440 | see board table |
| sd64g / h / i / j | jtagsel fix + sweep | 34.64 / 112.4 / 23.71 | 40440 | |
| sd64k | h + SD64_NEGCAP | 34.40 / 91.4 / 23.20 | 40440 | not tested |

## Board results

Phase numbers are CLKOUT0 / CLKOUT1 coarse+fine from each build's `pll_sd64_mod.v`. The
committed tree is the unshifted base (0/0 and 13/5).

| Build | CLKOUT0 / CLKOUT1 | Shift | Extra | Board |
|---|---|---|---|---|
| sd64a | (main PLL VCO 1600) | — | — | board dead, PLL never locks |
| sd64b | 0/0 , 13/5 | none | SDRAM64 | PLLs lock, helper serial OK; after `c` + space, static field of random coloured dots; TOS never starts (wrong SDRAM reads) |
| sd64c | same RTL as b | — | SDC only | not built |
| sd64e | 12/0 , 10/5 | -3.125 ns | SDRAM64 | TOS starts (logo), BAD ROM CRC, 2 bombs |
| sd64f | 11/0 , 9/5 | -4.17 ns | SDRAM64 | helper serial + HDMI dead (wedge; needed a physical re-plug) |
| sd64g | 11/4 , 10/1 | -3.65 ns | SDRAM64, jtagsel fix | one-way-serial wedge again after `c` |
| sd64h | 12/4 , 11/1 | -2.6 ns | SDRAM64, jtagsel fix | **best:** memory test 4096 KB OK, then `BAD ROM CRC IN CHIP E/O` and hang |
| sd64i | 13/0 , 11/5 | -2.08 ns | SDRAM64 | memory test with several X errors + BAD ROM CRC (worse than h) |
| sd64j | 13/4 , 12/1 | -1.56 ns | SDRAM64 | built, not tested |
| sd64k | 12/4 , 11/1 | -2.6 ns (as h) | SDRAM64 + SD64_NEGCAP | built, not tested |

The TOS ROM is served from flash, not SDRAM, so "BAD ROM CRC" most likely means occasional
RAM bit errors during the check (the quick memory test does not catch them). Around -2.6 ns
was the best point; both sides were worse, so the working range is narrow. That is why
sd64k (falling-edge capture) was built and left untested.

## What worked

- Two-PLL scheme (main PLL untouched at VCO 800, `pll_sd64` at VCO 960) locks and the
  helper comes up.
- Simulation of `prog_bus` and `prog_tt` (whole-ST bench) matched the 32 MHz build for
  sd64b..k, except two start-up commands (PRECHARGE, LOAD MODE) one clock earlier, before
  the RAM model was ready. `SD64_NEGCAP` traces were identical in the same way.
- A phase sweep can get TOS as far as the memory test (sd64h) or the logo (sd64e). The
  direction of the skew hypothesis was confirmed: shifting the 64 MHz clocks earlier moved
  the board from garbage RAM (sd64b) to a partial TOS boot.

## What did not

- No build reached a clean desktop, so no GEMBENCH / FrontBench numbers exist at 64 MHz
  and the real speed-ups (burst fills, faster TT-RAM) were never started.
- Cross-PLL STA is lying about the `clk32` / `clk_sd64` handover. Hand-tuned phase is a
  narrow, brittle workaround, not a design.
- sd64a (VCO 1600) bricks the fabric until the last-good bitstream is restored and, if
  the helper is wedged, the board is physically re-plugged.
- Some failing boots wedge the helper: serial still prints its banner (or even answers
  `?` once) then ignores commands, HDMI black. Reflashing tt26rmc2, USB resets and a
  remote power cycle did not always clear it; David re-plugging the board did. Seen after
  sd64a, sd64f and sd64g, each time around a cold boot (`c`) of a misbehaving ST side.
  Tying `jtagseln` to the main PLL only (sd64g+) did not prevent it.
- **Rule from that work:** on a test 64 MHz build do not send `c`; TOS starts by itself
  after flashing (seen with sd64i). Check that serial still answers `?` (it can take
  about 50 s) before anything else. If it wedges: reflash the last-good bitstream once,
  stop, and ask David to re-plug. Do not pull the SD card while the board is powered.
- The debugger USB location changes after every re-plug (4593, 4641, 4689, 4817 at the
  time). Flash scripts must rescan; never hard-code the location. Today's cable scans at
  location 5777.

## Key files to revisit on a restart

Port only the SDRAM64 ideas onto current `main`; expect conflicts with F110 (sdram
arbitration), later top-level / flash_unstick work, the current SDC and `build_sel.vh`.

| File | What the old branch added |
|---|---|
| `hdl/tang/mega138kpro/sdram.v` | `SDRAM64` ports, `ce`, one-cycle commands, 3-edge read capture, `SD64_NEGCAP` |
| `hdl/tang/console138k/top.sv` | `pll_sd64` instance, split `pll_lock` / `por` |
| `hdl/misterynano.sv` | `clk_sd64` into `sdram` |
| `hdl/tang/console138k/gowin_pll/pll_sd64.v` | wrapper (new) |
| `hdl/tang/console138k/gowin_pll/pll_sd64_mod.v` | generated PLL, phase fields (new) |
| `hdl/tang/console138k/atarist_st_helper.sdc` | `clk_sd64`, pad period, multicycle pair |
| `build_st_helper_hdn.tcl`, `hdl/tang/console138k/build_sel.vh` | `` `define SDRAM64 ``, add PLL files |
| `hdl/cpu030/sim/st/tb_bus.v`, `sim/ttram/tb_ttram.v` | pad-clock delay, `+sdtrace=` |

Do not copy `wf68k30L_*.vhd` or the RMC bridge tweak from `dec654f`.

Phase-sweep helper (old `docs/sdram64/scripts/bv.sh`): copy a work tree, set
`CLKOUTn_PE_COARSE` / `CLKOUTn_PE_FINE` in `pll_sd64_mod.v`, build. Useful again only
after a clean restart has a locking two-PLL design.

## Suggested restart order

1. Recreate `pll_sd64` (VCO 960 from `clk32`) and the `SDRAM64` `ce`/capture path on
   current `main`. Keep the main PLL at VCO 800.
2. Re-run `tb_bus` / `tb_ttram` / `prog_bus` / `prog_tt` against the 32 MHz reference.
3. SRAM-load before any flash. Do not send `c` on the first 64 MHz boots.
4. Prefer a structurally correct clock handover (same PLL, or capture on the mid-edge)
   over another coarse phase sweep. If a sweep is still needed, start near sd64h
   (-2.6 ns) and try `SD64_NEGCAP`.
5. Only after a clean desktop: GEMBENCH / FrontBench vs the baselines above, then burst
   fills and faster TT-RAM.
