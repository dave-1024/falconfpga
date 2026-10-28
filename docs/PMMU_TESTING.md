# Testing the 68030 PMMU (falconfpga)

## In short
Every PMMU feature gets three kinds of test:
- **Simulation** (`sim/rtl/prog_pmmu.s`, run by `run_rtl.sh`): fast, exact, and cycle-level.
- **Our own program on the board** (`tools/pmmutest/PMMUTEST.PRG`): checks each feature against the page of
  the Motorola manual (MC68030UM) that defines it.
- **Existing software** that uses the PMMU: shows that real programs work. A test suite made from a real 68030
  (WinUAE's cputester run on David's A1200 + ACA1233) is the best way to get exact reference values.

## 1. PMMUTEST.PRG (tools/pmmutest)
- Build it with `./build.sh` (GNU as, position-independent code, GEMDOS header with no relocations).
- Copy it to a floppy image; putting it in AUTO is easiest. Example:
  `mformat -C -i pmt.st -f 720 :: && mmd -i pmt.st ::AUTO && mcopy -i pmt.st TTRAM.PRG PMMUTEST.PRG ::AUTO/`.
  Upload it with `up2.py`, `mount a` it, then cold boot.
- Each line says PASS, FAIL, DEV (a known, documented deviation of the current stage) or SKIP, with
  "exp=" and "got=" values. The last line gives the FAILS/DEVS totals.
- The same text is written to `PMMUTEST.TXT` in the current directory (the root of A: when run from AUTO). Read it
  back by downloading the image with `get` and opening it with `mtools`.
- Stage 1 tests (manual pages):

| Test | Manual | Expected |
|---|---|---|
| TC write $7FFFFFFF, read back | 9.7.1 p9-52 | $03FFFFFF |
| TT0 / TT1 write $FFFF7FFF | 9.7.3 p9-57 | $FFFF0777 |
| MMUSR write $FFFF | 9.7.4 p9-59 | $EE47 |
| CRP / SRP write all ones | 9.7.2 p9-54 | $FFFF0003 / $FFFFFFF0 |
| Invalid TC (E=1, PS=0) | 9.7.1 p9-53 | stored with E=0 |
| ... and the exception | 9.8 p9-64 | vector 56 (DEV in stage 1: no exception yet) |
| PMOVE in user mode | 9.8 p9-65 | privilege violation, vector 8 |
| TT0/TT1 with CI over a TT-RAM loop | 9.7.3 p9-57 | loop at least 2x slower than cached |
| TT0 with an FC that never matches | 9.7.3 p9-57 | loop speed same as cached |

- On falconfpga only TT-RAM ($01xxxxxx) can be cached, because the bridge asserts CIIN for ST space. So the TT
  timing test copies its loop into a TT-RAM block from `Mxalloc(...,1)`. If there is no TT-RAM (TTRAM.PRG not
  loaded) the test prints SKIP.
- Adding later stages: write a routine `T_xxx` and add it to the `tests` table. Planned:
  - translation with a small table: map a page of TT-RAM to another, check the data, check the U and M bits;
  - ATC: 22 entries (fill 23 pages and time the 23rd), PFLUSH by FC/mask/EA, PFLUSHA;
  - PTEST levels 0..7 and the MMUSR result (B, L, S, W, I, M, T, N), PLOAD;
  - faults: invalid descriptor, write protect, supervisor only, limit; the bus error frame
    (format $A/$B) and the SSW fields;
  - timing: count 200 Hz ticks ($4BA) over 10^6 iterations, or cycle-count loops, and compare them with
    MC68030UM 11.7 (table search clocks p11-60).

