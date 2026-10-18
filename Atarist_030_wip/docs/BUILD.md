# Building and flashing Atarist_030_wip (Tang Console 138K)

Short version: run `gw_sh build_st_helper.tcl` in `Atarist_030_wip/` (Gowin V1.9.12.03, Windows or Linux), check
timing, and flash `impl/pnr/st_helper.fs` with `programmer_cli` op 53. Build the AE350 helper with
`helper_fw/companion/build_companion.sh` (Linux) or `.bat` (Windows), and flash it with op 56 at 0x600000.
Details, reasons and the rules are below. What went wrong before and why is in
[FALCON_LESSONS.md](FALCON_LESSONS.md); open work is in [TODO.md](TODO.md); the SD/floppy write path is in
[SD_WRITE_DEBUG.md](SD_WRITE_DEBUG.md).

## 1. What you need
- **Gowin EDA V1.9.12.03**: every build here was made and timed with it. Windows (`gw_sh.exe`) or Linux headless
  (`/opt/gowin/IDE/bin/gw_sh`, run with `QT_QPA_PLATFORM=offscreen`); both give the same results. Other versions
  place differently, and this design is placement sensitive (section 5).
- **Board:** Sipeed Tang Console 138K (GW5AST-LV138PG484AC1/I0, **device version C**) with the **Tang SDRAM module in
  J9**. Don't flash with J9 empty.
- **TOS:** TOS 2.06 (256 KB) for all tests; EmuTOS 256K also boots. It lives in the board flash at 0x500000, not in
  the bitstream, and is not in git.
- **SD card** (FAT) with `.st` floppy images. The helper mounts them (`atarist.ini` for power-up mounts, OSD or the
  console for runtime mounts).
- **AE350 helper firmware** at flash 0x600000 (section 8).

## 2. Layout
- `hdl/`: all HDL. `hdl/cpu030` (WF68K30L 68030 and the ST bus bridge), `hdl/atarist`, `hdl/gstmcu`, `hdl/ikbd`,
  `hdl/jt49`, `hdl/fdc1772`, `hdl/hdmi`, `hdl/misc` (ST core parts from MiSTeryNano, incl. `sd_card.v`/`sd_rw.v`),
  `hdl/helper` (AE350 SoC glue, PLLs), `hdl/tang/console138k` (top, pins `.cst`, timing `.sdc`).
- `helper_fw/`: AE350 helper firmware ([helper_fw/README.md](../helper_fw/README.md)).
- Build scripts: `build_st_helper.tcl` (**the main build**), `build_st_helper_hdn.tcl` (same + `SD_WRITE_DEBUG`,
  place 3: the build on the board), `build_st_68000*.tcl` (68000 comparison builds), `build_tc138k.tcl` (old desktop
  build without the helper), `build_st_helper_{sdlog,mch,dmaw,excw,gdt,hiwatch,hiv6,wrw,nocart}.tcl` (debug/test
  variants, one define each on top of the main build).
- Benches: `hdl/cpu030/sim/rtl/run_rtl.sh` (CPU RTL, GHDL), `hdl/cpu030/sim/st/run_bus.sh` (whole ST, Icarus),
  `hdl/misc/sim/tb_sd_*.v` (SD controller fault injection, Icarus), `hdl/fdc1772/sim/run_sim.sh` (FDC error status).

## 3. Build the core
```
cd Atarist_030_wip
gw_sh build_st_helper.tcl                         # Windows: C:\Dev\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe
QT_QPA_PLATFORM=offscreen /opt/gowin/IDE/bin/gw_sh build_st_helper.tcl   # Linux
```
Output: `impl/pnr/st_helper.fs`, timing report `impl/pnr/st_helper_tr_content.html`. About 25-40 min. The script
writes the switches into `hdl/tang/console138k/build_sel.vh` (Gowin has no command-line define), which `top.sv`
includes. To change a switch, edit the `puts $fh` lines at the top of the tcl. Name the copy you keep after the
commit and place option, e.g. `st_helper_hdn_917668c_p3.fs`, and keep it in `~/fpga_bitstreams`.

