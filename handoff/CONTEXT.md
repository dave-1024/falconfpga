# Agent context: FalconFPGA (read this first; update at each milestone)

Last update: 2026-10-16 22:00 (prefetch stop at change of flow merged and on the board; CACHE_PLAN.md added). Owner: David Dunne (dave-1024).

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

## Board state (2026-10-16, 22:00 UK)
- Core: `st_helper_hdn_pfcofvchain_db04754_p3.fs` (SHA256 f9f3742a50d56b6e1badce02fcbbb985e4de45cd67c079c6b36ba1e86ddff08b;
  main + prefetch stop at change of flow, merged), location 4193. 10 reloads + 3 `w` clean, GEMBENCH 89/251/132.
  Rollback: `st_helper_hdn_ph2wp_de35f5f_p3.fs` (SHA256 273083f29f4529f53e62ba29006948a937aeab706038b2ba22a1839a2e601285),
  then `st_helper_hdn_ph2fmax_5246d00_p3.fs` (c74d9676...).
  **Always `c` after a flash/reload before testing.** Board checks: `hc.sh s` first; halt = 5 black grabs over ~40 s.
- Previous board (de35f5f) results kept below.
- GEMBENCH 6 (gbref.st, ST Medium, STE reference, Blitter/FPU off), 16 Oct 2026:

  | Test | Time (s) | Ratio |
  |---|---|---|
  | GEM Dialog Box | 9.995 | 79% |
  | VDI Text | 14.175 | 99% |
  | VDI Text Effects | 25.730 | 94% |
  | VDI Small Text | 14.045 | 97% |
  | VDI Graphics | 26.105 | 72% |
  | GEM Window | 4.070 | 80% |
  | Integer Division | 2.695 | 667% |
  | Float Math | 12.370 | 107% |
  | RAM Access | 5.485 | 115% |
  | ROM Access | 5.480 | 115% |
  | Blitting | 9.635 | 91% |
  | VDI Scroll | 13.495 | 99% |
  | Justified Text | 14.155 | 97% |
  | VDI Enquire | 2.750 | 96% |
  | New Dialogs | 11.815 | 80% |
  | **Display / CPU / Average** | | **89% / 251% / 132%** |

- Helper: `helper_companion_sdwlog_3ec6e20.bin` (at 0x600000).
- Rollbacks: `st_helper_hdn_ph2fmax_5246d00_p3.fs` (SHA256 c74d9676..., phase 2 without posted writes, 132%),
  then `st_helper_hdn_berr_7e3660e_p3.fs` (F66, 123%), `st_helper_hdn_917668c_p3.fs`; all in `~/fpga_bitstreams`
  (SHA256SUMS). Helper `helper_companion_osd3.bin`; tag `rollback-2026-10-09-eas`.

## Branches
`main` is the truth (all done work merged; `berr-nowb` F66 merged 15 Oct, `cpu-phase2` merged 16 Oct). Feature branches (sd-harden, sd-mediach, sd-write-log, f65-handoff, berr-nowb ...) are merged or parked.

## Build
- Core: `cd Atarist_030_wip && QT_QPA_PLATFORM=offscreen /opt/gowin/IDE/bin/gw_sh build_st_helper.tcl` -> `impl/pnr/st_helper.fs`;
  check timing (TNS 0) before flashing; name the copy `st_helper_<tag>_<hash>_p<place>.fs`.
- Helper: `bash helper_fw/companion/build_companion.sh` -> `output/helper_companion.bin`.
- Tests: `hdl/cpu030/sim/rtl/run_rtl.sh` (must PASS, `GHDL=` to point at ghdl), `hdl/cpu030/sim/st/run_bus.sh`,
  `hdl/misc/sim/tb_sd_*.v`, `hdl/fdc1772/sim/run_sim.sh`.

## Doc map
README.md (top) · Atarist_030_wip/README.md (status) · docs/BUILD.md (build, switches, flash) · docs/TODO.md (order) ·
docs/FALCON_LESSONS.md (rules learnt + Bugs found) · docs/HISTORY.md · docs/PHASE2_DESIGN.md · docs/CACHE_PLAN.md · docs/SD_WRITE_DEBUG.md · docs/ST_HELPER.md ·
docs/float_panic/ · docs/notes/ (RAM_PATH, SPI_SDC, TF536_NOTES) · LICENSE-NOTES.md · UPSTREAM.md ·
hdl/cpu030/README.md + license/ · helper_fw/README.md · handoff/ (handovers, this file).

## Next-fix order (docs/TODO.md, updated 2026-10-16)
1. Warm-reset halt: PINNED (TODO.md; branch warm-reset 65e8b32). Includes the halt on a bare reload without `c`.
2. EmuTOS blitter greyed out.
3. Helper port (AE350 companion).
4. Phase 2 follow-ups: option (a) pipelined control unit; data-fault timing + $A/$B frame; stale bus-fault flag on a
   chained late BERR; clk_cpu030 decoder -> ADR_EFF path (before caches); clk32 blitter falling-edge path.
5. Caches (later): full plan in `Atarist_030_wip/docs/CACHE_PLAN.md` — I then D, CIIN on ST-side, CDIS hard off,
   match real MC68030; no cache logic in the bus path when disabled.
Pinned, final stage: remove the ST/STE switch, STE only.
