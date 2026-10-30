# falconfpga 030 core: FreeMiNT / XaAES start-up fault — full history for outside review

Written 30 Oct 2026 for an outside reviewer. Branch `copilot-review` = `pmmu` (as of 677863e) plus this
doc, `docs/XAAES_FAULT_BRIEF.md` (short brief) and `docs/cpu030_review.zip`. Times are UK time.
Everything here comes from the working log (quoted as "PROGRESS"), `Atarist_030_wip/docs/FALCON_LESSONS.md`
and the `pmmu` git history. Where something is a theory, it says so.

---

## 1. Setup

| Item | Detail |
|---|---|
| Board | Sipeed Tang Console 138K (Gowin GW5AST-138), HDMI out, SD card, USB debugger (serial + JTAG) on a Linux server ("linserver") |
| Design | STE core with a **WF68K30L** 68030 soft CPU (`Atarist_030_wip/hdl/cpu030/`), plus an **AE350 RISC-V helper** (SD card, floppy/ACSI emulation, serial console at 115200) |
| CPU build in use | **f97fw**: clk_cpu030 **20.123 MHz**, clk32_core 32.015 MHz, 44,524 LUT + 5,327 ALU, 18,213 registers, `tools/timing/timing_pairs.py` passes |
| CPU features | 68030 PMMU (memory protection), I-cache and D-cache (block RAM), no FPU |
| Memory | ST RAM + **16 MB TT-RAM** (alt RAM at $01000000) |
| ROM | **EmuTOS 1.4 256K UK** flashed at 0x500000 (TOS 2.06 backed up). EmuTOS 192K panics on this core (exception 33, pc $00FCCFE4) so it is not used |
| Disk | ACSI hard disk image (FAT16) on the SD card, served by the helper and a direct-map read path in `sd_card.v` |
| OS stack | FreeMiNT 1-19-4a6 `mint030.prg` (memory protection ON), `xaloader.prg` → `xaaes030.km` (XaAES v1.7.0), TeraDesk |
| Reference | Hatari (STE, 68030+MMU, no FPU, EmuTOS 256K, `--ttram 16`, **`--addr24 off`**), same disk image |

Branch: `pmmu`. `main` untouched. Recovery build at flash 0 untouched; test builds are loaded to SRAM.

## 2. The goal

A FreeMiNT desktop on the board: EmuTOS + ACSI disk + mint030 with memory protection + XaAES + TeraDesk.
Hatari runs the same image to the desktop. The board does not.

## 3. The current fault (exact)

Boot gets past the kernel, loads xaloader and xaaes.km, shows the **XaAES v1.7.0 banner**, reads xaaes.cnf, then:

```
pid 1 (xaloader): MEMORY VIOLATION type=hardware RW=w AA=3F97DDA PC=1053A1E BP=11A0000
```

then MiNT shuts down and reboots. **Deterministic**: the same AA and PC on every boot (PROGRESS 17:30, 18:58).
Screens: `/workspace/acsi/cap/mfw_240.png`, `mfx_sheet.png` (not in repo).

### 3.1 Where it is

- PC `1053A1E` = kernel text+0x523F2, inside the kernel's `strcpy` loop (`move.b d1,(a0)+`). The caller passed
  a bad destination pointer.
- Traced in Hatari (addr24 off, same load addresses as the board) to **xaaes.km text+0x6CEC2**, an
  environment-copy loop:

```
loop:  strcpy(a2, src)                 ; dest = a2
       ...
       jsr  kentry->strlen             ; kernel text+5246c
       lea  (1,a2,d0.l),a2             ; a2 += strlen+1   (full/brief indexed EA with d0 as index)
```

- Kernel `strlen` (text+5246c), shape:

```
       move.l a0,d0        ; FIRST write of d0  (d0 = s+1 after the first post-increment test)
       tst.b  (-1,a0)
       beq    s2           ; empty string path
       ...
s2:    suba.l d0,a0
       move.l a0,d0        ; SECOND (final) write of d0 = length
       rts
```

### 3.2 The arithmetic

- AA = 0x3F97DDA = **exactly 2 × 0x1FCBEED**.
- a2 was a TT-RAM pointer ≈ 0x1FCBEEC. If the `lea` used the *first* d0 (= s+1 = a2+1) instead of the
  final length, `a2 + 1 + (a2+1) = 2*a2 + 2` = 0x3F97DDA. Exact fit.
