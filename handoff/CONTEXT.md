# Agent context: FalconFPGA (read this first; update at each milestone)

Last update: 2026-10-15 (F66 BERR no-writeback on branch berr-nowb, built, not flashed). Owner: David Dunne (dave-1024).

## Goal
A 68030 Atari ST/STE on the Tang Console 138K (GW5AST-138), heading towards a Falcon-like machine.
Active core: `Atarist_030_wip/` = ST core (STE chipset) + WF68K30L 68030 (`hdl/cpu030`, Wolfgang Foerster,
CERN OHL v1.2) via the TF534-based bridge, plus the AE350 RISC-V helper (OSD, SD, floppy images).

## David's rules
- **Flash:** rescan cables every time (`programmer_cli --scan-cables`, location changes). Core = op 53 with
  `--fsFile` only (~300 s). Never write 0x500000 (TOS) or 0x600000 (helper) in a core flash. Helper = op 56
  `--mcuFile --spiaddr 0x600000` only. No bulk erase. No test builds on the board without David's OK.
  Always leave the board on a working build; then `--run 1` to reload. After flashing on Linux: `modprobe ftdi_sio`.
- **No hacks:** fix root causes, cycle-correct like real hardware; no timing-constraint relaxing.
- **Switches are `define`s** (build tcl), each documented in docs/BUILD.md with default.
- **Keep credits/licence headers** (WF68K30L CERN OHL v1.2, TF534 GPL-2, others); mark our changes (Fnn tags + dated revision block).
- **No HDD drivers** (use floppy/SD paths as built).
- **Git:** normal merges to main, no force push/rebase of pushed work. Identity on commit/pull/merge:
  `git -c user.name="David Dunne" -c user.email="david@dunne.dev" ...`
- **Fixed bugs move from TODO to the "Bugs found" list in docs/FALCON_LESSONS.md.**
- Report times in UK time.

## Machines / access
- **linserver** `dave@100.97.139.11` (Tailscale; from the box via SOCKS `localhost:1055`, `nc -X 5 -x localhost:1055`).
  Gowin V1.9.12.03 `/opt/gowin`, programmer `/opt/gowin/Programmer/bin/programmer_cli` (root), repo `~/falconfpga`,
  bitstreams `~/fpga_bitstreams` (SHA256SUMS), tools `~/fpga_tools` (README, `grab.sh` = HDMI frame grab, gbref/gbsnap .st),
  flash scripts `~/flash_core.sh`, `~/flash_both.sh`. The FT2232 helper serial is ttyUSB1 (unbound while programming; `modprobe ftdi_sio`).
- **David's laptop** (Windows): Gowin + programmer_cli as alternative.
- **hc.sh** (helper console): `/workspace/gb/hc.sh` on the box, copy in repo `tools/hc.sh`. Usage `hc.sh "cmd1" "cmd2" ...` (`sleep N` allowed);
  sends helper commands over linserver's `/dev/ttyUSB1` (115200) via ssh/SOCKS and prints the reply.
- **Box**: repo clone `/workspace/falconfpga`, GHDL 6 at `/workspace/tools/ghdl/bin/ghdl`, m68k binutils `/workspace/tools/m68k-binutils/bin`.

## Board state (2026-10-15)
- Core: `st_helper_hdn_917668c_p3.fs` (main switches + SD_WRITE_DEBUG, place 3), TOS 2.06. GEMBENCH ref A: CRC 791ee820.
- Helper: `helper_companion_sdwlog_3ec6e20.bin` (at 0x600000).
- Rollbacks: previous `.fs` in `~/fpga_bitstreams`; helper `helper_companion_osd3.bin`; tag `rollback-2026-10-09-eas`; `/workspace/fpga_rollback_20261009.zip` on the box.

## Branches
`main` is the truth (all done work merged). Open: `berr-nowb` (F66 core fix, no switch, sim PASS, bitstream
`st_helper_hdn_berr_7e3660e_p3.fs` built (TNS 0, clk_cpu030 16.21 MHz), awaiting David's OK to flash; linserver worktree `~/bldberr`). Feature branches (sd-harden, sd-mediach, sd-write-log, f65-handoff ...) are merged or parked.

## Build
- Core: `cd Atarist_030_wip && QT_QPA_PLATFORM=offscreen /opt/gowin/IDE/bin/gw_sh build_st_helper.tcl` -> `impl/pnr/st_helper.fs`;
  check timing (TNS 0) before flashing; name the copy `st_helper_<tag>_<hash>_p<place>.fs`.
- Helper: `bash helper_fw/companion/build_companion.sh` -> `output/helper_companion.bin`.
- Tests: `hdl/cpu030/sim/rtl/run_rtl.sh` (must PASS, `GHDL=` to point at ghdl), `hdl/cpu030/sim/st/run_bus.sh`,
  `hdl/misc/sim/tb_sd_*.v`, `hdl/fdc1772/sim/run_sim.sh`.

## Doc map
README.md (top) · Atarist_030_wip/README.md (status) · docs/BUILD.md (build, switches, flash) · docs/TODO.md (order) ·
docs/FALCON_LESSONS.md (rules learnt + Bugs found) · docs/HISTORY.md · docs/SD_WRITE_DEBUG.md · docs/ST_HELPER.md ·
docs/float_panic/ · docs/notes/ (RAM_PATH, SPI_SDC, TF536_NOTES) · LICENSE-NOTES.md · UPSTREAM.md ·
hdl/cpu030/README.md + license/ · helper_fw/README.md · handoff/ (handovers, this file).

## Next-fix order (docs/TODO.md, set 2026-10-15)
1. $FFFF bus-error writeback: F66 on `berr-nowb`, sim PASS, board test pending.
2. Warm-reset halt ($482, "System halted!" after `w`).
3. EmuTOS blitter greyed out.
4. Helper port (AE350 companion).
5. CPU rework phase 2 (operand cycles without IDLE).
Pinned, final stage: remove the ST/STE switch, STE only.
