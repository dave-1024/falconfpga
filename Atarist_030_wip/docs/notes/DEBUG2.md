# F62b freeze debug (F64), started 15:05 BST 8 Oct
- branch f64-prefetch = main 10c1dab (F63) + cherry-pick cc2acd5 (F62) + ed5718d (F62b)
- 15:1x Hatari: board freeze is with pointer ON a title (fe_r15: on "Extra", no highlight, no drop). Hatari menu-drop trace (gb/tr_m4.txt):
  VDI inner loop E0E85C-E0E91C GENERATES CODE ON THE SUPERVISOR STACK (lea -20(sp),sp; movea.l sp,a2; bsr E06D6C writes
  "or.w d1,(a5)+" x planes + "jmp (a3)" with move.w (a0)+) and runs it per row via jmp (a2) at $9E34 (2 planes = medium).
  Interrupt frames are pushed right below the fragment. => SMC/write-snoop + exception + restart candidate.
- tb030: IPL_MODE=3 (periodic level 4 every IRQ_PER, level 6 every IRQ_PER6, cleared on IACK), STOPDONE generic.
- prog_trapirq.s (AES TRAP#2/#13 loop, user mode, irqs): old vs F62b identical over IRQ_PER 701..1999 (no repro).
- prog_smcstack.s (code on stack like E0E85C): no irq old = F62b (E99F496E).
- 15:2x Title touch order in Hatari (tr_m4): Line-A $A000 (E17CF4 jsr E22870, handler E068E4 reads opword via stacked PC,
  RTE to E22872) -> SMC-on-stack fill (title invert) -> tas.b $CC00 (E21DEA, AES semaphore). None of these occur on bar entry alone.
- prog_linea.s (A000 at 4n/4n+2, TOS handler copy, user/supervisor): old = F62b. prog_tas.s: old = F62b
  (both cores run an opcode fetch between the TAS read and write; F62b a long - 68030 deviation, not new).
- prog_smcstack.s sweep IRQ_PER 1201..2700 (+level 6): all DONE with correct checksum (timeouts only under irq saturation,
  old core also times out there). No repro.
- Perf note: F62b re-fetches 2 speculative longs after a non-loop-mode dbra each iteration (checksum loop 48 clk/iter WS0).
- 15:3x Replay: Hatari breakpoint at E17CF4 (title touch) -> snap/ram.bin + regs (SR 2300, SSP 9FFA). tb030 got RAMFILE/RSSP/RPC
  generics (stub at $200000 restores regs, RTE to E17CF4), TOS at E00000-E3FFFF. 300k clk, no irq: old and F62b data-cycle
  sequences identical (no freeze). Running 3M clk (rp2.log in /tmp/swold, /tmp/swnew).
- 15:35 Steering: DIAG_OVERLAY board capture. Worktree /workspace/repos/fdiag (detached 7a53162 = F62b on F63) with `define DIAG_OVERLAY, build started (build_diag.log).
- 15:39 Steering: reproduce freeze 2-3x with overlay build, capture panel each time, compare.
- 15:47 diag build place_option 1: TNS clk32_core -16.6 (35 ep), clk_cpu030 -8.6 -> not flashable. Started place_option 2 (fdiag) and 3 (fdiag2).
- 16:03 diag build place_option 2: TNS 0 all clocks (clk32_core 32.024 MHz, clk_cpu030 16.361 MHz). place_option 3 run failed (license server, parallel). File st_helper_diag_f62b_7a53162.fs
- 16:2x BOARD (diag build st_helper_diag_f62b_7a53162.fs, place 2, TNS 0, SHA256 d46c4c57..9ba1; flash 1/2): cold boot OK,
  desktop menus in ST MEDIUM work (Options dropped), GEMBENCH loaded; pointer onto "Extra" -> FREEZE #1 (no drop).
  Panel (decode_diag.py) f1a/b/c 4 s apart identical: row f last prog fetch = E21D[0-7][0-E] (varying low bits, A11:8=D fixed)
  = loop inside E21D00-E21D7E; row d: FC=1x1 (S), RW=1 (reads), INPROG 0, HUNG 0, T_DSACK, HALT_OUTn 1, IPENDn 1,
  IPL=2 (HBL only, same as running). Not a bus hang: CPU loops, only reads.
  TOS E21D00-E21D10 = shift/subtract divide loop (tst.l d4; beq out; cmp.l d6,d7; bcs; or.l d4,d5; sub.l d6,d7; lsr.l #1,d4;
  lsr.l #1,d6; bra E21D00): ends after <=32 passes on a correct CPU -> F62b executes it wrongly (e.g. lsr.l #1,d4 skipped).
- Correction (fractions, decode_diag): row d RW ~0.9 (reads AND some writes, same as running). Row f low bits: A7=0, A6~0.8,
  A5~0.2, A4~0.7 -> fetches mostly E21D38-E21D5F = AES trap #2 handler (tst.w d0; beq; cmp #c8/#c9; move.l $6ABE,-(sp); rts).
  After the freeze the POINTER STILL MOVES (diag_f1d/f1e: mouse moves ok) -> interrupts serviced, AES stuck in a loop in E21D38-5F.
  Hypothesis: rts goes back to E21D38 (e.g. $6ABE = E21D38 instead of E0FA3C, or wrong rts/queue) -> endless VDI dispatch loop.
- 16:4x Repro #2 (warm reset 'w', same steps): pointer onto "Extra" -> freeze, NO drop. Panel (diag2_fa/fc) = same as #1 within
  pixel noise: live loop, prog fetches E21D38-E21D5F (A15:7 = 0001 1101 0, A6 .8, A5 .2, A4 .6), RW ~.9, INPROG 0, HUNG 0,
  T_DSACK, HALT_OUTn 1, IPENDn 1, IPL 2. Row a differs only by boot (cold 0041FFFE RAM probe, warm FFFF8E09 probe).
- Repro #3 (warm reset, same steps): DIFFERENT: pointer stopped at (410,95) on the way up (window title, just below Help),
  panel static (diag3_fa/fb): CPU HALTED (row d HALT_OUTn 0, STATUSn 0, S16 yellow, S17/S19 stopped) = DOUBLE BUS FAULT.
  Last started cycle (row c) = 0x02000000, FC 5 (S data), RW 0 (write), SIZ long, terminated T_BERR -> exception stacking
  with SSP ~0x02000004 (garbage stack pointer). Last program fetch (row f) = E00D36 (inside TOS E00D1C-E00D3C:
  "wait for VBL" E00D1C..E00D32 rts, E00D34 move.l $404,-(sp)/moveq/rts = etv_critic). IPL 4 pending (VBL), not taken.
  Row b (got FC/RW/SIZ) 1101 1010. Cycle count G1-G2 = AA.
  => same trigger, two outcomes (endless AES trap #2 chain loop at E21D38 vs. corrupted SSP + double fault): CPU state
  corruption (wrong instruction stream / stack), not a bus hang. TOS never calls the vector-install routines (E21ABA) on a
  title touch in Hatari, so the loop at E21D38 (rts back to E21D38, i.e. $6ABE = E21D38 or a wrong return) is corruption.
- 16:30 User: lead = 'move.l abs,-(sp); [moveq;] rts' idiom in both outcomes. Writing prog_pushrts.s (old vs F62b, WS 0-7, random waits, irqs). Board still on diag build (fallback flash attempt aborted before start).

## 17:00-17:30 push/rts lead, board-faithful replay
- prog_pushrts.s (move.l abs/imm,-(sp);[moveq;]rts, pea, targets 4n/4n+2, stack near code/far, WS 0/1/3/5/7, WSRND, irqs): F62b = old, 43 ok.
- Sim-only monitor (copy in /tmp/dbgsrc): write chosen in START_CYCLE with WP_BUFFER /= DATA_FROM_CORE (stale write data
  after a prefetch-entered START): never fires (pushrts WS 0-7, snapshot replay 1.5M clk with irqs + WSRND 4).
- GHDL snapshot replay reaches the AES dispatcher move.l $6ABE,-(sp);rts 454x (first at clk 33564), 1256 screen writes, no fault.
- Panel interpretation: repro 1/2 loop = trap#2 handler E21D38 -> E21D48 move.l $6ABE,-(sp); rts returning to E21D38 forever,
  i.e. the pushed long = E21D38 = the value just read from vector $88 (stale data), not $6ABE (E0FA3C). Repro 3: E00D34
  move.l $404,-(sp); rts pushes garbage -> double fault. Consistent with "push of move.l abs,-(sp) carries stale data".
- tb030 differs from the board bridge: tb gives data with DSACK and samples write data late; the bridge gives DSACK early
  (data one clk later) and samples address/data live at the first clk_32 edge with AS low.
- New bench rp/tb_rp.v: cpu030_st_bridge + F62b Gowin netlist (/tmp/synF62b) + ST bus model + snapshot replay. ~410 clk/s.
  6 runs (phase 15625/46875, random waits) to 400k clk.

## 17:20-17:50 lead "bridge latches write data at AS, core drives DATA_OUT late" -> NOT confirmed
(b) cpu030_st_bridge.v (F63/F61): write data is latched only at the first clk_32 edge with AS low
    (live q_wdata -> r_dout at accept, else c_wdata <= cpu_dout[31:16] on that edge); never re-sampled at DS.
(a) WF68K30L RTL: DATA_PORT_OUT = mux(WP_BUFFER, SIZE_I, ADR_OUT_I); WP_BUFFER loads at IDLE->START_CYCLE,
    AS asserts (S0) on the START->DATA_C1C4 edge, write DS at S3 -> data is valid >= 1 clk before AS and constant
    to the end; the F62 prefetch path does not change this (PF only enters START from IDLE too; monitor: write chosen
    in START with WP_BUFFER /= DATA_FROM_CORE never happens).
    Netlist check (fresh F62b Gowin netlist /tmp/synF62b, bench rp/tb_rp.v = bridge + netlist + ST bus model,
    snapshot replay): monitor compares core DATA_OUT at the bridge's AS latch edge, at DS low, and bridge c_wdata:
    phase 15625: 377 writes, phase 46875: 234 writes (24k clk) + 96k-clk runs both phases: 0 mismatches.
    Long netlist replays (phase 46875, random waits 0/2/3, 400k clk each): 17-20 AES dispatches
    (move.l $6ABE,-(sp); rts pushes E0FA3C correctly), no fault, no halt.
    (phase-15625 runs were invalid: bench IACK-clear pulse missed -> irq storm; fixed (toggle), rerunning.)
=> Latching at DS would be more 68030-like but is not the cause here; no bridge change made.
Board: reflashed st_helper_f63_f484271.fs (SHA b50d52b8...705a5, op 53, loc 417) at ~17:45; helper up, cold boot OK
(mailbox self-test, memory test 4096 KB) -> f63_after_reflash2/3.png. Stage flashes used: 2 of 2 (diag build, F63 restore).
- 18:50 board F63 at TOS desktop (f63_desk_1848.png)
- Phase-15625 netlist replays (fixed bench) 320k clk x3: 12303 writes, badDS 0, badLatch 0, 13-17 AES dispatches, no fault.

## 18:50-19:20 static timing/CDC review (no flash)
Reports: F63 f484271 = impl/pnr/st_helper_tr_content.html (11:22), F62b@F63 = tr_diag_p2.html (diag overlay build 7a53162),
F62b@F60-bridge = tr_fetch_ed5718d.html (also froze).
(b) Clocks: clk32_core (CLKOUT1 ODIV25 PE0), clk_cpu030 (CLKOUT5 ODIV50 PE0), clk_cpu030_n (CLKOUT6 ODIV50 PE25 = 180 deg),
    one PLL (VCO 800 MHz), SDC generated clocks match the PLL defparams; all three in the same clock group = related, every
    crossing timed. SDC has no set_false_path / multicycle / max_delay; async groups only HDMI and AE350/DDR3.
    "Timing Exceptions Report": none in all 3 builds.
(a) Unconstrained/excluded paths touching cpu030/bridge/queue: none (no exceptions; only cut = HDMI/AE350 groups).
    Recovery/removal violations exist in all 3 builds (incl. working F63), all outside cpu030 (pll_init xsint_delay, DDR3, csD/dtack_d).
(c) Worst slacks (F63 / F62b@F63 / F62b@F60):
    cpu030->cpu030 setup 3.799 / 1.380 / 0.312 ns; cpu030->cpu030_n 24.98/22.82/25.30; cpu030_n->cpu030 24.30/21.77 (HALT_In->WP_BUFFER CE)/22.35 (->Q_W);
    clk32->cpu030_n 23.20/20.17; clk32->cpu030 22.41/17.31; cpu030->clk32 6.81/2.55 (ADR_WB->r_adr CE)/12.44;
    holds all >= 0.29 ns. Queue/WP_BUFFER/DATA_VALID regs are not in any worst list except the half-period paths (>= 21 ns).
    Note F62b@F60 (12.4 ns on cpu030->clk32, old 2-flop bridge) froze the same way -> bridge crossing slack is not the discriminator.
(d) Async resets: whole core has only P_BSY (OPCODE_RD_I, clear = OPCODE_RDY or BUSY_EXH&!IPIPE_FILL, the latter a comb.
    decode of EX_STATE -> glitch-capable) and exception P_D (clear = DATA_RDY, a register). Both pre-existing; F62 adds none.
    New exposure: the queue samples OPCODE_RD_I every clock (Q_HIT/Q_MISS/Q_DUMMY, Q_DISMISS mirror of the decoder's
    OPCODE_FLUSH) instead of only at IDLE. A glitch after an edge gives both consumers the same value at the next edge, so
    no divergence unless a clear->Q path is late (not analysed by STA); no evidence.
(e) Bridge-sampled CPU outputs: ASn/DSn/RWn/DATA_OUT unchanged; F62 makes ADR_OUT (mux F_CUR/ADR_IN_P on PF_ACC), FC_OUT (F_FC/FC_IN)
    and SIZE (queue long) depend on new registers, still comb. outputs as before, timed into clk32 (slack 2.5 ns diag build).
    The F60 bridge (2-flop synchronisers) froze too, so live sampling of comb. outputs is not the cause.
=> No credible timing/CDC cause. No fix, no build, no flash. Board stays on F63 (desktop confirmed 18:48).

## 18:55 slow-clock diagnostic build (worktree /workspace/repos/fslow, branch diag-slowclk @7a53162, not for merge)
- Bridge assumes every clk_cpu/clk_cpu_n edge is a clk_32 rising edge (phase-locked related clocks, no synchronisers).
  VCO/60 = 13.33 MHz: edges not on clk32 edges -> rejected. VCO/75 = 10.67 MHz: rising edges align, but 180 deg = 37.5 VCO
  cycles (PE_COARSE integer) -> clk_cpu_n edges fall on clk32 falling edges -> breaks the same assumption. Chosen VCO/100 = 8 MHz
  (CPU_DIV 4, the bridge's documented 8 MHz mode; CPU_DIV is not used in bridge logic, only comments; RESET_HOLD/DR_GAP were
  sized for 8 MHz). Edits: pll_160m_mod.v ODIV5/6 50->100, CLKOUT6_PE_COARSE 25->50; SDC clk_cpu030(_n) x8/25 -> x4/25;
  atarist.v CPU_DIV(4) (comment only). No overlay, place_option 1.
- tb_bridge (unit bench) CPU_DIV=4, F62b netlist, clk_cpu phases 15625/46875/78125/109375 ps: ERRORS=0 all.
- Build (place_option 1): TNS 0 all clocks (setup+hold); clk_cpu030 period 125 ns, Fmax 16.048 MHz (2x margin),
  cpu030->cpu030 setup slack 62.7 ns; NOTE crossings into clk32 keep the clk32 relation: cpu030->clk32 2.63 ns,
  clk32->cpu030 19.95 ns, holds >= 0.36 ns (the slow clock only relaxes CPU-internal paths).
  st_helper_slow8_7a53162.fs SHA256 aff22f08f1fcbda74fd377e955608b48914eadbc755c02a85721357ca080cb63 (laptop hash verified).
- Flash 1/2 (op 53 loc 417, 103 s). Helper up, blank.st on A, cold boot 'c': black screen, no "hello from the ST" (slow_boot2.png);
  warm reset 'w': white screen, no Atari logo/self-test text after 35 s (slow_warm.png, slow_warm2.png). TOS 2.06 does not boot.
  Likely cause: CPU-speed-dependent TOS boot (the E013F6 vblank-sync loop must finish within the 60 Hz blank; F62 being 24% slower
  there already gave a black screen at boot, see F62b commit); 8 MHz is 50% slower. Test inconclusive for the freeze
  (never reached GEMBENCH).
- Flash 2/2: st_helper_f63_f484271.fs (hash verified, 101 s). Cold boot -> TOS desktop (f63_desk_after_slow3.png). Board on F63.

## 19:30 F62c: prefetch queue uses the decoder's OPCODE_FLUSH directly (f64-prefetch on 7a53162, 16 MHz)
- Change: decoder exports OPCODE_FLUSH as OPCODE_DISMISS (opcode_decoder.vhd l.106 port, l.232 assign); bus_interface
  port IPIPE_FLUSH -> OPC_DISMISS (l.119), Q_DISMISS mirror register removed from P_QUEUE (old l.658-664, reset l.724),
  `Q_DISMISS <= OPC_DISMISS` (l.722-725); pkg components (l.250, l.527); top signal + both port maps (l.349, 1071, 1370).
  RTL-equivalent to F62b except the mirror's RESET_CPU_I clear (one flip-flop now decides dismissal for both blocks).
- RTL sims: run_rtl.sh PASS (srmask, chk/branch WS 0/1/3/7, prog_loop 44627 <= 45885). Full bus traces F62b vs F62c
  cycle-identical for all 8 programs (chk, branch, loop, pushrts, smcstack, linea, tas, trapirq) x WS/WSRND 0/0,1/7,3/3,5/0,
  IPL_MODE=3 PER 397/677. Expected-value runs (PER 1301-2699, PER6 3001): pushrts 00007688, smcstack B7138722,
  trapirq 04ED78EE all ok; only smcstack PER 1301 WS>=1 times out (irq saturation, as before; trace identical to F62b).
- Whole-ST bench (run_bus.sh, F62c netlist /tmp/synF62c vs fresh F62b netlist run, both phases): result registers
  R1000-R1200 identical, "late for A+375: 0" everywhere. Only difference is at reset: the F62b netlist does a dummy opcode
  fetch of 000000/000002 (FC6) before the vector fetch; F62c goes straight to the FC5 vector reads (as a real 68030). All
  10k bus cycles after that are identical in content (cycle counts differ by 1-3 at the fixed end time).
- Commits (local, f64-prefetch, not pushed): d7b6b8d F62c, 479b82b RTL bench/tests.
- Build (no overlay, place_option 1): TNS 0 setup+hold on all clocks. clk32_core Fmax 32.053 MHz, clk_cpu030 17.736 MHz.
  Worst setup slack: clk32->clk32 0.026 ns, cpu030->cpu030 6.118, cpu030->clk32 5.294, clk32->cpu030 22.05,
  cpu030<->cpu030_n 23.8/23.0. Worst hold: clk32->cpu030 0.310, clk32->cpu030_n 0.362, cpu030->clk32 0.899.
  (F62b had cpu030->cpu030 1.38, cpu030->clk32 2.55.) Report saved as tr_flush_d7b6b8d.html.
  st_helper_flush_d7b6b8d.fs SHA256 5ad1c0b26ce586ddc42d7004d086e636e2a0cb2f8b67b551b5457201c260dc9b (laptop hash verified).
- ~20:05 Flash 1/2 (op 53 loc 417, 100.6 s). Cold boot: hello, logo, memtest 4096 KB (flush_boot.png), desktop (flush_desk2.png).
  Warm reset 'w': hello + desktop (flush_warm.png). Desktop menus in low res, all 4 titles dropped (flush_t1..t6).
  Set Preferences -> ST Medium -> OK (flush_med3.png), A: opened (flush_m2.png), GB608B31.PRG main screen (flush_gb1.png).
- ~20:3x GEMBENCH: the first move up toward the menu bar froze the ST: pointer stuck at (455,90) between Extra and Help, just
  under the bar, no menu dropped (flush_touch_01_H.png); 21 more moves and a big move change nothing (flush_touch_02..21,
  flush_touch_22.png, flush_freeze.png). Helper link OK, core IRQ idle. = the F62b freeze, unchanged. Touches: 0 successful.
  => The Q_DISMISS mirror was NOT the cause (expected: logic-equivalent, and timing is now better than F62b and it still freezes).
- Flash 2/2: st_helper_f63_f484271.fs (hash verified, 101.5 s). Cold boot -> hello -> TOS desktop (flush_f63_desk.png). Board on F63.

## 20:45 On-board trace of the F62c freeze (diag-trace branch, worktree /workspace/repos/ftrace, from d7b6b8d)
- GAO: gao_analyzer.exe is GUI-only (SUG114: launched with -gao/-device/-fs, Start/Trigger/Export are toolbar actions);
  gao_sh.exe only says "invalid gao file"; programmer_cli has no GAO arm/readback op. Not headless -> in-fabric trace.
- In-fabric trace behind `define WF030_TRACE (build_trace.tcl = build_st_helper.tcl + the define + 2 files):
  WF68K30L_TOP/BUS_INTERFACE get an observation-only DBG/DBG_Q port (unconnected in normal builds).
  cpu030/trace/wf030_trace_cap.v (clk_cpu): one 144-bit entry per clk_cpu edge with an event (bus cycle end at AS
  negation, OPCODE_RDY, IPIPE_FLUSH rise, BUSY_EXH change, Q_DUMMY rise): ts, A23:0/FC/RW/SIZ/DSACK/BERR, D31:16
  (read: last sample with AS low, write: DATA_OUT), OPCODE_TO_CORE, PC_L, Q_CNT, OPC_RD, OPCODE_RDY, Q_DISMISS,
  IPIPE_FLUSH, Q_HIT/MISS/DUMMY, BUSY_EXH, IPL, PC. 4096-entry ring (~33k clk_cpu = 2 ms of ST-bus activity) + 16-entry
  watch ring of writes to $88/$404/$6ABC-$6AC3. Per-event (not per-clock) so the ring covers ~8x more time.
  Trigger (armed 67 s after CPU reset; warm reset re-arms): HALT_OUTn low | fetch E21D38 right after E21D40-5F fetches
  (AES trap #2 loop) | BERR outside I/O/ROM | program fetch outside RAM/ROM/cart | no VBL IACK for 262 ms. +64 entries.
  cpu030/trace/wf030_trace_view.v (pixel clock): after the trigger the HDMI picture becomes a bit dump (2x4 px cells,
  white markers, calibration + status rows, 19 pages x 2 s); before it only an 8x8 square (yellow / green = armed).
  gao_decode.py decodes frames/captures. End-to-end sim (gao_sim/tb_trc.v: snapshot replay + DBG netlist + cap + view,
  forced trigger, frames upscaled to 1920x1080): 2956/2956 ring entries decoded bit-exact.
- Build t1 (place_option 1): TNS 0 setup+hold on ALL clocks; clk32_core Fmax 32.183 MHz, clk_cpu030 16.832 MHz; BSRAM 208/340.
  gao_trace_d7b6b8d_t1.fs SHA256 af85894f5fd8348fe034eb929c2b39abb9393dc1893ddf115e495135c533ff3b (laptop hash verified).
  Timing report gao_trace_t1_timing.html.
- ~21:19 Flash 1 (op 53 loc 417, 104.6 s, flash ends at 0x04E8600). Helper up, blank.st on A (drive 0), cold boot 'c':
  hello, logo, memtest 4096 KB (gao_r1_boot.png, gao_r1_desk.png).
- Run 1 FALSE TRIGGER (~75 s after 'c', during boot): src=BERR at F00039 (TOS 2.06 IDE probe, read, BERR is the normal
  answer). My BERR filter treated A31:24 /= 0 as bad, but TOS uses $FFF00039 (short absolute, sign-extended -> FF).
  Dump captured over HDMI (gao_r1/f_001..088.png, 2 fps, 44 s) and decoded: all 19 pages, missing=0, disagree=0,
  badframes=0 -> board readout path works end-to-end. gao_r1/r1.txt = boot history (4031 entries before the probe).
  Watch ring at boot: $88 written 3x (E0FA3C last), $404 written (E00D3A), $6ABC-$6AC3 cleared. All normal.
- Warm reset 'w' clears the trace (square back to yellow); warm boot reaches the desktop at ~28 s, before arming (67 s),
  so the IDE probe no longer fires -> continued with this build (green = armed, desktop low res, gao_r1_d3.png).
- UI observation (trace build = F62c + capture logic): the AES reacts ONE MOUSE EVENT LATE (menu entry highlight
  shows the entry under the PREVIOUS pointer position, ui/b4-b6.png) and clicks on dialog radio buttons (Set Preferences,
  ST Medium) do not register (ui/a7-a11, b8, b9); Return closes the dialog; menu clicks work when the highlight is right.
  Possibly a symptom of the same bug (AES event/timer handling), to be checked against F63.
- ~21:35-22:05 tool outage (box shell + laptop disconnected). Board left on the trace build, low res desktop with the
  Set Preferences dialog open, trace armed, no trigger. Flashes this task so far: 1.
- 22:10 trace build t2 (same worktree, uncommitted): BERR trigger ignores A31:24 = FF (TOS short-absolute I/O probes),
  new src 5 HELPKEY = CPU reads scan code $62 from $FFFC02 (helper 'key help' freezes the ring by hand), src field 6 bits
  (status 43..38; gao_decode.py updated - r1 was decoded with the old 5-bit layout). place_option 1: TNS 0 setup+hold all
  clocks, clk32_core 32.007 MHz, clk_cpu030 16.308 MHz. gao_trace_d7b6b8d_t2.fs SHA256
  369ce68d50cc5a55dee72e115eeca9488e8fc5e6d0d0f4363526520169677493 (gao_trace_t2_timing.html). Laptop offline 21:35-22:32+.
- Code reading while offline (F62 queue vs core): WP_BUFFER loads at every IDLE->START (also PF-started), but WR_REQ in
  START is WR_REQ_I = DATA_WR sampled at that same edge, so a PF-entered START cannot turn into a write -> no stale write
  data from that path. Candidates kept: decoder P_BSY async clear (OPCODE_RDY) now strobed by queue hits every 2-3 clocks.
- t2 capture/view validated in sim (gao_sim/t2: netlist replay, forced trigger): 2956/2956 ring entries bit-exact.
  opcheck.py (new): every delivered, non-dismissed opword vs TOS ROM at PC_L - r1 board trace 1172 ok / 0 bad, sim 993/0.
- 23:0x-23:30 (laptop still offline) GHDL monitor bench /tmp/mon (d7b6b8d RTL + tb030 from 479b82b, sim-only P_MON in the
  bus interface): M1 = dismissal strobe (Q_DUMMY) while BUSY_EXH, M2 = a dismissal OPCODE_RDY reaching the decoder
  undismissed (stale OBUFFER taken as an opword). 250 runs (trapirq/pushrts/smcstack/linea/tas x IRQ_PER 397..1999 with
  level 6 VEC6=70 x WS/WSRND 0/0,0/3,1/2,3/0,5/4): all DONE, M1 = M2 = 0. Not that race (in these programs).

## 09 Oct 06:57- (laptop back; it rebooted at 06:54)
- programmer_cli: location 417 no longer exists ("Cable failed to open via the location"); --scan-cables now lists
  USB Debugger A/0/290 and A/1/289 (same FT2232, serial 2025041420, A = COM3 VCP, B = COM4 helper). --scan at 290:
  first attempt hung (killed after 3 min), then "Cable open failed / no valid JTAG target" at 290 and by cable index.
  Shell is not elevated, so no USB device restart possible. -> needs a physical replug of the board's USB (or power cycle).
  t2 NOT flashed. No flash happened.
- Board had reloaded t1 from flash overnight (power/USB cycle with the laptop reboot): same false IDE-probe trigger at
  boot (gao_r2, decoded clean: missing 0, disagree 0). Continuing the freeze capture with t1 via warm reset.
- 07:08-07:16 on t1 (warm reset, armed): Options menu entries never highlight and a click on them just closes the menu;
  the window fuller box stays inverted after a click until the mouse moves away (button release seen one packet late).
  Opened A: by double click, GB608B31.PRG in low res -> "needs 640x200" alert, Return (Quit) -> 07:15 the trace
  TRIGGERED (green/bit dump) = the program-quit crash. gao_r3 (88 frames, decoded: missing 0, disagree 0).

## ROOT CAUSE (gao_r3, 07:20-07:50)
- t1 trigger src (old 5-bit layout, decoded as "VBLTMO" by the new decoder) = exception into the TOS bomb handler: the
  CPU executes the string "A:\GB608B31.PRG" at $B576 (opwords 413A 5C47 4236 3038 = "A:\GB60...") -> CHK.L (d16,PC)
  -> vector 6 ($18 = $06E010E2) -> E010E2. So the PC was wrong, not the instruction stream.
- How it got there: TOS 2.06 AES Pexec wrapper E21BCE..E21C46 (jsr E21DCA; ...; trap #1 Pexec; adda.w #16,sp;
  jsr E21DCA; ...; jsr E21DD6; ...; rts). The GEMDOS return path E0FBB0..E0FBC4 builds a format-0 frame at $9B34
  (SR 2300, PC E21C0C, format 0000) and RTEs: SP = $9B3C. ADDA.W #16,SP -> SP must be $9B4C, so the JSR at E21C10
  must push at $9B48. The ring shows the JSR writing E21C16 at $9B4C, i.e. the SP decrement was lost; the RTS at
  E21C46 then pops $9B50 = the Pexec filename pointer $0000B576 instead of the return address -> crash.
- Bench repro (/tmp/rte, now cpu030/sim/rtl/prog_spwb.s; GHDL, d7b6b8d RTL): the exact sequence "RTE lands on
  ADDA.W #16,SP ; JSR (d16,PC)" fails at WS 0/1/2/3/5 every time ($BAD0000D = case 13). Probes: RTE deallocation is
  correct (+8, SP $7FFC); in the clock where JSR leaves START_OP the address register file gets AR_WR_1 (ADDA
  writeback, A7, $800C) and AR_DEC (JSR, A7) together; the ISP chain gives the write priority, the decrement is lost.
- Core defect: in START_OP, JSR decrements A7 (AR_DEC, "BSR/JSR/LINK and START_OP and NEXT /= START_OP") for every
  addressing mode, but only the (An)/(An)+/-(An)/An modes waited for AR_IN_USE; (d16,An), (d8,An,Xn), abs and PC
  modes went straight to FETCH_DISPL/... BSR right next to it already waits ("wait until A7 has been updated before
  decrementing"). Before F62 the opword/extension word arrived later than the ADDA writeback; the F62 queue delivers
  them back to back after an RTE refill, so the window opened. A real 68030 executes these strictly in order.
- Fix F62d (cpu030/wf68k30L_control.vhd, FETCH_DEC START_OP, CLR|JMP|JSR|LEA|PEA|Scc): for modes 101/110/111 JSR now
  stays in START_OP while AR_IN_USE (AR_SEL_RD_1 = A7 there), exactly like BSR. No other change.
  Bench: prog_spwb.s (17 cases x 4 loops: ADDA/SUBA/ADDQ/LEA/MOVEA to SP followed by JSR all modes, BSR, PEA,
  MOVE -(SP), plus RTE/RTS/BRA targets) and prog_rte.s pass at WS 0/1/2/3/5 with the fix, fail without it.
- The "AES one event late / radio clicks ignored" symptom is NOT explained by this yet (to be compared on F63 and on the
  fixed build).

## 09 Oct 07:25- flash cable, F63 comparison, tests
- programmer_cli --scan --location 289 (read-only scan): GW5AST-138 found (ID 0x0001081B) on "Gowin USB Cable(FT2CH)/0/289"
  -> the JTAG channel of the same FT2232 renumbered from 417 to 289 by the laptop reboot (290 = channel A, no JTAG target).
  Only one GW5AST on the chain. Flashing continues with op 53 at --location 289 (rule said 417 = this same cable).
- 07:28 Flash 1 today: st_helper_f63_f484271.fs (SHA256 b50d52b8...705a5 verified), op 53 loc 289, 102.4 s, ends 0x04D8D00.
  Helper up (blank.st on A), cold boot 'c': hello, logo, memory test 4096 KB, desktop at ~07:33 (ui/f63_0733.png).
- AES symptom on F63 (ui/f63_m1..m6.png): SAME as on F62c/t1. Menu entry under the pointer is not highlighted until a
  further mouse packet arrives; a single 'click' on a dialog radio button (ST Medium) is ignored, 'click 2' selects it;
  Return = OK. So "AES one event late / single clicks lost" is NOT the CPU fix's business (exists on F63; it is in the
  helper's mouse/button injection or IKBD path, not investigated further). F63 medium res desktop reached (f63_m6.png).
- RTL with the F62d fix (control.vhd only):
  * run_rtl.sh (+ new prog_spwb.s case): PASS - srmask a/b, chk/branch WS 0/1/3/7, spwb WS 0/1/3/7, prog_loop 44627 <= 45885.
  * 479b82b programs sweep (/tmp/mon sweep.sh, 250 runs trapirq/pushrts/smcstack/linea/tas x IRQ_PER x WS/WSRND, level 6
    VEC6=70): all DONE, monitors 0, result lines identical to the F62c sweep.

## 09 Oct 07:40- F62d build and board
- Build F62d (falconfpga f64-prefetch + fix, build_st_helper.tcl, place_option 1, copy in /tmp/bF62d): TNS 0 setup AND hold
  on all 46 clock rows; clk32_core Fmax 32.023 MHz, clk_cpu030 17.833 MHz (tr_f62d.html).
  st_helper_f62d.fs SHA256 21904e5aa09916f651a414dd32f8f1ae58504429387d7a17fbedb2cb89f58363.
- Whole-ST bench (run_bus.sh) F62d netlist /tmp/synF62d vs F62c netlist /tmp/synF62c started 07:38 (/tmp/simbusF62d, F62c).
- Commit 92a0a6a on f64-prefetch (local, not pushed): control.vhd fix + prog_spwb.s + run_rtl.sh.
- 07:44 Flash 2 today: F62d (hash verified, op 53 loc 289, 102.4 s, ends 0x04D8D00). The ST came up (TOS low-res desktop,
  ui/d_now.png) but the AE350 helper did NOT: COM4 silent, mouse commands ignored; cartridge self-test shows
  "helper not running (BOOT $02 = no flash-done)" (ui/d_r2.png).
- 07:50 Flash 3: F62d again (same file): same, BOOT $02, helper dead.
- 07:53 Flash 4: F63 (hash verified): helper boots normally (full COM4 log, hello from the ST). -> the helper boot failure is
  specific to this F62d place_option 1 bitstream (same size as the working F62c build; ST side fine). Board on F63.
- 07:57 rebuilding F62d with place_option 2 (allowed: other place option/seed) to get a bitstream whose AE350 boots.
- 08:11 place_option 2 build: NOT flashable (clk32_core setup TNS -84.3 / 63 ep, clk_osc hold -3.6, spi_io_clk hold -0.9). Kept in /tmp/bF62d/p2.
- 08:22 place_option 3 build: TNS 0 setup+hold on all 46 rows; clk32_core Fmax 32.092 MHz, clk_cpu030 18.862 MHz
  (tr_f62d_p3.html). st_helper_f62d_p3.fs 39420756 bytes,
  SHA256 49a67e59942c892cfa177b4881f2c624426fd645a1b9a1521aa626874d8833ae (laptop Get-FileHash identical).
- ~08:27 Flash 5 today: F62d p3, op 53 loc 289, 102.3 s, ends 0x04B2100 (< 0x500000). Helper BOOTS (full COM4 log,
  "hello from the ST"). -> the p1 helper failure was placement-dependent (same RTL, same files, only place_option differs).
- p3 cold boot 'c': hello, desktop (ui/p3_cold.png). Warm reset 'w': hello, desktop (ui/p3_warm.png).
- Options > Set Preferences opened fine (p3_m2/m3). ST Medium radio: click 2 / click+jiggle repeatedly did not select it
  (p3_m4..m8); pointer still moves. AES is alive: 'key ret' closes the dialog (p3_m10). Reopened: radio
  (click/click 2/click 3 + jiggles), 'No' button and 'Cancel' button clicks ALL ignored inside form_do (p3_m11..m14).
  On the desktop clicks mostly work (drive A double click opens the window, icon single click selects, menu clicks
  work; some double clicks on file icons lost). On F63 'click 2' selected ST Medium (f63_m*); on the F62c flush build
  ST Medium also worked (flush_med3.png); on trace build t1 radio clicks were ignored as here.
  -> medium res not reachable on this build with the helper's 60 ms clicks (console.c mouse_click: press 60 ms,
     release 80 ms). Not diagnosed further (form_do-specific click loss; F63 has a milder form of it).
- Fallback CPU test in LOW res (the exact F62c crash path: Pexec + quit through the TOS 2.06 AES wrapper E21C0C):
  * gb403.st mounted on A under a running TOS (no media change) -> stale A: listing (old blank.st contents) and
    "TOS error #35" on launch. That is the stale directory, not the CPU; after a warm reset with gb403 mounted the
    listing was correct.
  * GEMBENCH.PRG (gb403) via select + File>Open: "GEM Bench does not run in this resolution ... Quit", Return ->
    clean return to the desktop, 3/3 times (p3_g11/g12, p3_q2a/b, p3_q3a/b). On F62c t1 the same sequence (with
    GB608B31) bombed (CHK at $B576, gao_r3). -> the F62d fix works on hardware for the crash path.
- Medium-res workaround attempt: built gb6med.st = blank.st + NEWDESK.INF with "#E 18 02 00 06" (Hatari inffile.c
  format, 02 = ST medium) on the box (/workspace/gb/gb6med.st). sd_upload.ps1 to the SD FAILED on the first data line:
  "SDC: write timeout on sector 4738"; core sd_card.v went to card state 13 (status DC); 'sd init' did not recover.
  -> another F62d p3 fabric problem (SD write path in the core), or SD writes are fragile in general (not tried on
     F63 today). A 0-byte /sd/gb6med.st entry is left on the card (not deleted).
- ~09:00 Flash 6 today: F63 (SHA256 b50d52b8...705a5 verified), op 53 loc 289, 102.0 s, ends 0x04D8D00. Helper boots,
  SD ready (state 8), ls OK, crc blank.st 0076a0a2 and gb403.st 791ee820 = box copies -> card contents intact.
  Cold boot 'c': hello, desktop (ui/f63_final.png). BOARD LEFT ON F63.
- GEMBENCH numbers on F62d: NOT measured (medium res not reachable). F63 reference stays RAM 61, ROM 69, Display 37,
  CPU 137, Avg 71.
- Helper boot failure (p1), brief analysis: BOOT $02 = st_helper_ctrl handshake timeout ('T': AE350 never drove GPIO
  0xA5 within 2 s after DDR3 trained), STATUS $29 (HFAIL), COM4 completely silent -> the AE350 never ran its
  bootloader/firmware from flash 0x600000. Same RTL and files as p3 (only place_option differs), so it depends on
  placement. Candidates: the AE350 flash SPI path through the fabric pad mux (ae350_flash_clk/spi_io_clk not fully
  constrained: "spi_io_clk was determined to be a clock but was not created"; AE350 clocks are declared asynchronous
  to the fabric group), or the AE350 PLL init (hold slack 0.015 ns, clk_osc u_gowin_pll_ae350/u_pll_init, in p1).
  STA reported TNS 0 for p1, so the failing path is outside the constrained set. A proper fix would constrain the
  AE350 flash pad path (not done: a constraint change needs review, "don't hack constraints").
- Bench: whole-ST bench (run_bus.sh) F62d netlist vs F62c netlist: identical summary/result lines. GHDL cmp of 32 bus
  traces original vs fixed control.vhd on the TOS-derived programs: 0 differ (the fix only stalls in the RTE->ADDA->JSR
  case that prog_spwb case 13 covers).
- p3 bitstream was built from the /tmp/bF62d copy with build_st_helper.tcl place_option 3 (repo tcl still says 1; not
  changed or committed).

## 9 Oct 2026, 09:15-10:30: C (JSR fix on main) and A (helper flash SPI constraints)
- C done: commit 79f5951 on main (WF68K30L JSR waits for a pending A7 writeback; prog_spwb.s; run_rtl.sh spwb case;
  docs/ST_HELPER.md 7k with credits), pushed origin main 10c1dab..79f5951. run_rtl.sh on main+fix: PASS
  (/tmp/rtl_main_fix.log). Unfixed main also PASS (bug latent on the old fetch path, as expected).
- Board sanity flash for C: NOT done (optional; no F63+JSR bitstream was built or copied to the laptop).
  Checked 10:2x after the 10:05 interruption: last laptop flash log is flash_f63_3.txt (09:00), last capture
  f63_final.png (09:05), no programmer process running, no .fs newer than st_helper_f62d_p3.fs.
  -> BOARD IS ON F63 (st_helper_f63_f484271.fs, SHA256 b50d52b8...705a5), as left at ~09:05 (helper boots, desktop).
- A in progress: proposed SDC in /tmp/bSDC copy only (92a0a6a + SDC), box builds place_option 1/3/2, no flash.
  Write-up: SPI_SDC.md.
- ~11:00 A written up in SPI_SDC.md (diff, reasoning, builds f1/f3/f2 with the proposed SDC; no flash). Key results:
  TA1132 0; MISO at the reference 20 ns fails in all placements (-3.5 p1 / -4.1 p3 / -7.1 p2) and is not in the TNS
  table; p3 (boots originally) is worse than p1 -> not the discriminator. f2 fails TNS (clk32 -73, clk_osc hold).
  PLL-init hold margins come from clk_osc on generic routing (PR1014). Board still on F63.

## 9 Oct 2026, 10:51-11:45: SDC part 1 + reset synchronisers on main
- SDC part 1 (clock definitions/groups only, docs 7l) committed 6fd2bad on main, pushed ~11:45.
  Note: main+SDC1 alone at place_option 1 (/tmp/bM/r_sdc1) did NOT meet TNS (clk32_core setup -30.7 ns on 51
  blitter->gstmcu half-cycle endpoints, clk_osc hold -2.17 ns on pll_init). Placer variance + the clk_osc skew issue.
  Recovery worst -5.416 ns (DDR3 PHY reset -> OSER8 RESET, ddr3_clkin -> ddr3_memory_clk), removal worst -1.425 ns
  (por -> sth_frel), 25+ removal violations por -> clk32 / flash_clk flops. Header "setup violated endpoints" 2542.
- Reset work (uncommitted, /workspace/repos/fmain):
  * tang/console138k/reset_sync.v: 3-flop async-assert/sync-deassert chain.
  * top.sv: por32 (clk32) and por_flash (flash_clk) copies of por; every clk32 por consumer (s1 sync, dualshock2,
    audio/i2s, AE350 loan FSM, st_helper_ctrl, helper phase FSM, mailbox, misterynano.por) uses por32; sth_frel and
    the ST flash controller use por_flash (new misterynano input por_flash). Raw por kept for jtagseln/spi_dir/
    boot_button (combinational/pin, bl616 jtagsel stays off por). Sequencing unchanged (+3 clocks of release delay).
  * clk_osc for fabric loads (pll_init FSMs, S0/SPI-ext, ddr3/AE350 debounce) through a DCE global buffer (clk_g);
    PLL CLKIN still from the pad. hdmi_testpattern_640 got an init_clk port.
  * SDC: clk_g generated clock (added to the clk_osc groups), set_false_path to the PRESET pins of the two sync
    chains only, Gowin-reference exclusive group ddr3_memory_clk/ddr3_clkin (IP releases OSER resets with the memory
    clock stopped).
- Build r2 (/tmp/bR/r2, place 1): TNS 0 on all 48 rows; clk32 32.005 MHz, cpu030 17.823 MHz. Recovery worst +7.237,
  removal worst +0.247 (both tables fully positive, 400/233 rows listed). clk_g pll_init hold min +0.25 ns (was
  0.005-0.03, -0.36 in r_sdc1). TA1132: none. PR1014 still reported for the pad->DCE hop only.
- RTL tests (run_rtl.sh) on the reset tree: PASS.
- ~11:50 Flash 7 today: main+reset r2 (st_helper_mainrst_r2.fs, SHA256 d4f19cfd...efd268, laptop hash identical),
  op 53 loc 289, 102.0 s, ends 0x04CD300. Helper up (full COM4 log, SD ready, blank.st on A), 'hello from the ST'.
  Cold boot 'c': mailbox self-test BOOT $05 STATUS $37, memtest 4096 KB, desktop (ui/mr_cold2.png, mr_desk.png).
  SD read: crc blank.st 0076a0a2 (= box copy). Options > Set Preferences opens (mr_m2); radio "File Deletes: No"
  selected with ONE click (mr_m3). Exit buttons: Cancel ignored on click / click 2 / jiggle+click (mr_m4-m8,
  pointer moves fine, link OK) -> same exit-button click loss as F62d p3 (pre-existing form_do issue, not reset);
  'key ret' closed the dialog (mr_m10). Double click on drive A opens A:\ (6 items, mr_m11).
- Bus bench (run_bus.sh, wf030 netlist of main+JSR /tmp/synMain): running.
- Bus bench on main+JSR+reset: register dump R1000-R1200, 8914 ST cycles, RAM/ROM/IO data-valid lines identical to
  the F63 reference (busfix/f63_run3.log), no late reads. RTL PASS.
- ~12:00 committed 382524f (reset synchronisers + DCE clk_g + SDC + docs 7m) and pushed: main 6fd2bad..382524f.
  Bitstream = r2 = st_helper_main_382524f.fs (SHA256 d4f19cfd...efd268). Board currently on it.
- ~12:05 f64-prefetch rebased onto main 382524f (backup tag f64-prefetch-pre-rebase = 92a0a6a): 8f104b3 F62,
  9e612d5 F62b, ef56b11 F62c, 8317fd1 RTL bench, 75bfc8c F62d. Conflicts only run_rtl.sh / control.vhd (took the
  branch version = JSR fix identical to main's). cpu030/ tree identical to 92a0a6a; diff vs pre-rebase = main's
  SDC/reset/docs only. Not pushed. Building F62d-rb place 1 in /tmp/bF64.
- RTL on the rebased F62d: PASS (incl. chk/branch, SP writeback, loop timing).
- F62d-rb place 1 (/tmp/bF64/r1): TNS FAIL (clk32_core setup -1.536 / 9 ep, ikbd microcode + blitter->gstmcu half
  cycle; spi_io_clk hold -0.051 / 1 ep) -> not flashable. Recovery +6.07, removal +0.264 (clean). Trying place 3,2,0,4.
- F62d-rb place 3 (/tmp/bF64/r3): TNS 0 on all 48 rows; clk32 32.414, cpu030 17.898 MHz; recovery worst +7.50,
  removal worst +0.347 (all rows positive); clk_g pll_init hold min +0.248. Bitstream st_helper_f62d_rb_75bfc8c_p3.fs
  SHA256 2d4c2a10...38a780c. (Build tree tcl place_option 3; repo tcl unchanged at 1.)

## 9 Oct 2026, 12:32- F62d-rb place 3 on the board (flash 8 today)
- ~12:35 Flash 8: st_helper_f62d_rb_75bfc8c_p3.fs (SHA256 2d4c2a10...38a780c, laptop hash identical), op 53 loc 289,
  98.2 s, ends 0x04B2100. Helper BOOTS (SD ready, blank.st on A, 'hello from the ST').
- Cold 'c': mailbox self-test BOOT $05 STATUS $27, memtest running at +45 s (ui/rb_cold.png). Warm 'w': same
  self-test, memtest (rb_warm.png), desktop at ~+55 s (rb_warm2.png).
- mount a /sd/gb403.st + warm reset -> desktop. Options > Set Preferences: ST Medium radio selected with ONE click
  (rb_o3.png), 'key ret' -> medium-res desktop (rb_o4.png). A: double click -> GEMBENCH 6.31 files (rb_a1.png),
  GEMBENCH.PRG double click -> main window, ST Medium, reference STE (rb_g2.png).
- Menus: the 5 menu-bar titles (GEMBench/File/Test/Windows/Help) dropped/highlighted 3 rounds (forward, back, forward;
  rb_mn1_1..5, rb_mn2_*, rb_mn3_*). No freeze (the F62b/F62c freeze is gone).
- Test > All Tests (Display + CPU groups) completed (~4 min). Menus work after the run (rb_post1/2), helper link OK.
  Results screenshot ui/gb6_results_f62d_rb_75bfc8c.png:
    test                F63 f484271   F62d-rb 75bfc8c (time s)
    GEM Dialog Box      47%           71%  (11.130)
    VDI Text            33%           74%  (18.825)
    VDI Text Effects    40%           75%  (31.905)
    VDI Small Text      37%           74%  (18.320)
    VDI Graphics        68%           69%  (27.385)
    GEM Window          42%           68%  (4.805)
    Integer Division    611%          662% (2.715)
    Float Math          -             77%  (17.180)
    RAM Access          61%           76%  (8.260)
    ROM Access          69%           85%  (7.365)
    Blitting            13%           77%  (11.390)
    VDI Scroll          28%           77%  (17.375)
    Justified Text      33%           72%  (19.050)
    VDI Enquire         68%           68%  (3.870)
    New Dialogs         -             67%  (14.065)
    Display/CPU/Average 37/137/71     72/225/112
- PASS -> BOARD LEFT ON F62d-rb place 3 (st_helper_f62d_rb_75bfc8c_p3.fs, SHA256 2d4c2a10...38a780c), GEMBENCH open
  in ST Medium. Fallback: st_helper_main_382524f.fs (laptop copy st_helper_mainrst_r2.fs, SHA256 d4f19cfd...efd268).
  Note: self-test STATUS $27 here vs $37 on main r2 (both BOOT $05, helper fine); not investigated.

## 9 Oct 13:35 fix 2 (core: no idle states between transfers) - NOT done, blocked by design
- wf68k30L_top.vhd:744-764 hides the requests while BUS_BSY=1 (RD/WR/OPCODE_REQ_I <= 0, comment: avoids
  combinatorial loops); they are only seen in IDLE. So the next transfer cannot be picked up in the last DATA_C1C4
  clock. Skipping IDLE at best: 156 -> 94 ns. The slot model says 94 ns alone = 0 gain (the request must be <= 62.5 ns
  after the ST AS rise to hit the en1). The 31 ns target needs a reworked control<->bus handshake. No change, no build, no flash.
  Board still on F62d-rb p3.
- 14:3x BRIDGE_EARLY_AS d43f5fd p3 (/tmp/bE/r3): TNS 0 (48 rows), clk32 32.037, cpu030 16.985 MHz, recovery +7.974, removal +0.256.
  Bus bench (prog_bus.s, define on): R1000-R1200 identical, 0 late. Flash 9 (102 s), cold boot desktop, ST Medium,
  GEMBENCH All Tests: RAM 86 ROM 86 Display 74 CPU 230 Avg 115 (F62d-rb 76/85/72/225/112). ui/gb6_results_eas_d43f5fd.png.
  Board left on it (fallback st_helper_f62d_rb_75bfc8c_p3.fs).
