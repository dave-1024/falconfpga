# CONTEXT: external memory for catching up after a context reset

**Update this file whenever the project state changes.** Detailed state and next steps: [`handoff/CONTEXT.md`](handoff/CONTEXT.md).

## Goal
A cycle-exact 68030 (WF68K30L, Wolfgang Foerster) on an Atari ST/STE core on the Tang Console 138K (GW5AST-138),
via a TF534-style bridge, with the SOM's AE350 RISC-V as helper (OSD, SD, floppy images). Later: a Falcon build
with the DSP56001.

## Repo layout and key docs
- `Atarist_030_wip/`: the live core. Main build `build_st_helper.tcl` = the board build (cart off, no SD debug);
  `debug_builds/` (e.g. `build_st_helper_hdn.tcl` = main + `SD_WRITE_DEBUG`), `build_legacy/` (retired scripts).
- Docs: [`handoff/CONTEXT.md`](handoff/CONTEXT.md) (state, next steps) · `Atarist_030_wip/docs/TODO.md` (work order) ·
  `Atarist_030_wip/docs/HISTORY.md` · `Atarist_030_wip/docs/FALCON_LESSONS.md` (lessons, bugs found) · `docs/TOS_COMPAT.md` (top-level `docs/`) ·
  `Atarist_030_wip/docs/BUILD.md` (switches, defaults, flash map).
- Docs index: `docs/README.md`; beginner guide `docs/HOWTO_BUILD.md`; history (retired agent files, dated handoffs,
  patches, investigations such as float_panic/prefetch_cof) in `docs/history/`.
- Reference trees under `reference/` (see `reference/README.md`): `rigsdram/` (030 + SDRAM oracle, do not rebuild),
  `misterynano_tc138k/` (stock fx68k ST), `Hybrid030/` (frozen history).
- `tools/` (hc.sh, up2.py); root `LICENSE` (GPL-3.0 for original work) + `NOTICE.md`.

## Machines and access
- **linserver** `dave@100.97.139.11` over Tailscale (from the box: SOCKS5 `localhost:1055`, ssh `ProxyCommand nc -X 5
  -x localhost:1055 %h %p`). Gowin V1.9.12.03 in `/opt/gowin` (V1.9.12.04 also builds main); repo `~/falconfpga`; bitstreams `~/fpga_bitstreams`
  (SHA256SUMS); tools `~/fpga_tools` (`grab.sh` HDMI grab). sudo password in env `LINSERVER_PASSWORD`.
- **Flashing:** `pgrep programmer_cli` first (a hung one holds the cable); `programmer_cli --scan-cables`, use the
  single reported location; wrap in `timeout -k 10`. Then `--run 1` to reload.
- **Flash map:** core at 0 (op 53 `--fsFile`), TOS at 0x500000 (op 56 `--mcuFile`), helper firmware at 0x600000
  (op 56 `--mcuFile --spiaddr 0x600000`).
- **USB quirks:** after a reload ttyUSB can vanish: `sudo modprobe ftdi_sio`. The helper port can come back as
  ttyUSB0 instead of ttyUSB1 (hc.py/up2.py still hard-code ttyUSB1). Helper serial: 115200 baud.
- **Box quirks:** userspace tailscaled can get stuck (ping works, TCP 22 times out at the SOCKS proxy): restart it with
  its existing state. The box sometimes loses its ssh client: reinstall and recreate `~/.ssh/config` (Host linserver
  as above).

## David's working preferences (defaults, not rules; ask before anything hard to undo)
- Correctness fixes go in with no switch, each with a FALCON_LESSONS entry.
- clk_cpu030 at 17 MHz or above; report Fmax and LUT/ALU for every build.
- Credit contributors; keep licence headers.
- One SDRAM module (J9). TT-RAM and caches on by default; always STE.
- Finish the current queue before starting new work. Keep tokens lean.
- Keep CUPS on linserver working.
- PR flow: push a branch, give David the compare link, he opens the PR, then merge it with the GitHub tool. Keep main current.
- Main tcl = board build; variants in `debug_builds/`, retired in `build_legacy/`.
- Bulk erase, BL616, other flash areas: check with David first (writing the helper at 0x600000 to restore it is fine).

## Current state (summary, 31 Oct 2026)
main = 8972091 (9fe250b merged `pmmu`; 8972091 restored the `syn_keep` on `ae350_flash_clk` for Gowin V1.9.12.04).
The 68030 PMMU is done. FreeMiNT with memory protection + XaAES 1.7.0 + TeraDesk 4.08 run on EmuTOS 1.4 from the ACSI
image; desktop menus work after F121. Flash 0 holds **f121a**: clk_cpu030 20.19 / clk32 34.21 MHz, 45636 LUT + 5317 ALU.
Rule: timing_pairs must pass before any board load. Next: 64 MHz SDRAM / TT-RAM speedup on branch `sdram64`
(based on d270586; rebase onto main first, see `docs/sdram64/REBASE_NOTE.md` on that branch).
Details: [`handoff/CONTEXT.md`](handoff/CONTEXT.md); fixes: [`docs/BUGS.md`](docs/BUGS.md).

## Still-true background (from the Sept 2026 file)
- Locked SOM DDR3 faults: write lane 4 dead; 64-bit read upper half dead; extended AHB HWDATA upper 32 dead. Unmapped
  Falcon IO must bus error.
- PnR: Replicate Resources = TRUE, device version C. Git holds source only (no `.fs`, `impl/`, ROMs or images).

History: until 28 Sep 2026 this file was a base64 block for the retired watcher flow (MiSTeryNano bring-up, Nano HDMI,
rigsdram oracle); see git history.
