# Building and flashing Atarist_030_wip (Tang Console 138K)

Short version: install Gowin V1.9.12.03, run `gw_sh build_st_helper.tcl` in `Atarist_030_wip/`, check timing,
flash `impl/pnr/st_helper.fs` with `programmer_cli` operation 53. The details and the reasons are below.

## 1. What you need
- **Gowin EDA V1.9.12.03** (Windows, the version every build here was made and timed with). Other versions place
  differently, and this design is placement sensitive (see section 5).
- **Board:** Sipeed Tang Console 138K (GW5AST-LV138PG484AC1/I0, device version C) with the SDRAM module.
- **TOS image:** TOS 2.06 (256 KB, `tos206.img`, any language) is what all tests use. EmuTOS 256K also boots.
  TOS is stored in the board flash at 0x500000 (section 7), not in the bitstream.
- **SD card** (FAT) with floppy images, e.g. `blank.st` and GEMBENCH `gb403.st`. The AE350 helper mounts them.
- **AE350 helper firmware** (`helper_fw/`, see ST_HELPER.md) flashed at 0x600000.

## 2. Layout
- `hdl/`: all HDL. `hdl/cpu030` (the WF68K30L 68030 core and the ST bus bridge), `hdl/atarist`, `hdl/gstmcu`,
  `hdl/ikbd`, `hdl/jt49`, `hdl/fdc1772`, `hdl/hdmi`, `hdl/misc` (ST core from MiSTeryNano), `hdl/helper` (AE350 SoC glue,
  PLLs), `hdl/tang/console138k` (top level, pins `.cst`, timing `.sdc`).
- `helper_fw/`: firmware for the AE350 RISC-V helper (FPGA-Companion based).
- `build_st_helper.tcl` (the main build), `build_tc138k.tcl` (desktop only, no helper), `build_ae350_serial.tcl`.
- Benches: `hdl/cpu030/sim/rtl/run_rtl.sh` (CPU RTL, GHDL), `hdl/cpu030/sim/st/run_bus.sh` (whole ST, Icarus).

## 3. Build
```
cd Atarist_030_wip
C:\Dev\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe build_st_helper.tcl
```
Output: `impl/pnr/st_helper.fs`, the timing report `impl/pnr/st_helper_tr_content.html`. A build takes about 25 min.
The script writes the compile-time switches into `hdl/tang/console138k/build_sel.vh` (Gowin has no command-line
define), which `top.sv` includes. To change a switch, edit the `puts $fh` lines at the top of the tcl.

## 4. Compile-time switches (`define)
Rule of the project: options are `define switches, off unless they are needed; no runtime hacks.

| switch | default in build_st_helper.tcl | what it does | why |
|---|---|---|---|
| `ST_HELPER` | on | AE350 RISC-V helper next to the ST: SD card, floppy/HD images, keyboard/mouse from the console, OSD | the board has no other way to load disks |
| `ST_HELPER_OSD` | on | MiSTeryNano OSD drawn on the HDMI picture by the helper | menu without a PC |
| `ST_COLOUR_MONITOR` | on | colour monitor (low/medium res); off = mono ST High | GEMBENCH and most software need colour |
| `ST_STE` | on | STE chipset (TOS in the ST ROM slot) | TOS 2.06 + STE features |
| `BRIDGE_EARLY_AS` | on | 030 bridge asserts AS for ST RAM cycles 62.5 ns after the address instead of 125 ns (still a legal 68000 cycle) | an 030 request lands just after the 8 MHz edge; without this every new transfer misses its 500 ns GSTMCU slot (notes/RAM_PATH.md). Delete the line to get the original 68000 timing, e.g. to measure a CPU-side fix alone |
| `ST_030_CACHES` | off | experimental 030 I/D caches | incomplete (no CIIN, burst, DMA snoop), see TODO.md |
| `ST_SD_WRITE_FIX` | off | helper SD write busy-wait/retry | SD writes still time out, see TODO.md |
| `DIAG_OVERLAY` | off | on-screen diagnostic overlay (DIAG_OVERLAY.md) | debugging only; never commit it switched on |
| `WF030_TRACE` | off (branch `diag-trace`, `build_trace.tcl`) | in-fabric bus trace, dumped over HDMI | how the JSR bug was found |
| `DISABLE_BLITTER`, `DISABLE_ACSI` | off | leave those blocks out | resource/debug |

## 5. place_option (placement)
The design is sensitive to placement: the same RTL can fail timing or, in one case, give a bitstream whose AE350
helper did not boot. Builds here use `set_option -place_option 3` first and `1` if 3 fails. Never accept a build that
does not meet timing; try the other place option instead of changing constraints.

## 6. Check timing (before every flash)
In `impl/pnr/st_helper_tr_content.html`:
1. **TNS table: 0 on every clock**, setup and hold. Typical: clk32_core ~32 MHz, clk_cpu030 ~17 MHz.
2. **Recovery and removal tables** (further down, NOT included in the TNS table): every slack positive. These are
   the asynchronous reset paths; the reset synchronisers (HISTORY.md) made them clean (recovery ~+7.5 ns,
   removal ~+0.25 ns).
3. Ignore the header's "violated endpoints" count; it does not match the tables.

## 7. Flash (programmer_cli)
Find the cable location first (it changes when the PC reboots):
```
programmer_cli.exe --scan-cables
programmer_cli.exe --scan --location 289
```
Bitstream (to the flash, op 53):
```
programmer_cli.exe --device GW5AST-138B --operation_index 53 --fsFile impl\pnr\st_helper.fs --location 289
```
- TOS lives at flash 0x500000 (written once with op 56 `--mcuFile tos206.img` at that address), the helper
  firmware at 0x600000. Operation 53 only writes the bitstream area; the bitstream must end below 0x500000
  (the log prints the end address, about 0x04D0000).
- **Never bulk erase** and never write over 0x500000/0x600000 by accident: TOS and the helper firmware are gone then.
- Check the file hash before flashing (`Get-FileHash`), and after flashing cold boot to the desktop at once. Keep the
  last good `.fs` to go back to.

## 8. Tests
- `bash hdl/cpu030/sim/rtl/run_rtl.sh` must print PASS (CPU core, GHDL).
- `bash hdl/cpu030/sim/st/run_bus.sh <wf030.vg>` (whole ST with sdram.v): read-data timing, no late reads.
- On the board: cold boot (memory test 4096 KB, desktop), warm reset, ST Medium, GEMBENCH 6 All Tests.
