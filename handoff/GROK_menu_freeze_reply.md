# XaAES menu freeze on first hover/click — detailed diagnosis

**Date:** 31 October 2026  
**Source:** Review of `handoff/BRIEF_menu_freeze.md` (copilot-review), PC samples, F116 fix in `wf68k30L_address_registers.vhd`, and `prog_pea.s`.  
**Gateware:** f116a (TT-RAM on). Branch `pmmu` (HEAD 085fa99 at time of brief).  
**Reference:** Hatari (same image, 68030+MMU, 16 MB TT-RAM) opens the Desk menu immediately.

---

## 1. Exact symptom

Gateware f116a boots FreeMiNT 1-19-4a6 + XaAES 1.7.0 + TeraDesk (EmuTOS 1.4 etos256uk) from an ACSI image to the TeraDesk desktop reliably (5/5 cold boots).

- First mouse hover over “Desk”: title turns inverse, drop-down never draws.
- After a click: pointer disappears, screen freezes.
- No reset, no MEMORY VIOLATION, no other fault message.
- Hatari opens the drop-down at once (“TeraDesk Info… / XaAES v1.7.0 Beta / Tera Desktop”).

## 2. PC samples (f117b = f116a + ~33 ms register sampler)

File: `handoff/pcs_f117b.txt`.

- **Before hover:** kernel idle loop at `$0103B3xx` / `$0103CFA4`, SP `$01088xxx`.
- **After click:** always supervisor (SR 2300), SP `$01EEDxxx`–`$01EEExxx` (process kernel stack; XaAES runs in kernel space ~`$01F4xxxx`). Never returns to idle.

Sampled PCs include:

- `$010548AA`–`$0105491C`: kernel `vsprintf` format loop (`%` check), helpers `$01054786` (number, `divul.l`) and `$01054852` (padding).
- `$01053A98`: `strlen`.
- `$01039BEC`…: pipefs write; `$01039D0E` `lea (a2,d0.l,$10),a0` (idx & `$FFF` = 4 KB pipe ring copy; pipe list at `$0108AC30`).
- Also `$010499B4` (name lookup), `$01033296` (memory block magic ‘S1’/‘S2’/‘S4’ checks), `$01021444`, `$01013E64`, `$0104F9C6`.

Hatari breakpoints on the same run: the pipe write `$01039D0E` is never hit after desktop, and `vsprintf` runs ~135× during boot and ~0× after desktop (hover and click included). On the board, opening the menu causes continuous formatting into a pipe (kernel ALERT into XaAES’s alert pipe, or an XaAES log path that only the board takes).

Disassembly came from a Hatari TT-RAM dump (kernel loads at the same addresses on both).

## 3. Recent related fixes

From `docs/FALCON_LESSONS.md`:

- **F110** `hdl/tang/mega138kpro/sdram.v`: ST CAS sets bank 0; REFRESH deferred while a TT bank is open (wrong-bank reads).
- **F112** `hdl/atarist/mfp.v`, `io_fifo.v`: MFP TX-empty and TX interrupt from its own baud timer.
- **F116** `hdl/cpu030/wf68k30L_address_registers.vhd`: `muls.w`/`mulu.w` then a full-format EA using the same Dn as index (`pea (bd.l,Dn.l)`) used Dn from before the multiply. This was the cause of the earlier XaAES reboot loop. Fix: `AR_IN_USE` stays high while `IDX_TRK` is set. F97 had covered single-clock writers (`lsl`/`add`). Test: `hdl/cpu030/sim/rtl/prog_pea.s` + `expect_pea.txt`.

Relevant F116 code (`wf68k30L_address_registers.vhd` ~241–245):

```vhdl
-- [F116] While a full-format EA tracks a pending write-back of its index Dn (IDX_TRK, F97), report the
-- address unit busy so the control unit holds the EA calculation ... until INDEX holds the written value.
-- F97 alone covered single-clock writers (lsl, add); after MULS/MULU the next PEA/LEA (bd,Dn) used Dn
-- from before the multiply (XaAES +$3266).
AR_IN_USE <= '1' when IDX_TRK = '1' else
             ...
```

## 4. Which 68030 instructions/idioms can fail the same way as F116?

F116 was a multi-cycle Dn write (`muls.w`/`mulu.w`) followed by a full-format indexed EA that used that Dn as the index, sampled before write-back. The menu path (screen-area save under the menu, VDI blit/raster copy, form/rectangle lists, mouse/event handling, ALERT/pipe formatting) contains the same shape.

| Instruction / idiom | Why it can fail like F116 | Where it appears in the menu path |
|---------------------|---------------------------|------------------------------------|
| `divs.w` / `divu.w` / `divs.l` / `divu.l` / `divul.l` | Multi-cycle; quotient/remainder written late. Subsequent indexed EA using that Dn. | `vsprintf` number conversion (`$01054786` in the samples), rectangle scaling, mouse coordinate math. |
| `muls.l` / `mulu.l` | Same class as the `.w` forms F116 already hit, but 32-bit. | Width/height calculations, blit pitch. |
| `bfextu` / `bfins` / `bfffo` / `bfchg` etc. | Multi-cycle bit-field; destination Dn/An written late. Full- or brief-format EA that uses the result as index. | VDI bit-block transfers, form lists, cookie/flag packing. |
| `cas` / `cas2` | Multi-cycle; updates Dn and memory. Subsequent EA using the updated Dn. | Lock/refcount paths (less common). |
| `movem` (to memory, or with post-increment An) then indexed EA using one of the written registers | Register write-back timing vs. EA calculation. | Saving/restoring menu context, rectangle lists. |
| Brief-format indexed EA after any of the above | F97/F116 focused on full-format; brief path relies on `DR_IN_USE`/`AR_IN_USE` interlock. A late write can still race if the interlock drops one cycle early. | The pipe-ring `lea (a2,d0.l,$10),a0` at `$01039D0E` is brief-format and appears in the stuck samples. |
| Memory-indirect `[bd, Dn]` or outer-displacement forms after a multi-cycle writer | Same sampling window as full-format. | Possible in complex VDI or AES object walks. |
| Misaligned long access that splits and re-uses a Dn as index on the second half | Address calculation sees intermediate state. | Rare, but VDI can do unaligned copies. |