## 2. Existing software that uses the 68030 PMMU
| Software | What it uses | Can run here? | Notes |
|---|---|---|---|
| **WinUAE cputester** (Toni Wilen) | Runs every opcode, including PMOVE/PTEST/PFLUSH/PLOAD, on real hardware first, saves the results, then compares on the target. Has 68030 MMU modes. | Generate the reference data on David's **A1200 + ACA1233** (a real 68030). The Amiga side needs porting: a TOS loader for the test data, and a way to keep ST hardware out of the address map. | Best source of exact values from real silicon, including cycle counts if run with cycle counting. |
| **EmuTOS 1.4** (256K/512K/1M, `CONF_WITH_68030_PMMU=1`) | At boot: detects an 030 with `PMOVE TC,abs.L`, then sets up CRP/TC/TT0/TT1 tables (identity map, cache-inhibit regions). | Yes, if an EmuTOS image is flashed (not done this session). | Simple boot check: it must boot with the PMMU registers implemented. With stage 1 only the registers are used (TC.E stored, no translation yet). |
| **FreeMiNT** (with memory protection, `mint030.prg`) | Builds full page tables and turns on TC: separate tables per process, write protection, faults and recovery. | Needs stage 2 (translation + ATC) and stage 3 (faults). | The real end-to-end test. Without memory protection (`MP=NO`) it only uses TT regs. |
| **Outside** (virtual memory for the TT/Falcon) | Paging to disk: page faults, restarting instructions, the U/M bits. | Needs stages 2-3. | A hard test of bus error frames and restarting. |
| **Linux/m68k** (Atari kernel) | Full MMU (030 tables, TT0/TT1), PTEST in fault handling. | Needs stages 2-3, plus enough RAM and a disk image. | Gold standard, but slow to boot. |
| **TOS 3.06** | Its 030 table setup (TT tables, cache inhibit for I/O). | **No: TT only** (TT video, second MFP, SCC). It will not boot on the STE+030 core. | Use it only in Hatari TT mode, as a reference for how Atari builds the tables. |
| **Hatari** (`--cpulevel 3 --mmu on`) | WinUAE CPU core with MMU. | Runs PMMUTEST on the box. Getting it to run from a floppy or GEMDOS drive with TOS 2.06 is still to be sorted out. | Gives the expected results of a reference emulator. It is not cycle exact for the table search. |

## 3. Where results go
`docs/PMMU_PROGRESS.md`, plus screenshots in `docs/img/pmmu/`.

## 4. FreeMiNT with memory protection (tools/minttest)
Recipe and test: `tools/minttest/README.md` (`mkimg.sh` downloads the pinned FreeMiNT 1.19 snapshot, builds
MPTEST.PRG and a 720 KB floppy; no hard disk needed).

Hard disks on this setup (for later): the helper mounts ACSI images with `mount h0|h1 <file>` (targets 0 and 1
only, `hdl/atarist/acsi.v`), raw `.hd`/`.img` files anywhere on the FAT32 SD card (`sdc.c` accepts `.ST`/`.HD`;
contiguous files are direct-mapped). TOS 2.06 has no ACSI driver of its own, so an HD image needs a boot
driver (AHDI/HDDRIVER/...) in its root sector; that is why the MiNT test uses a floppy.

Findings so far (27 Oct 2026):
- MiNT's default memory protection is not strict: a `Pexec(100)` child is forked from its parent and keeps
  the parent's regions mapped (`k_exec.c`, `exec_region`: they are only marked invalid with MPF_STRICT). With
  `KERN_MPFLAGS=1` (MPF_STRICT, a normal mint.cnf option) the child's write gets "memory violation".
- Hatari 2.5 (STE, TOS 2.06 UK, 030 + MMU, 4 MB): MPTEST FAILS=0 (MP on, child V killed by SIGBUS, parent
  memory unchanged, three W children exit 0). Without strict mode the child's write goes through (FAILS=2).
  Hatari with 1 MB does not get to MPTEST (no BOOT.LOG), with 14 MB it does.
- Board (pmmu8, TOS 2.06, 4 MB): AUTO is reached (STAGE0.TXT), but MiNT never opens BOOT.LOG and MPTEST never
  runs, with memory protection on **and off**. So the stop is before MiNT's file system init and is not caused
  by MiNT's page tables (with MEM_PROT=NO MiNT does not set TC.E). Cause not found yet; see PMMU_PROGRESS.

