# FLOAT_PANIC (GEMBENCH Float Math, EmuTOS 192, F65 + early AS) - 12 Oct 2026, read-only analysis

Source: Hatari .sav (uncompressed RAM image). The program header `601a`, tlen $355C, dlen $178, blen $110 sits at
snapshot offset $6237E0, apparently a file buffer copy. Its TEXT, disassembled at the board base $5581A
(objdump m68k:68030; relocation table not in the buffer, so absolute refs are unrelocated), matches the panic:
data $58D76 = A4, bss $58EEE. This is the Float Math binary (Lattice C, the AUTOFPU code).

## The bad addresses are real code addresses with the upper word corrupted
- panic pc $00416528 = $00056528 XOR $00440000. $56528 is `subi.l #1022,d2` INSIDE `frexp()` (entry $564F8,
  exponent extraction; D2 = $3FF00000 = 1.0 high word fits). It is not a call target, so this is no bad jump table or
  function pointer: the PC itself came back with a bad upper word.
- fault addr $00416722 = $00056722 XOR $00440000. $56722 is the return address after `bsr $56DF4` at $5671E
  (a float routine that saves d2-d7/a1 with MOVEM). It is a value that lives on the (user) stack.
- Same mask on both: high word $0005 read back as $0041 (data bits 2 and 6 of the high word). Two different
  stack-borne PCs (a return address, and very likely the PC restored by an RTE after an interrupt/exception taken
  in frexp) carry the same corruption.
- D0 = A0 = pc is probably the panic handler's own use of D0/A0, not a program `jmp (a0)`. The only indirect call
  in the binary is the atexit loop at $58088 (`movea.l 4(a3),a0; jsr (a0)`), which is not involved.

## The FPU probe itself is correct for a real 68030
$579A0-$57A56: Setexc(11) -> FNOP; Line-F handler at $57A64 (`moveq #-1,d3; move.l a2,2(sp); rte`) on a
format 0 frame. Then Setexc(2) and an SFP004 probe at $FFFA40. The BERR handler at $57A6C checks `_longframe`
($59E) and converts a format A frame (lea 24) or anything else as B (lea 84) to a format 0 frame with PC = A2.
So the program handles A and B frames correctly. A non-A/B format from the core would make it lea 84 the wrong
size: that matches the earlier "two bombs" on TOS 2.06, but this panic is later (in the float math itself, D3=0 =
software path chosen).

## Suspects (ranked)
1. **Bus data corruption of the first (high) word of a long on the ST bus**: a write of a long return address /
   exception frame word, or the read back by RTS/RTE/MOVEM. Board-only, so the new timing is the likely cause:
   BRIDGE_EARLY_AS (write DS at S2 en2, read DS at S0 en2) or F65 (chained prefetch next to an operand cycle). The
   pattern (fixed bits, high word only, stack values) fits sampling the wrong data or stale data, not ISA logic.
2. Exception stacking/RTE of the PC high word (`DATA_EXH` STACK_POS=2: `SR_CPY & PC(31:16)`) if an interrupt is
   taken inside frexp. Less likely: the same mask also hits a plain BSR return address.
3. ISA paths (bitfield, PC-relative indexed, 030 modes): none are used in this code path. frexp and its callers use
   plain MOVEM, LINK/UNLK, BSR/RTS and ASR/AND/SUBI.

## Cheapest confirmation (no build)
1. Flash the existing images and run Float Math on EmuTOS 192 (atarist.ini mount, power cycle):
   `st_helper_eas_d43f5fd_p3.fs` (early AS only) and `st_helper_f62d_rb_75bfc8c_p3.fs` (neither switch).
   Panic only with F65 -> F65; also with EAS-only -> early AS; neither -> core.
2. On TOS 2.06, note the bomb PC/address: the same XOR $440000 signature points at the same fault.
3. A tiny stack-stress PRG (deep BSR/RTS + MOVEM + RTE under timer/VBL interrupts, checking every popped long)
   would reproduce the fault outside GEMBENCH.

