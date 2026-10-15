# SD write corruption / "state 13" jam: findings (2026-10-15)

Builds (place_option 3, sdw_p3 config = 7e3d5dd, which includes F65 bb9baa2):
- `st_helper_sdlog_d94dde4_p3.fs` (sd-core-log, SD_WRITE_DEBUG): debug build (superseded by mch).
- `st_helper_mch_7df7f29_p3.fs` (sd-mediach, + ST_FLOPPY_MEDIACH): flashed 15 Oct, swap retest PASSED.
- `st_helper_hdn_054b0b6_p3.fs` (+ ST_SD_HARDEN): board test PASSED.
- `st_helper_hdn_917668c_p3.fs` (+ give-up -> FDC CRC status): on the board.
- helper `helper_companion_sdwlog_3ec6e20.bin` (sd-write-log): sdwlog / sdstate / sdrw / scrc / get.

## Root cause of the misdirected writes (gb403): runtime image swap, no media change
Reproduced on scratch images. tools2.st was A: and the desktop was saved. Then `mount a gbsnap.st`
(no reset) and ^S Save Desktop. The core wrote image sectors 1, 4, 7, 420 and 421 to gbsnap,
each to card = base + sector (no MOVED flag, no hardware misaddressing). But they carried
tools2's FAT and root directory, and DESKTOP.INF went into cluster 205. In gbsnap that cluster is
inside GEMBENCH.RSC. Afterwards gbsnap's root directory reads TOOLS/REF/AUTO and its sector 420
holds "#R 02 ... #E ... #Q ... #K". That is the gb403 pattern (INF text inside AUTOFPU.BIN).
Cause: `floppy_protected` is only the static OSD setting. Nothing toggles WP when the helper
swaps an image, so TOS never sees a media change and keeps the old disk's FAT/dir cache. This
also explains GEMDOS -35 / unreadable floppies after runtime mounts, and why .ini power-up
mounts are fine.
Fix (sd-mediach, `ST_FLOPPY_MEDIACH`): hold WP for about 0.75 s after each sd_img_mounted pulse.

## State 13 (sd_rw CMD24) jam
`card_stat` is `sdcmd_stat`; 13 = CMD24. Upstream: a CMD24 with no response has no exit, because
CMD24 is not in the `~busy` resend list and no `done` comes. That is the jam in b5a7f96.
ST_SD_WRITE_FIX (7e3d5dd, newer than b5a7f96) retries it 16 times and then reports done.
With it (p3/debug builds) I could not reproduce a jam. I tried a runtime mount plus 2x 737 KB
uploads, including 3 desktop saves injected mid-upload. Result: max 580 clocks in CMD24, 0 WERR,
0 give-ups, 0 read timeouts, 0 bad data tokens, card state 8.
Remaining weaknesses (proposed, not applied):
1. The data-response token (wack) is never checked. A CRC-rejected (101) or write-error (110)
   block counts as success. Now visible as "BAD DATA TOKEN".
2. The CMD24 give-up reports done, so the write is lost silently. It should flag an error and
   re-init the card (CMD0 path) so it doesn't stay in rcv/prg state.
3. CMD17 read-timeout retries are unbounded. A card left in rcv state after an abandoned CMD24
   makes every read retry forever (looks like "not readable" until a reload, which re-inits with
   CMD0). Bound it and fall back to re-init.
4. fdc1772 `sd_lba` is combinational and sd_card latches rsector only when it starts the request.
   It is safe today (the ring flags any change: none seen), but should be latched at the request
   edge.

## ST_FLOPPY_MEDIACH board retest (mch build, 15 Oct 2026): PASS
Restored gbsnap.st (CRC 9bb44fbd). Steps: `mount a tools2.st`, `c`, Save Desktop, then `mount a gbsnap.st`
(no reset), Save Desktop. gbsnap now gets writes to image sectors 1, 4, 7 (its own FAT/root) and 494/495.
Those are cluster 242, its own first free cluster; before the fix they were tools2's 420/421, inside
GEMBENCH.RSC. Per-sector diff against the clean copy: only those 5 sectors. Root directory: gbsnap's own
entries plus EMUDESK.INF (cluster 242, 640 bytes); sector 494 holds the INF text. A further runtime swap to
gbref.st showed gbref's directory (7 items) and GEMBENCH.PRG loaded with its RSC: no -35, no "not
readable". gbref.st CRC still 791ee820.

## ST_SD_HARDEN (on main since 15 Oct 2026)
Implements the 4 items above in sd_rw.v / sd_card.v behind `HARDEN`. Fault-injection bench
`hdl/misc/sim/tb_sd_harden.v`:

| case | result |
|---|---|
| clean write + read | done, data match, 0 recoveries |
| 1 rejected token (CRC error) | 1 re-init, write re-issued, data match |
| 5 rejected tokens / CMD24 never answered | done after 2 re-inits (3 tries) + error count, no hang, card usable after |
| 10 dead reads | 2 re-inits, read completes with the right data |
| 40 dead reads | done after the budget, card usable after |
| HARDEN=0 + rejected token | upstream: block silently counted as written |

FDC error status (`917668c`): a give-up raises `sd_err` (sd_card.v, a level cleared by the next request), which
goes to fdc1772 as status bit 3 (CRC error) and stops multi-sector commands. Bench
`hdl/fdc1772/sim/run_sim.sh`: clean read/write gives status 80; a give-up gives 88 with busy cleared and an
IRQ; the next command clears it; a multi-sector read stops after the failing sector.

Board, 15 Oct 2026: `st_helper_hdn_054b0b6_p3.fs`. Runtime mounts, gbsnap/tools2 swaps with desktop saves (each
image changed only in its own root sector 7), a 737 KB upload with 3 injected desktop saves (CRC ec90e609 ok),
and Float Math 13.080 s from gbref. sdrw: 0 WERR / give-ups / read timeouts / bad tokens, max 580 clocks in CMD24.
CRCs: gbref 791ee820, fnop/blank/gb403 unchanged. Then `st_helper_hdn_917668c_p3.fs` (+FDC error): timing TNS 0,
swap + save + cold boot OK, gbref 791ee820, counters 0. It is on the board now.