### Status 27 Oct 21:30 UTC (MiNT on the board)
- Last on-screen text, MP on (mint_scr.st, WRITE_BOOT=NO): FAT/VFAT banner `(c) 2000-2010 by Frank Naumann.`
  (img/pmmu/mint_board_stop.png). With DIAG_OVERLAY (img/pmmu/mint_mpon_overlay_halt.png) the CPU is halted
  (double bus fault) right after mint030 set_mmu does `pmove 12(sp),tc` (TC $80D04447, CRP table $BC000);
  last bus cycle = a table-search read at $BC186.
- Theory: a PMMU/table-search fault seen only on the board (bridge/bus side): the same state replayed on the
  RTL core (tools/minttest/sim) translates correctly. Next: whole-ST bench or DIAG_EXCWATCH.
- MP off (mint_nomp.st) is separate: CPU keeps running past `Installing BIOS keyboard table`, no BOOT.LOG yet.

## Morning summary (27 Oct 2026, written ~23:00 GMT)

**Where FreeMiNT stops (MP on, pmmu8):** the last on-screen text is the FAT/VFAT 1.27 banner (docs/img/pmmu/mint_board_stop.png). The DIAG_OVERLAY build shows the CPU **halted** (double fault). The last fetch was $5CE9A, just after `pmove 12(sp),tc; rts` in MiNT's set_mmu. The last cycle was an FC5 table-search read at $BC186 (docs/img/pmmu/mint_mpon_overlay_halt.png). With MP off the CPU does not halt (a separate, open issue).