- So the observed address is consistent with "`lea (1,a2,d0.l)` read d0 from one write too early" — the same
  "one write stale" family as F93/F97/C10 (section 5). **This is not confirmed on hardware.** It could
  equally be a2 being wrong before strcpy for another reason.
- 0x3F97DDA also = 0x1F97DDA + 0x2000000 (one extra address bit 25). TT-RAM was tested to rule out an
  address-bit fault (TTMEM, section 6).

## 4. How we got here (timeline, 28–29 Oct)

From PROGRESS, condensed:

1. **First board crash (EmuTOS PRG over TOS 2.06)**: "MEMORY VIOLATION RW=w AA=0" at "Launching GEM", pid 0,
   garbage PC A101A00. Even a 60-byte `GEM.PRG` (HELLO) crashed the same way (11:50) → kernel side.
2. **ACSI integrity proven** (10:40): `tools/mintacsi/crct.s` (CRCT.PRG) CRC32s six files via GEMDOS and
   writes `C:\CRC.TXT`; read back on the host: all match. Disk reads are byte-correct; GEMDOS write+read-back
   works under EmuTOS.
3. **TT-RAM / NOTT detour (self-inflicted, software)**: see section 7.
4. **EmuTOS flashed to ROM** (13:00, David approved). New fault: `RW=r AA=2E020613 PC=101B258` = kernel
   text+0x19c2c after `movea.l (bd.l,d0.l),a0` (full-format extension word). Hatari OK.
5. **F97 found** (14:30) with EATEST and fixed by forwarding (17:13). See section 5.
6. With f97fw MiNT gets to XaAES and hits the **current fault** (17:30).
7. 17:45 – 19:30: isolation tests all pass (section 6).
8. 19:3x – next morning: attempts to run a patched xaaes.km with self-checks (section 8), blocked by
   disk-image problems (F99, section 9).
9. 30 Oct: Copilot suggestions checked (section 10), capture-register and caches-off builds started (section 11).

## 5. F97 — stale index in full-format indexed EA (fixed, but with an unexplained twist)

