# SD write corruption / "state 13" jam: findings (2026-10-15)

Builds (place_option 3, sdw_p3 config = 7e3d5dd, which includes F65 bb9baa2):
- `st_helper_sdlog_d94dde4_p3.fs` (sd-core-log, SD_WRITE_DEBUG): on the board now.
- `st_helper_mch_7df7f29_p3.fs` (sd-mediach, + ST_FLOPPY_MEDIACH): built, timing clean, NOT flashed.
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