**Ruled out:**
- RTL replay of the Hatari snapshot at that exact PC (TOS ROM, wait states 0/1/3/random, IRQ sweep): no failure.
- MTREE.PRG (MiNT's exact TC and long-descriptor tree, translated with IRQs, under TOS) PASSES on the board.
- PROBE/PROBE2: every TOS call MiNT makes before this point completes on the board.

So the tree format and TC are not the cause. The failure depends on MiNT's real RAM/stack state or timing through the bridge and caches.

**Tonight's attempt:** I built pmmu (d7663f8) with DIAG_OVERLAY + DIAG_EXCWATCH as `st_helper_hdn_pmmu8exc_d7663f8.fs` (clk_cpu030 20.15 MHz, clk32_core 32.49 MHz, 45678 LUT + 5308 ALU, 19335 regs). With it flashed, the helper serial stopped answering (no `s` reply), and after a cold boot of mint_scr.st the screen showed only orange/blue stripes. Reflashing pmmu8 brought serial back once; after a second excwatch try it did not.

**Board state now — needs attention:** pmmu8 is flashed (programmer rc=0). The helper on /dev/ttyUSB1 prints its boot lines and then stops answering commands, even after waiting more than a minute. Per the rules I stopped board work: pmt5.st was **not** remounted or re-verified. Please power-cycle/replug the board, then `mount a pmt5.st`, `c`, and check PMMUTEST.TXT FAILS=0.

**Next:** find out why the DIAG_EXCWATCH build kills the helper link (likely the debug mux on the companion link, or timing; 43 endpoints failing, worst -13.7 ns, against 44 / -12.9 ns for the overlay-only build). Then capture the exception trail before the halt.

## Flash rule: no negative slack on any clock pair (27 Oct 2026, 22:50 GMT)

**Do not flash a build with negative setup or hold slack in any explicit `report_timing` clock-pair table.** That includes pmmu8exc (worst −13.7 ns) and pmmu8ovl (worst −12.9 ns).

Check with `python3 tools/timing/timing_pairs.py <impl/pnr>` (exit 1 means do not flash). The Gowin "Total Negative Slack" table showed **0** for every clock on these builds and on pmmu8, so TNS alone is not enough.

Correction: in my previous note, "43" and "44" were the logic depth of the worst path (number of nodes), not a count of failing endpoints.

**Finding:** pmmu8 itself (the build where MiNT stops, bitstream md5 ced52e19) fails `clk_cpu030 -> clk32_core` by **−7.0 ns**. The path is:

DC_OA → FILL_WADR (+1 incrementer) → ADR_OUT_I → MMU ATC lookup (XLATE/HIT_OK → BLK) → P_ASn → bridge live request → r_adr/r_dout CE.

The MMU gates AS combinationally with the ATC result, so this path exists only while **translation is on**. It is the bridge's half-cycle (31.25 ns) path. When it is too slow, the bridge can see AS low with a still-settling (logical, untranslated) address and start an ST cycle with it. That matches a failure right after `pmove tc` that RTL simulation cannot reproduce.

The plain builds before the data cache work passed this pair (pmmu_b2: +3.76 ns).

## Overnight status (27 Oct 2026, 23:35 GMT, sim only, board untouched)
- **Likely cause found (timing):** on pmmu8, clk_cpu030 -> clk32_core fails by −7.0 ns on the MMU's AS/address path. With TC.E = 1 the ATC lookup gates AS in the same clock, and the ST bridge samples it 31.25 ns later. See FALCON_LESSONS "Bridge sampled translated 030 pins…".
- **Fix (pushed, not flashed):**
  - F65: DC_OA+4 is now registered.
  - F66: with MMU_ON, the bridge takes requests only on clk_32 edges aligned to clk_cpu rising edges. The SDC gives the paths through BLK_PIN/XLATE_PIN/H_PA two clk_32 cycles.
- **Checks so far:**
  - CPU bench cmp_full old vs new: SAME on every program tried. prog_df differs only in report-line numbers.
  - Whole-ST bench prog_bus with MMU off: results and traces are byte-identical to the old bridge.
  - MMU-on bench run (`ASFLAGS="--defsym MMU=1"`): in progress.
- **Build f66 (first version):** cpu030->clk32 now passes (+4.25 ns), but clk_cpu030_n -> clk_cpu030 fails by −9.5 ns. syn_keep on HIT_OK/XLATE deepened the BLK -> DSACK core path. I moved the keeps to pin-side copies; build f66b is running.
- 23:55: the MMU-on whole-ST bench gives the same results as the old bridge (R1000/R1100/R1200 equal). Translated ST cycles start later: AS->S0 is mostly 5×31.25 ns instead of 2, and the bench runs 9.69 ms instead of 8.37 ms (about 16% slower with translation on; no change with it off).
- f66b timing: cpu030->clk32 is +3.2 ns (fixed), but clk_cpu030_n -> clk_cpu030 is −5.2 ns. That path is SLICE_CNT_N -> RMC_PIN (T_SLICE term) -> MMU WP check/TT RWM -> CIIN -> core. F67 gives the MMU/TT an RMC signal without the T_SLICE term (equal while AS is low). Build f67 is running.
- 00:25: f67 timing: the core half-cycle path is fixed (+11.4 ns), but clk_cpu030 -> clk32_core is −3.6 ns on the *untranslated* path (FILL_WADR + ADR_OFFSET adder -> A31:24 -> TT/fast-RAM decode -> bridge live start). Not flashable. Trying place_option 1 (f67p1); if that doesn't close it, the next step is shortening that decode. CPU bench cmp_full old vs F65–F67: SAME on all 38 runs checked.
- 00:50: f67 with place_option 1 (f67p1): the MMU/bridge pair passes (+7.8 ns), but it misses by a hair elsewhere (clk_cpu030 -> clk_cpu030_n −0.36 ns, clk32 −0.2 ns / 31.6 MHz). Not flashable; trying place_options 2 and 0.
- 01:15: full run_rtl.sh PASSES on F65–F67. Timing of f67 with place_options 2/0 also fails (−3.0/−4.4 and −2.1/−5.6 ns), so placement alone won't close it. Next: shorten the untranslated bus-address path by dropping the ADR_OFFSET adder on fill cycles, if sim shows ADR_OFFSET is always 0 during a fill (sim check running).
- 01:45: **f68 (9d8e37f) meets timing on every pair** (timing_pairs.py rc=0; recovery +8.2, removal +0.26, TNS 0). Slack is thin: cpu030->clk32 +0.18 ns, clk32 +0.08 ns. clk_cpu030 20.37 MHz, clk32_core 32.17 MHz. 45012 LUT + 5191 ALU, 17989 regs. Bitstream `~/fpga_bitstreams/st_helper_hdn_9d8e37f-f68.fs` (sha256 3f2daf3a28ba0959…). **Ready, NOT flashed.** cmp_full for F68: SAME on all 80 runs (40 programs × WS 0/3); run_rtl.sh PASS on F68.

### Morning summary (updated 01:45 GMT)
1. **Board:** untouched since about 22:35 GMT. The helper serial was silent after the excwatch build; needs a replug. pmmu8 is flashed. pmt5.st was not re-verified.
2. **Likely cause of the FreeMiNT stop:** a timing failure, not logic. pmmu8 fails clk_cpu030 -> clk32_core by −7.0 ns on the path through the MMU's ATC lookup to AS/A31:8, sampled by the ST bridge 31.25 ns after AS. The path is only active with TC.E = 1, which fits a halt right after MiNT's `pmove tc` that RTL sim can't reproduce. The TNS table hid it; new rule: `tools/timing/timing_pairs.py` must pass before any flash.
3. **Fix on pmmu:**
   - F65: DC_OA+4 registered.
   - F66: while MMU_ON, the bridge takes requests a full clk_cpu after AS; SDC multicycle through the kept nets BLK_PIN/XLATE_PIN/H_PA.
   - F67: the MMU WP check and TT RWM use RMC without the falling-edge T_SLICE term.
   - F68: no ADR_OFFSET adder on fill cycles.

   All are cycle-identical in the CPU bench: cmp_full SAME (80/80), run_rtl PASS (F65–F68). The whole-ST bench with MMU off is byte-identical. MMU on: same results, about 16% slower ST access while translating.
4. **To test after the replug (David):**
   - Serial check, flash f68, serial check.
   - Run pmt5.st (expect FAILS=0).
   - Run mint_mp2.st (expect MPTEST FAILS=0).
   - Fallback: pmmu8.

## Board run after replug (28 Oct 2026, 06:50–07:05 GMT)
- Before: helper serial OK (`link OK`), f68 sha256 3f2daf3a28ba0959 verified, no stray programmer_cli, cable found.
- Flashed f68: programmer rc=0. Afterwards the helper printed its help/boot text once, then **stopped answering** (no `s` reply after more than 1 min, raw read empty).
- Fallback: reflashed pmmu8, rc=0. **Same result:** one burst of help text, then silent.
- This is the same pattern as last night with pmmu8exc → pmmu8. Since even the known-good pmmu8 leaves the helper silent, the problem is **probably not the f68 bitstream**. More likely, the helper (or its link) does not survive a JTAG reflash. Not tested: pmt5/mint (no serial, so no mount).
- Stopped board work per the rules. **Needs another physical replug.** pmmu8 is currently flashed.
- Suggestion for the next try: after the replug, check the serial first, then flash f68, then wait about 2 min before the first command. If it is silent again, the helper side should be looked at (not touched by me: BL616 is off limits).

## Helper firmware check (28 Oct 2026, from 07:04 GMT)
- Known-good helper (AE350) firmware: `~/fpga_bitstreams/helper_companion_sdwlog_3ec6e20.bin`, sha256 eada916a85401b3a…acd0af (handoff/CONTEXT.md; flash_both.sh writes it at 0x600000 with op 56).
- programmer_cli has no raw flash read. Op 66 (exFlash Verify Arora V) can compare a file with flash without writing, so I'll use that for the 0x600000 check.
- Core sizes: the f68 binary is 0x4E46CA bytes (pmmu8ovl 0x4D8CCA, pmmu8exc 0x4BDA4A). All are below TOS at 0x500000, so the core image does not reach 0x600000 by size alone. Whether op 53 erases beyond the image is still open.
- 07:05–07:11: serial silent, and the USB device number is unchanged (no replug seen yet). Screen black.

## Board after 07:12 replug (28 Oct 2026, 07:13–07:25 GMT): left on pmmu8, no flash
- Serial link OK after the replug (`core status: 5C 42 ... link OK`); board is running pmmu8 (the last image flashed).
- `programmer_cli --run 66` (exFlash verify) of helper_companion_sdwlog_3ec6e20.bin (sha256 eada916a…0af) with `--spiaddr 0x600000`
  reported "Verify Flash Failed" twice. It is not clear that op 66 honours `--spiaddr` for a raw .bin, so this does **not** prove
  the helper region is corrupt; it needs a check against a known-good region first (e.g. verify pmmu8.fs at 0).
- Verify ops are read-only; the link was OK again afterwards (first poll after the ftdi_sio reload was empty).
- No helper rewrite and no f68 flash were done. Every earlier flash (pmmu8exc, f66, f68, and even pmmu8) left the helper silent until
  a physical replug, so a fallback cannot be put back remotely. With David away, the steering was to stay conservative.
- Next, with David present: rewrite the helper (op 56 `--mcuFile --spiaddr 0x600000`), flash f68, then pmt5 / mint_mp2 / mint_nomp.
  If the helper goes silent again, look into whether op 53 erases or disturbs blocks past the bitstream, or whether the AE350 boot handshake fails when the FPGA is configured over JTAG/SPI without a power cycle.

## Correction 07:20: board work continues, low-risk route (28 Oct 2026, 07:20–07:50 GMT)
**Note on 07:17:** one helper rewrite (op 56) was started before the stop order. It was interrupted after ~3 s, and nothing showed it reached the flash. The helper answered normally afterwards. An earlier attempt never wrote anything (a script error made it run op 66 verify instead).

**Is op 66 verify trustworthy?** Yes for .fs files. `pop.sh 66 --fsFile st_helper_hdn_pmmu8.fs` passed ("Verify Flash successfully", 38 s).
`--fsFile f68.fs` failed at address 12, as expected. So **flash at 0 still holds pmmu8.**
op 66 `--mcuFile helper.bin --spiaddr 0x600000` fails. That is probably not real damage: it does not look like op 66 takes the C-bin
layout or offset. Meanwhile the helper boots from 0x600000 on every power-up and answers, so I judged the region **not damaged and did not rewrite it**.
TOS at 0x500000 was not verified (no trustworthy raw-bin verify).

**SRAM load (op 2) of f68 (sha 3f2daf3a…): helper survives.** Link OK 10 s after the load. So the silence comes from the
flash path (op 53 erase/program and/or op 1 reprogram), not from the bitstream contents. With f68 in SRAM only, a power-cycle brings back pmmu8.
New helper script on linserver: `~/pop.sh <op> [args]` (rescans the cable location and refuses the bulk-erase ops).

**Results on f68 (SRAM):**
- pmt5.st cold boot: `PMMUTEST.TXT` **FAILS=0 DEVS=0**.
- mint_mp2.st (MP on): **gets past `pmove tc` now** (the old halt). The screen shows "Initializing system components", Core 3533474 B,
  "No alternative RAM", "no XHDI", the crypto warning, the dynamic RAM fs 0.72 and FAT/VFAT/FAT32 1.27 lines, then nothing more for >3 min.
  No MPTEST.TXT, no BOOT.LOG. Frames: linserver `~/cap_f68mp2b/f3.png`, `~/cap_f68mp2c/f4.png`.
- mint_nomp.st (MP off): same lines, then "Installing BIOS keyboard table ... AKP 0, ISO 0", then
  **"pid 0 (MiNT): unable to open CONSOLE device / FATAL ERROR"**. Frame: `~/cap_f68nomp/f9.png`. That is an image/setup problem
  (u:\dev\console not available), not an MMU one. MP stops one step earlier (before the keyboard-table line), so it is worth comparing in Hatari next.
- Next: fix the CONSOLE fatal in the image (Hatari first), then recheck MP. Board flash untouched since the replug (pmmu8). f68 is loaded in SRAM.

## Correction + MiNT on f68 follow-up (28 Oct 2026, ~08:20 GMT)
- **Correction:** the MP-on result on f68 (last line = FAT/VFAT 1.27 banner) is the **same last screen as on pmmu8** (see the pmmu8 note above).
  The screen alone does not show whether f68 still halts after `pmove tc`. An f68 + DIAG_OVERLAY build (`~/f68ovl_build.sh`, no EXCWATCH) is running;
  it is SRAM-loaded only if `timing_pairs.py` passes.
- **Hatari, same config as the board** (`--machine st` and `ste`, 030, MMU, 4 MB, TOS 2.06): the board's own images mint_mp2.st (sha 44e31e55…)
  and mint_nomp.st (sha 58fefaba…) both boot to MPTEST (mp2: FAILS=0; nomp: FAILS=3, as expected with MP off). **The images are fine.**
  So the CONSOLE fatal on the board is a board/core problem, not a setup one.
- In init.c, "unable to open CONSOLE device" is `do_open("u:/dev/console")` failing after init_keybd, init_cookies and `ccw_set(CACHE_ON)`.
- **Cache ruled out:** mint_nompnc.st = mint_nomp with the kernel's `ccw_set(CACHE_ON, CCW_MASK)` immediate patched to 0 (mint030.prg file
  offset 0x21204: C567 -> 0000; the earlier `ccw_set(0, mask)` leaves caches off). Hatari OK. On the board: **the same CONSOLE fatal.**