## 4. Compile-time switches (`define)
Rule: options are `define switches; fixes that are proven go on by default; debug defines stay off on main.

| switch | default (build_st_helper.tcl) | what it does |
|---|---|---|
| `ST_HELPER` | on | AE350 RISC-V helper: SD card, floppy images, USB keyboard/mouse, console (ST_HELPER.md) |
| `ST_HELPER_CART` | on | self-test cartridge at $FA0000 (helper mailbox check at boot) |
| `ST_HELPER_USB` | on | USB host on the Console USB-A ports for the helper |
| `ST_HELPER_OSD` | on | MiSTeryNano OSD drawn by the helper over HDMI (F12) |
| `ST_COLOUR_MONITOR` | on | colour monitor (low/medium res); off = mono ST High |
| `ST_STE` | on | STE chipset, TOS in the ST ROM slot (0x500000). Pinned in TODO.md: the ST/STE switch will be removed and STE hardwired |
| `BRIDGE_EARLY_AS` | on | "early AS": the bridge asserts AS for ST RAM cycles at S0 en2 (62.5 ns after the address, still a legal 68000 cycle), so a 030 request makes its GSTMCU slot (notes/RAM_PATH.md). Off = the original 68000 phase timing |
| `WF030_FAST_HANDOFF` | on | F65: prefetch-to-prefetch S5-to-S0 handoff in WF68K30L. Phase 2 (PH2, PH2-WP: prefetch<->operand chaining, writes complete at S3 of the last portion) is a correctness change with no switch; see PHASE2_DESIGN.md |
| `ST_SD_WRITE_FIX` | on | sd_rw waits for DAT0 not busy before CMD17/CMD24, bounded CMD24 retry, a failed write completes instead of jamming in state 13 |
| `ST_FLOPPY_MEDIACH` | on | holds floppy write-protect ~0.75 s after each image insert/eject, so TOS sees a runtime disk swap. Without it TOS writes the old disk's FAT/directory into the new image (the gb403 corruption) |
| `ST_SD_HARDEN` | on | sd_rw checks the data-response token, re-inits the card and re-issues (2 re-inits), bounds read retries, latches the sector at request time; a give-up shows as an FDC CRC error (status bit 3) |
| `ST_030_CACHES` | off | no effect since 17 Oct 2026: the 68030 I and D caches are always built (no switch, CACR enables them as on a 030); the bridge drives CIIN from a per-cycle decode (ST ROM/RAM/IO inhibited, only `$01000000-$01FFFFFF` cachable); the old experimental modules are gone |
| `ST_CPU_68000` | off (`build_st_68000.tcl`, `build_st_68000_st.tcl`) | build the fx68k 68000 instead of the 030, for comparisons |
| `SD_WRITE_DEBUG` | off (on in `build_st_helper_hdn/mch/sdlog.tcl`) | SD request ring + state/counters in sd_card.v/sd_rw.v, read by the helper's `sdwlog`/`sdstate`/`sdrw` |
| `DIAG_OVERLAY` | off | on-screen 030 state overlay (DIAG_OVERLAY.md) |
| `DIAG_HIWATCH`, `DIAG_HIWATCH_V6`, `DIAG_EXCWATCH`, `DIAG_DMAWATCH`, `DIAG_GDTRACE` | off (own tcl each) | float-panic hunt probes (float_panic/FLOAT_PANIC.md); debug only, never on main |
| `WF030_TRACE` | off (branch `diag-trace`) | in-fabric bus trace (how the JSR SP bug was found) |
| `DISABLE_BLITTER`, `DISABLE_ACSI` | off | leave those blocks out |

## 5. place_option
The same RTL can fail timing, or (once) give a bitstream whose helper didn't boot, depending on placement.
`build_st_helper.tcl` uses `place_option 1`; the board builds (`*_p3.fs`, `build_st_helper_hdn.tcl`) use 3. If one
fails timing, try the other. Don't relax constraints to make a build pass.

## 6. Check timing (before every flash)
In `impl/pnr/st_helper_tr_content.html`:
1. **TNS table: 0 on every clock**, setup and hold (targets clk32 32 MHz, clk_cpu030 16 MHz; the ph2wp build reaches
   34.2 / 19.65 MHz at place_option 3). Keep clk_cpu030 headroom: it varies between placements (17.4-23.0 MHz seen).
2. **Recovery/removal tables** (not in the TNS table): every slack positive.
3. Ignore the header's "violated endpoints" count.

## 7. Flash the core (programmer_cli)
Linux (`/opt/gowin/Programmer/bin`, as root) or Windows (`programmer_cli.exe`):
```
./programmer_cli --scan-cables                     # every time: the location changes (e.g. 4289)
./programmer_cli -d GW5AST-138C --location 4289 --run 53 --fsFile st_helper_hdn_917668c_p3.fs
./programmer_cli -d GW5AST-138C --location 4289 --run 1   # reload the FPGA from flash
modprobe ftdi_sio                                  # Linux: the programmer unbinds the helper's ttyUSB1
```
Rules:
- **Op 53 only**, always with `--fsFile`. Give it about 300 s and log the output; the log prints the end address
  (about 0x04B6000), which must be below 0x500000.
- **Flash map:** bitstream from 0; **TOS at 0x500000**; **helper firmware at 0x600000**. Never write either of those
  by mistake, and **never bulk erase**.
- Rescan the cables before each flash. Check the file's SHA-256. Keep the last good `.fs`.
- After a flash, a second op 1 is sometimes needed before the helper console answers.
- Then **cold boot (`c` on the helper console) before any test** and check the desktop. A bare reload (op 1) without a
  `c` can stop at "System halted!" after the cartridge self-test (TODO.md); after a `c`, reloads and `w` resets are clean.

## 8. The AE350 helper
Source: `helper_fw/fpga-companion` (FPGA-Companion with an AE350 port in `src/ae350/`). Build script:
`helper_fw/companion/build_companion.sh` (Linux) or `build_companion.bat` (Windows); both give the same image.

Linux setup (once):
1. Toolchain: **Andes AST v5.1.1** Linux, `nds32le-elf-newlib-v5` (gcc 10.3.0), from
   github.com/andestech/Andes-Development-Kit, release `ast-v5_1_1-release-linux`. Unpack to
   `~/andes/5_1_1/` (or set `FALCON_TC` to its `bin/`). It matches AndeSight RDS v5.1.1 on Windows; a generic
   riscv-gnu or xPack gcc is not a drop-in.
2. BSP: from Gowin's **RiscV_AE350_SOC_V1.3** zip, unpack so that `~/ae350sdk/library/bsp` exists (or set
   `FALCON_SDK`). The script uses `bsp/ae350`, `driver`, `config`, `lib` and the linker script `sag/ae350-ddr.ld`.
3. `bash helper_fw/companion/build_companion.sh` gives `output/helper_companion.bin` (prints size and SHA-256; it
   warns if the `.bootloader` section is missing, in which case don't flash).

Flash it (core flash untouched):
```
./programmer_cli -d GW5AST-138C --location 4289 --run 56 --mcuFile helper_companion.bin --spiaddr 0x600000
```
Keep a known-good helper `.bin` to roll back to (e.g. `helper_companion_osd3.bin`, `helper_companion_sdwlog_3ec6e20.bin`).

Helper console: the BL616 USB serial (Linux `/dev/ttyUSB1`), 115200 8N1. Useful commands: `c` cold boot, `w` warm
reset, `ls`, `mount a <img>`, `eject`, `save` (atarist.ini), `crc <file>`, `scrc <file>` (per-sector CRC),
`get <file> [off] [len]`, `put`/`h`/`pend` (upload), `key`, `type`, `mouse dx dy`, `click [2]`, `sd`, and with
`SD_WRITE_DEBUG`: `sdwlog`, `sdstate`, `sdrw`. Avoid two programs on the port at once (a concurrent upload left a
0-byte file).

## 9. Tests
- `bash hdl/cpu030/sim/rtl/run_rtl.sh` must print PASS (includes the I and D cache unit tests `run_icache.sh`,
  `run_dcache.sh`); `run_bus.sh` for the whole ST.
- Gate level (CPU netlist): `gw_sh hdl/cpu030/sim/wf030_syn.tcl` makes `impl/gwsynthesis/wf030.vg`; then
  `hdl/cpu030/sim/run_unit.sh` (bridge + netlist, ERRORS=0), `run_icache_net.sh <wf030.vg>` and
  `run_dcache_net.sh <wf030.vg>` (cache hits through the bridge at the fast-RAM alias) must PASS.
- After a Gowin build, check the syn log has "Extracting RAM for identifier" for the cache arrays (D00..D13, TAG0/1,
  DATA_RAM, TAG_RAM): an array that falls back to flip-flops costs thousands of LUTs.
- SD/FDC: `iverilog` benches in `hdl/misc/sim/` and `hdl/fdc1772/sim/run_sim.sh`.
- Board: cold boot (4096 KB memory test, desktop), ST Medium, GEMBench 4.03 All Tests (`gbref.st`) and GEMBENCH 6.08
  All Tests (`gb608.st`, key `a`; reference sets STE20608 default and STFM1048 via File > Open Test) from known-good images
  (check its CRC first: a corrupt image once looked like a CPU bug for days), a runtime image swap with a desktop save.
- Board scripts (box, from `docs/prefetch_cof/board/`, run in a dir with `../hc.sh`): `rl.sh tag` = `c` + 10 reloads with the
  5-grab halt rule; `gembench.sh tag` = GEMBENCH All Tests (ST Medium, STE ref) from a fresh low-res desktop, result
  image `gb_<tag>_result.png`; `go.sh`/`gg.sh`/`grab2.sh`/`cls.py` helpers. Check the serial with `hc.sh s` first.
  The disk-A double-click often needs a second `click 2`; GEMBENCH 6.08 All Tests is started with the `a` key.
- CPU changes to MOVEM or the bus interface: `sim/rtl/prog_movemx.s` (regenerate with `gen_movemx.py`) must be
  identical old vs new in `cmp_wr.sh` at WS 0/1/3/7 (`FILT=5000` for handler-recorded frames), plus prog_movemr/w,
  prog_berrwb, prog_fault, prog_wpberr.