The PC samples already highlight the highest-value cases: `divul.l` inside `vsprintf` and the brief-format `lea` inside the pipe write.

## 5. Short GHDL test programs (pattern of `prog_pea.s`)

Each writes results to `$5000+` and ends with the usual `move.l #$600dc0de,$3300` + hang. Expected values are the correct post-instruction results. Run under `run_rtl.sh` (tb030, ROMFILE=hex) at WS=0/1/3/7 and with caches on/off. A failure that uses the pre-instruction register value is the same bug class as F116.

### 5.1 `divul.l` then brief LEA (matches the pipe `lea` shape)

```asm
        lea     0x5000,a5
        lea     0x2000,a2
        move.l  #100,d0
        move.l  #7,d1
        divul.l d1,d0               ; d0 = 14
        lea     (10,a2,d0.l),a0
        move.l  a0,(a5)+
        move.l  #0x600dc0de,0x3300
h:      bra.s   h
; expect a2+10+14 = 0x2018
```

### 5.2 `divs.w` then full-format PEA (direct F116 analogue)

```asm
        lea     0x5000,a5
        move.w  #100,d3
        divs.w  #7,d3
        pea     (0x1000.l,d3.l)
        move.l  (a7)+,(a5)+
        move.l  #0x600dc0de,0x3300
h:      bra.s   h
; expect 0x1000 + 14 = 0x100E
```

### 5.3 `muls.l` then brief LEA

```asm
        lea     0x5000,a5
        lea     0x3000,a2
        move.l  #6,d0
        muls.l  #8,d0
        lea     (4,a2,d0.l),a0
        move.l  a0,(a5)+
        move.l  #0x600dc0de,0x3300
h:      bra.s   h
; expect a2+4+48 = 0x3034
```

### 5.4 `bfextu` then indexed EA

```asm
        lea     0x5000,a5
        lea     0x4000,a2
        move.l  #0x00ff0000,d0
        bfextu  d0{8:8},d1          ; d1 = 0xff
        lea     (0,a2,d1.l),a0
        move.l  a0,(a5)+
        move.l  #0x600dc0de,0x3300
h:      bra.s   h
; expect a2 + 0xff = 0x40FF
```

### 5.5 `movem.l` then LEA using a written An (optional)

```asm
        lea     0x5000,a5
        lea     0x5000,a2
        movem.l a2-a3,-(a7)
        ; restore or use one of them as base/index in a following LEA
        move.l  #0x600dc0de,0x3300
h:      bra.s   h
```

## 6. What a menu open does that boot/desktop drawing does not

- First use of the AES menu drop-down path: save the screen rectangle under the menu (VDI `vro_cpyfm` / blit or raster copy), build the drop-down object list, and draw it.
- First heavy use of XaAES’s alert/pipe path after the desktop is up. The samples show continuous `vsprintf` + pipe write that Hatari never does post-desktop. Something on the board is raising a kernel ALERT (or an XaAES log that formats into the alert pipe) that only occurs on the first menu interaction.
- Mouse event → AES menu bar hit-test → possible first call into a code path that does a multi-cycle arithmetic operation (divide for item height, multiply for blit pitch) then an indexed EA to walk a structure or a pipe ring.
- The pipe-ring copy at `$01039D0E` (`lea (a2,d0.l,$10),a0`) is brief-format and appears in the stuck samples; Hatari never executes it after desktop. That is a concrete place the core can still mis-execute an index even after F116.

## 7. Recommended next steps

1. Add the four short tests above (especially `divul.l` + brief LEA and `divs.w` + full PEA) and run them under `run_rtl.sh` at multiple wait states. A failure reproduces the F116 class on an instruction the menu path actually uses.
2. On the board, capture the index value and computed EA at the pipe `lea` (`$01039D0E`) the same way `IDX_DEBUG` did for the earlier env-loop LEA. If it shows a stale Dn, the bug is still in the brief-format path after a multi-cycle writer.
3. If the tests pass, the continuous `vsprintf`/pipe activity is a symptom of an earlier fault (bad pointer or length) that only the menu path triggers; the sampler already shows the kernel is stuck formatting into a pipe that Hatari never touches post-desktop.

## 8. Summary

The F116 fix closed the `muls.w` + full-format case that caused the earlier XaAES reboot loop. The menu freeze is consistent with the same hazard on a different multi-cycle writer (most likely a divide inside `vsprintf` or a brief-format LEA in the pipe path) that the current `IDX_TRK`/`AR_IN_USE` cover does not yet catch. The PC samples point directly at `divul.l` and the brief-format pipe `lea`. The four short GHDL tests above are the fastest way to confirm or rule out that class of bug.
