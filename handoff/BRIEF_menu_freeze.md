# BRIEF: XaAES menu freeze on the first menu hover/click (Tang Console 138K, wf68k30L core)

Code is on branch `pmmu` (HEAD 085fa99). Paths below are relative to that branch.

## Symptom
- Gateware f116a with TT-RAM on, booting FreeMiNT 1-19-4a6 + XaAES 1.7.0 + TeraDesk (EmuTOS 1.4 etos256uk) from an ACSI image:
  it boots to the TeraDesk desktop reliably (5/5 cold boots).
- The first time the mouse hovers over "Desk", the title turns inverse but the drop-down never draws. After a click the
  pointer disappears and the screen freezes. There is no reset and no fault message.
- Hatari (same image, 68030 + MMU, 16 MB TT-RAM) opens the drop-down at once, showing
  "TeraDesk Info... / XaAES v1.7.0 Beta / Tera Desktop".

## PC samples (f117b = f116a + a register sampler every ~33 ms): `handoff/pcs_f117b.txt`
- Before the hover: kernel idle loop at $0103B3xx/$0103CFA4, SP $01088xxx.
- After the click: always supervisor (SR 2300), SP $01EEDxxx-$01EEExxx (a process's kernel stack, XaAES runs in kernel
  space at ~$01F4xxxx). It never returns to idle. The samples land in:
  - `$010548AA..$0105491C`: kernel vsprintf (format loop, '%' check), with helpers `$01054786` (number, divul.l) and `$01054852` (padding);
  - `$01053A98`: strlen;
  - `$01039BEC..`: pipefs write; `$01039D0E lea (a2,d0.l,$10),a0` with idx & $FFF = the 4 KB pipe ring copy (pipe list at $0108AC30);
  - also $010499B4 (name lookup), $01033296 (memory block magic 'S1'/'S2'/'S4' checks), $01021444, $01013E64, $0104F9C6.
- Hatari breakpoints over the same run: the pipe write `$01039D0E` is never hit, and vsprintf ran 135x during boot and ~0 after the
  desktop, hover and click included. So on the board, opening the menu makes something keep formatting text into a pipe,
  probably a kernel ALERT into XaAES's alert pipe, or an XaAES log.
- Disassembly (kernel loads at the same addresses in Hatari and on the board) came from a Hatari TT-RAM dump with m68k objdump.

## Recent fixes (see `docs/FALCON_LESSONS.md`)
- F110 `hdl/tang/mega138kpro/sdram.v`: the ST CAS sets bank 0 and REFRESH is deferred while a TT bank is open (wrong-bank reads).
- F112 `hdl/atarist/mfp.v`, `io_fifo.v`: the MFP TX-empty and TX interrupt come from its own baud timer (no external drain needed).
- F116 `hdl/cpu030/wf68k30L_address_registers.vhd`: `muls.w/mulu.w` then a full-format EA using the same Dn as index
  (`pea (bd.l,Dn.l)`) used Dn from before the multiply. Fix: AR_IN_USE while IDX_TRK. This was the cause of the XaAES reboot loop.
  F97 had earlier handled the single-clock writers (lsl/add -> index). Test: `hdl/cpu030/sim/rtl/prog_pea.s` + `expect_pea.txt`.
- CPU RTL: `hdl/cpu030/wf68k30L_*.vhd`. GHDL bench: `hdl/cpu030/sim/rtl/run_rtl.sh` (tb030, ROMFILE=hex, WS=0/1/3/7).

## Asks
1. Which 68030 instructions or idioms in the MiNT kernel / XaAES menu path (AES menu drop-down: screen-area save
   under the menu, VDI blit/raster copy, form/rectangle lists, event and mouse handling, ALERT/pipe paths) could the core mis-execute
   in the same way as F116? Candidates: other multi-cycle writers (divs/divu/divul, mulu.l/muls.l, bitfield, cas/cas2, movem)
   feeding a dependent EA (brief and full format, memory indirect), An/Dn forwarding after movem/postincrement, bfextu/bfins,
   cmp2/chk2, movep, move16, misaligned long accesses, and address errors.
2. For each, write a short GHDL test program (68k asm, writing results to $5000+ like prog_pea.s) with its expected values.
3. Is there anything an XaAES menu does first that it doesn't do earlier during boot or desktop drawing?