FALCON_LESSONS: `Atarist_030_wip/docs/FALCON_LESSONS.md` line 481 ("full-format indexed EA used the index Dn
before the previous instruction wrote it").

### 5.1 The bug

MiNT kernel text+19c14..19c22:

```
moveq  #0,d1
move.w d6,d1
move.l d1,d0
add.l  d0,d0
add.l  d1,d0
lsl.l  #3,d0
movea.l (bd.l,d0.l),a0     ; 2070 09b0 <bd32>  full format, base suppressed, 32-bit bd, long index
movea.l (a0),a0
```

EATEST.PRG (`tools/mintacsi/eatest.s`) copies this with a table of known values. On the board: index 0 right,
1..7 wrong; the values read correspond to d0 **before** the `lsl.l #3` (idx*3 instead of idx*24). Brief format
`(0,a1,d2.l)` and `(An)` were right. Hatari: PASS. In a hot I-cache tight loop it failed only ~2/1000 →
pipeline-timing dependent. RTL sim (`sim/rtl/prog_fidx.s`) reproduced it at all wait states once written.

Root cause: in `wf68k30L_control.vhd` state FETCH_EXWORD_1 the **brief** format waits while the index register
is in use (DR_IN_USE / AR_IN_USE), but the **full** format left the state on EW_ACK without that check.
`STORE_ADR_FORMAT` latches INDEX on that exit edge, so an index written by the previous instruction was taken
before its write-back.

### 5.2 First fix: interlock in control.vhd → BLACK SCREEN on board (unexplained)

Commit 0356787. Full-format ext word stays in FETCH_EXWORD_1 while the index reg is in use. Variants built:

| Build | Change | Sim | Board |
|---|---|---|---|
| f97n | interlock (Dn + An), exits accept EW_RDY | prog_fidx 16/16, run_rtl/icache/dcache PASS | **black HDMI** |
| f97p1 | same, Gowin place_option 1 | pass | **black** |
| f97B | Dn-only wait | pass | **black** |
| f97fx | registered FX_WAIT flag, no EW_RDY exits (fixes a real EW_RDY/MOVES/PMOVE concern found by reading) | 16/16 | **black** |
| f97C | same tree with *original* control.vhd | – | **desktop** |

- tb030 sim of the EmuTOS 256K ROM boot, fixed vs unfixed, three configs (default 1.5M clk; IPL_MODE=3 WS=3
  3M clk; CIMODE=1 WS=0): **bus traces bit-identical**. EmuTOS doesn't use full-format EAs early.
- timing_pairs passes on all; no new loop warnings; SDC has no false/multicycle path near FETCH_DEC.
- The black screen follows the control.vhd change, not placement (f97C vs f97p1). **Still unexplained**: a
  sim/hardware mismatch somewhere in the control FSM. Reverted in d3ec40d.
- F94 (registering the ST_HELPER mailbox read select on clk_32, commit 22b6c04) also gave black on its own and
  was reverted (ff9a375). Two unrelated changes both blacking is noted in FALCON_LESSONS (line ~526).

### 5.3 Working fix: forwarding (commit 8c55cb0, build f97fw)

No fetch-logic change. Data register file exposes "write-back pending for this Dn" and its live value; the
address unit keeps re-reading INDEX while pending, plus one clock.

- `Atarist_030_wip/hdl/cpu030/wf68k30L_data_registers.vhd`
  - ports l.70–72: `DR_IDX_SEL`, `DR_IDX_OUT`, `DR_IDX_PEND`
  - pending tracking `DR_USED_1/2` set at l.114/116
  - l.130–135:
    ```vhdl
    DR_IDX_OUT  <= DR(conv_integer(DR_IDX_SEL));
    DR_IDX_PEND <= '1' when DR_USED_1(3) = '1' and DR_USED_1(2 downto 0) = DR_IDX_SEL else
                   '1' when DR_USED_2(3) = '1' and DR_USED_2(2 downto 0) = DR_IDX_SEL else '0';
    ```
- `Atarist_030_wip/hdl/cpu030/wf68k30L_address_registers.vhd`
  - ports l.72–74 `INDEX_LIVE`, `INDEX_PEND`, `IDX_SEL`; signal `IDX_TRK` l.152
  - l.182: `IDX_SEL <= EXT_WORD(14 downto 12) when STORE_ADR_FORMAT = '1' else IDX_N;`
  - l.327–333: while `IDX_TRK='1'`, `INDEX := INDEX_LIVE` (long) or sign-extended word
  - l.335–345: IDX_TRK is set at STORE_ADR_FORMAT when `EXT_WORD(15)='0'` (Dn index) and `INDEX_PEND='1'`;
    cleared when INDEX_PEND drops (one clock later the written value has been taken)
- Wiring: `wf68k30L_pkg.vhd` l.150–152, 541–543; `wf68k30L_top.vhd` l.545.

Points a reviewer may want to check:
- Forwarding only covers a **Dn** index (`EXT_WORD(15)='0'`); An index relies on the existing path.
- IDX_TRK is set **only** on the STORE_ADR_FORMAT edge. If PEND is 0 at that edge but a *second* write to the
  same Dn is still to come (back-to-back writes like strlen's `move.l a0,d0 … move.l a0,d0`), is that covered?
  `prog_dw2.s` (section 6) was written for exactly this and passes in sim.
- Does it apply to the **brief** format too? The brief format had the control.vhd wait already.
  `lea (1,a2,d0.l)` is a brief-format EA (8-bit displacement), so if the fault is the lea, it is the brief
  path's interlock, not F97 forwarding, that would be failing.
- DR_USED tracks at most two pending writes (DR_USED_1/2).

Results f97fw: prog_fidx 16/16, run_rtl/icache/dcache PASS, EmuTOS desktop after cold boot, EATEST PASS
(`cap/eatfw.png`), MiNT past the old crash to XaAES.

## 6. Everything that passes (but the full boot still fails)

| Test | Source | What it does | Hatari | Board | RTL sim |
|---|---|---|---|---|---|
| EATEST | `tools/mintacsi/eatest.s` | exact MiNT text+19c14 sequence, table of known values | PASS | PASS (f97fw) | `prog_fidx.s` 16/16 |
| CRCT | `tools/mintacsi/crct.s` | CRC32 of 6 boot files via GEMDOS + write CRC.TXT | PASS | PASS | – |
| EA3 | `tools/mintacsi/ea3/gen.py`, `tail.s`, `tests.txt` | **692** generated EA cases: brief/full, bd.w/bd.l, base-suppressed, PC-rel, memory pre/post-indexed × Dn/An index × .w/.l × scale 1–8 × prior op writing the index (moveq/move/lsr/addq/add/move.w/load/lea/adda) + base reg loaded by previous insn; 2 passes, caches on | PASS | PASS (`cap/ea3_b2.png`) | – |
| TTMEM | `tools/mintacsi/ttm/ttm2.s` | 16 MB TT-RAM, addr^key, move.l and movem pairs, per-MB errors | PASS | P0–P3 0 errors | – |
| SLTEST | `tools/mintacsi/sl/sl.s` | exact strcpy/strlen/lea sequence, 2×5000 loops, direct and kentry-table jsr | PASS | PASS (ST RAM) | – |
| SLTT | `tools/mintacsi/sl/sltt.s` | same code copied to TT-RAM | PASS | PASS (`cap/sl8.png`) | – |
| SLE | `tools/mintacsi/sl/sle.s` | empty-string strlen path, TT-RAM | PASS | PASS (`cap/sl9b.png`) | – |
| prog_slmmu | `hdl/cpu030/sim/rtl/prog_slmmu.s` | strlen+lea, PMMU on, strlen in own page, pflusha/cache flush, empty string | – | – | 16/16 |
| prog_irqwb | `hdl/cpu030/sim/rtl/prog_irqwb.s` | strlen('') tail + lea with periodic level-4 irq, movem save/restore handler | – | – | 0 errors (WS=0, ~1050 irqs ×2); WS=3 no error in 1.6M clk |
| prog_dw2 | `hdl/cpu030/sim/rtl/prog_dw2.s` (commit 47cef5b) | **8 cases** of two back-to-back pending Dn writes + `lea (1,a2,d0.l)`, bsr/jsr/rts, word and long index | – | – | 16/16 configs |

Sim configs: `run_rtl.sh` sweeps CIMODE 0/1, FASTH 0/1, WS 0/1/3/7. All of the above sim programs are in
`Atarist_030_wip/hdl/cpu030/sim/rtl/run_rtl.sh`.

Conclusion so far: **the isolated sequence never fails**, on the board or in sim. Only the full MiNT boot
does, deterministically. Whatever differs (MMU state, TT-RAM placement, interrupts, cache contents, timing of
a particular fetch) has not been reproduced.

## 7. TT-RAM / NOTT detour (software, self-inflicted — resolved)

- We tried hiding TT-RAM with `AUTO\NOTT.PRG` clearing `_ramtop` ($5a4) and `ramvalid` ($5a8). MiNT then
  panicked: "Alt: 16196400 B" then bus error at addr 0200003b, pc text+537b6 (8 MB TT-RAM → 0180003b).
  Reproduced identically in Hatari.
- Cause, from source:
  - EmuTOS 1.4 `bios/memory2.c`: `detect_ttram_size()` l.36–72, `ttram_detect()` l.79–120 sets `_ramtop`,
    `altram_init()` l.138 `xmaddalt(TTRAM_START, ramtop-TTRAM_START)` — the whole 16 MB is added.
  - FreeMiNT `sys/memory.c` l.430–443: alt regions come from `Mxalloc(-1, F_ALTONLY)`, not `_ramtop`.
  - FreeMiNT `sys/arch/mprot030.c` l.250–258 `mint_top_tt = *(ulong*)0x5a4`; l.302
    `global_mode_table_size = 2048 + tt_mbytes*128`; l.648 `mark_region()` does an unchecked
    `memset(&global_mode_table[start>>13], mode, len>>13)`.
  - With `_ramtop` cleared, the table is 2 KB but TT regions still exist → memset runs off the top of TT-RAM.
- Lesson: don't touch `_ramtop`/`ramvalid`. Latent FreeMiNT bug (no bounds check). Without NOTT, Hatari
  (EmuTOS256 + ttram16 + MP on) boots to XaAES with xaaes.km in TT-RAM (0x1F44170).
- Earlier, clearing the TT-load prgflags on xaaes.km/xaloader/DESKTOP (mint030c) did **not** fix the
  (pre-F97) hang either.

## 8. EmuTOS choices

- EmuTOS **PRG** over TOS 2.06: the old "AA=0 at Launching GEM" crash; the same kernel + HELLO under plain TOS
  2.06 from floppy worked (12:50).
- EmuTOS **1.4 256K ROM** at 0x500000 (David approved; TOS 2.06 backup kept): used now.
- EmuTOS **1.4 192K**: "Exception number 33" at pc $00FCCFE4 before disk boot on this core (unexplained, not
  investigated further).

## 9. Patched xaaes.km attempts and the disk-image trouble

Aim: answer "is d0 already wrong when strlen returns, or does the lea read it wrong?" with a patched xaaes.km.

- **helper1** (`tools/mintacsi/xp/helper.s`): at site text+6ced8, jumps to a helper at text+0x10886 that
  compares d0 against the real string length before the lea and prints both.
- **helper2** (`tools/mintacsi/xp/helper2.s`): at the strcpy site text+6ceb8, checks the destination a2
  (fault address encodes d2/a2 if a2 ≥ 0x2000000). Both pass in Hatari.
- **KMCOPY** (`tools/mintacsi/xp/cp.s`): floppy AUTO program to copy the patched km onto C:.

What happened:
1. mint030g / mint030x (patched km in a copy of the image) → "FreeMiNT loader: **Pexec() failed!**".
2. KMCOPY from floppy, then boot mint030b: fault **identical**, helper never fired. But we could never confirm
   KMCOPY ran (key presses at the splash may have dismissed it; a no-key version never ran from AUTO at all).
   **So the "helper did not fire" results are not trustworthy.**
3. Every freshly uploaded image (x, y, ...) failed with Pexec() failed even with matching CRCs.
4. **F99 theory — SD position (DISPROVED).** Failing images all started above ~card LBA 2^18 (128 MB), working
   ones below. Tried `sd_card.v` direct_start in flip-flops (`syn_ramstyle`, module-level `ds`) — commit
   dd4763d, build f99a (21.98 MHz, 45,763 LUT) — no change. Then f99d with `SD_WRITE_DEBUG` logged the
   core's reads: correct base (361624), correct last sector (base+2167), 61 reads, **0 timeouts/bad tokens**.
   The core reads the right sectors. (Pitfall: `build_st_helper.tcl` rewrites `build_sel.vh`, so the debug
   define was silently off in the first attempt.)
5. **Real split: image content.** Card-native `mint030.hd` (boots) has 040SP/060SP.PRG and a 185-byte
   MINT.INI; the local copy everything was built from (crc 31dc9006) lacks them, has a 72-byte MINT.INI
   (WRITE_BOOT=YES) and BOOT.LOG. Rebuilt with the card's MINT.INI (mit_q1.hd): **still Pexec() failed**, so
   MINT.INI isn't the difference either. The cause is still open; that image boots in Hatari.
6. Pulling files off the card over the helper's serial `get` hangs intermittently, so diffing images that way
   is very slow. The patched-km route was dropped for now.
7. Earlier one SD read showed a timeout at sector 272163 (mint030x); not seen in the f99d log.

FALCON_LESSONS entry: "F99 'Pexec() failed' after uploading .hd images (OPEN)", line 544.

## 10. Copilot's suggestions and what was checked

| Suggestion | Checked | Result |
|---|---|---|
| Register file mapped to BSRAM, read-during-write differs from sim | Gowin synthesis report | **No RAM extracted** for data/address registers; they're flip-flops. Ruled out |
| BSRAM read-during-write elsewhere (C10-style) | Synthesis | **I-cache and D-cache arrays are BSRAM.** C10 was exactly this in the I-cache (FALCON_LESSONS l.202): DATA_RAM mapped to SDPB, read sampled at the edge, no write-through, fixed by an FW_V/FW_IDX/FW_DATA forwarding register (tt19, 71624aa). A similar stale read in the D-cache or another I-cache path could produce a stale value → **caches-off build f100nc** |
| Capture what the lea actually used | – | **f100d** capture registers |
| Compare forwarding-path timing between black-screen and boot builds | not done yet | – |
| Check full-format decoding uses the same forwarded value | partially (section 5.3 notes) | – |

## 11. In progress now (30 Oct)

- **f100d** (F100 `IDX_DEBUG`): small registers capturing the INDEX value used, the index register selected
  and the computed address (`INDEX_S` in address_registers), readable over serial after the crash. dw2 sim
  16/16 with it. Rebuilding because the first build pruned the latches (needs `DEBUG_LOG`/`SD_WRITE_DEBUG`
  defines too). Not on `pmmu` yet.
- **f100nc**: CDISn=0, both caches hard-off, no debug. Boot to the crash: if it disappears, look at the caches.
  The NOCACHE generic (F90, 8fcc0f8) and nc1/nc2/nc3 build scripts exist
  (`Atarist_030_wip/debug_builds/build_st_helper_nc*.tcl`). Note: earlier (F84) nc builds gave black screens
  "build, not caches" — a recurring black-screen problem.

## 12. Related recurring pattern ("one write stale")

FALCON_LESSONS l.504: C10 (I-cache BSRAM returns old long), F93 (l.460: scaled index used previous brief word's
scale, fixed 39ab2c4), F97 (index latched before write-back). The current fault's arithmetic fits the same
pattern. F93 was found with an on-board BRAM bus trace (`cpu_trace.v`, `debug_builds/build_st_helper_trace*.tcl`);
C10 with a DIAG ring of the decoder word stream plus reading the `.vg` netlist.

## 13. Open questions for the reviewer

1. Why would a pipeline interlock in `wf68k30L_control.vhd` FETCH_EXWORD_1 (four variants) give a black screen
   on the board while RTL sim of the EmuTOS boot is bit-identical? What sim/synthesis mismatches in a VHDL FSM
   are typical (incomplete sensitivity lists — see FALCON_LESSONS just above C10 — `bit` vs `std_logic` init,
   uninitialised signals, latches inferred)?
2. Given the fault arithmetic, which paths could deliver a stale d0 to `lea (1,a2,d0.l)` (brief format) only in
   a full OS context: return from `rts` with prefetch from a different page, PMMU table walk or ATC miss on
   the jsr/rts target, an interrupt or exception between strlen and lea, D-cache/I-cache BSRAM read-during-write?
3. Is the brief-format interlock (DR_IN_USE / AR_IN_USE wait in FETCH_EXWORD_1) complete for two pending writes
   to the same Dn (DR_USED_1 and DR_USED_2)?
4. Could a2 be wrong for an unrelated reason (e.g. strcpy return value, kentry table call path) — what's the
   cheapest discriminating board test?
5. Why do images built from our local copy give Pexec() failed on the board but boot in Hatari, while the core
   is shown to read the right sectors?
6. Why does EmuTOS 192K hit exception 33 on this core?
7. Better hardware-capture approaches than GAO that change placement less?

## 14. Key files

- CPU: `Atarist_030_wip/hdl/cpu030/wf68k30L_{control,address_registers,data_registers,top,pkg,icache,dcache,mmu,bus_interface,opcode_decoder,exception_handler,alu}.vhd`
- Sim: `Atarist_030_wip/hdl/cpu030/sim/rtl/` (`run_rtl.sh`, `prog_fidx.s`, `prog_slmmu.s`, `prog_irqwb.s`, `prog_dw2.s`)
- Board test PRGs: `tools/mintacsi/` (`eatest.s`, `crct.s`, `ea3/`, `ttm/`, `sl/`, `xp/`, `NOTES.md`)
- Lessons: `Atarist_030_wip/docs/FALCON_LESSONS.md` (C10 l.202, F93 l.460, F97 l.481, F94 note ~l.526, F99 l.544)
- Timing check: `tools/timing/timing_pairs.py`; build: `Atarist_030_wip/build_st_helper.tcl`
- Short brief: `docs/XAAES_FAULT_BRIEF.md`; source zip: `docs/cpu030_review.zip`

## 15. Commits (pmmu, newest first)

```
677863e FALCON_LESSONS F99: position theory disproved by SD_WRITE_DEBUG; content difference
661b4ad FALCON_LESSONS F99: register fix did not cure it; cause open, workaround
dd4763d F99: sd_card direct_start in registers + module-level ds
47cef5b F98: prog_dw2 (two back-to-back pending Dn writes + lea (1,a2,d0.l)) - passes 16/16
3be5155 xp: helper2 (strcpy dest check) and KMCOPY floppy copier
502eb8f F97 follow-up: EA3/TTMEM/strlen test PRGs, prog_slmmu, prog_irqwb, xaaes.km d0-check helper
8c55cb0 F97: forward the index Dn write-back into INDEX (f97fw: desktop, EATEST PASS, MiNT reaches XaAES)
d3ec40d Revert F97 control.vhd interlock: blacks the board, sim passes
0356787 F97: full-format extension word waits for the index write-back (board black)
ff9a375 Revert F94
a56dc96 FALCON_LESSONS: F93
39ab2c4 F93: indexed EA takes SCALE from the brief word at the STORE_ADR_FORMAT edge
8fcc0f8 F90: NOCACHE generic
```