- DEBUG_LEVEL=4 in MINT.INI prints nothing extra on the board (release kernel without debug output).
- Flash-silence problem (op 53 + op 1 leave the helper silent until a replug; an SRAM load does not): parked for later.

## Board stopped: helper silent after SRAM-loading f68ovl (28 Oct 2026, 08:00–08:12 GMT)
- f68 + DIAG_OVERLAY (`st_helper_hdn_f68ovl_64d2b49.fs`, sha 5c9f428a…) passed `timing_pairs.py` (all pairs ok, worst setup 0.867 ns clk32).
- SRAM load (op 2) rc=0. After it **the helper did not answer** (`hc.py s` empty; nothing at all on ttyUSB1, even after a CR). HDMI was black.
  No overlay data.
- Restore attempts (no flash writes): SRAM-load f68 (which had worked at 07:22) → still silent for 2 min. Then op 1 (reconfigure from flash = pmmu8)
  → still silent, HDMI black. The FTDI and ttyUSB1 are present.
- **Board work stopped.** Flash is untouched since the replug (pmmu8 at 0, verified by op 66; helper fw and TOS as at 07:12). A power-cycle/replug
  should bring back pmmu8 + helper.
- So the helper going silent is **not specific to the flash path** (op 53 + op 1). It also happened after an SRAM load. One SRAM load (f68, 07:22)
  kept it alive and the next (f68ovl) did not. Parked, as asked; one theory to check later is the AE350/helper handshake on any FPGA reconfiguration
  (for example a reset or boot-mode pin state while the fabric is reloaded).

