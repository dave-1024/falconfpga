# Agent context: FalconFPGA (read this first; update at each milestone)

Last update: 2026-10-18 13:00 (F3 back-to-back MOVEM writes done on f3-write-queue, merge to main approved by David; board f3a_7919eb3). Owner: David Dunne (dave-1024).

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

## Board state (2026-10-18 midday, UK)
- Core: `st_helper_hdn_f3a_7919eb3_p3.fs` (SHA256 56556195a0eedbee3a4a23b2978d05bbfe7a16ad41cbe6a46dd79168e211d78e; F1/F2 + F3
  back-to-back MOVEM writes, branch f3-write-queue 304b885 = same HDL as 7919eb3), location 4193. Cold boot `c` clean
  (2/2). GEMBENCH 6.08 vs STE20608: RAM 101%, ROM 104%, Display 46, CPU 186, Average 92; vs STFM1048: Display 94,
  CPU 186, Average 132. GEMBench 4.03: 135 / Display 91 / CPU 255. LUT 37,870, Fmax clk_cpu030 20.94 / clk32_core
  34.02 MHz, TNS 0.
  **Rollback order: F3a `st_helper_hdn_f3a_7919eb3_p3.fs`, then F2 `st_helper_hdn_f2_c4de2ec_p3.fs`, then
  `st_helper_hdn_dc_ff6af03_p3.fs`**.

## Previous board state (2026-10-18 morning, UK)
- Core: `st_helper_hdn_f2_c4de2ec_p3.fs` (SHA256 f7d2672c0cd87ee585b1fe9a086436c914d1d70b98979c394a429b3cf7a796fb;
  main = caches + MOVEM timing F1/F2, merged 18 Oct 2026; built from c4de2ec, same HDL tree), location 4193. Cold boot
  `c` clean (3/3). GEMBENCH 6.08 (gb608.st) vs STE20608: RAM 91%, ROM 104%, Display 46, CPU 180, Average 91; vs
  STFM1048: Display 93, CPU 180, Average 129. GEMBench 4.03 (gbref.st): 134 / Display 90 / CPU 254. LUT 38,034,
  Fmax clk_cpu030 22.33 / clk32_core 32.44 MHz, TNS 0.
  **Rollback order: F2 `st_helper_hdn_f2_c4de2ec_p3.fs`, then `st_helper_hdn_dc_ff6af03_p3.fs`** (below), then the
  older ones listed below.
