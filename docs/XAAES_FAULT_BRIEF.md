# XaAES start-up fault on the 030 core (brief for outside review)

Setup: WF68K30L 68030 core in an STE core on a Tang Console 138K (build f97fw, about 20 MHz),
EmuTOS 1.4 with 16 MB TT-RAM, ACSI hard disk image, FreeMiNT mint030 with MMU memory protection on, no FPU, xaaes030.km.

Symptom: boot reaches the XaAES v1.7.0 banner, then the same failure every time:
`pid 1 (xaloader): MEMORY VIOLATION RW=w AA=3F97DDA PC=1053A1E`.
The same disk image runs cleanly in Hatari (030, MMU, TT-RAM, --addr24 off).

Where: xaaes.km text+0x6CEC2, an environment-copy loop: strcpy into a2, kernel strlen, then
`lea (1,a2,d0.l),a2`. The bad address is exactly 2 x 0x1FCBEED, consistent with the lea using strlen's
first `move.l a0,d0` value instead of the final length (unconfirmed on hardware).

Recent fix F97 (see FALCON_LESSONS.md): a full-format indexed EA used a stale index Dn right after it was written.
The fix forwards the pending data register write-back to the address unit. A pipeline-interlock version in
control.vhd matched simulation exactly but gave a black HDMI screen on the board (unexplained).

Passing in isolation, on the board and in RTL simulation: 692 indexed-EA cases, TT-RAM and cache tests,
MMU plus interrupt write-back tests, and 8 strlen-then-lea patterns (prog_dw2) across cache and wait-state settings.

Questions: why could hardware differ from RTL here (bypass timing, BSRAM read-during-write, multicycle paths)?
Why would the interlock version give a black screen? Is there any 68030-specific lea / full-format index subtlety?