## Sim: MiNT do_open("u:/dev/console") on the RTL core (28 Oct 2026, sim only)
- Kernel TEXT base in Hatari (ST, 4 MB, TOS 2.06): **$CEBA**. The CONSOLE open is `jsr (a1)` at **$2E2E8** → do_open at $35EA4
  (from init.c: FATAL at TEXT+$21B54).
- Hatari (MP off): do_open returns **d0 = 0** (13.6k instructions, trace kept on the box at /workspace/mtr/h3.log).
- RTL tb030 from Hatari's RAM snapshot at $2E2E8 (`tools/minttest/sim/doopen.sh`, stub `mint_doopen_stub.s`): returns **d0 = 0** at
  WS 1, WS 3 and WS 1 + CIMODE 1, with no exceptions. **The core runs this path correctly from Hatari's state.**
  So on the board the state reaching do_open must already differ (some earlier step in MiNT init diverges), or the problem depends on the board
  (interrupt timing, SDRAM). Next: snapshot earlier (MiNT entry / init_filesys) and compare bus writes against Hatari.
- Helper silence analysis and options: see docs/HELPER_SILENCE.md (the leading theory, a PLL not locking after a warm reconfigure, fits the black HDMI + no UART byte).

## Sim: MiNT from its entry on the RTL core (28 Oct 2026, running)
- Hatari snapshot at the MiNT entry (2nd hit of PC $CEBA, user mode, after STAGE0): `tools/minttest/sim/stub_entry.s` + `run_entry.sh`.
  tb030 with level 6 vector $45 (timer C) every 80000 clk (200 Hz) and level 4 (VBL) every 320000 clk; it logs only EXC/HALT and the
  do_open call ($2E2E8), its return ($2E2EA) and the FATAL path ($2EA0E).