- Note on names: `gbref.st` holds GEMBench 4.03 (older notes called its results "GEMBENCH 6"); `gb608.st` holds
  GEMBENCH 6.08 (title bar "GEMBENCH 6.31", reference sets SETS/*.GB6, loaded with File > Open Test).

## Previous board state (2026-10-17, evening UK)
- Core: `st_helper_hdn_dc_ff6af03_p3.fs` (SHA256 c9a160b6c34df3c28a97826b73198999a57cbe03be9961f8217cdbae1d41c39e;
  main = fault fixes + 68030 I and D caches, merged 17 Oct 2026), location 4193. Cold boot `c` clean, TOS 2.06 shows
  "Cache" ticked, GEMBENCH 133 / Display 89 / CPU 252 (unchanged as expected: only $01000000-$01FFFFFF is cachable,
  no fast RAM fitted). LUT 37,662, Fmax clk_cpu030 22.79 / clk32_core 33.78 MHz, TNS 0.
  Rollback order: `st_helper_hdn_ic_47eba71_p3.fs` (fault fixes + I cache, SHA256 da5f2238...6ce034, 133%), then
  `st_helper_hdn_oa_039c710_p3.fs` (SHA256 f543ebe4737b5d45abdbffecd211b418eacdf5528a6ec5ea2a6c57f001923ba6;
  option (a) steps 2/3, 133%), then `st_helper_hdn_oa_08e1cf8_p3.fs` (SHA256 3996f7cacab88d607d4d7c313b9fab28a0581248582a6b3537311951e48ae1fb),
  then `st_helper_hdn_pfcofvchain_db04754_p3.fs` (SHA256 f9f3742a50d56b6e1badce02fcbbb985e4de45cd67c079c6b36ba1e86ddff08b).
  **Always `c` after a flash/reload before testing.** Board checks: `hc.sh s` first; halt = 5 black grabs over ~40 s.
  Count a warm reset only if `w` answers "ST reset via sysctrl" (the first command after reloads can come back as the
  help text or the serial can go silent; op 1 reload restores it; TODO item 7).
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
`main` is the truth (all done work merged; `berr-nowb` F66 merged 15 Oct, `cpu-phase2` merged 16 Oct, `option-a` and
`caches` (contains `fault-fixes`) merged 17 Oct, `f1-movem-timing` merged 18 Oct). `f3-write-queue` (F3): done, merge approved by David 18 Oct. Feature branches (sd-harden, sd-mediach, sd-write-log, f65-handoff, berr-nowb ...) are merged or parked.

## Build
- Core: `cd Atarist_030_wip && QT_QPA_PLATFORM=offscreen /opt/gowin/IDE/bin/gw_sh build_st_helper.tcl` -> `impl/pnr/st_helper.fs`;
  check timing (TNS 0) before flashing; name the copy `st_helper_<tag>_<hash>_p<place>.fs`.
- Helper: `bash helper_fw/companion/build_companion.sh` -> `output/helper_companion.bin`.
- Tests: `hdl/cpu030/sim/rtl/run_rtl.sh` (must PASS, `GHDL=` to point at ghdl), `hdl/cpu030/sim/st/run_bus.sh`,
  `hdl/misc/sim/tb_sd_*.v`, `hdl/fdc1772/sim/run_sim.sh`.

## Doc map
README.md (top) · Atarist_030_wip/README.md (status) · docs/BUILD.md (build, switches, flash) · docs/TODO.md (order) ·
docs/FALCON_LESSONS.md (rules learnt + Bugs found) · docs/HISTORY.md · docs/PHASE2_DESIGN.md · docs/CACHE_PLAN.md · docs/ICACHE_DESIGN.md · docs/DCACHE_DESIGN.md · docs/FAULT_FIXES.md · docs/MOVEM_TIMING_F1_F2.md · docs/SD_WRITE_DEBUG.md · docs/ST_HELPER.md ·
docs/float_panic/ · docs/notes/ (RAM_PATH, SPI_SDC, TF536_NOTES) · LICENSE-NOTES.md · UPSTREAM.md ·
hdl/cpu030/README.md + license/ · helper_fw/README.md · handoff/ (handovers, this file).

## Next-fix order (docs/TODO.md, updated 2026-10-17)
1. Warm-reset halt: PINNED (TODO.md; branch warm-reset 65e8b32). Includes the halt on a bare reload without `c`, and
   the one-off halt noted during the fault-fixes testing (not reproduced).
2. EmuTOS blitter greyed out.
3. Helper port (AE350 companion).
4. D-Q2: board check of D cache write allocate (CACR-read program; with WA, ST-side aligned long writes allocate
   entries). Fallback CDIS.
5. 030-side fast RAM ($01000000-$01FFFFFF) so the caches have something to cache; then burst.
6. ~~F3~~ done (MOVEM writes back to back, f3-write-queue). Open from it: bus-error frame stage B ($0E) holds a
   stale BIW_2 (TODO.md); read->write gaps in copy loops; the general A3 request queue stays deferred.
7. 68030 PMMU: planned later step, in HDL inside the core (not on the AE350); its tables mark I/O and ST-RAM
   cache-inhibited like TT/Falcon, which resolves D-Q2.
8. Phase 2 follow-ups still open: stale bus-fault flag on a chained late BERR; clk_cpu030 decoder -> ADR_EFF path;
   clk32 blitter falling-edge path.
Pinned: the ~10% GEMBench 4.03 display gap (Display 90%); GEMBENCH 6 sees no blitter ("BLiTTER NP"), see TODO.md. Final stage: remove the ST/STE switch, STE only.