## Board A/B, 12 Oct 2026 (EmuTOS 192, GEMBENCH 4.03 Test > CPU, ST Medium)
| Image | Switches | Result |
|---|---|---|
| st_helper_f65_5394948_p3.fs (David's run) | F65 + early AS | Panic: Bus Error fw=a008 ssr=2005 addr=00416722 pc=00416528, D7=2 |
| st_helper_eas_d43f5fd_p3.fs | early AS only | identical panic (same pc/addr/fw/ssr/regs, only D7=3) - ui/fp_eas_panic.png |
| st_helper_f62d_rb_75bfc8c_p3.fs | neither | identical panic, D7=2 - ui/fp_f62d_panic.png |

XOR $440000 holds on all three. **Neither F65 nor BRIDGE_EARLY_AS is the cause**: the fault predates both
(F62d core/bridge or older). Deterministic (same addresses every run), so a data/timing race is less likely than a
logic fault on a specific path. Re-rank: suspect 2 (exception frame / RTE PC high word, or an interrupt taken in
frexp) and pre-F64 bus/bridge paths move up; a stack-stress PRG and sim of the frexp sequence with interrupts are next.

## 12 Oct 20:10: STKTEST and notes
- STKTEST.PRG (Atarist_030_wip/hdl/cpu030/tests/stktest/, branch fix-hiword): recursion with $0005xxxx patterns and
  return-address checks, MOVEM all regs, LINK/UNLK, TRAP #3/RTE, frexp mirror. Hatari STE/68030/EmuTOS 256: >1,050,000
  passes, no fail. Floppy /workspace/gb/gb_stk.st (gb403.st + STKTEST.PRG, 737280 bytes). Upload path exists:
  helper_fw/tools/sd_upload.ps1 (put/h/pend over COM4). Not run: laptop offline since ~20:04.
- Re-read of the panic: ssr=$2005 has RC=1, DF=0 = an instruction-stream (stage C) fault, not a data fault. So the CPU
  really fetched near $416722 and the stacked PC $416528 means it had been EXECUTING at $4165xx, i.e. reads above 4 MB
  did not bus-error at first (check the gstmcu/bridge decode of $400000-$DFFFFF with 4 MB: real ST GLUE gives BERR).
- The offset is also exactly additive: +$3C0000 to two genuine code addresses. Candidates: a PC-relative / displacement
  calculation (PC_I + DISPLACEMENT, address_registers.vhd:553) or a return address altered on the stack. Not found yet;
  no fix made (no evidence for one).

## 12 Oct 20:25: whole-ST bench, board config (netlist FAST_HANDOFF=1, -DBRIDGE_EARLY_AS)
Program sim/st/prog_stk.s (fix-hiword), run_bus.sh with ROM arg, both CPU phases (15625/46875 ps), ~12 ms ST time:
- >4 MB decode is right (enable_extra_ram=0): `tst.w $416528` -> BERR format B (vector 8); `jmp $416528` -> BERR
  format A, PC $416528, fault addr $416536. Reads of $4165xx go to the ST bus and time out like a real 4 MB ST.
  (Board: check atarist.ini/companion "M" = 4 MB; with extra RAM on, $400000+ is RAM and would not fault.)
- 30 loops of recursion/MOVEM/LINK/TRAP-RTE/frexp mirror with HBL (level 2, ~190 interrupts) and VBL enabled: PASS,
  no stack long corrupted, no $0041 high word anywhere.
- So the +$3C0000 shift does not reproduce from the instruction mix plus interrupts in sim. Remaining: the real
  GEMBENCH code path (the value is computed, A0 = D0 = target: look for the Lattice FP library code that builds an
  address from data, e.g. a table index with a stale upper word), or a board-only effect not in the bench (SDRAM
  timing, DMA/blitter, helper). No fix proposed (no sim evidence).

## 13 Oct 07:15: board STKTEST attempt - BLOCKED by the SD write fault
- Helper memory option: XML default "M"=0 (4MB); the current atarist.ini value cannot be read over COM4 (no cat).
- sd_upload.ps1 gb_stk.st: `put` ok, first `h` block -> "e write" x5, then "SDC: write timeout on sector 39744";
  `pend` closed the file with 512 bytes. After that `ls` shows "0 entries" and "write timeout on sector 4738":
  the known sd_card.v state-13 jam (TODO item 6). Only a core reload clears it (power cycle). A 512-byte gb_stk.st
  stub may now exist on the SD; check FAT on a PC. STKTEST not run on the board.

## 13 Oct 08:2x-08:45 STKTEST attempt (build st_helper_sdw_p3.fs)
- gbstk2.st (= /workspace/gb/gb_stk.st, 737280 B) uploaded as NEW file in 222 s with no SD error (old core jammed on uploads); crc e0b550d9 read back. gb_stk.st 0-byte stub left in place.
- Mounted on A (session only, no save), then a cold boot. All grabs after that were pure black (8695 B): stk_g1..g6, including after remounting gb403 and running c/w. Helper link OK, ST sends hello. An earlier sdw_desk3.png (08:1x, gb403, after c) showed the desktop, so video/capture is intermittent and not disk-related.
- STKTEST and GEMBENCH Float NOT run (can't drive the GUI without frames). No mismatch values.

## 13 Oct ~20:15 STKTEST on board (st_helper_sdw_p3.fs, cables now at 417/418)
- gbstk2.st on A (session only). STKTEST "stack long check" ran ~2.5 min: passes 2710..13880 hex (80000), NO mismatch lines (grabs sdwrite/stk_b6..b8.png).
- GEMBENCH.PRG from the same disk: "does not run in this resolution, needs 640x200" (gb_f8.png), so Float Math was not run (machine boots in ST low). Quit; gb403 remounted.

## 14 Oct 01:5x: memory setting checked on the board (linserver, helper UART /dev/ttyUSB1)
- Helper boot log: atarist.ini `M = 0` (4 MB), so enable_extra_ram=0 and $400000+ must BERR (matches sim). The
  "program loaded into alt/extra RAM at $41xxxx" theory is ruled out by config. Opening the port reset the helper
  (boot log replayed); link OK afterwards (`s` -> 5C 42 link OK).
- Open puzzle: ssr RC=1 fault at $416722 with stacked PC $416528 implies the CPU fetched ~$1FA bytes beyond the
  bad PC, i.e. it ran code at $4165xx. With 4 MB that needs a mirror or a wrong PC formed late (e.g. by RTS/RTE).
  Next: run Float Math in medium res on the board with a bus-trace (SignalTap/GAO on A[23:16] != 0 trigger).

## 14 Oct 02:3x: overnight run (linserver)
- Licence: gw_sh builds on linserver (QT_QPA_PLATFORM=offscreen), "license expires in 10 days".
- GAO not needed: DIAG_HIWATCH (branch fix-float-hiword, 7de1ce6) reuses the DIAG_OVERLAY bit rows.
  Rows c..f = {frz, why(1=addr,0=BERR), 00, trig{FC,RW,A23:0}, h0{FC,RW,A,D16}, h1, 00}; armed after first user cycle.
  Decoder: st_helper_out/fpdbg/dec.py (ref frame h1.png). First version (no arming) froze at boot on BERR $FF8C80 (TOS probe).
- Panic reproduced on st_helper_sdw_p3 driving via helper link (fpdbg/m16.png): same pc/addr, sr=0310, D0=A0=$416528.
- Driving recipe: mouse to corner, Options ^R -> Yes (medium), alt+a, fuller, double-click GEMBENCH.PRG, Test>CPU.
- Board now: st_helper_hiwatch_7de1ce6.fs (debug).
- 02:5x run on 7de1ce6: froze on the BERR at $FFFA40 FC5 read (GEMBENCH SFP004 probe, expected). Panic still
  followed. h0 = $FFFA40-area. Rebuilding with address trigger only (commit after 7de1ce6). Cold boot ("c") needed
  after flash: the first boot sat on the cartridge self-test screen.
- 03:4x run on c39328c (fpdbg/k3.png): FROZE on the address trigger: user program fetch (FC2) at $416528.
  The 2 cycles before it: h1 = user data WRITE $0003 @ $05A208 (USP area), h0 = user data WRITE $31C2 @ $04A20A
  ($05A20A with bit 16 wrong), then the fetch @ $416528 ($056528 with bits 22,18 wrong).
  => the 030 drives wrong A23:16 on consecutive cycles (address output, not stack data). Upper bits only = long
  carry/mux path -> suspect a timing (setup) failure in the WF68K30L address path, or a wrong ADR source select.
- Analysis of k3: the core's own FAULT_ADR/PC also hold $4165xx (EmuTOS frame), so the wrong address is inside
  the WF68K30L (PC_L / ADR_LATCH), not a bridge sampling artefact. ADR_OFFSET is 6 bits, so the +$3C0000 is
  not an offset. Write 2nd half $04A20A = ADR_LATCH+2 with ADR_LATCH != the live address of the 1st half.
  Timing: clk32_core Fmax 32.03 MHz (31.25 ns needed), clk_cpu030 17.2 MHz: met but ~0.03 ns margin on clk32.
  Hatari: 57290 (`move.l d0,-(sp); or.l d1,(sp)+`) is an RMW-postinc candidate; 566a4 dispatch (tst.l 476(a4)):
  0 -> software 5671a (movem/bsr 56df4).
- fd98991: 16-entry history, paged (2 per page, ~0.13 s), write data at DS. Building.
- 03:23: fd98991 build still running on linserver (synth tech-mapping, ~50 min in). Board = st_helper_hiwatch_c39328c.fs (debug).
- 04:2x fd98991 run: 16-entry history decoded (fpdbg/pg*.png, pages.py). Sequence before the trigger: data reads $55910 (41FA) / $?5912 (0041), code $..31BE-31C6 = jsr (a0) dispatcher, push of return addr (2nd half again with wrong A23:16: $01A20A), then fetch $416528 => A0 came out as $416528.
- Hatari text: $55910 = `0C00 0041 6528` (cmpi.b #'A',d0; bcs). So the bad A0 long $00416528 is the BYTES at
  $55912 of GEMBENCH's own code: the pointer was read from the wrong address (A23:16 wrong again), then jsr (a0).
  Every bad cycle seen: A15:0 correct, A23:16 wrong ($05->$01/$04/$41), mostly on the 2nd word of a split long
  (ADR_LATCH + ADR_OFFSET path, wf68k30L_top.vhd ADR_P/ADR_LATCH, bus_interface ADR_OUT_I). Root cause line NOT
  identified yet. Next: probe ADR_LATCH vs live ADR_P vs ADR_L upper byte at BUS_BSY rise (needs core ports),
  and check the clk_cpu030_n -> clk_cpu030 half-cycle paths into ADR_L/ADR_LATCH in the timing report.
- 04:3x: reflashing st_helper_sdw_p3.fs (fallback, no verified fix).
- 04:1x timing check: setup slack on the 030 paths ~25 ns (st_helper.timing_paths), not a timing failure -> logic. Probe build (DBG_ADR: ADR_LATCH/ADR_P/PC_L/ADR_L 23:16 per cycle) started.
- 05:0x probe build c195f92 done, flashing + run_fm.sh
- 05:1x c195f92 flashed, run done, panic frozen (q0.png). Collecting pages q*.png (pages2.py).
- 05:2x c195f92 pages (pages2.py): core-internal ADR_LATCH/ADR_P = $05 on the stack writes while the overlay
  bus field read $01 -> the A23:16 "corruption" in bus rows was a DECODER bar misread (bit 18), not real. The push
  of the return address $000331C4 to $5A208 is correct. Real chain: code at $0331B6-$0331C6 (RAM, not GEMBENCH
  text) reads a long from $055912 (ADR_L = $05, core-computed EA) = GEMBENCH code bytes $0041 6528, then
  jsr (a0) at $331C2 -> PC_L = $41 -> $416528. So the bad thing is the EA/pointer used at $331Bx.
- 05:40 Hatari RAM image (.sav, base 0x19eb) has the same RAM code at $30000-$33400: a resident module with
  exception stubs (`bsr 30512; dc.b vec` for vectors $51,$0B (Line-F),$06,$09) and a string printer at $331B0
  that calls a hook at 504(a5) (default if 0). It uses A5 as its globals base WITHOUT loading it. On the board A5 =
  GEMBENCH's $5571A, so 504(a5) = $55912 -> code bytes $00416528 -> jsr -> BERR -> EmuTOS panic.
  => The panic is SECONDARY. The primary event is an exception taken during Float Math that Hatari does not take
  (likely Line-F / coprocessor, or BERR from the SFP004 path at $FFFA40). Next probe: record the last
  exception vector fetched before the trigger.
- 06:1x 0412dd7 (last-vector probe) built; flashing + run_fm.sh in background on linserver.
- 06:3x 0412dd7 run (fpdbg/v*.png): last exception vector before the trigger = 6 (CHK/CHK2/TRAPcc... vector $018), >=15 cycles before. The resident module's vector-6 stub then crashes (A5). PRIMARY = an unexpected CHK exception.
- 06:4x HiSoft runtime (resident at $30000) bounds-checks with CHK.W (a1)+,Dn; vector 6 = 'subscript out of range' handler, which then crashes. CHK itself was fixed in F60. Hypothesis: a wrong integer/float-emulation result upstream gives an out-of-range index (CHK trap is then correct). Next: check ADDX/SUBX/NEGX Z-flag, ROXL/ROXR, ASL V-flag etc. in wf68k30L_alu.vhd.
- ALU check (wf68k30L_alu.vhd): ADDX/SUBX/NEGX Z sticky handling and CHK compare look correct by inspection.
  Root instruction not found tonight. Plan: differential test - run GEMBENCH's HiSoft float routines (from the
  Hatari RAM image, $30000-$34000 runtime + Float Math code) in the GHDL RTL bench and in a reference 68k emulator
  (Musashi), compare register state per instruction; first divergence = the core bug.
- 06:5x reflashing st_helper_sdw_p3.fs (no verified fix).
- 07:0x board on st_helper_sdw_p3.fs, desktop OK (fpdbg/final2.png).
- 06:2x Disk: GEMBENCH (HiSoft BASIC, runtime at $30000) Pexecs BIN/AUTOFPU.BIN (Lattice, the $5581A program) for Float Math. Panic A5 = $55718 ~ child basepage: hypothesis = parent's A5 not restored after the child (Pexec/Pterm path, exception frame/MOVEM), parent then runs with a bad globals pointer -> CHK trap -> handler crash.
- 06:3x sim: prog_fpuprobe.s (AUTOFPU probe replica, SSP before/after) for tb030.
- 06:4x sim prog_fpuprobe.s: probe OK on the core (BERR frame format B $B008, handler converts, D3=0, SSP unchanged). Not the probe. New hypothesis: vector 6 is global, so the CHILD (AUTOFPU, A5=$55718) raising vector 6 runs the parent's HiSoft handler with the child's A5 -> exactly the crash. Find what in the child the core treats as CHK/CHK2.
- 06:5x Prior F62c bug (RESULT_OVERNIGHT): lost A7 predecrement when an AR writeback and AR_DEC hit the same clock (JSR fix F62d). Same hazard class likely here: a lost/raced An update -> stray RTS/jump -> executing data words like $41xx = CHK.L -> vector 6. Checking which ops in control.vhd START_OP do not wait for AR_IN_USE.
- 07:3x LINK/UNLK-after-An-writeback RTL test (sim/rtl/prog_link.s, 10 cases x4, WS 0/1/3/7): PASS. Not LINK.
- 07:4x Differential bench /tmp/dt: AUTOFPU.BIN relocated at $5581C (basepage $5571C, A4=$58D78), FPU probe
  patched to software float (clr.l 476(a4)), GEMDOS/BIOS/XBIOS traps -> moveq #0,d0;rte, other vectors -> $BAD0vvvv
  at $3300. Musashi (machine68k 0.4.1, 68030) vs tb030 ST=1 (3M clocks, WS=1, no IRQ): 74736 bytes of writes
  (outside the SSP area, normalised per long) IDENTICAL, no exception. Clean core runs the float code correctly.
  Now: same with periodic level 4/6 IRQs + random wait states (gh_a/b/c).
- 08:0x Differential runs, all 3M clocks, all IDENTICAL to Musashi, no exception vector taken:
  a WS=1 IRQ4/997; b WSRND=3 IRQ4/613+IRQ6/1543; c WS=3 IRQ4/211; d CACR=$3111 (I+D cache, WA) no IRQ;
  e cache+WSRND=3+IRQ4/613; f cache+WS=1+IRQ4/997. (61176/39232/5940/74736/47656/61168 bytes compared.)
  => The core executes AUTOFPU's software-float path correctly in the RTL bench, also with IRQs/caches/wait states.
  No diverging instruction found. Remaining differences vs the board: real EmuTOS GEMDOS/BIOS + IRQ handlers
  (MFP timer C 200 Hz, VBL, IKBD ACIA), Pexec/Pterm return into the HiSoft parent (A5 hypothesis), ST bus bridge,
  real FPU probe (BERR at $FFFA40). Harness: docs/float_panic/diff/{mk,mu,cmp}.py.
- 07:0x Pexec/Pterm A5 test (docs/float_panic/pexec/t.s): parent sets D3-D7/A3-A6 to magic, Pexec(5)+Pexec(4) a child
  that trashes them (A5=$55718, A4=$58D78) and Pterm()s. Hatari (STE, 68030 16 MHz, 4 MB, EmuTOS 256 1.4 - Hatari
  forces EmuTOS 192 to 68000): $600DC0DE. RTL core in tb030 from the Hatari RAM snapshot (EmuTOS 256 ROM, caches on,
  trap #1 vector restored from Hatari's cartridge hook to $E12D1C): $600DC0DE; variant t2 (child does Super(0)/Super(old)
  like AUTOFPU) also $600DC0DE. => The parent's A5 survives the child exit on the core. A5 hypothesis NOT confirmed
  (no IRQs: tb030 IRQ runs hang in EmuTOS's VBL path at E03C2x without a real MFP/video, so inconclusive with IRQs).
- 07:1x David's Hatari .sav (Hatari 2.2.0, gzip, EmuTOS 256uk): RAM base in the file is $19ED (memvalid $420 at $1E0D),
  not $19EB. AUTOFPU's relocated code is NOT in RAM (only the unrelocated file buffer copies at file $6237FE/$627272, outside
  RAM), so the $5581A board base was an inference. HiSoft runtime is at $30000 in RAM. CPU register block of the 2.2 format
  not located reliably by pattern search (needs Hatari 2.2 to load it, or the 2.2 module sizes); not used.