- tb030 change: MFP timer A/B/C/D data registers count down (before this only timer C did); TOS polls timer B data ($FFFA21).
- ~22M clocks (Hatari: 1.4 s from entry to do_open) is about 1 h of GHDL. Result to follow. Hatari has no bus-write log, so the
  comparison is at the checkpoints (do_open result, exceptions) and a RAM diff if it gets there.
- Box note: the box was reset around 08:29 (/tmp and installed packages lost). Hatari now runs from /workspace/hroot (dpkg -x of the trixie .deb
  + libcapstone5) via ~/bin/hatari; ssh to linserver uses ~/bin/socks5nc.py instead of nc.

## Board workflow (agreed with David, 28 Oct 2026)
- Test builds go into **SRAM only** (`~/pop.sh 2 --fsFile <build>` on linserver, with `~/sramlog.sh <fs> <secs>` logging U15 across the load).
- Flash at 0 holds a known-good build for recovery: pmmu8 now; f69 (PLL watchdog) once proven. **TOS at 0x500000 and the helper firmware at
  0x600000 are never rewritten.** No bulk erase, never the BL616.
- **Before every SRAM load** run a read-only flash op (`~/pop.sh 66 --fsFile <the .fs in flash at 0>`). It takes the flash out of the ST controller's
  continuous-read mode, so the AE350 can boot (docs/HELPER_SILENCE.md). This is also the recovery for a silent helper: verify, then SRAM-load. No replug needed.

## f69 on the board (SRAM, 28 Oct 09:25–09:35 GMT)
- After op 66 + op 2: AE350 banner, helper link OK, TOS desktop. pmt5.st: **FAILS=0 DEVS=0**.
- mint_mp2.st: same last screen as before (FAT/VFAT 1.27 banner, no MPTEST.TXT). Frame linserver `~/cap_f69mp/f1.png`.
- run_rtl.sh after the tb030 MFP/ACIA/shifter model changes: **PASS** (all checks).
- MiNT-from-entry RTL run: still going (0.65 s emulated so far: 131 timer C ticks, 558 BIOS traps, no fault).
- MiNT-from-entry RTL run **stopped** at ~0.72 s emulated: TOS sits in its floppy wait loop ($E03F32: polls MFP GPIP bit 5 with an _hz_200 timeout),
  because tb030 has no FDC/DMA model, so every disk read MiNT does (MINT.CNF, the sysdir) times out. Up to there: no fault, 145 timer C ticks, 558 BIOS traps.
  To go further, tb030 needs a disk hook: for example, point hdv_rw ($476) at a stub that passes the request through a magic I/O port to the
  testbench, which serves sectors from the .st file. Or snapshot later, after the last disk access before init_filesys. Not done yet.
