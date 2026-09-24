# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260924-2
RESULT: FAIL
GOWIN_VERSION: (not run)
PROJECT: rigsdram
TOP: RIGSDRAM_TOP

ERRORS:
git apply patches/H48_20260924-2.patch failed: "error: corrupt patch at line 17"
Also: patch -p1 --dry-run → "malformed patch at line 17: @@ -268,23 +269,33 @@"
Root cause: first hunk header claims @@ -140,10 +140,11 @@ but the new-side line count is 9
(3 context + 3 added + 3 context), not 11. Second hunk never reached by git apply.
CRLF handling: target was CRLF; converted to LF and re-tried — same corrupt-patch error.
File restored to pre-apply state (CRLF, pll_lock_50 still present).

WARNINGS:
(none — build not started)

RESOURCES:
LUT: (not run)
FF: (not run)
BSRAM: (not run)
DSP: (not run)

TIMING:
Fmax: (not run)
Setup: (not run)
Hold: (not run)

UART:
(not flashed)

NOTES:
Manual/watcher build for 20260924-2 stopped before Gowin. H48_20260924-1 was NOT re-applied.
H48_20260924-2.patch is malformed; fix hunk line counts (first hunk should be
@@ -140,10 +140,9 @@) and/or regenerate the patch, then re-issue BUILD_REQUEST.
lock_meta/lock_sync NOT present; pll_lock_50 still present. No bitstream attempted.
```
