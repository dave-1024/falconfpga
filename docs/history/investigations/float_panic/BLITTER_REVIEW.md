# Blitter review for the Float Math panic (read-only, 2026-10-14)

Scope: `Atarist_030_wip/hdl/atarist/stBlitter.sv`, its hookup in `atarist/atarist.v`, and the
arbitration in `cpu030/cpu030_st_bridge.v` (branch fix-float-hiword @ ef533aa). Nothing was built or flashed.

## Verdict
No defect found that would make the blitter write late or to the wrong address.
`stBlitter.sv` is Jorge Cwik's FX ST Blitter, byte-identical to `misterynano_tc138k/atarist/stBlitter.sv`
(the known-good 68000 core). The hookup and the BR/BG/BGACK chain follow the MiSTer layout. The bridge's
arbiter respects BGACK and doesn't start a 030 cycle while a grant is pending.
Our own earlier evidence also points away from it: the overwrites we caught came from **CPU** code
(HiSoft clear loop at PC $02FFB2, EmuTOS VDI at PC $E1DD02). Those are software drawing into GEMBENCH's
off-screen bitmap, not blitter DMA.

## Checked items
| Area | Where | Finding |
|---|---|---|
| BUSY/HOG | stBlitter.sv:210-227 | BUSY is cleared asynchronously by XYZ (the last write) and also reads 0 while being written, as on a real blitter. When EmuTOS restarts in non-HOG mode (`bset #7`), BUSY just gets set again, and the counters carry on from where they stopped. Correct. |
| Stop/restart | stBlitter.sv:464, 495-502 | `bltActive` only changes at `negIas` (the S6 edge, same clock as oAS rising), so it can't stop mid-cycle and leave a stray write. The exception is the async `negedge busy` (see S2). |
| 64-cycle timeout | stBlitter.sv:263-275 | Counts `as_n` falling edges from every master. Matches the original, including its known quirk. |
| Address counters | stBlitter.sv:634-656 | Src/dst addresses are 23 bits (A23:1). Increments are sign-extended 15-bit values. They only change on `busOwned & updCycle`, and the CPU can only load them while the blitter doesn't own the bus. Wrap only at 16 MB; the GSTMCU then folds that to RAM. Correct. |
| X/Y reload, end masks | stBlitter.sv:563-605, 676-735 | X reloads from xStart when X=1 and Y decrements. A YCOUNT write (`rBltReset`) clears the state machine, XYZ, newLine and the mask selection. No stale state between blits beyond what the hardware keeps (FXSR latch, LineCtr, halftone RAM), and those are reloaded through register writes. |
| Bus mux | atarist.v:286-303 | AS/DS/RW/A/FC are switched on `blitter_has_bus` (= ctrlOe = bltActive), and BGACK on busOwned. With busOwned=1 and bltActive=0 (the first dummy cycle, or yield) the mux shows the CPU side, which is idle. That's the original design. |
| BR/BG/BGACK chain | atarist.v:452-456, 629-637, 1000-1014 | CPU BR = blitter_br & mcu_br. CPU BGACK = blitter_oBGACK & mcu_bgack. Blitter BGO → MCU BG_N (the DMA chip is downstream). Floppy DMA and the blitter can't own the bus together. Correct. |
| Bridge arbiter | cpu030_st_bridge.v:333-386, 550 | BR and BGACK are sampled on en1, arb changes on en2, and BG goes out on en1. No grant during S0 (or during RMC). `can_start` needs arb==IDLE and BGACK high, so a granted or acknowledged bus can't get a 030 cycle. The blitter also waits for AS high (`rdyGranted`, stBlitter.sv:408). I traced both race orders (grant-then-start and start-then-grant, with or without BRIDGE_EARLY_AS) and both are safe. |
| Clocks | atarist.v:568-572, 981-982 | `cpu_16mhz_enable`=0, so the blitter, bridge and MCU all use mhz8_en1/en2. No phase mismatch. |

## Weak spots (unlikely to cause this, but worth a probe)
* **S1: write-data priority.** At atarist.v:440 (MCU DIN) and 296-301 (`mbus_dout`), `~rdy_i`
  (DMA data) wins over `blitter_sel`. `blitter_sel` = dataOe = `busOwned & writeCycle`
  (stBlitter.sv:175), which doesn't depend on bltActive. If `rdy_i` were ever low while the blitter writes,
  RAM would get DMA data at the blitter's address, or blitter data during a DMA cycle. The BR chain should
  prevent this; the DMAWATCH tag `{~rdy_i, blitter_has_bus, ~mcu_bgack_n}` would show both bits set.
* **S2: asynchronous clears.** At stBlitter.sv:217 (`posedge XYZ`) and 495 (`negedge busy`),
  `busy = rBusy & ~ctrlWr` is combinational from the muxed bus (`SEL`, `cpu_rw`, `uds_n`). A glitch could
  stop a blit early (truncated write, missing graphics), but it can't send a write to a new address. This is
  inherited from the FX/MiSTer code.
* **S3: RWn input.** At atarist.v:985, `.RWn(cpu_rw)` is the CPU's RW and not the muxed `rw`. That's fine
  for register access. It only matters for S2, because it keeps ctrlWr false while the blitter is master.

## How to test
1. **Blitter fully off:** set the OSD chipset to plain ST (`blitter_en = core_chipset >= 1`,
   misterynano.sv:733). This also gates the blitter's AS (atarist.v:984), so it can't touch the bus. If
   Float Math still panics, the blitter is cleared. This is cleaner than the EmuTOS desktop
   Options → Blitter toggle, which only stops EmuTOS from using it. Do that one too, as a second check.
2. **DIAG_DMAWATCH** (already on this branch, atarist.v:651-680; decoder `pages_dma.py`): logs every
   RAM write into $55C96-$55D21 with its source. Expect CPU-only entries (bit 3 DMA=0, bit 2 blitter=0).
   Any entry with blitter=1 or DMA=1 is the culprit. Both bits set together means S1.
3. If both show CPU-only writes, the question is software layout, not the bus: why GEMBENCH or VDI still
   draws into the block after it's been handed to Pexec for AUTOFPU. Compare the Mfree/Malloc/Pexec order
   and the bitmap pointer with the Hatari dump.
