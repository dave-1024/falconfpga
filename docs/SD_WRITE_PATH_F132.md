# SD write-path bug (Łukasz: A:->C: copy works once, then wrong data / C: in A: window) — 3 Nov 2026

Branch sd-write (worktree /workspace/sdbug/repo, from main 528aea1).

## Phase 1 (read-only)
- dma.v, acsi.v, floppy.v, sdcmd_ctrl.v, mcu_spi.v identical to stock misterynano_tc138k.
- Ours vs stock: sd_rw.v WRITE_FIX/HARDEN, sd_card.v HARDEN sector latch + debug ring, fdc1772 crc_err,
  ST_FLOPPY_MEDIACH, AE350 bit-banged helper link, and the 030 core (D-cache, TT-RAM).
- Latent (also in stock): FDC and ACSI share one SD port with no ownership: sd_busy/sd_done/sd_rd_byte_strobe go to
  both; drive = lowest pending bit but rsector/inbyte mux = is_acsi (last requester); dma.v WRITE_START_SD takes any
  sd_busy as its ack. fdc1772 write-sector raises INTRQ before the posted SD write runs. An overlap would mix images.
- D-cache: WF68K30L dcache follows MC68030: CIIN ignored on writes, so with CACR.WA a write miss to ST-RAM allocates.
  Nothing snoops DMA -> stale lines after floppy/ACSI DMA. Stock 68000 has no cache.

## Phase 2 board test (f131 in flash, EmuTOS 256K, 22:06-22:20 UK)
tools/sdrace/sdrace.s (AUTO prg): 40x Flopwr(trk79) -> DMAwrite(ACSI lba 64+) -> read both back.
Results written to sdrace.hd lba 100 (read back with helper `get`).
| mode | floppy readback errors /40 | ACSI errors |
| A caches on (EmuTOS CACR, WA set), no gap | 40 | 0 |
| B caches on, 0.5 s gap | 40 | 0 |
| C CACR=0 | 1 (run 2) / 0 (run 1) | 0 |
| D caches on, WA cleared | 0 | 0 |
| E caches on, CACR.CD after each Floprd | 35 (data = an OLD sector from 27 iterations earlier) |
| T Floprd into TT-RAM buffer (EmuTOS _FRB) | ok, ST alias untouched |
Card image always had the right data (helper get): writes fine, CPU reads stale cache. E shows the stale
copy happens inside EmuTOS's floppy path (its own buffer), not in our buffer.

## Fix (F132)
wf68k30L_top.vhd generic WA_ADR_HI; bridge sets 1: write-allocate only for $01xxxxxx (TT/fast RAM).
ST-side writes still update hits; no ST entry can be created, so DMA'd ST-RAM stays coherent.
Workaround without a rebuild: clear CACR bit 13 (WA).
