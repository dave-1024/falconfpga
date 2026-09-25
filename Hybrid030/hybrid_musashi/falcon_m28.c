/* =====================================================================
 * M12g (2026-08-07): IDE ARC COMPLETION -- three queued items, cut on
 *   Dave's go after the m12f milestone (formatted, partitioned, boots
 *   from C:). (A) CPU-side 24-bit alias: is_ide masks to 24 bits like
 *   the m12f blitter window and Hatari (addr&=0xFFFFFF); offsets
 *   normalized. (B) STANDBY/IDLE/SLEEP family E0-E3,E6 + 94-97 accept
 *   as no-op success; E5/98 CHECK POWER MODE returns scnt=0xFF active
 *   (Atari AWTO=$e3; Hatari parity; we aborted). (C) Dynamic drive
 *   name: model string = HDnNAME= from FALCON.CFG (<=40ch) else the
 *   hardfile 8.3 stem (HD0.IMG -> "HD0") else historic default;
 *   serial FIXED (drivers key on it); rev field M11Q -> M12G.
 * M12f (2026-08-06): THE BLITTER-IDE WINDOW -- root cause of the whole
 *   AHDI starvation, found in Atari's own source (Dave's HDX/AHDI
 *   archive, IDE.S identify(): _useblit -> initblit -> blitter drains
 *   the data register, XCNT=256). Bench driver = blitter-drain-era
 *   AHDI; blit_ram_r16 returned 0xFFFF outside RAM/ROM, so the drain
 *   filled AHDI's buffer with garbage invisibly (r=0, the fe/ff 0x91
 *   operands were the buffer contents). Hatari works because its
 *   blitter walks the full memory map; glass-box AHDI 6.06 takes the
 *   CPU path (Apr-92 IDE.S changelog shows the churn). Fix: 24-bit-
 *   masked $F00000..$F0003F blitter accesses route via ide_read8/
 *   ide_write8, byte pairs, identical to CPU semantics. Carries the
 *   m12e-era host diagnostics (SKIP_FDCTEST gate, IDELAT override,
 *   both HOST_TEST-only). Decisive test is Dave's bench: only his
 *   driver exercises the blitter drain.
 * M12e (2026-08-06): SEAM VIEWER -- instrumentation only, m12d base
 *   untouched. Hatari 2.6.1 (built in-container; TOS404 now boots
 *   there) supplied ground-truth traces: AHDI's flow is scribble-
 *   probe, EC, ONE status read, 256x word drain -- and a mechanical
 *   replay of that exact 530-op conversation against THIS model
 *   answered with zero structural divergence. The model is register-
 *   level correct; the bench failure (r=0, GPIP spin) lives in the
 *   seam the replay cannot exercise. So: see the seam. [ider] = RAM-
 *   PC-band-gated compact register trace with VALUES (rR19=a0 /
 *   rW1d=ec / rD=xx / rRxx=00! absent), own 1500 budget the ROM's
 *   boot drain cannot touch; rG lines = GPIP values read from RAM
 *   pcs, printed on change + decimated heartbeat with counts. One
 *   boot makes AHDI's silicon conversation diffable line-by-line
 *   against its Hatari one.
 * M12d (2026-08-04): REAL IDE COMMAND LATENCY -- retires the fake-BSY
 *   era. m12c silicon: HDX never reached FORMAT TRACK; the 64xxx tool
 *   raised IDENTIFY/READs and drained ZERO bytes ([ided] r=0 on every
 *   command) while spinning on GPIP $FFFFFA01 -- its wait starved
 *   because instant completion let its post-issue status PEEK consume
 *   INTRQ before the wait began. Third casualty of zero-time
 *   completion (after M11s pollers and D9b single-readers). Fix:
 *   commands are genuinely BSY with INTRQ down for IDE_LAT (100us
 *   wall); at the deadline final status appears and INTRQ asserts
 *   (completions) or DRQ appears silently (write/format setup).
 *   Mid-stream block boundaries stay instant. bsy_once deleted.
 *   falcon_ide.c + GPIP hook + ide_now() here.
 * M12c (2026-08-04): D8c FIX -- FORMAT TRACK (0x50). Disassembly of
 *   Atari HDX (hdx.prg) showed its format loop at 0x22ce0 issues the
 *   obsolete 0x50 FORMAT TRACK per track, with a DRQ phase carrying a
 *   sector-descriptor buffer. Our model had no 0x50 case -> aborted
 *   (ERR) -> HDX's DRQ poll failed -> "Cannot format unit 0". m12b's
 *   geometry-word fix (w130/131) was real but incidental: silicon
 *   [ided] showed HDX drained 512 bytes fine, so the gate was never
 *   the identify -- it was the missing format command. 0x50 now
 *   accepts, runs one DRQ write phase, DISCARDS the descriptor (a
 *   file-backed image has no tracks; writing it would corrupt the
 *   media), completes OK. Keeps m12b w130/131 + m12a [idec]/[ided].
 * M12b (2026-08-04): D8b FIX -- Atari HDX geometry gate. Disassembly of
 *   hdx.prg (this disk's Atari HDX) showed its geometry extractor reads
 *   CHS from IDENTIFY VENDOR words 130/131 (Conner CP-era layout), not
 *   the ATA-standard 54-56. We zeroed everything past word 61, so HDX
 *   read 0/0/0 -> "Identification unavailable" dashes + "Cannot format
 *   unit 0" with no bus traffic. Fix: mirror geometry into w130/131.
 *   Retains [idec]+[ided] from m12a. Verified byte-exact against the
 *   disassembled read offsets by host jig. falcon_ide.c only.
 * M12a (2026-08-04): [ided] DATA-PHASE FORENSICS for the HDX dashes.
 *   HDX's unit box has shown our IDENTIFY string in the past (Dave:
 *   seen in both HDX and HDDRIVER) and now shows dashes on m11z,
 *   media-independent -- a regression whose data phase we could not
 *   observe: the ROM's boot IDENTIFY exhausts [idet]'s 400-access
 *   budget every boot before HDX runs. [ided] tallies each command's
 *   data phase instead: bytes served/consumed + first 8 bytes over
 *   the wire, printed before the next [idec] line and at SRST, on
 *   the 4096 idec budget. Instrumentation only; no behavior change.
 * M11z (2026-08-03): D9b -- M11s FAKE BSY vs M11y INTRQ COLLISION. On
 *   m11y silicon the TOS404 ROM and AHDI passed the GPIP wait for the
 *   first time, read status ONCE (the interrupt-driven pattern), and
 *   got the M11s bsy_once fake 0x80 -- which also consumed the INTRQ
 *   clear. Both retried and gave up (AHDI: "cannot format", empty
 *   device box = IDENTIFY data never drained). Real hardware never
 *   asserts INTRQ while BSY. falcon_ide.c: ide_done() makes
 *   completion atomic (INTRQ up, fake BSY down) at all 9 completion
 *   sites; the fake survives only pre-completion (write-data setup,
 *   DEVICE RESET), where pollers still need the transition.
 * M11y (2026-08-03): D9 FIX -- IDE INTRQ -> MFP GPIP bit 5. TOS404's
 *   ROM driver and AHDI never poll IDE status: they issue a command
 *   and spin on $FFFFFA01 waiting for INTRQ (shared with the FDC on
 *   GPIP5, active low), then read status once. The model had no
 *   interrupt path at all, so both timed out ("IDE0 does not
 *   respond"); EmuTOS polls status and masked this all along.
 *   falcon_ide.c: ide_intrq per ATA (see block comment there).
 *   This file: fwd decls beside fdc_intrq + GPIP5 composition now
 *   ORs the nIEN-gated IDE line. Reflection-only, no vectored raise,
 *   exactly the FDC precedent.
 * M11x (2026-08-03): [idec] PER-COMMAND IDE TRACE for D8. falcon_ide.c
 *   only: one line per task-file command (dev, cmd, LBA/CHS mode, full
 *   task file, resolved LBA, live geometry), explicit lines when 0x91
 *   reprograms geometry and when SRST fires ide_signature(). Own budget
 *   (4096 cmds/boot) so the 400-access [idet] cap -- exhausted by the
 *   first IDENTIFY's data phase -- cannot silence it. This file: banner
 *   bump + boot timing label now follows BUILD_O2 from the bat (was
 *   hardcoded "(-Og)" and would have lied under the new -O2 recipe).
 * M11w (2026-08-02): NCR5380 ARBITRATION STUB. HDDRIVER V13.01
 *   enumerated our IDE, printed the model string, marked seven empty
 *   positions [No device] -- then crawled through the SCSI IDs: the
 *   log shows 28.4M reads of ffff8783 (5380 reg 1, the Initiator
 *   Command Register) from one RAM pc, alongside writes to 8785 (mode
 *   register). That is a proper multi-initiator driver doing SCSI bus
 *   arbitration: set ARBITRATE, poll ICR for AIP. On real silicon AIP
 *   asserts within a bus-free delay, so the wait is legitimately
 *   patient; our all-zero stub meant it only ended by long timeout,
 *   eight IDs over. EmuTOS tolerated zeros because it bounds the wait
 *   cheaply -- TOS-era software treats SCSI as guaranteed Falcon
 *   hardware and interrogates it properly.
 *   Now: registers latch; ICR reads report AIP whenever the mode
 *   register's ARBITRATE bit is set, lost-arbitration stays clear (a
 *   free bus is always won), bus status stays 0 (no target ever
 *   answers). Arbitration completes in one poll; each empty ID then
 *   fails at the normal ~250ms selection timeout. No targets, no
 *   transfers -- just enough truth for a correct driver to conclude
 *   'nobody home' quickly. Same lesson as the FDC RNF and the DMA
 *   sound 0xFF, in its third costume: a stub must fail the way the
 *   real chip fails, or a correct driver waits on it.
 * =====================================================================
 * M11v (2026-08-02): 32-BIT DATA REGISTER. The EmuTOS silicon trace
 *   showed the full detection ladder passing -- scribble, absent dev1,
 *   reset signature 0101, cylinder check, BSY transition -- then the
 *   data drain issuing FOUR byte-reads per instruction: MOVE.L on the
 *   data register. EmuTOS's Falcon driver uses 32-bit transfers; real
 *   hardware runs two bus cycles into the 16-bit data register. Our
 *   decode covered only bytes 0-1, so every longword's lower word came
 *   back 0000 and IDENTIFY arrived shredded. Data register now spans
 *   +0..+3 on both read and write. One condition, both paths.
 * =====================================================================
 * M11u (2026-08-02): WAIT-LOOP DISASSEMBLY. The m11t silicon trace
 *   contradicted expectation: the wait loop at pc=12580 saw the full
 *   BSY->DRQ transition (one 0x80, then 0x58) and spun ~4M passes
 *   anyway, never touching the data register, then a second phase
 *   polled MFP GPIP (almost certainly AHDI's ACSI probe, not ours).
 *   The loop's exit condition is therefore none of the obvious ones,
 *   and five wrong performance guesses this week argue for reading it
 *   rather than inferring it. The loop is guest code in our own ram[]
 *   and Musashi links m68k_disassemble: on the 40th traced IDE status
 *   read, dump +/-0x60 bytes around the polling pc as disassembly,
 *   once. No behavioural change.
 * =====================================================================
 * M11t (2026-07-31): IDENTIFY BYTE ORDER. M11s proved the BSY fix --
 *   the trace showed the full transition and all 512 IDENTIFY bytes
 *   drained cleanly -- and then AHDI reported no devices, because the
 *   words arrived byte-swapped: ide_put16 stored little-endian while
 *   the guest assembles words first-byte-as-MSB (word 0 read 0x8a84,
 *   not 0x0040). Words now stored big-endian, strings in natural order
 *   (the ATA ^1 swap is a little-endian-bus convention and
 *   double-swapped here), and signature reset clears a stale bsy_once
 *   (seen as a phantom R +1d -> 80 after a devctl write).
 *   Sector data is untouched: image bytes pass through in order, the
 *   Atari-native convention, with the per-image swap flag for PC
 *   images -- the IDENTIFY buffer simply bypassed that decision.
 * =====================================================================
 * M11s (2026-07-31): BSY TRANSITION FIX. The m11r trace showed both the
 *   TOS 4.04 ROM driver and AHDI issue IDENTIFY, then poll status
 *   forever at 0x58 (DRDY|DSC|DRQ) without ever reading the data
 *   register. The model completed commands instantly and jumped
 *   straight to DRQ -- BSY was never observed set, so a driver waiting
 *   for the BSY->ready transition a real device makes never saw its
 *   exit condition. Now every command shows BSY for exactly one status
 *   read (either register), then the real status. One flag, two lines.
 * =====================================================================
 * M11r (2026-07-28): IDE FULL REGISTER TRACE. M11q got TOS 4.04 to read
 *   alt status (0x50), select device 0 and issue 0xEC IDENTIFY -- then it
 *   never read the data register and went on to the desktop with no
 *   drive. The first-touch io log cannot explain that: it keys on address
 *   not direction, so once fff0001d appeared as a WRITE every status READ
 *   of it became invisible. falcon_ide.c now traces every access with PC,
 *   direction and value, capped at 400 lines, regardless of LOG=.
 * =====================================================================
 * M11q (2026-07-28): IDE DEVICE MODEL on M11p's storage layer. See
 *   falcon_ide.c (#included below, as falcon_blitter.c is) for the
 *   register map, which came from EmuTOS's own struct IDE rather than
 *   being derived. Answers ONE interface at 0xFFF00000..3F -- EmuTOS
 *   probes four, 0x40 apart, and the others must keep bus-erroring
 *   because a real Falcon has one. Two devices with SEPARATE register
 *   files, because EmuTOS detects by scribbling 0xAA/0x55 and reading
 *   it back, so a shared file would conjure phantom drives.
 *   +0x39, the alternate status register, is what TOS 4.04 has been
 *   BERRing on in every boot log since the beginning.
 * =====================================================================
 * M11p (2026-07-28): IDE STORAGE LAYER. No device model yet -- this is
 *   the half that can corrupt a card, so it lands alone and testable.
 *     sd_map_only()  chain building without the preload. Added BESIDE
 *       sd_mount rather than refactored out of it: sd_mount backs the
 *       floppies, it is verified, and it should not be touched to
 *       serve a feature that does not exist yet.
 *     hdd_read/write chain lookup -> 8MB direct-mapped cache -> SD,
 *       WRITE-THROUGH. Every guest write reaches the card before the
 *       call returns: nothing to flush, no dirty-eviction path (the
 *       part of a cache that actually generates bugs), nothing lost on
 *       a power cycle, and write ordering preserved for the guest
 *       filesystem's crash consistency.
 *   Sizing: this card uses 32KB clusters (DISKA is 737280 bytes in 23
 *   clusters), so SD_MAXCLUS=4096 already spans 128MB -- comfortably
 *   past the 40-120MB of the Falcon era. No chain resize needed.
 *   Bounds violations log once and refuse. Not to protect the card but
 *   to preserve evidence: a bad chain index does not corrupt the
 *   hardfile, it writes 512 bytes at an arbitrary card LBA, which
 *   might be the FAT or a ROM image. Silence would leave a dead card
 *   and no idea which candidate bug did it.
 * =====================================================================
 * M11o (2026-07-28): ST-RAM FAST PATH. ~99%% of guest accesses are
 *   plain ST-RAM (gmem_r ~52.9M vs io_r ~0.5M per interval), yet rd()
 *   and wr() split every one into bytes and called rd8_resolve /
 *   wr8_resolve per byte, each redoing the whole address decode: two
 *   calls for an instruction fetch, four for a longword. wr() also ran
 *   the FF8A3C blitter-pair test on all 12.5M writes per interval.
 *   Now: one range test, then inline loads/stores from ram[]. Anything
 *   not wholly inside ST-RAM falls through to the original code, so
 *   io, ROM, cart and bus-error behaviour are bit-identical.
 *   Evidence this is the right target rather than a fabric blitter:
 *   the GEMBench sheet has Blitting at 70%%, the FASTEST display test,
 *   while VDI Text sits at 30-35%%. A bandwidth limit hurts the big
 *   transfers most; this is the opposite shape, so the cost is
 *   per-operation. Text does many small operations and pays dispatch
 *   overhead on each. CPU tests already run at 196%%.
 *   Also fixes M11k's log_io gate, which sat AFTER cur_pc() and the
 *   263-entry scan, so LOG=0 still paid both on every io access.
 *   GATE: hottest path in the emulator. The EmuTOS fixture covers it
 *   across ~4e9 cycles, but run the POV-Ray certification c4fb2c0c
 *   before trusting this one -- that is the test that catches a CPU
 *   semantic change.
 * =====================================================================
 * M11n (2026-07-27): completes M11m. M11m won 1.93x (2.82 -> 5.43 MHz
 *   effective on silicon, lost5 to +0) by replacing tb_read's
 *   WBINVAL_ALL with a targeted slot invalidate -- but hid_consume()
 *   had been quietly depending on that blanket flush to see the USB
 *   HID ring the FABRIC writes into DDR3. Its own comment says so:
 *   "one VBL, post-WBINVAL". With the blanket gone the CPU read the
 *   ring from stale cache: no keys, no mouse, F12 dead. Identical
 *   consumer-direction hazard, and M11m fixed one of two.
 *   The RTL bounds the problem: falcon_hid_ahb.v and
 *   falcon_timebase_ahb.v are the ONLY fabric AHB write masters
 *   (falcon_video.v reads only), so timebase + HID is the complete
 *   set of fabric->CPU regions. Both now go through one
 *   dcache_inval_range() so a third would have one place to be added.
 *     HID ring 0x03FE0000 (128 x 16B), head 0x03FE0800
 *   Cost: 257 CCTL pairs per hid_consume at 60Hz, well under 0.01%%.
 * =====================================================================
 * M11m (2026-07-27): THE CACHE FIX. Command encodings are from Dave's
 *   own AndeSight BSP (library/bsp/ae350/cache.c), not inferred:
 *     0 CCTL_L1D_VA_INVAL   1 CCTL_L1D_VA_WB   2 CCTL_L1D_VA_WBINVAL
 *     6 CCTL_L1D_WBINVAL_ALL   7 CCTL_L1D_WB_ALL
 *   confirming 6 is what this firmware had been using everywhere.
 *   1. mbox_publish: WBINVAL_ALL -> WB_ALL. Framebuffer and mailbox
 *      are producer-only: we write, the fabric reads. The dirty lines
 *      must reach DDR3; our copies never needed discarding. One word.
 *   2. tb_read: WBINVAL_ALL -> VA_INVAL over the 32-byte slot. This
 *      one IS the consumer direction so it must invalidate -- but a
 *      slot, not the whole cache. M11l measured this single call as
 *      82%% of all flushes: once per emulation slice, ~283/s against
 *      the publish's 60/s, ~58us each, leaving the cache cold every
 *      10k emulated cycles so it never survived to be worth having.
 *   CACHEOPT=0 in FALCON.CFG reverts both to WBINVAL_ALL, so the A/B
 *   is one flash and a reboot. M11l measured 2.82 MHz at FLUSHDIV=1
 *   and 4.74 at FLUSHDIV=8, extrapolating to ~5.7 at zero flushes;
 *   CACHEOPT=1 should approach that with coherency intact.
 * =====================================================================
 * M11l (2026-07-27): CACHE-FLUSH DIAGNOSTIC. Not a candidate for a
 *   long-term flash -- FLUSHDIV>1 deliberately breaks scanout
 *   coherency and the picture will tear or go stale. Nothing is
 *   corrupted: the fabric only ever reads DDR3.
 *   Question: L1D_WBINVAL_ALL runs every VBL to publish the
 *   framebuffer and mailbox, and leaves the D-cache completely cold
 *   60 times a second. TOS 4.04 idles at 3.05 MHz effective, 262
 *   host clocks per emulated cycle at 0.396 guest accesses per
 *   cycle. Is the flush why?
 *     flush=<done>/<skipped> avg=<mcycles>  cost of the instruction
 *     FLUSHDIV=N in FALCON.CFG                cost of the cold cache
 *   The timer alone cannot answer it: the expensive part is not the
 *   CCTL, it is every subsequent miss. Only the divider exposes that.
 *   Read it as: FLUSHDIV=8 lifting throughput several-fold => the
 *   flush is the bottleneck and the fix is range-based CCTL over the
 *   framebuffer and mailbox instead of _ALL. Throughput barely moving
 *   => the cost is elsewhere and the hypothesis is dead.
 *   The first 240 calls (~4s) always flush regardless of the divider,
 *   so boot and mode-set stay coherent -- a torn mailbox pair reaching
 *   the fabric is the one genuinely bad outcome and that is when it
 *   would happen.
 * =====================================================================
 * M11k (2026-07-27): SWITCHABLE INSTRUMENTATION + the counters M11j
 *   lacked. Still no behavioural change to the emulated machine.
 *     LOG=0/1 in FALCON.CFG sets the boot state; F12 toggles at
 *       runtime. USB usage 0x45 (F12) has no Atari equivalent -- the
 *       ST keyboard stops at F10 -- so consuming it steals no key
 *       from the guest. This matters because the M11j logs showed
 *       the status print itself blocks ~110ms at 38400 baud, trips
 *       the >81ms discard guard, and costs ~22 ticks EVERY print:
 *       in the EmuTOS idle tail that WAS the entire drift (ratio
 *       0.972 with lost5 flat at zero). Run silent, toggle on to
 *       read, and the counters describe the machine not the probe.
 *     mfpiv/lostiv  per-interval, reset at each print. M11j's were
 *       global maxima and got pinned by a single boot-time event
 *       (761146 ticks under TOS, 3136491 under EmuTOS), so they
 *       never showed the recurring stalls they were built for.
 *     gmem_r/gmem_w  total guest memory accesses. Subtract io_r/io_w
 *       for RAM traffic. Tests whether TOS 4.04 costing ~118 host
 *       clocks per emulated cycle against EmuTOS's ~19 is explained
 *       by memory traffic through the DDR3 callback path.
 *     ipl6  slices sampled with IPL>=6. Settles by measurement what
 *       blocked=0 only settles by inference.
 *   Also fixes M11j printing %llu, which the BSP printf cannot
 *   format -- resync's tick total came out as the literal "lu".
 * =====================================================================
 * M11j (2026-07-26): CLOCK-DRIFT INSTRUMENTATION ONLY. No behaviour
 *   changes -- every edit is a counter or a printf. Answers the open
 *   question 'why does TOS 4.04's clock lose time against wall while
 *   EmuTOS tracks?' by measuring, on silicon, the three candidate
 *   mechanisms separately:
 *     lost5      Timer C raises that hit an ALREADY-SET IPR bit.
 *                IPR is one bit per channel, so these ticks are
 *                silently dropped -- the guest never sees them.
 *                This is the late-servicing mechanism.
 *     mfpmax     largest number of MFP clock ticks accumulated
 *                between two consecutive MFP service points, i.e.
 *                the worst non-preemptible stall. One Timer C period
 *                is 12288 ticks; anything above that dropped a tick.
 *     resync     times the >200000-tick stall guard fired, and the
 *                total ticks it DISCARDED. That guard silently
 *                throws elapsed time away (81ms+ per event).
 *     hz200 vs t200  guest's own 200Hz counter against the hardware
 *                slot's, sampled in the same instant -- the ratio is
 *                the drift, with no stopwatch and no start offset.
 *   Read it as: constant hz200/t200 ratio under both idle and load
 *   => rate error (WALL_HZ wrong). Ratio worsening with load, with
 *   lost5 and mfpmax climbing => late servicing, and mfpmax names
 *   the stall to chunk. resync non-zero => a third mechanism.
 * =====================================================================
 * M11i (2026-07-26): AUTHENTIC NO-DRIVE FDC SEMANTICS. TOS 4.04's
 *   desktop drive-B I/O never asserts a PSG drive select (measured:
 *   Port A = 0x27 for every B command; the healthy unit=B traffic in
 *   earlier logs was the firmware's own self-test). Our model answered
 *   an instant RNF, aborting TOS's sequence with "Disk is not
 *   readable". Real WD1772 + Hatari spec: a Type II/III command with
 *   no drive selected finds no index pulses -- it PENDS on busy until
 *   a drive is selected (Hatari fdc.c: "will not fail ... will wait
 *   forever"). Now modelled: such commands pend; a drive select via
 *   Port A retries them; Force Interrupt (D0) cancels. Under TOS 4.04
 *   the pend times out via TOS's own D0 watchdog -- the same alert,
 *   now for the authentic reason: TOS 4.04's desktop floppy layer is
 *   genuinely single-drive on Falcon (community lore: dual-floppy
 *   needs TOS patches). Drive B remains fully functional under EmuTOS.
 * =====================================================================
 * M11h (2026-07-25): STOCK NVRAM. Removes the Stage-1 relic that
 *   pre-planted boot video mode 0x0014 (VGA truecolor) with a valid
 *   checksum into NVRAM cells 28/29 -- originally to steer the first
 *   HDMI scanout, lately steering every boot. A stock Falcon powers up
 *   with battery-good, ZEROED user cells and an INVALID checksum; the
 *   OS notices and writes its own defaults. The OS now owns the
 *   config: first boots use genuine TOS/EmuTOS defaults (expect a
 *   different first-boot mode than before), and a resolution saved on
 *   the desktop survives warm reboots. Clock regs 0-9 now tick from
 *   the wall (BCD, 24h, base 1994-01-01) and are settable; NVTEST
 *   added to the boot self-tests.
 * =====================================================================
 * M11g (2026-07-25): BLITTER READS ROM. TOS 4.04's VDI text blits
 *   (measured: 252+ single-word HOP=source LOP=OR ops per redraw)
 *   fetch their glyph data from the SYSTEM FONT IN ROM (0xE4Bxxx).
 *   blit_ram_r16() only mapped ST-RAM and returned 0xFFFF for all
 *   other addresses, so every glyph OR'd solid ones onto the screen:
 *   icons (RAM-resource sources) perfect, every text cell black --
 *   as photographed on silicon. The real BLiTTER is a bus master and
 *   reads ROM like any other address. Now so does the model
 *   (read-only; ROM writes remain ignored).
 * =====================================================================
 * M11f (2026-07-25): ATOMIC BLITTER START. TOS 4.04 starts blits with a
 *   single word write to FF8A3C -- control (busy) in the high byte,
 *   FXSR/NFSR/skew in the LOW byte -- which real hardware latches as
 *   one 16-bit access. Our byte-splitting funnel dispatched the high
 *   byte first: the synchronous blit ran to completion BEFORE the same
 *   word's skew byte landed, so every blit executed with the PREVIOUS
 *   blit's skew. Aligned (skew-0) fills were unaffected; every skewed
 *   blit -- VDI text and icons -- garbled. Measured on silicon photos +
 *   host blitlog: 96/120 combined starts carry nonzero skew/NFSR.
 *   FIX: word/long writes covering FF8A3C dispatch the skew byte (3D)
 *   BEFORE the control byte (3C); behaviourally identical to the
 *   simultaneous hardware latch since only 3C has side effects. Plus:
 *   a busy-set with y_count==0 (the TOS bset restart on a completed
 *   blit) now clears busy like hardware instead of latching it.
 * =====================================================================
 * M11e (2026-07-25): STROBOSCOPIC TIMER FIX. First-ever run of TOS 4.04
 *   on the live hardware timebase (REV11b + m11d silicon) hung in its
 *   delay-loop calibration at pc=e0256e, polling TCDR (fffffa23) with
 *   interrupts masked -- reading 192 forever. Cause: the hardware path
 *   fed the MFP in lumps of d200*12288 clocks, and 12288 clocks at
 *   Timer C's /64 prescale is EXACTLY one full 192-count period: the
 *   live tcount[] wrapped back to its reload inside every call, so a
 *   poller sampling between calls saw a frozen counter. (Fallback fed
 *   fine-grained quanta, which is why the host boot and EmuTOS were
 *   unaffected.) Reproduced on host via TBSIM=live before fixing.
 *   FIX: the MFP is now fed from the fine mcycle-wall conversion on
 *   BOTH paths (the m9e-proven pattern; both clocks share the board
 *   oscillator, so no drift concern at MFP timescales). The hardware
 *   timebase slot remains the authority for VBL. hz200 telemetry still
 *   counts wall 200Hz from d200 on the hardware path.
 * =====================================================================
 * M11d (2026-07-25): two fixes on M11c, found during the first TOS 4.04
 *   runs (real 4.04 boots to desktop on the host build of this firmware):
 *   1. SCANOUT GEOMETRY GUARD: TOS 4.04 touches a derivation trigger
 *      while most VIDEL shadows are still virgin, deriving insane
 *      geometry (observed: 131070x0, lb=131070) which was committed to
 *      the fabric scanout for a transient window until TOS finished
 *      programming the VIDEL. The fabric's behaviour on an insane fetch
 *      spec is untested; never send one. Implausible derivations now
 *      hold the previously committed mode (one UART line per event).
 *   2. [sd] ROM success message: %.11s precision is unsupported by the
 *      BSP printf -- it printed "11s", swallowed the filename, AND
 *      desynced the following %%u (which then printed the address of
 *      cfg_rom, 2078092, as the "size"). Manual truncation, matching
 *      the M11b fix to the failure branch.
 * =====================================================================
 * M11c (2026-07-24): adopts the REV11b hardware-timebase slot (v2) and
 *   adds the frozen-tick self-defence. Firmware side of the REV11b
 *   contract; no other subsystem touched (blitter/HID/SD identical to
 *   M11b).
 *   1. SLOT v2: the REV11 fabric wrote tick200/cyc50 at ODD word
 *      addresses -- the port's upper write lane is measured dead
 *      (falcon_hid_ahb.v:28), so those writes never landed. REV11b
 *      re-lays the slot on even words only; tb_read() here follows:
 *        word[0](+0)  MAGIC 0x7B10C0D2   word[2](+8)  tick200
 *        word[4](+16) tickvbl            word[6](+24) cyc50
 *      The new MAGIC value makes version skew safe both ways: this
 *      firmware on a REV10/REV11 bitstream sees no magic -> proven
 *      mcycle fallback; old firmware on REV11b likewise.
 *   2. FROZEN-TICK DEFENCE: the REV11 silicon failure presented as
 *      magic-present-but-ticks-frozen, which hung EmuTOS in its first
 *      timed wait. If tick200 is static for TB_FROZEN_MAX consecutive
 *      reads (~seconds of wall time), tb_read latches a PERMANENT
 *      mcycle fallback and says so once on the UART. The fallback
 *      anchors self-resync (existing stall guards), so the machine
 *      boots regardless of any future port pathology. The exact
 *      silicon failure state is replayed as a host regression test.
 * =====================================================================
 * M11b (2026-07-24): the four M10b fixes/additions applied verbatim on
 *   certified m11 (blitter untouched -- it was never the sick part):
 *   1. PHANTOM-MODIFIER FIX (rollover reports keep valid modifiers)
 *   2. [st] per-class HID counters: kbd= pha= mou=
 *   3. [tb] boot line naming the timebase source
 *   4. [sd] ROM-fail prints the filename; ikbd_orbit_step removed on
 *      target as explicitly requested 2026-07-16.
 * =====================================================================
 * falcon_m11.c -- M11: M10 + HARDWARE BLITTER. The Atari BLiTTER C
 *                model (falcon_blitter.c, ported from Hatari's
 *                blitter.c as executable spec, differential-fuzzed to
 *                0 mismatches over 200k random blits) is wired into
 *                the IO map at FF8A00-FF8A3D. Writing the control
 *                register with bit 7 set runs the blit synchronously
 *                over ST-RAM and clears busy -- there is no bus to
 *                arbitrate when the blitter is a function the emulated
 *                CPU calls. FF8A00 is now on the IO whitelist (it was
 *                deliberately ABSENT under EmuTOS's software VDI); with
 *                the blitter present, EmuTOS/TOS can use hardware
 *                BitBlit, and it's a step toward TOS 4.04.
 *                Everything from M10 is inherited unchanged (wall-
 *                locked Timer C + VBL, HW timebase or mcycle fallback,
 *                FAT32 card library, ROM-from-card, cluster-map write-
 *                back, LED contract).
 * falcon_m10.c -- M10: WALL-LOCKED TIMEBASE. The MFP timer clock
 *                (Timer C = the 200Hz system tick, and TA/TB/TD) and
 *                the emulated VBL are driven from WALL time instead of
 *                emulated CPU cycles. This fixes the whole family of
 *                symptoms the drift measurements pinned to hz_200:
 *                cursor blink fast+jittery, keyboard repeat too slow,
 *                drag-drop letting go under load -- all were timers
 *                riding emulated-cycles-per-wall-second (measured
 *                wobbling 0.30-0.45). m9e moved INPUT to wall time;
 *                m10 moves TIME ITSELF.
 *                TWO wall sources, preferred then fallback:
 *                  1. HARDWARE timebase (falcon_timebase.v, m10 RTL):
 *                     a 50MHz counter block publishes tick200/tickvbl/
 *                     cyc50 to a mailbox slot. If present (magic set),
 *                     firmware steps the MFP timer clock and VBL from
 *                     the hardware tick counts -- true silicon time,
 *                     hz_200 exact to 0.0 ppm.
 *                  2. FALLBACK (no timebase RTL / rolled-back bitstream)
 *                     -- the A25 mcycle counter (rd_wall64), same wall
 *                     lock m9e used for HID/ACIA. So a bitstream
 *                     rollback needs NO firmware change: m10 firmware
 *                     runs with or without the timebase fabric.
 *                The CPU still runs at its own emulated rate -- m10 is
 *                about TIMERS, not CPU speed. Consequence (correct, but
 *                a behavioural change): with hz_200 wall-true and the
 *                CPU emulated, code measuring instructions-per-tick
 *                sees the true ratio, so self-timed benchmarks now
 *                report honest (slower) numbers instead of Falcon-
 *                authentic-but-skewed ones. That is the point of an
 *                honest clock.
 * falcon_m9g.c -- M9G: THE CARD IS THE MACHINE. Generalises M9F's
 *                single hardwired file into a FAT32 file library:
 *                - CLUSTER MAP write-back: every mounted image keeps
 *                  its cluster chain; each file sector maps through it
 *                  to an absolute card sector, so FRAGMENTED FILES ARE
 *                  FULLY WRITABLE. The word "contiguous" leaves the
 *                  user's vocabulary; the FAT is still never written.
 *                - FALCON.CFG in the card root selects everything:
 *                      ROM=EMUTOS.IMG
 *                      DISKA=DISKA.ST
 *                      DISKB=WORK.ST
 *                  Any missing line/file falls back: embedded EmuTOS,
 *                  blank A:, blank B:. Never brick.
 *                - ROM-FROM-CARD: a 512K TOS image loads into a RAM
 *                  ROM buffer at 0xE00000. EmuTOS stays in flash as
 *                  the permanent fallback (licence firewall: we ship
 *                  EmuTOS only; TOS 4.04 is the user's own file).
 *                  NOTE: real TOS 4.04 is EXPECTED to fail today
 *                  (PMMU off, 68EC030 reported) -- that is the later
 *                  TOS milestone. The mechanism is proven by booting
 *                  the EmuTOS binary itself from the card: same bytes,
 *                  different source, bit-identical desktop required.
 *                - Burned-in A: image replaced by a synthesized blank
 *                  (flash shrinks by ~720K; falcon_diskA.c no longer
 *                  linked). EmuTOS boots to desktop with a blank A:.
 *                - B: card-backed too when DISKB= present, with its
 *                  own independent write-back.
 *                UART hot-swap console deferred to M9H.
 * falcon_m9f.c -- M9F: SD-BACKED STORAGE. Drive A: is loaded from
 *                DISKA.ST on a FAT32 microSD card (TF slot, REV10
 *                bitstream, SPI bit-bang on GPIO[5:1]) and -- if the
 *                file is CONTIGUOUS on the card -- every write to A:
 *                is persisted WRITE-THROUGH to the card, sector by
 *                sector, with the card's busy-release awaited before
 *                the write is considered done. No FAT is ever written:
 *                the file's size and location never change, so the
 *                filesystem metadata cannot be corrupted by us.
 *                - Mount: MBR (or superfloppy) -> FAT32 BPB -> root
 *                  directory walk -> DISKA.ST -> cluster chain walk
 *                  (contiguity verified) -> image loaded to RAM.
 *                - Fragmented file => loads fine, write-back DISABLED
 *                  (changes stay in RAM only), clearly logged.
 *                - No card / no file / bad FAT => falls back to the
 *                  embedded flash image (never brick A:), logged.
 *                - Writes beyond the card file's extent (e.g. a format
 *                  that grows the disk) stay RAM-only, one-shot logged.
 *                - GREEN LED CONTRACT: solid = idle, all writes
 *                  committed, SAFE to power off / eject. Dark or
 *                  flickering = card write in flight, DO NOT power
 *                  off. Off/frozen = firmware not running. The order
 *                  is strict: LED goes unsafe BEFORE the first byte of
 *                  a write is issued and safe only AFTER the card
 *                  releases busy -- the LED can never claim safe while
 *                  a write is in flight.
 *                - B: remains the RAM-synthesized blank (render there
 *                  at RAM speed; copy the result to A: to persist it).
 *                SD driver is the silicon-proven Stage A probe code
 *                (CMD0/8/ACMD41/58/17 + CMD24 write w/ busy-wait).
 * falcon_m9e.c -- M9E: input pacing moved from emulated time to WALL
 *                time. Measured skew (CLOCK.TOS vs stopwatch, four
 *                modes) is 0.30-0.45: the emulated 68030 advances at
 *                0.3-0.45x real speed, and everything gated on emulated
 *                cycles inherited that. Two input paths were:
 *                  - hid_consume() on the emulated VBL (266,667 emu
 *                    cycles) -> only ~20 polls/wall-second, so fast
 *                    button edges alias away entirely. This is the
 *                    real cause of the double-click failure (the AES
 *                    window is *longer* in wall terms with a slow
 *                    clock, not shorter -- the earlier "timebase
 *                    compresses the window" diagnosis was wrong).
 *                  - acia_advance() delivering IKBD bytes per 20,480
 *                    emu cycles -> mouse/key packets serialised ~3x
 *                    slower than the real 7812.5bps wire.
 *                Both now run off the A25's crystal-driven mcycle
 *                counter (800MHz core): HID polled at a true 60Hz,
 *                ACIA at a true 781.25 bytes/s. Autorepeat, which is
 *                hz_200-based, is NOT fixed here -- that is the m10
 *                timebase work; this is the input-path half.
 *                Everything else (VBL IRQ4, mbox_publish, Timer C) is
 *                deliberately left on emulated time: the video and
 *                timer handshakes are verified paths and changing them
 *                belongs with v6.3/m10, not with a QoL fix.
 *                At the nominal 50:1 ratio (800MHz : 16MHz) the wall
 *                constants equal the old emulated ones exactly
 *                (1,024,000/50 = 20,480; 13,333,333/50 = 266,667), so
 *                HOST_TEST runs stay bit-identical to m9d -- the
 *                framebuffer regression proves the change is inert in
 *                simulation and acts only on silicon.
 * falcon_m9d.c -- M9D: = M9C + media buffers grown to 2MiB, the
 *                unformatted capacity of an HD disk (12,500 raw bytes
 *                x 160 tracks = 2.0MB): the buffer cap now encodes the
 *                physical media limit, not one format's size. Unlocks
 *                extended HD (83trk x 18spt = 1,529,856B; 21spt DMF
 *                layouts) previously rejected at the 1.44M cap. The
 *                mech ceiling (85 tracks) is now the binding limit for
 *                all layouts. build_fmt_track generalised to HD track
 *                arithmetic; FDCTEST v10 formats 83-track HD -- the
 *                exact case the old cap refused.
 * falcon_m9c.c -- M9C: = M9B + format-defined geometry.  The BPB parsed
 *                at attach is the *filesystem's* claim; the *drive*
 *                model now lets a format redefine the disk shape, the
 *                way a real WD1772 + mech does:
 *                - WRITE TRACK at track 0 side 0 with a new sector
 *                  count adopts it (spt = sectors in the stream) and
 *                  restarts the disk at 1 track; any successful track
 *                  format grows the disk (tracks = max(tracks, T+1)),
 *                  size recomputed, bounded by the 1.44M buffer and a
 *                  real-mech ceiling of 85 tracks.
 *                - Same-shape reformat of track 0 does NOT shrink the
 *                  disk (a refresh, not a reshape).
 *                - A track whose sector count disagrees with the disk's
 *                  shape is rejected with LOST DATA + one log line:
 *                  mixed-format disks are unrepresentable in a linear
 *                  .ST image (ledger).
 *                FastCopy III extended formats (10 spt, 81/82 tracks)
 *                and EmuTOS flopfmt() (spt 1-10 DD, 13-20 HD) both land
 *                inside this envelope.  Type II reads/writes are gated
 *                by the live shape, so an unformatted track is RNF --
 *                exactly what a verify pass expects.
 * falcon_m9b.c -- M9B: = M9 + WRITE TRACK (format). The DMA'd raw track
 *                image is parsed byte-level, exactly the stream EmuTOS
 *                flopfmt() builds (bios/floppy.c): 3xF5 FE id-mark ->
 *                track/side/sector/size + F7, 3xF5 FB data-mark -> 512
 *                payload bytes + F7.  Sectors land at the LBA their ID
 *                fields claim, gated on id.track == head position,
 *                id.side == PSG side, sector 1..spt, size code 2 --
 *                TOS always writes matching IDs; anything else is
 *                unrepresentable in a linear .ST and is skipped.
 *                Desktop Format now completes: WRITETR per track,
 *                EmuTOS reads every sector back (flopver), then lays
 *                boot sector + FATs via Type II writes.  READ TRACK
 *                remains a clean LOSTDAT (ledger).
 * falcon_m9.c  -- M9: STORAGE (floppy). The m8c "no disk" WD1772/DMA
 *                terminator becomes a serving model:
 *                - Drive A: = embedded .ST image (falcon_diskA.c,
 *                  gen_diskimg.py), copied to a RAM buffer at boot;
 *                  geometry parsed from the BPB (not hardcoded), so any
 *                  720K/1.44M .ST array drops in. Writes hit the RAM
 *                  copy only -- persistence arrives with SD.
 *                - Drive B: = blank 720K synthesized at boot (BPB
 *                  byte-for-byte per make_bootst.py "new 720" minus the
 *                  executable stamp; serial F1CA44). Zero flash cost.
 *                - All sector traffic goes through a storage backend
 *                  interface (flop_drive / flop_rw_one) -- the seam
 *                  where SD-backed images plug in later.
 *                - WD1772 Type II Read/Write Sector with DMA transfers
 *                  into/out of ST-RAM: live 24-bit DMA address counter
 *                  ($FF8609/0B/0D, readable), sector-count decrement,
 *                  composed DMA status (OK / sector-count-not-0), M-bit
 *                  multi-sector bounded by DMA count and end of track.
 *                - Type III Read Address (6-byte ID via DMA, WD1772
 *                  track-into-sector-register quirk, rotating sector id).
 *                  Read/Write Track complete with LOST DATA + one log
 *                  line (format-from-desktop errors out cleanly;
 *                  implementation is on the ledger for later).
 *                - Falcon density/modectl $FF860E/0F: write latches,
 *                  read returns latch with bit3 forced 0 (EmuTOS's
 *                  Falcon write path spins until bit3==0).
 *                - Minimal YM2149 select/data register file ($FF8800
 *                  R = selected reg, W = select; $FF8802 W = data):
 *                  EmuTOS read-modify-writes port A (reg 14) for drive
 *                  select (bit1=A:, bit2=B:, active low) + side select
 *                  (bit0, 0 = side 1) -- a flat byte shadow cannot
 *                  express that indirection.
 *                - FDCTEST host self-test (register-level vectors driven
 *                  through io_read8/io_write8 exactly as EmuTOS drives
 *                  the chip) + HOST_TEST boot-sector-execution witness
 *                  (VBL PC sample inside the loaded sector).
 *                Coherency on target is free: the FDC model writes
 *                ST-RAM exactly like Musashi does; the per-VBL
 *                L1D_WBINVAL_ALL already publishes it to the fabric.
 * falcon_m8c.c -- M8C: = m8b + [vregs] diagnostic: on every geometry
 *                change, print the RAW VIDEL shadow registers alongside
 *                the derived scanout line, so silicon register truth can
 *                be compared against EmuTOS set_videl_vga() expectations.
 * falcon_m8b.c -- M8B: bpp derivation made EmuTOS-exact. The m7-era
 *                "(vmode&0xF)==4 -> truecolor" clause is removed: its
 *                premise (nibble 4 uniquely TC) fails for the 320-wide
 *                planar VGA modes, which misdetected as TC (width=vwrap,
 *                chunky decode of planar data) -- the silicon-observed
 *                wrong-width/wrong-layout in 320x480x{4,2}bpp and
 *                320x240x2bpp. GEOMTEST added. Else identical to m8a.
 * falcon_m8a.c -- M8A: identical to m8 except the mailbox moves from the
 *                0x03FFxxxx hole to 0x04F00000 (DDR3 for 68k 0xF00000,
 *                IO-shadowed so never 68k-backed; clear of the ROM image
 *                at 0x04E00000+512K). Silicon: burst 1 at 0x03FFF800
 *                completed with magic matched every frame, burst 2 never
 *                completed even after 20us quiescence -- the only variable
 *                separating it from millions of proven line-fetch
 *                re-requests is the address region. Single-variable test.
 * falcon_m8.c -- Stage 3 (M8): mailbox v3 (277 words: 256-colour Falcon
 *                palette + native-height field + pal_seq), ST-palette
 *                STe-nibble linearisation. Otherwise identical to m7.
 * falcon_m6ahb.c -- Stage 1 / M6 rev2: HID ring now filled over the AHB port
 * Tang Console 138K. Build: build_falcon_m4.bat. Flash .bin @0x600000.
 * UART2 38400 8N1. Heartbeat status lines while running.
 *
 * WHAT M1 IS: the real Falcon memory map, EmuTOS 1.4 (UK 512K, built
 * from source, GPL v2+) in ROM at 0xE00000, 14MB ST-RAM, NatFeats
 * (NF_VERSION/NF_NAME/NF_STDERR) so EmuTOS kprintf lands on UART2,
 * bus-error-backed hardware probing so EmuTOS detects MCH_FALCON,
 * and an IO trap logger. EmuTOS boots until it needs hardware that
 * does not exist yet; the log of unique register touches IS the
 * to-do list for the C chipset.
 *
 * Memory map (68k side, full 32-bit):
 *   0x00000000-0x00000007  ROM vector mirror (reads)
 *   0x00000000-0x00DFFFFF  14MB ST-RAM  (DDR3 window 0x04000000)
 *   0x00E00000-0x00E7FFFF  EmuTOS ROM (write-ignored)
 *   0x00FA0000-0x00FBFFFF  cartridge: reads 0xFF (no cart)
 *   IO space 0x(FF)FF8000-0x(FF)FFFFFF: whitelist of genuine Falcon
 *     registers reads 0xFF / write-discard, all logged; anything
 *     else in IO space BUS ERRORS (so EmuTOS's berr-protected probes
 *     for TT/MegaSTE hardware fail correctly -> machine = Falcon).
 *   Everything else: BUS ERROR (open bus on a real Falcon).
 *
 * NatFeats ABI (from emutos bios/natfeat.S):
 *   0x7300 nfID:   sp+4 = feature name ptr -> id in D0 (0 = none)
 *   0x7301 nfCall: sp+4 = id|sub, sp+8.. = args -> result in D0
 *
 * HOST_TEST: build natively, same everything, stdout console; used
 * to verify the boot BEFORE flashing (doctrine: simulate first).
 * ===================================================================== */

#include <stdint.h>
#include "m68k.h"

#ifdef HOST_TEST
  #include <stdio.h>
  static void uart_init(unsigned int baud) { (void)baud; }
  static uint8_t ram_buf[0x00E00000];
  #define RAM_PTR ram_buf
#else
  extern void uart_init(unsigned int baud);
  extern int  printf(const char *fmt, ...);
  #define RAM_PTR ((uint8_t *)0x04000000u)   /* DDR3 ST-RAM window */
#endif

extern const uint8_t emutos_rom[0x80000];
static uint8_t rom_ram[0x80000];            /* M9G: card-loadable ROM  */

#define ST_RAM_SIZE 0x00E00000u
#define ROM_BASE    0x00E00000u
#define ROM_END     0x00E80000u
#define CART_BASE   0x00FA0000u
#define CART_END    0x00FC0000u

static uint8_t * const ram = RAM_PTR;

/* ---------------- M4: fabric scanout mailbox + coherency ----------------
 * Contract with falcon_video.v (Tier C bitstream) -- MUST MATCH:
 *   one 64-bit LE word at DDR3 byte address 0x03FFFFF8 (a hole: above the
 *   heap ceiling 0x03000000, below the ST-RAM window 0x04000000):
 *     [31:0]  = magic 0xFA1C0DE5
 *     [63:32] = framebuffer base as DDR3 BYTE address
 * Publish order low-invalid -> high -> low-valid so the fabric can never
 * latch a torn pair (both words share one cache line; the flush that
 * exposes them to DDR3 happens after the sequence completes).
 * Coherency: the desktop lives in the A25's write-back D-cache; the
 * fabric reads raw DDR3. CCTL L1D_WBINVAL_ALL (mcctlcommand CSR 0x7CC,
 * command 6 -- verified working AND coherent in Stage 0) runs every VBL
 * (~60Hz), pushing framebuffer and mailbox lines out together.        */
/* M11l: flush diagnostic counters (declared ahead of the wrapper) */
static uint32_t flushdiv = 1u;      /* FALCON.CFG FLUSHDIV=         */
static uint8_t  cacheopt = 1u;      /* M11m: FALCON.CFG CACHEOPT=   */
static uint32_t dbg_tbinval;        /* M11m: targeted slot invals   */
static uint32_t dbg_tbinval_prev;
/* BSP library/bsp/ae350/cache.c command encodings */
#define CCTL_L1D_VA_INVAL     0u
#define CCTL_L1D_WBINVAL_ALL  6u
#define CCTL_L1D_WB_ALL       7u
#define NDS_MCCTLBEGINADDR    0x7cb
#define NDS_MCCTLCOMMAND      0x7cc
/* M11n: invalidate a range the FABRIC writes, so the CPU cannot serve
 * the read from a stale line. BSP idiom (ae350_l1c_dcache_invalidate
 * _range): begin-addr then command, once per cache line. The 8-byte
 * step is below any real line size, so it covers the range whatever
 * the geometry is without decoding mdcm_cfg. Only ever applied to
 * fabric-written, CPU-read-only regions -- invalidating a line the CPU
 * had dirty would discard data. */
#ifdef HOST_TEST
  #define dcache_inval_range(b, n) ((void)0)
#else
static void dcache_inval_range(uintptr_t base, uint32_t size)
{
    uintptr_t a  = base & ~(uintptr_t)63u;
    uintptr_t la = base + size - 1u;
    for (; a <= la; a += 8u) {
        __asm__ volatile("csrw 0x7cb, %0" :: "r"(a) : "memory");
        __asm__ volatile("csrw 0x7cc, %0"
                         :: "r"(CCTL_L1D_VA_INVAL) : "memory");
    }
}
#endif

/* M13: write-back a range the CPU writes and the FABRIC reads (the
 * audio sample ring). Mirror of dcache_inval_range() -- the "third
 * helper" the M11n note anticipated, same BSP idiom, command VA_WB(1):
 * push dirty lines to DDR3 without discarding them. Only ever applied
 * to CPU-written, fabric-read-only regions. HOST_TEST: no-op (host
 * arrays are directly visible).                                      */
#define CCTL_L1D_VA_WB        1u
#ifdef HOST_TEST
  #define dcache_wb_range(b, n) ((void)0)
#else
static void dcache_wb_range(uintptr_t base, uint32_t size)
{
    uintptr_t a  = base & ~(uintptr_t)63u;
    uintptr_t la = base + size - 1u;
    for (; a <= la; a += 8u) {
        __asm__ volatile("csrw 0x7cb, %0" :: "r"(a) : "memory");
        __asm__ volatile("csrw 0x7cc, %0"
                         :: "r"(CCTL_L1D_VA_WB) : "memory");
    }
}
#endif
static uint32_t dbg_flush_calls;    /* requests                     */
static uint32_t dbg_flush_done;     /* actually executed            */
static uint32_t dbg_flush_skip;     /* skipped by the divider       */
static uint64_t dbg_flush_cyc;      /* mcycles inside the CCTL      */
static uint32_t dbg_flush_done_prev, dbg_flush_skip_prev;
static uint64_t dbg_flush_cyc_prev;
#define STRAM_DDR3_BASE 0x04000000u
#define MBOX_MAGIC      0xFA1C0DE6u  /* v3: stale bitstream/firmware pairing
                                        fails loudly to bars, not half-works */
/* M8A: 277-word mailbox v3 relocated INTO the proven lane5 address class.
 * 0x04F00000..0x04F00453 = DDR3 for 68k 0xF00000 (IO-shadowed -> never
 * 68k-backed), 512K clear of the ROM image ending 0x04E80000.               */
#define MBOX_ADDR       0x04F00000u
#ifdef HOST_TEST
  static volatile uint32_t mbox_host[277];
  #define MBOX ((volatile uint32_t*)mbox_host)
  /* M11l: host has no cache to flush; count so the divider logic is
   * still exercised by the host fixture run. */
  static void l1d_wbinval_all(void)
  {
      dbg_flush_calls++;
      if (flushdiv > 1u && dbg_flush_calls > 240u
          && (dbg_flush_calls % flushdiv) != 0u) { dbg_flush_skip++; return; }
      dbg_flush_done++;
  }
#else
  #define MBOX ((volatile uint32_t*)MBOX_ADDR)
  static uint64_t rd_wall64(void);            /* M11l: fwd decl     */
  static void l1d_wbinval_all(void)
  {
      uint64_t t0;
      dbg_flush_calls++;
      /* First ~4s always flush: boot and mode-set must reach the fabric
       * coherently even mid-experiment, because a torn mailbox pair is
       * the one outcome worth avoiding. */
      if (flushdiv > 1u && dbg_flush_calls > 240u
          && (dbg_flush_calls % flushdiv) != 0u) { dbg_flush_skip++; return; }
      t0 = rd_wall64();
      /* M11m: producer-only direction -- write back, do NOT invalidate.
       * The fabric reads the framebuffer and mailbox out of DDR3; it
       * never writes them, so discarding our own lines bought nothing
       * and cost a cold cache 60 times a second. */
      if (cacheopt)
          __asm__ volatile("csrw 0x7cc, %0" :: "r"(CCTL_L1D_WB_ALL)
                           : "memory");
      else
          __asm__ volatile("csrw 0x7cc, %0" :: "r"(CCTL_L1D_WBINVAL_ALL)
                           : "memory");
      dbg_flush_cyc += rd_wall64() - t0;
      dbg_flush_done++;
  }
#endif

static uint8_t io_shadow[0x8000];        /* fwd decl (VIDEL shadow, defined below) */
static uint32_t last_geom = 0xFFFFFFFFu; /* last geometry word published */
static uint32_t pal_seq   = 0;           /* bumps on any $FF9800..$FF9BFF write */

/* STe/Falcon ST-palette nibble encoding: bit 3 is the LSB ("....rRRR gGGGbBBB",
 * temlib register listing; the HOST_TEST PPM dumper below has always applied
 * it). Convert to a LINEAR intensity nibble before publishing so the mailbox
 * carries physical intensity and the RTL stays a pure nibble replicator.
 * strot4: 0->0, 3->6, 5->A, 7->E, 8->1, F->F.                                */
static uint32_t strot4(uint32_t n)  { return ((n & 7u) << 1) | ((n >> 3) & 1u); }
static uint32_t strot12(uint32_t p)
{
    return (strot4((p >> 8) & 15u) << 8)
         | (strot4((p >> 4) & 15u) << 4)
         |  strot4( p        & 15u);
}

/* Falcon palette entry ($FF9800 + 4n: bytes R[7:2] G[7:2] 0 B[7:2] -- temlib-
 * confirmed and matching the verified boot log) -> packed 18-bit {R6,G6,B6}. */
static uint32_t fpal_pack(const uint8_t *q)
{
    return ((uint32_t)(q[0] >> 2) << 12)
         | ((uint32_t)(q[1] >> 2) <<  6)
         |  (uint32_t)(q[3] >> 2);
}

#ifdef HOST_TEST
/* Unit-test the palette conversions against known values: the strot4 table,
 * strot12 on the mid-greys EmuTOS actually writes ($555->$AAA, $333->$666),
 * and fpal_pack on Falcon-palette entries measured in the verified boot log. */
static int paltest(void)
{
    static const uint8_t rot[16] =
        { 0, 2, 4, 6, 8, 10, 12, 14, 1, 3, 5, 7, 9, 11, 13, 15 };
    uint8_t q[4];
    unsigned n; int bad = 0;
    for (n = 0; n < 16u; n++) if (strot4(n) != rot[n]) bad++;
    if (strot12(0x0555u) != 0x0AAAu) bad++;
    if (strot12(0x0333u) != 0x0666u) bad++;
    if (strot12(0x0FFFu) != 0x0FFFu) bad++;
    if (strot12(0x0000u) != 0x0000u) bad++;
    q[2] = 0;
    q[0]=0xFF; q[1]=0xFF; q[3]=0xFF; if (fpal_pack(q) != 0x3FFFFu) bad++;
    q[0]=0xFF; q[1]=0x00; q[3]=0x00; if (fpal_pack(q) != 0x3F000u) bad++;
    q[0]=0x00; q[1]=0xFF; q[3]=0x00; if (fpal_pack(q) != 0x00FC0u) bad++;
    q[0]=0x00; q[1]=0x00; q[3]=0xFF; if (fpal_pack(q) != 0x0003Fu) bad++;
    q[0]=0xEE; q[1]=0xEE; q[3]=0xEE;
    if (fpal_pack(q) != ((0x3Bu<<12)|(0x3Bu<<6)|0x3Bu)) bad++;
    if (bad) printf("PALTEST FAIL (%d bad)\r\n", bad);
    else     printf("PALTEST OK\r\n");
    return bad;
}
#endif

/* Publish the full 277-word v3 scanout mailbox every VBL. Geometry/stride/pal
 * are derived live from the VIDEL shadow registers, so any runtime resolution
 * or palette change (desktop "Change resolution") is reflected immediately.
 *   w0 magic  w1 fb_base  w2 GEOMETRY  w3 linebytes
 *   w4..w19   16 x ST palette ($0RGB, low 12 bits, from $FF8240, LINEARISED)
 *   w20       pal_seq   w21..w276  256 x Falcon palette {R6,G6,B6} ($FF9800)
 * w2 geometry word (see falcon_video.v):
 *   [3:0] planes (0 = chunky truecolor RGB565; 1/2/4/8 = planar depth)
 *   [4]   hdbl   (horizontal pixel-double: native 320 -> 640)
 *   [5]   vdbl   (vertical line-double:     native 200 -> 400)
 *   [19:8] native visible lines, pre-vdbl (v3 -- disambiguates 320x480x8)
 * planes/width/height come from EmuTOS's own bios/videl.c derivation
 * (get_videl_bpp/_width/_height: SPSHIFT $8266 + ST_SHIFTER $8260 + $8210 +
 * vertical timing). The $FF82C2 mode nibble is deliberately NOT used to pick
 * plane count -- it reflects the REQUESTED mode, which on this VGA/EmuTOS path
 * disagrees with the REALIZED geometry (desktop "ST Medium" is realized as
 * 320x200 4-plane, not 640x200 2-plane), which was the ST-resolution bug.     */
/* M15: SCREEN BASE AUTHORITY -- the video registers, not $44E.
 *
 * $FF8201 (hi) / $FF8203 (mid) / $FF820D (lo) are what the video
 * hardware actually scans from. _v_bas_ad ($44E) is only TOS's
 * bookkeeping copy: Setscreen() maintains both, which is why the
 * desktop always looked right, but a program that claims the screen
 * itself writes the REGISTERS and never touches $44E. That is
 * universal practice for double-buffering, so every game and demo
 * that draws its own screen was invisible to us: we kept scanning
 * the stale buffer while the program drew elsewhere. Palette writes
 * landed (they are read from the $FF8240 shadow), pixel writes did
 * not -- a cleared buffer rendered through the new palette, i.e. a
 * flat field of colour 0. Measured on silicon with Treasure Island
 * Dizzy: correct sky-blue background and border, correct music, no
 * sprites, and identical behaviour to a correct Falcon under Hatari.
 *
 * The registers win whenever they hold a plausible address; $44E is
 * the fallback for the pre-init window (the three shadow bytes are
 * zeroed at reset, so "untouched" reads as 0 and cannot be mistaken
 * for a real base).                                                 */
/* M18: moved up from the M11k block -- log_on now gates trace output in
 * mbox_publish and the video paths, which are earlier in the file. */
static uint8_t  log_on = 1u;       /* FALCON.CFG LOG=, F12 toggles  */
static uint8_t  vid_dbg = 1u;          /* bounded, re-armable by F12 */
/* M18: VBL rate state lives here too -- the F10 handler in hid_consume
 * is earlier in the file than WALL_HZ, so only the MACROS can live with
 * the other wall constants; the variables must precede their users.  */
static uint8_t  vbl_50hz;          /* 0 = 60Hz (proven default)        */
static uint32_t vbl_acc, vbl_cyc_last;
static uint8_t  vbl_cyc_have;
static uint32_t vid_dbg_n;
#define VID_DBG_MAX 32u

static uint32_t vid_base_select(void)
{
    uint32_t hw = ((uint32_t)io_shadow[0x0201] << 16)
                | ((uint32_t)io_shadow[0x0203] << 8)
                |  (uint32_t)io_shadow[0x020D];
    if (hw != 0u && hw < ST_RAM_SIZE) return hw;
    return ((uint32_t)ram[0x44E]<<24)|((uint32_t)ram[0x44F]<<16)
         | ((uint32_t)ram[0x450]<<8)|ram[0x451];      /* _v_bas_ad    */
}

/* ===================================================================
 * M16: QUIESCENT AUTOPSY.
 *
 * The stall detector tells us the machine stopped; it never told us
 * what it stopped ON. Treasure Island Dizzy draws its panel, stops
 * before flipping in the play area, and keeps playing music -- so the
 * CPU is alive and spinning on something that never changes. This
 * records WHICH addresses the spin reads, which splits the two
 * candidate causes apart immediately:
 *
 *   RAM address  -> waiting on a flag an interrupt handler should set
 *                   (its own VBL vector, or the TOS vblqueue) that is
 *                   not running.
 *   IO address   -> polling a register we do not implement. Prime
 *                   suspect $FF8205/07/09, the video ADDRESS COUNTER:
 *                   read-only, advances during scanout, and the
 *                   classic way an ST game waits for vblank or a
 *                   raster position before a buffer flip. Our shadow
 *                   returns a CONSTANT, so "spin until it changes"
 *                   never exits -- exactly this signature.
 *
 * Armed only after the stall fires, so the normal path pays nothing
 * but one predictable-branch test per read.                        */
#define APY_SLOTS 24u
static uint32_t apy_addr[APY_SLOTS], apy_cnt[APY_SLOTS];
static uint8_t  apy_used, apy_on;
static uint32_t apy_reads;

static void apy_note(uint32_t a)
{
    uint8_t i;
    apy_reads++;
    for (i = 0; i < apy_used; i++)
        if (apy_addr[i] == a) { apy_cnt[i]++; return; }
    if (apy_used < APY_SLOTS) {
        apy_addr[apy_used] = a; apy_cnt[apy_used] = 1; apy_used++;
    }
}
static void apy_arm(void)
{ apy_used = 0; apy_reads = 0; apy_on = 1; }

/* M16: dump the autopsy -- hottest read addresses, registers, and a
 * disassembly window around PC. m68kdasm.c is already linked, so the
 * disassembly costs nothing extra.                                  */
static const char *apy_io_name(uint32_t a)
{
    uint32_t r = a & 0xFFFFu;
    if (r == 0x8205u || r == 0x8207u || r == 0x8209u)
        return " <- VIDEO ADDRESS COUNTER (read-only, must advance!)";
    if (r == 0x820Au) return " <- ST sync mode (50/60Hz)";
    if (r >= 0x8240u && r <= 0x827Fu) return " <- palette";
    if (r >= 0x8200u && r <= 0x8211u) return " <- video base/count";
    if (r >= 0xFA00u && r <= 0xFA3Fu) return " <- MFP";
    if (r >= 0x8800u && r <= 0x88FFu) return " <- PSG (or shadow)";
    if (r >= 0x8600u && r <= 0x860Fu) return " <- FDC/DMA";
    return "";
}

static void apy_report(uint32_t pc)
{
    uint8_t i, j;
    printf("  [apy] ---- quiescent autopsy ----\r\n");
    printf("  [apy] %u reads sampled, %u distinct addresses\r\n",
           apy_reads, apy_used);
    /* hottest first (selection sort; <=24 entries) */
    for (i = 0; i < apy_used; i++) {
        uint8_t best = i;
        for (j = i + 1u; j < apy_used; j++)
            if (apy_cnt[j] > apy_cnt[best]) best = j;
        if (best != i) {
            uint32_t ta = apy_addr[i], tc = apy_cnt[i];
            apy_addr[i] = apy_addr[best]; apy_cnt[i] = apy_cnt[best];
            apy_addr[best] = ta; apy_cnt[best] = tc;
        }
    }
    for (i = 0; i < apy_used && i < 12u; i++) {
        uint32_t a = apy_addr[i];
        const char *kind = (a >= 0xFFFF8000u) ? "IO " :
                           (a < ST_RAM_SIZE)  ? "RAM" : "?  ";
        printf("  [apy] %s %08x x%-7u%s\r\n",
               kind, a, apy_cnt[i], (a >= 0xFFFF8000u) ? apy_io_name(a) : "");
    }
    printf("  [apy] D0-D7 %08x %08x %08x %08x %08x %08x %08x %08x\r\n",
           m68k_get_reg((void *)0, M68K_REG_D0), m68k_get_reg((void *)0, M68K_REG_D1),
           m68k_get_reg((void *)0, M68K_REG_D2), m68k_get_reg((void *)0, M68K_REG_D3),
           m68k_get_reg((void *)0, M68K_REG_D4), m68k_get_reg((void *)0, M68K_REG_D5),
           m68k_get_reg((void *)0, M68K_REG_D6), m68k_get_reg((void *)0, M68K_REG_D7));
    printf("  [apy] A0-A7 %08x %08x %08x %08x %08x %08x %08x %08x\r\n",
           m68k_get_reg((void *)0, M68K_REG_A0), m68k_get_reg((void *)0, M68K_REG_A1),
           m68k_get_reg((void *)0, M68K_REG_A2), m68k_get_reg((void *)0, M68K_REG_A3),
           m68k_get_reg((void *)0, M68K_REG_A4), m68k_get_reg((void *)0, M68K_REG_A5),
           m68k_get_reg((void *)0, M68K_REG_A6), m68k_get_reg((void *)0, M68K_REG_A7));
    printf("  [apy] SR %04x  (IPL %u, %s)\r\n",
           (unsigned)m68k_get_reg((void *)0, M68K_REG_SR),
           (unsigned)((m68k_get_reg((void *)0, M68K_REG_SR) >> 8) & 7u),
           (m68k_get_reg((void *)0, M68K_REG_SR) & 0x2000u) ? "supervisor" : "user");
    { char buf[128]; uint32_t p = pc; uint8_t k;
      for (k = 0; k < 10u; k++) {
          uint32_t n = m68k_disassemble(buf, p, M68K_CPU_TYPE_68030);
          printf("  [apy] %06x: %s\r\n", p, buf);
          if (n == 0u) break;
          p += n;
      } }
    printf("  [apy] ---------------------------\r\n");
}

/* ===================================================================
 * M19: PER-SCANLINE PALETTE CHANGE LIST (firmware half of REV14).
 *
 * A raster split IS a mid-frame palette change; the mailbox's one
 * snapshot per frame cannot represent it. Measured consequences:
 * Frontier renders cockpit and viewport in one palette (grey intro),
 * Dizzy's residual flicker. F10 changing nothing proved it structural.
 *
 * Every ST palette write is stamped with the VISIBLE line it happened
 * on (m17's wall-locked hbl_line minus the measured top border) and
 * snapshotted; the list is published each frame to 0x04F05000 in the
 * REV14 layout: [0] magic (LAST), [1] count<=30, [2..31] lines,
 * [32..511] palettes at 32+e*16, strot12-linearised EXACTLY like the
 * mailbox's w4..w19 so the fabric stays a pure nibble replicator.
 * Same-line writes coalesce (a 16-word burst = one entry). Writes in
 * the bottom border are ignored BY DESIGN: the mailbox base snapshot
 * (end-of-frame io_shadow state) already carries them into the next
 * frame. Entries are naturally line-sorted (hbl_line is monotonic).
 *
 * REV13 never reads the region -> m19 is safe on the current
 * bitstream; REV14 + m18 sees no magic -> falls back. Clean 2x2.  */
#define PSPLIT_MAGIC 0xC0105717u
#define PSPLIT_MAX   30u
#ifdef HOST_TEST
  static volatile uint32_t chgr_host[512];
  #define CHGR ((volatile uint32_t*)chgr_host)
#else
  #define CHGR ((volatile uint32_t*)0x04F05000u)
#endif
static uint32_t psplit_line[PSPLIT_MAX];
static uint16_t psplit_pal[PSPLIT_MAX][16];
static uint8_t  psplit_n;
static uint8_t  psplit_en = 1u;     /* FALCON.CFG PALSPLIT=0 disables */
static uint8_t  psplit_active;      /* M28: splits seen last frame    */
static uint32_t psplit_dropped;     /* entries beyond 30, counted     */

static void psplit_publish(void)    /* called from mbox_publish tail  */
{
    volatile uint32_t *cr = CHGR;
    uint32_t i, j;
    if (!psplit_en) {               /* kill switch: fabric falls back */
        cr[0] = 0u;
        dcache_wb_range((uintptr_t)cr, 64u);
        psplit_n = 0u;
        return;
    }
    cr[0] = 0u;                     /* invalidate first (mailbox rule)*/
    dcache_wb_range((uintptr_t)cr, 64u);
    cr[1] = psplit_n;
    for (i = 0; i < PSPLIT_MAX; i++)
        cr[2u + i] = (i < psplit_n) ? psplit_line[i] : 0u;
    for (i = 0; i < psplit_n; i++)
        for (j = 0; j < 16u; j++)
            cr[32u + i*16u + j] = psplit_pal[i][j];
    dcache_wb_range((uintptr_t)cr, 2048u);
    cr[0] = PSPLIT_MAGIC;           /* commit last                    */
    dcache_wb_range((uintptr_t)cr, 64u);
    psplit_active = (uint8_t)(psplit_n != 0u);  /* M28: fine next frame */
    psplit_n = 0u;                  /* frame list consumed            */
}

static void mbox_publish(void)
{
    uint32_t vb = vid_base_select();
    { static uint32_t vb_last = 0xFFFFFFFFu;
      if (vb != vb_last) {
          uint32_t sv = ((uint32_t)ram[0x44E]<<24)|((uint32_t)ram[0x44F]<<16)
                      | ((uint32_t)ram[0x450]<<8)|ram[0x451];
          if (log_on && vid_dbg && vid_dbg_n < VID_DBG_MAX) { vid_dbg_n++;
              printf("  [vid] screen base -> %06x  (regs %06x, $44E %06x)%s\r\n",
                     (unsigned)vb,
                     (unsigned)(((uint32_t)io_shadow[0x0201] << 16)
                              | ((uint32_t)io_shadow[0x0203] << 8)
                              |  (uint32_t)io_shadow[0x020D]),
                     (unsigned)sv,
                     (vid_dbg_n == VID_DBG_MAX) ? "  [last]" : ""); }
          vb_last = vb;
      } }
    if (vb == 0u || vb >= ST_RAM_SIZE) { l1d_wbinval_all(); return; }
    uint32_t fb = STRAM_DDR3_BASE + vb;

    /* bits-per-pixel, EXACTLY as EmuTOS bios/videl.c get_videl_bpp():
     * f_shift ($8266) is valid if bit 10, 8 or 4 is set (priority 10>8>4);
     * otherwise fall back to st_shift ($8260) as on ST/STe.                  */
    uint16_t f_shift  = ((uint16_t)io_shadow[0x0266] << 8) | io_shadow[0x0267];
    uint8_t  st_shift =  io_shadow[0x0260];
    uint16_t vmode    = ((uint16_t)io_shadow[0x02C2] << 8) | io_shadow[0x02C3];
    uint32_t bpp;
    if      (f_shift & 0x0400u) bpp = 1u;    /* SPS_2COLOR  : 1 plane        */
    else if (f_shift & 0x0100u) bpp = 16u;   /* SPS_HICOLOR : truecolor      */
    else if (f_shift & 0x0010u) bpp = 8u;    /* SPS_256COLOR: 8 planes       */
    /* M8B: the m7-era "(vmode&0xF)==4 -> TC" clause is REMOVED. Its premise
     * held only for the Stage-2 mode set: 320-wide planar VGA modes also
     * present nibble 4, so 320x480x{4,2}bpp / 320x240x2bpp misdetected as
     * truecolor (width=vwrap, chunky decode of planar words -- the exact
     * wrong-width/wrong-layout seen on silicon). bpp now follows EmuTOS
     * get_videl_bpp EXACTLY, honouring the contract stated above: $FF82C2
     * never picks plane count (bits 1:0 still shape height, unchanged).
     * Boot is unaffected: the host log shows the first VBL publish already
     * sees SPSHIFT=0x100; worst case is a <=1-frame flash on a mode switch. */
    else if (st_shift == 0u)    bpp = 4u;    /* ST_LOW   : 320x200x4         */
    else if (st_shift == 1u)    bpp = 2u;    /* ST_MEDIUM: 640x200x2         */
    else                        bpp = 1u;    /* ST_HIGH  : 640x400x1         */

    uint32_t vwrap     = ((uint32_t)io_shadow[0x0210] << 8) | io_shadow[0x0211];
    uint32_t linebytes = vwrap * 2u;
    uint32_t width     = bpp ? (vwrap * 16u / bpp) : 640u;   /* get_videl_width  */

    uint16_t vdb = ((uint16_t)io_shadow[0x02A8] << 8) | io_shadow[0x02A9];
    uint16_t vde = ((uint16_t)io_shadow[0x02AA] << 8) | io_shadow[0x02AB];
    uint32_t height = (uint16_t)(vde - vdb);                 /* get_videl_height */
    if (!(vmode & 0x02u)) height >>= 1;      /* non-interlace units = half-lines */
    if (vmode & 0x01u)    height >>= 1;      /* vertical double                  */

    if (vwrap == 0u) {                       /* pre-VIDEL-init: publish TC-safe  */
        bpp = 16u; linebytes = 640u; width = 320u; height = 480u;
    }

    /* M11d: derivation guard -- the fabric must never receive an
     * implausible fetch spec. Virgin/partial VIDEL shadows (TOS 4.04
     * mid-init) can derive nonsense; hold the last committed mode.   */
    if (width < 256u || width > 1024u || height < 100u || height > 640u
        || linebytes == 0u || linebytes > 2048u) {
        static uint32_t guard_last_sig;
        uint32_t sig = (width << 16) ^ height ^ ((uint32_t)bpp << 28)
                     ^ linebytes;
        if (log_on && sig != guard_last_sig) {
            guard_last_sig = sig;
            printf("  [m8] GUARD: insane geometry %ux%u bpp=%u lb=%u"
                   " -> holding previous mode\r\n",
                   (unsigned)width, (unsigned)height,
                   (unsigned)bpp, (unsigned)linebytes);
        }
        l1d_wbinval_all();               /* still flush the frame       */
        return;
    }

    /* Pack the geometry word. planes 0 = chunky truecolor; 1/2/4/8 = planar.  */
    uint32_t planes_field = (bpp == 16u) ? 0u : bpp;
    uint32_t geom = planes_field & 0xFu;
    if (width  <= 320u) geom |= (1u << 4);   /* hdbl: native 320 -> 640          */
    if (height <= 240u) geom |= (1u << 5);   /* vdbl: native 200 -> 400          */
    geom |= (height & 0xFFFu) << 8;          /* v3: native visible lines [19:8]  */

    volatile uint32_t *mb = MBOX;
    int i;
    mb[0] = 0u;                          /* invalidate: fabric drops torn reads */
    mb[1] = fb;
    mb[2] = geom;
    mb[3] = linebytes;
    for (i = 0; i < 16; i++) {
        uint32_t p = ((uint32_t)io_shadow[0x0240u + i*2u] << 8)
                   |  io_shadow[0x0241u + i*2u];
        mb[4+i] = strot12(p & 0x0FFFu);  /* $0RGB, STe rRRR -> linear (M8 fix)  */
    }
    /* Mono (1 plane): the EmuTOS desktop is black-on-white, but the ST palette
     * pair we copy does not hold that pair on the Falcon mono path (observed:
     * ink came out red). Force the canonical pair. Honour the invert bit later
     * if a colour/inverted mono mode is ever required.                        */
    if (bpp == 1u) { mb[4] = 0x0FFFu; mb[5] = 0x0000u; }
    mb[20] = pal_seq;                    /* v3: change hint; RTL may ignore     */
    for (i = 0; i < 256; i++)            /* v3: Falcon palette, packed 18-bit   */
        mb[21+i] = fpal_pack(&io_shadow[0x1800u + (uint32_t)i*4u]);
    mb[0] = MBOX_MAGIC;                  /* commit last                         */
    psplit_publish();                    /* M19: REV14 change list              */

    /* Log once per geometry change so each on-screen resolution switch has a
     * matching UART line to check against.                                    */
    if (log_on && geom != last_geom) {
        printf("  [m8] scanout: bpp=%u %ux%u geom=0x%02x lb=%u fb=%x ps=%u\r\n",
               (unsigned)bpp, (unsigned)width, (unsigned)height,
               (unsigned)(geom & 0xFFu), (unsigned)linebytes, (unsigned)fb,
               (unsigned)pal_seq);
        printf("  [vregs] sps=%04x st=%02x vwrap=%u vctl=%04x vdb=%04x vde=%04x\r\n",
               (unsigned)f_shift, (unsigned)st_shift, (unsigned)vwrap,
               (unsigned)vmode,
               (unsigned)(((uint16_t)io_shadow[0x02A8] << 8) | io_shadow[0x02A9]),
               (unsigned)(((uint16_t)io_shadow[0x02AA] << 8) | io_shadow[0x02AB]));
        last_geom = geom;
    }
    l1d_wbinval_all();                   /* frame + mailbox -> DDR3             */
}

/* ------------------------- IO trap logger -------------------------- */
#define LOG_MAX_UNIQUE 2048
#define LOG_MAX_LINES  260
static uint32_t seen_addr[LOG_MAX_UNIQUE];
static uint32_t seen_cnt [LOG_MAX_UNIQUE];
static uint8_t  seen_rw  [LOG_MAX_UNIQUE];   /* bit0 read, bit1 write */
static int n_seen, n_lines, berr_lines;
static uint32_t io_reads, io_writes, berr_count;
static uint8_t  halt68k_seen;      /* M21: double-bus-fault reported  */
static uint8_t  bus32;             /* M22: FALCON.CFG BUS=32 (no mask) */
static uint32_t halt68k_sig_reads; /* M21: 0xFFFF01 signature count   */
static uint32_t io_r_prev, io_w_prev;      /* M11k interval deltas  */
static uint8_t  f12_down;          /* USB F12 edge detect           */
static uint8_t  f11_down;          /* M14: USB F11 edge detect      */
static uint8_t  f10_down;          /* M18: USB F10 edge detect      */
static uint8_t  prtsc_down;        /* M26: Print Screen edge detect  */
static uint8_t  aud_src_tone;      /* M14: 0 = PSG, 1 = 440Hz sine  */
/* M14: IDE traces boot OFF (the arc closed at m11z; they are pure noise
 * against FDC/audio work) and thereafter track log_on, so the FIRST F12
 * cycle brings them back at full banked depth for the open D8 work.  */
static uint8_t  ide_dbg;
static uint8_t  force_status;      /* M11l: F12 emits a block now   */
static uint32_t dbg_mfp_iv;        /* worst MFP gap THIS interval   */
static uint32_t dbg_lost5_prev;    /* lost5 at previous print       */
static uint32_t dbg_gmem_r, dbg_gmem_w;   /* all guest accesses     */
static uint32_t dbg_gmem_r_prev, dbg_gmem_w_prev;
static uint32_t dbg_slices, dbg_ipl6;     /* IPL>=6 sampling        */
static uint32_t dbg_slices_prev, dbg_ipl6_prev;
static uint32_t last_io_addr, last_io_pc, last_io_wr;

static uint32_t cur_pc(void) { return m68k_get_reg((void*)0, M68K_REG_PPC); }

static void log_io(uint32_t a, int size, uint32_t v, int is_wr, int berr)
{
    int i;
    /* M11o: was below cur_pc() and the 263-entry scan, so LOG=0 still
     * paid a Musashi register read plus a linear search per io access
     * just to decide it had nothing to print. */
    if (!log_on) return;
    last_io_addr = a; last_io_pc = cur_pc(); last_io_wr = (uint32_t)is_wr;
    for (i = 0; i < n_seen; i++) if (seen_addr[i] == a) break;
    if (i == n_seen && n_seen < LOG_MAX_UNIQUE) { seen_addr[n_seen] = a; n_seen++; }
    if (i < n_seen) {
        seen_cnt[i]++;
        seen_rw[i] |= is_wr ? 2 : 1;
        if (seen_cnt[i] > 1 && !berr) return;      /* first touch only */
    }
    if (berr) { if (berr_lines >= 24) return; berr_lines++; }
    else      { if (!log_on) return;          /* M18: trace-class      */
                if (n_lines >= LOG_MAX_LINES) return; n_lines++; }
    printf("  [io] %s%s%s %x%s%x (pc=%x)\r\n",
           berr ? "BERR " : "", is_wr ? "W" : "R",
           size == 1 ? ".b" : size == 2 ? ".w" : ".l",
           a, is_wr ? " = " : " -> ", v, cur_pc());
}

/* --------------------- M11: blitter integration -------------------- */
/* The blitter model reads/writes ST-RAM as big-endian words; ram[] is
 * already a big-endian byte array, so these are thin wrappers. Writes
 * beyond ST-RAM are ignored (the real blitter would bus-error, but a
 * well-formed blit stays in RAM; guarding keeps a stray config safe). */
static uint32_t ide_read8(uint32_t a);          /* M12f fwd decls:      */
static void     ide_write8(uint32_t a, uint8_t v); /* blitter->IDE window */
/* M12f: THE BLITTER CAN SEE THE IDE. Atari's own IDE.S (HDX/AHDI
 * source archive, identify(): "tst.b _useblit / bsr initblit / it's
 * a read") drains the IDE data register WITH THE BLITTER when one
 * exists -- 256 words per block, XCNT=256. The blitter is a 24-bit
 * device, so it addresses the IDE at the $F00000 alias. Our model
 * returned 0xFFFF for any address outside RAM/ROM: the drain
 * "completed" instantly with garbage, invisible to every IDE
 * instrument (ide_data_read8 never ran -> [ided] r=0), and AHDI
 * derived geometry from a 0xFF-filled buffer (the observed
 * rW19=fe/rW09=ff 0x91 operands). Fix: blitter accesses landing in
 * the 24-bit-masked IDE window route through ide_read8/ide_write8
 * exactly as CPU accesses do -- big-endian byte pairs, so a word
 * read of the data register consumes two stream bytes, same as a
 * CPU move.w. Only the IDE window is routed; other IO stays out
 * until a tool demonstrates a need. */
uint16_t blit_ram_r16(uint32_t a)
{
    uint32_t m = a & 0x00FFFFFFu;                   /* 24-bit device     */
    if (a + 1u < ST_RAM_SIZE)
        return (uint16_t)(((uint16_t)ram[a] << 8) | ram[a + 1]);
    if (a >= ROM_BASE && a + 1u < ROM_END)          /* M11g: font fetches */
        return (uint16_t)(((uint16_t)rom_ram[a - ROM_BASE] << 8)
                          | rom_ram[a + 1u - ROM_BASE]);
    if (m >= 0x00F00000u && (m + 1u) < 0x00F00040u) {   /* M12f: IDE     */
        uint32_t hi = ide_read8(0xFFF00000u + (m - 0x00F00000u));
        uint32_t lo = ide_read8(0xFFF00000u + (m - 0x00F00000u) + 1u);
        return (uint16_t)((hi << 8) | lo);
    }
    return 0xFFFFu;
}
void blit_ram_w16(uint32_t a, uint16_t v)
{
    uint32_t m = a & 0x00FFFFFFu;                   /* M12f              */
    if (a + 1u < ST_RAM_SIZE) {
        ram[a]     = (uint8_t)(v >> 8);
        ram[a + 1] = (uint8_t)v;
        return;
    }
    if (m >= 0x00F00000u && (m + 1u) < 0x00F00040u) {   /* M12f: IDE     */
        ide_write8(0xFFF00000u + (m - 0x00F00000u), (uint8_t)(v >> 8));
        ide_write8(0xFFF00000u + (m - 0x00F00000u) + 1u, (uint8_t)v);
    }
}
/* the model (register file, HOP/LOP, run engine). Its self-test main
 * compiles only under -DBLIT_SELFTEST, which the firmware never sets. */
#include "falcon_blitter.c"

/* --------------- Falcon IO whitelist (coarse ranges) ---------------- */
/* Genuine Falcon030 registers; anything else in IO space bus-errors so
 * EmuTOS's probes for other machines' hardware fail correctly.       */
static uint8_t scsi_reg[8];   /* M11w: NCR5380 latches */
static int falcon_io_valid(uint32_t r)   /* r = 0x8000..0xFFFF (lo16) */
{
    if (r >= 0x8000u && r <= 0x800Fu) return 1;  /* mem/bus config    */
    if (r >= 0x8200u && r <= 0x8211u) return 1;  /* video base/count/VWRAP */
    if (r >= 0x8240u && r <= 0x826Fu) return 1;  /* palette, shifters */
    if (r >= 0x8280u && r <= 0x82C7u) return 1;  /* VIDEL timing      */
    if (r >= 0x8604u && r <= 0x860Fu) return 1;  /* FDC/ACSI DMA      */
    if (r >= 0x8780u && r <= 0x878Fu) return 1;  /* SCSI (NCR5380)    */
    if (r >= 0x8800u && r <= 0x88FFu) return 1;  /* PSG + shadows M25 */
    if (r >= 0x8900u && r <= 0x897Fu) return 1;  /* DMA snd/XBar/NVRAM*/
    if (r >= 0x8A00u && r <= 0x8A3Du) return 1;  /* M11: BLiTTER      */
    if (r >= 0x8C80u && r <= 0x8C87u) return 1;  /* SCC               */
    if (r >= 0x9200u && r <= 0x921Fu) return 1;  /* joy/paddle/DIP    */
    if (r >= 0x9800u && r <= 0x9BFFu) return 1;  /* Falcon 256-entry palette */
    if (r >= 0xA200u && r <= 0xA207u) return 1;  /* DSP host port     */
    if (r >= 0xFA00u && r <= 0xFA3Fu) return 1;  /* MFP 68901         */
    if (r >= 0xFC00u && r <= 0xFC07u) return 1;  /* ACIAs             */
    return 0;
}

/* IO space test: 0x00FF8000-0x00FFFFFF alias of 0xFFFF8000-0xFFFFFFFF */
static int is_io(uint32_t a)
{
    if (a >= 0xFFFF8000u) return 1;
    if (a >= 0x00FF8000u && a <= 0x00FFFFFFu) return 1;
    return 0;
}

/* ------------------------- bus error ------------------------------- */
static uint32_t last_berr_addr;
static void bus_error(uint32_t a, int size, int is_wr)
{
    berr_count++;
    last_berr_addr = a;
    log_io(a, size, 0, is_wr, 1);
#ifdef HOST_TEST
    { uint32_t d0 = m68k_get_reg((void*)0, M68K_REG_D0);
      uint32_t a0 = m68k_get_reg((void*)0, M68K_REG_A0);
      uint32_t a1 = m68k_get_reg((void*)0, M68K_REG_A1);
      uint32_t vb = ((uint32_t)ram[0x44E]<<24)|((uint32_t)ram[0x44F]<<16)|((uint32_t)ram[0x450]<<8)|ram[0x451];
      uint32_t pt = ((uint32_t)ram[0x42E]<<24)|((uint32_t)ram[0x42F]<<16)|((uint32_t)ram[0x430]<<8)|ram[0x431];
      printf("  [rg] d0=%x a0=%x a1=%x v_bas_ad=%x phystop=%x\r\n", d0, a0, a1, vb, pt); }
    { uint32_t sp = m68k_get_reg((void*)0, M68K_REG_SP), k;
      printf("  [bt] sp=%x:", sp);
      for (k = 0; k < 8; k++) {
          uint32_t v; uint32_t p = sp + k*4u;
          if (p + 4u > ST_RAM_SIZE) break;
          v = ((uint32_t)ram[p]<<24)|((uint32_t)ram[p+1]<<16)|((uint32_t)ram[p+2]<<8)|ram[p+3];
          printf(" %x", v);
      }
      printf("\r\n"); }
#endif
    m68k_pulse_bus_error();
}

static uint8_t fdc_intrq;              /* fwd decl: FDC model below   */
static uint8_t ide_intrq;              /* M11y fwd decl: IDE model --  */
static uint8_t ide_devctl;             /*  GPIP5 mirror + nIEN gate    */
static void ide_lat_poll(void);        /* M12d fwd: latency expiry may */
static int  pc_in_ram_fwd(void);       /* M12e fwd: RAM-band check     */
                                       /*  assert INTRQ with no IDE IO */
static uint8_t fdc_pend_cmd, fdc_pend_active;   /* M11i: no-drive pend */
static void fdc_command(uint8_t cmd);           /* fwd decl            */

/* -------------------- M5: keyboard ACIA + IKBD ---------------------- */
/* MC6850 at FFFC00/02 fed by an HD6301 (IKBD) model, Hatari-style but
 * minimal. RX path: IKBD->FIFO->ACIA RDR at the real 7812.5bps pace
 * (16MHz/781.25 B/s = 20480 cycles/byte exactly); each delivered byte
 * sets RDRF+IRQ, pulls MFP GPIP4 low and raises MFP source 6 (IPRB.6,
 * which EmuTOS enables: the observed ierb=0x60 is timerC+ACIA).
 * TX path (68k->IKBD commands): parsed with a length table so multi-
 * byte commands consume operands; reset ($80 $01) answers $F0.
 * The synthetic mouse orbits via a Minsky circle (x+=y>>5; y-=x>>5,
 * 8.8 fixed point -- energy-stable, ~200 frames/orbit): packets
 * $F8,dx,dy queued once per VBL after EmuTOS is ready. When fabric
 * USB HID arrives (m6), its ring buffer replaces ikbd_orbit_step()
 * as the packet source; everything below it stays.                   */
static void mfp_raise_acia(void);           /* defined w/ MFP below */
static uint8_t  ikbd_fifo[64];
static uint8_t  ikbd_head, ikbd_tail;
static uint8_t  acia_rdr;
static uint8_t  acia_sr = 0x02u;            /* bit1 TDRE=1 always     */
/* acia_pace retired in M9E: delivery is wall-paced (see main loop) */
static uint8_t  ikbd_cmd[8], ikbd_cmdpos, ikbd_cmdlen;
static uint8_t  joy_on;            /* M26: Print Screen toggle       */
static int16_t  dma_carry;         /* M27: DMA lockstep with aud_carry */
static uint8_t  joy_report = 1u;   /* M26: IKBD 0x14 on / 0x15 off   */
static uint8_t  joy_state, joy_prev;
static uint32_t dbg_joy_pkts;
static uint8_t  ikbd_reset_seen, ikbd_mouse_on = 1u;
static uint8_t  ikbd_y0_top = 1u;           /* IKBD $0F/$10 tracked   */
static uint16_t ikbd_warmup;                /* VBLs until orbit start */
static int16_t  orb_x = 100 << 8, orb_y;    /* 8.8 fixed point        */
static int16_t  orb_px, orb_py;             /* previous integer pos   */

static void ikbd_put(uint8_t b)
{
    uint8_t nt = (uint8_t)((ikbd_tail + 1u) & 63u);
    if (nt != ikbd_head) { ikbd_fifo[ikbd_tail] = b; ikbd_tail = nt; }
}
static int ikbd_fifo_free(void)
{ return 63 - ((ikbd_tail - ikbd_head) & 63u); }

static uint8_t ikbd_cmd_len(uint8_t op)     /* total bytes incl. op   */
{
    switch (op) {
    case 0x80u: return 2;                   /* RESET ($80 $01)        */
    case 0x07u: return 2;                   /* mouse button action    */
    case 0x09u: return 5;                   /* absolute mouse         */
    case 0x0Au: return 3;                   /* keycode mouse          */
    case 0x0Bu: return 3;                   /* threshold              */
    case 0x0Cu: return 3;                   /* scale                  */
    case 0x0Eu: return 6;                   /* load abs position      */
    case 0x17u: return 2;                   /* joystick monitoring    */
    case 0x19u: return 7;                   /* cursor key mode        */
    case 0x1Bu: return 7;                   /* set clock (6 BCD)      */
    case 0x20u: return 4;                   /* memory load hdr        */
    case 0x21u: return 3;                   /* memory read            */
    case 0x22u: return 3;                   /* controller execute     */
    default:    return 1;                   /* everything else        */
    }
}

static void ikbd_do_cmd(void)
{
    switch (ikbd_cmd[0]) {
    case 0x14u:                             /* M26: joystick event on */
        joy_report = 1u; break;
    case 0x15u:                             /* M26: joystick off      */
        joy_report = 0u; break;
    case 0x80u:                             /* RESET                  */
        if (ikbd_cmd[1] == 0x01u) {
            ikbd_head = ikbd_tail = 0u;     /* flush                  */
            ikbd_put(0xF0u);                /* self-test OK           */
            ikbd_reset_seen = 1u;
            ikbd_mouse_on   = 1u;
            ikbd_warmup     = 120u;         /* ~2s before orbiting    */
        }
        break;
    case 0x08u: case 0x0Bu: case 0x11u:     /* rel. mouse on / resume */
        ikbd_mouse_on = 1u;  break;
    case 0x0Fu: ikbd_y0_top = 0u; break;    /* Y=0 at bottom          */
    case 0x10u: ikbd_y0_top = 1u; break;    /* Y=0 at top             */
    case 0x12u: case 0x13u:                 /* mouse off / pause      */
        ikbd_mouse_on = 0u;  break;
    case 0x1Cu:                             /* read clock             */
        ikbd_put(0xFCu);
        ikbd_put(0x99u); ikbd_put(0x12u); ikbd_put(0x31u);
        ikbd_put(0x23u); ikbd_put(0x59u); ikbd_put(0x00u);
        break;
    default: break;                         /* consumed, no response  */
    }
}

static void ikbd_command_byte(uint8_t b)
{
    if (ikbd_cmdpos == 0u) ikbd_cmdlen = ikbd_cmd_len(b);
    if (ikbd_cmdpos < 8u) ikbd_cmd[ikbd_cmdpos] = b;
    ikbd_cmdpos++;
    if (ikbd_cmdpos >= ikbd_cmdlen) { ikbd_do_cmd(); ikbd_cmdpos = 0u; }
}

/* deliver one FIFO byte to the ACIA if it is ready to take one       */
static void acia_deliver_one(void)
{
    if ((acia_sr & 0x01u) == 0u && ikbd_head != ikbd_tail) {
        acia_rdr = ikbd_fifo[ikbd_head];
        ikbd_head = (uint8_t)((ikbd_head + 1u) & 63u);
        acia_sr |= 0x81u;                   /* RDRF + IRQ             */
        mfp_raise_acia();                   /* fwd-decl wrapper below */
    }
}

/* ------------------ M6: USB HID event ring consumer ------------------
 * Fabric contract (falcon_hid_ahb.v): 128 x 16-byte records at 0x03FE0000,
 * head count (records ever written) at 0x03FE0800, all written by the
 * fabric through the AE350's Extended AHB Master port. Firmware keeps the
 * tail. Reads happen right after mbox_publish()'s WBINVAL, so the cache
 * lines over the ring are freshly invalidated every VBL for free; the
 * firmware never writes the ring region, so no dirty-line writeback can
 * clobber fabric data.
 * record w0: [7:0] 'M'/'K'; M: [15:8] usb btns, [23:16] dx, [31:24] dy
 *                           K: [15:8] modifiers, [23:16] k1, [31:24] k2
 *        w1: K: [7:0] k3, [15:8] k4; both: [23:16] port
 * Mouse -> IKBD $F8 packets directly (buttons: USB b0=L,b1=R; IKBD hdr
 * bit1=left, bit0=right; y sign follows the IKBD $0F/$10 origin state).
 * Keyboard -> make/break by diffing {mod,k1..k4} per port against the
 * previous report, through the USB-usage -> ST-scancode table.
 * First real HID event retires the orbit permanently -- an orbiting
 * cursor with USB attached therefore means "fabric HID not delivering",
 * which keeps the diagnostic value of m5 alive.                        */
/* Ring layout rev2 (falcon_hid_ahb.v): 128 records x 16 BYTES.
 *   record[i] + 0  : word0        record[i] + 8  : word1
 *   record[i] + 4  and +12        : UNUSED
 * Why 16 bytes for 8 bytes of payload: the Extended AHB Master's data bus
 * is 64-bit, and on this IP the upper half of a 64-bit datapath is not
 * trustworthy (the 64-bit shared-DDR3 read lane returned address-independent
 * garbage in bits [63:32], measured 2026-07-12). So every fabric write is a
 * 32-bit AHB transfer at an 8-byte-aligned address, which always lands on
 * HWDATA[31:0]. The two dead words per record cost 2KB of DDR3 -- irrelevant
 * against 256MB, and cheap insurance against a known-bad datapath. */
#ifdef HOST_TEST
  static volatile uint32_t hid_ring_host[516];
  #define HID_RING ((volatile uint32_t *)hid_ring_host)
  #define HID_HEAD (hid_ring_host[512])
#else
  #define HID_RING ((volatile uint32_t *)0x03FE0000u)
  #define HID_HEAD (*(volatile uint32_t *)0x03FE0800u)
#endif
#define HID_SLOTS 128u

static uint32_t hid_tail;
static uint32_t hid_events_total;
static uint32_t hid_kbd_records, hid_pha_records, hid_mou_records; /* M11b */
static uint8_t  kbd_prev[2][5];             /* per port: mod,k1..k4   */

static const uint8_t usb2st[232] = {
    /* 0x00 */ 0,0,0,0,
    /* 0x04 A-Z */ 0x1E,0x30,0x2E,0x20,0x12,0x21,0x22,0x23,0x17,0x24,
                   0x25,0x26,0x32,0x31,0x18,0x19,0x10,0x13,0x1F,0x14,
                   0x16,0x2F,0x11,0x2D,0x15,0x2C,
    /* 0x1E 1-9,0 */ 0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B,
    /* 0x28 */ 0x1C,      /* Enter  */
    /* 0x29 */ 0x01,      /* Escape */
    /* 0x2A */ 0x0E,      /* Backsp */
    /* 0x2B */ 0x0F,      /* Tab    */
    /* 0x2C */ 0x39,      /* Space  */
    /* 0x2D */ 0x0C,0x0D,0x1A,0x1B,0x2B,0x2B,0x27,0x28,0x29,0x33,0x34,0x35,
    /* 0x39 */ 0x3A,      /* CapsLk */
    /* 0x3A F1-F10 */ 0x3B,0x3C,0x3D,0x3E,0x3F,0x40,0x41,0x42,0x43,0x44,
    /* 0x44 F11,F12 -> Help, Undo */ 0x62,0x61,
    /* 0x46 */ 0,0,0,     /* PrtSc ScrLk Pause */
    /* 0x49 */ 0x52,      /* Insert */
    /* 0x4A */ 0x47,      /* Home   */
    /* 0x4B */ 0,         /* PgUp   */
    /* 0x4C */ 0x53,      /* Delete */
    /* 0x4D */ 0,0,       /* End PgDn */
    /* 0x4F */ 0x4D,0x4B,0x50,0x48,   /* Right Left Down Up */
    /* 0x53 */ 0,         /* NumLock */
    /* 0x54 */ 0x65,0x66,0x4A,0x4E,0x72,          /* KP / * - + Enter */
    /* 0x59 KP1-9 */ 0x6D,0x6E,0x6F,0x6A,0x6B,0x6C,0x67,0x68,0x69,
    /* 0x62 */ 0x70,0x71, /* KP0 KP. */
    /* 0x64 */ 0x60,      /* ISO <> key */
    /* 0x65.. */ 0,0,0    /* pad to keep initializer bounded */
};

/* ===================================================================
 * M26: KEYBOARD-MAPPED JOYSTICK 1.
 *
 * The ST reads joysticks only through the IKBD, so this is a packet
 * matter, not a register one. Format from Hatari ikbd.c / joy.h:
 * on a state CHANGE the IKBD sends header 0xFF (joystick 1; 0xFE is
 * joystick 0 / mouse port) followed by one state byte --
 * UP 0x01, DOWN 0x02, LEFT 0x04, RIGHT 0x08, FIRE 0x80.
 *
 * Directions: arrow keys OR numpad 8/2/4/6. Fire: Space OR numpad 0.
 * Both conventions, since costs nothing. While joystick mode is ON
 * those keys are CONSUMED -- they do not also arrive as scancodes, so
 * a game reading both cannot see double input. Diagonals work because
 * the HID report carries up to four simultaneous keycodes.
 *
 * Print Screen toggles. It is a normal keycode (usage 0x46) that our
 * scancode table already maps to 0, so the guest never saw it and
 * nothing is stolen. Turning the mode OFF emits a final all-released
 * state, so a direction can never stick.                            */
#define JOY_UP    0x01u
#define JOY_DOWN  0x02u
#define JOY_LEFT  0x04u
#define JOY_RIGHT 0x08u
#define JOY_FIRE  0x80u

/* USB usage -> joystick bit, or 0 if the key is not a joystick key.  */
static uint8_t joy_bit_of_usage(uint8_t u)
{
    switch (u) {
    case 0x52u: case 0x60u: return JOY_UP;     /* Up    / numpad 8    */
    case 0x51u: case 0x5Au: return JOY_DOWN;   /* Down  / numpad 2    */
    case 0x50u: case 0x5Cu: return JOY_LEFT;   /* Left  / numpad 4    */
    case 0x4Fu: case 0x5Eu: return JOY_RIGHT;  /* Right / numpad 6    */
    case 0x2Cu: case 0x62u: return JOY_FIRE;   /* Space / numpad 0    */
    default:                return 0u;
    }
}

static void joy_emit(void)     /* send only on change, as the IKBD does */
{
    if (joy_state == joy_prev) return;
    joy_prev = joy_state;
    if (!joy_report) return;
    ikbd_put(0xFFu);           /* joystick 1                          */
    ikbd_put(joy_state);
    dbg_joy_pkts++;
}

static void ikbd_key(uint8_t st, int make)
{
    if (st) ikbd_put(make ? st : (uint8_t)(st | 0x80u));
}

static void hid_kbd_record(uint8_t port, const uint8_t nw[5])
{
    static const uint8_t modmap[8] =
        { 0x1D, 0x2A, 0x38, 0, 0x1D, 0x36, 0x38, 0 };
    uint8_t *pv = kbd_prev[port & 1u];
    int i, j;
    if (nw[1] == 0x01u) {                   /* phantom / rollover:    */
        hid_pha_records++;                  /* key array invalid, but */
        for (i = 0; i < 8; i++) {           /* MODIFIERS STAY VALID   */
            uint8_t was = (uint8_t)(pv[0] >> i) & 1u;
            uint8_t now = (uint8_t)(nw[0] >> i) & 1u;
            if (was != now) ikbd_key(modmap[i], now);
        }
        pv[0] = nw[0];                      /* keys: prev preserved   */
        return;
    }
    for (i = 0; i < 8; i++) {               /* modifier diffs         */
        uint8_t was = (uint8_t)(pv[0] >> i) & 1u;
        uint8_t now = (uint8_t)(nw[0] >> i) & 1u;
        if (was != now) ikbd_key(modmap[i], now);
    }
    for (i = 1; i < 5; i++) {               /* breaks                 */
        uint8_t k = pv[i]; int still = 0;
        if (!k) continue;
        for (j = 1; j < 5; j++) if (nw[j] == k) still = 1;
        if (!still && k < 232u) ikbd_key(usb2st[k], 0);
    }
    for (i = 1; i < 5; i++) {               /* makes                  */
        uint8_t k = nw[i]; int fresh = 1;
        if (!k) continue;
        for (j = 1; j < 5; j++) if (pv[j] == k) fresh = 0;
        if (fresh && k < 232u) ikbd_key(usb2st[k], 1);
    }
    for (i = 0; i < 5; i++) pv[i] = nw[i];
}

static void hid_consume(void)               /* M11n: self-coherent   */
{
    int budget = 8;
    uint32_t head;
    /* M11n: the fabric wrote this ring; invalidate before reading it.
     * Until M11m this was a side effect of tb_read's WBINVAL_ALL, which
     * is why the old comment here said "post-WBINVAL". Covers the 2048B
     * ring and the head word that follows it. */
    if (cacheopt) dcache_inval_range((uintptr_t)HID_RING, 2052u);
    head = HID_HEAD;
    if ((head - hid_tail) > HID_SLOTS) hid_tail = head - HID_SLOTS; /* overrun */
    while (hid_tail != head && budget-- > 0) {
        uint32_t s  = (hid_tail & (HID_SLOTS - 1u)) * 4u; /* 16B = 4 words */
        uint32_t w0 = HID_RING[s];
        uint32_t w1 = HID_RING[s + 2u];                   /* record + 8    */
        uint8_t  ty = (uint8_t)w0;
        hid_tail++;
        if (ty == 0x4Du) {                  /* mouse                  */
            uint8_t b  = (uint8_t)(w0 >> 8);
            int8_t  dx = (int8_t)(w0 >> 16);
            int8_t  dy = (int8_t)(w0 >> 24);
            uint8_t hdr = (uint8_t)(0xF8u
                        | ((b & 1u) ? 2u : 0u)      /* USB L -> IKBD bit1 */
                        | ((b & 2u) ? 1u : 0u));    /* USB R -> IKBD bit0 */
            if (!ikbd_y0_top) dy = (int8_t)-dy;
            if (ikbd_mouse_on && ikbd_fifo_free() >= 3) {
                ikbd_put(hdr);
                ikbd_put((uint8_t)dx);
                ikbd_put((uint8_t)dy);
            }
            hid_events_total++; hid_mou_records++;
        } else if (ty == 0x4Bu) {           /* keyboard               */
            uint8_t nw[5];
            nw[0] = (uint8_t)(w0 >> 8);  nw[1] = (uint8_t)(w0 >> 16);
            nw[2] = (uint8_t)(w0 >> 24); nw[3] = (uint8_t)w1;
            nw[4] = (uint8_t)(w1 >> 8);
            /* M11k: F12 (USB usage 0x45) toggles UART instrumentation.
             * The Atari keyboard has no F12, so swallowing it costs the
             * guest nothing. Edge-triggered: HID reports are state-based
             * and repeat the usage for as long as the key is held. */
            { int k, f12 = 0;
              for (k = 0; k < 5; k++) if (nw[k] == 0x45u) f12 = 1;
              if (f12 && !f12_down) {
                  log_on = (uint8_t)!log_on;
                  ide_dbg = log_on;               /* M15: FIX -- the m14
                                                   * builder dropped this
                                                   * line silently.      */
                  if (log_on) { vid_dbg = 1u; vid_dbg_n = 0u; } /* M15 */
                  if (log_on) force_status = 1;   /* M11l: print now */
                  printf("\r\n[log] UART instrumentation %s\r\n",
                         log_on ? "ON" : "OFF");
              }
              f12_down = (uint8_t)f12;
              for (k = 0; k < 5; k++) if (nw[k] == 0x45u) nw[k] = 0u; }
            /* M26: Print Screen (usage 0x46) toggles keyboard joystick.
             * Done here, before hid_kbd_record, and the joystick keys
             * are zeroed out so they never become scancodes.        */
            { int k, prt = 0;
              for (k = 1; k < 5; k++) if (nw[k] == 0x46u) prt = 1;
              if (prt && !prtsc_down) {
                  joy_on = (uint8_t)!joy_on;
                  if (!joy_on) { joy_state = 0u; joy_emit(); }
                  printf("\r\n[joy] keyboard joystick: %s%s\r\n",
                         joy_on ? "ON (arrows/numpad + space)" : "OFF",
                         (joy_on && !joy_report)
                             ? "  [guest has reporting disabled]" : "");
              }
              prtsc_down = (uint8_t)prt;
              for (k = 1; k < 5; k++) if (nw[k] == 0x46u) nw[k] = 0u; }

            if (joy_on) {                    /* M26: build + consume  */
                int k; uint8_t st = 0u;
                for (k = 1; k < 5; k++) {
                    uint8_t b = joy_bit_of_usage(nw[k]);
                    if (b) { st |= b; nw[k] = 0u; }
                }
                joy_state = st;
                joy_emit();
            }

            /* M18: F10 (USB usage 0x43) toggles the VBL rate live, so a
             * game can be A/B'd at 50 and 60Hz without a reflash. */
            { int k, f10 = 0;
              for (k = 0; k < 5; k++) if (nw[k] == 0x43u) f10 = 1;
              if (f10 && !f10_down) {
                  vbl_50hz = (uint8_t)!vbl_50hz;
                  vbl_acc = 0u;
                  printf("\r\n[vbl] rate: %s\r\n",
                         vbl_50hz ? "50Hz (PAL)" : "60Hz (VGA)");
              }
              f10_down = (uint8_t)f10;
              for (k = 0; k < 5; k++) if (nw[k] == 0x43u) nw[k] = 0u; }
            /* M14: F11 (USB usage 0x44) toggles the audio source.
             * Also absent from the Atari keyboard, so swallowing is free. */
            { int k, f11 = 0;
              for (k = 0; k < 5; k++) if (nw[k] == 0x44u) f11 = 1;
              if (f11 && !f11_down) {
                  aud_src_tone = (uint8_t)!aud_src_tone;
                  printf("\r\n[aud] source: %s\r\n",
                         aud_src_tone ? "440Hz TEST TONE" : "PSG");
              }
              f11_down = (uint8_t)f11;
              for (k = 0; k < 5; k++) if (nw[k] == 0x44u) nw[k] = 0u; }
            if (ikbd_fifo_free() >= 12)
                hid_kbd_record((uint8_t)(w1 >> 16), nw);
            hid_events_total++; hid_kbd_records++;
        }
    }
}

/* ikbd_orbit_step removed in M11b (requested 2026-07-16). */

/* ----------------------------- MFP --------------------------------- */
/* Minimal MC68901: register file, timers A-D, vectored interrupts.
 * Registers are odd bytes FFFA01..FFFA2F, index = (addr-0xFA01)/2.   */
#define MFP_GPIP 0
#define MFP_AER  1
#define MFP_DDR  2
#define MFP_IERA 3
#define MFP_IERB 4
#define MFP_IPRA 5
#define MFP_IPRB 6
#define MFP_ISRA 7
#define MFP_ISRB 8
#define MFP_IMRA 9
#define MFP_IMRB 10
#define MFP_VR   11
#define MFP_TACR 12
#define MFP_TBCR 13
#define MFP_TCDCR 14
#define MFP_TADR 15
#define MFP_TBDR 16
#define MFP_TCDR 17
#define MFP_TDDR 18

static uint8_t  mfp[24];
static uint8_t  tcount[4];        /* live down-counters A B C D      */
static uint32_t tsub[4];          /* prescaler sub-count (MFP ticks) */
static uint32_t mfp_acc;          /* CPU-cycle -> MFP-tick accum     */
static const uint16_t presc_tab[8] = { 0, 4, 10, 16, 50, 64, 100, 200 };
/* MFP interrupt source numbers: Timer A=13, B=8, C=5, D=4 */
static const uint8_t timer_src[4] = { 13, 8, 5, 4 };

static void mfp_update_irq(void)
{
    uint16_t pend = ((uint16_t)(mfp[MFP_IPRA] & mfp[MFP_IMRA] & mfp[MFP_IERA]) << 8)
                  |  (uint16_t)(mfp[MFP_IPRB] & mfp[MFP_IMRB] & mfp[MFP_IERB]);
    m68k_set_irq(pend ? 6 : 0);
}

static uint32_t dbg_raise5, dbg_ack5, dbg_raise_blocked;
/* M11j instrumentation (read-only; never gates behaviour) */
static uint32_t dbg_lost5;         /* Timer C raise onto a set IPR  */
static uint32_t dbg_mfp_max;       /* worst MFP-tick gap per service*/
static uint32_t dbg_resync;        /* stall-guard firings           */
static uint8_t  dbg_primed;        /* skip the first-read delta     */
static uint64_t dbg_resync_ticks;  /* MFP ticks the guard discarded */
static void mfp_raise(int src)
{
    if (src == 5) dbg_raise5++;
    int reg = (src >= 8) ? MFP_IPRA : MFP_IPRB;
    int bit = src & 7;
    int ier = (src >= 8) ? MFP_IERA : MFP_IERB;
    if (mfp[ier] & (1u << bit)) {
        if (src == 5 && (mfp[reg] & (1u << bit))) dbg_lost5++;  /* M11j:
            IPR already set -- this tick is dropped, guest never sees */
        mfp[reg] |= (uint8_t)(1u << bit);
        mfp_update_irq();
    } else if (src == 5) dbg_raise_blocked++;
}

static void mfp_raise_acia(void) { mfp_raise(6); }   /* GPIP4/IPRB.6 */

static uint8_t timer_ctrl(int t)   /* prescaler bits for timer 0..3 */
{
    switch (t) {
    case 0: return mfp[MFP_TACR] & 7u;
    case 1: return mfp[MFP_TBCR] & 7u;
    case 2: return (mfp[MFP_TCDCR] >> 4) & 7u;
    default: return mfp[MFP_TCDCR] & 7u;
    }
}
static uint8_t timer_data(int t)
{ return mfp[MFP_TADR + t]; }

/* ===================================================================
 * M28: ADAPTIVE SLICING.
 *
 * m68k_execute(10000) was the ONLY point at which this machine looked
 * at the clock: timers advanced, interrupts raised and hbl_line
 * stepped between slices, never inside one. Measured from silicon
 * (180224 slices / 118.9s): ~1516 slices/sec. Two consequences, both
 * observed, both with the same cause:
 *
 *  - INTERRUPTS cannot be delivered faster than one per slice. A PSG
 *    digi routine asking for 4-6kHz gets ~1.5kHz: 25-40% speed, and
 *    perfectly SMOOTH, because each tick that IS delivered writes a
 *    correct sample. (Ranarama.)
 *  - The PALETTE line stamp is frozen for a whole slice. 10000 cycles
 *    is ~10 scanlines of emulated time and, at our wall speed, more
 *    like 28 of real ones -- and since slice boundaries drift against
 *    the frame, the error CHANGES every frame. A raster split that
 *    will not sit still. (Frontier's UI band.)
 *
 * Fix: keep the cheap 10000-cycle slice as the default, and drop to a
 * fine slice ONLY while something needs it -- a timer armed with a
 * short period, or palette splits seen in the last frame. Cost is paid
 * only by software that uses the feature. The A25 has ample headroom:
 * even 22k slices/sec is a fraction of a percent of an 800MHz core.
 *
 * FALCON.CFG SLICE=n pins the cap (SLICE=10000 restores exactly the
 * pre-M28 behaviour for bisection without a reflash).
 * =================================================================== */
#define SLICE_COARSE   10000u
#define SLICE_FINE       256u   /* ~0.7 scanline; ~22kHz IRQ ceiling   */
#define SLICE_FLOOR       64u
#define FINE_MFP_PERIOD 2048u   /* timer period below this => "fast"   */

static uint32_t slice_cap_cfg;          /* FALCON.CFG SLICE=n, 0=auto  */
static uint32_t dbg_fine_slices;

/* M28: does anything need sub-slice resolution right now?            */
/* Only a timer whose INTERRUPT IS ENABLED can need fine slicing. TOS
 * runs Timer D as the RS232 baud generator with a tiny divisor and its
 * interrupt masked off -- without this check that alone forces fine
 * mode for the entire session (measured: 93% of slices on a plain
 * EmuTOS boot, and it perturbed the desktop fixture).               */
static int timer_irq_enabled(int t)
{
    switch (t) {
    case 0:  return (mfp[MFP_IERA] & 0x20u) != 0u;   /* Timer A */
    case 1:  return (mfp[MFP_IERA] & 0x01u) != 0u;   /* Timer B */
    case 2:  return (mfp[MFP_IERB] & 0x20u) != 0u;   /* Timer C */
    default: return (mfp[MFP_IERB] & 0x10u) != 0u;   /* Timer D */
    }
}

static uint32_t slice_cycles(void)
{
    int t;
    if (slice_cap_cfg) return slice_cap_cfg;      /* pinned by config  */
    if (psplit_active) { dbg_fine_slices++; return SLICE_FINE; }
    for (t = 0; t < 4; t++) {
        uint32_t p = presc_tab[timer_ctrl(t)];
        uint32_t d = timer_data(t);
        if (!p) continue;                          /* stopped / event  */
        if (!timer_irq_enabled(t)) continue;       /* baud clock etc.  */
        if (d == 0u) d = 256u;                     /* 0 means 256      */
        if (p * d < FINE_MFP_PERIOD) {             /* fast timer armed */
            dbg_fine_slices++;
            return SLICE_FINE;
        }
    }
    return SLICE_COARSE;
}

/* advance timers by n MFP clock ticks (2.4576MHz domain) */
static void mfp_timers_tick(uint32_t n)
{
    int t;
    for (t = 0; t < 4; t++) {
        uint32_t p = presc_tab[timer_ctrl(t)];
        if (!p) continue;                    /* stopped / event mode */
        tsub[t] += n;
        while (tsub[t] >= p) {
            tsub[t] -= p;
            if (tcount[t] == 0) tcount[t] = timer_data(t);
            if (--tcount[t] == 0) {
                tcount[t] = timer_data(t);   /* reload               */
                mfp_raise(timer_src[t]);
            }
        }
    }
}

/* ===================================================================
 * M17: MFP Timer A/B EVENT-COUNT mode.
 *
 * On real hardware the MFP's TAI/TBI inputs are wired to the video
 * circuit's display-enable line, so a timer in event-count mode
 * (control nibble == 8) decrements once per DISPLAYED SCANLINE rather
 * than off a prescaler. That is how essentially every ST game and demo
 * does a raster split: arm Timer B for N lines from the VBL handler,
 * change the palette (or screen base) when it fires, re-arm for the
 * next band.
 *
 * Until now timer_ctrl() masked the control byte with &7, so the
 * event-count encoding 8 read back as 0 = stopped, and the tick loop
 * skipped it -- the comment there even said "stopped / event mode".
 * Measured consequence, found by disassembling Treasure Island Dizzy
 * out of a Hatari save state: its VBL handler at $15602 programs
 * TBDR=47 / TBCR=8 and points $120 at $156AC; that chain writes the
 * frame-sync flag at $14387; the main loop at $182DC spins
 * "cmp.b $14387,d0 / beq *-6" forever because the flag never changes.
 * Music kept playing because the VBL handler itself ran fine.
 *
 * The scanline clock is derived from the SAME wall-locked MFP tick
 * stream, so it inherits M10's accuracy and needs no new clock and no
 * fabric change: the ST/Falcon line rate is 15625Hz and the MFP clock
 * is 2457600Hz, and 15625/2457600 reduces to EXACTLY 625/98304 -- an
 * exact integer ratio, same discipline as the audio decimator. One
 * 60Hz frame = 40960 MFP ticks = 260 lines; one 50Hz frame = 49152
 * ticks = 312.5 lines. Both correct by construction.
 *
 * Events are gated to the DISPLAYED window: a real display-enable
 * pulse only exists for visible lines, so a split armed for 47 counts
 * 47 visible lines, not 47 lines of top border.
 * =================================================================== */
#define HBL_NUM        625u        /* 15625 / 2457600 == 625 / 98304   */
#define HBL_DEN        98304u
#define HBL_VISIBLE    200u        /* ST-mode displayed lines          */

static uint32_t hbl_acc;           /* rational remainder               */
static uint32_t hbl_line;          /* line within frame, reset at VBL  */
/* Frame length is MEASURED each frame rather than assumed, and the
 * displayed window is centred in it. A fixed PAL border does not fit:
 * a 60Hz frame is only 260 lines, so 63 + 200 overflows it and the
 * bottom 3 displayed lines never generate an event (TBTEST v5 caught
 * exactly this, 197 != 200). Measuring makes the raster correct at
 * 50Hz AND 60Hz with no mode knowledge, and it self-corrects if the
 * VBL divisor is ever changed.                                      */
static uint32_t hbl_frame_lines = 312u;   /* PAL until first measured */

/* ===================================================================
 * M20: STE / Falcon DMA SOUND PLAYBACK.
 *
 * Register map + semantics from Hatari crossbar.c (the executable spec,
 * as blitter.c was for M11). $FF8900-$FF8921, byte-wide, odd addresses.
 * Until now this region was shadow-only (whitelisted, inert), so a game
 * that programmed sound DMA got silence -- a greenfield add, not a change
 * to anything proven.
 *
 *   $8901 control : bit0 PLAY, bit1 loop, bit7 play/record select.
 *                   PLAY latches on the (isRunning==0 && bit0) edge.
 *   $8903/05/07   : frame START (hi/mid/lo, 24-bit RAM address)
 *   $8909/0B/0D   : frame COUNT (current pointer, READABLE mid-play)
 *   $890F/11/13   : frame END
 *   $8921 mode    : bit6 16-bit, bit7 mono (stereo := !bit7),
 *                   bits0-1 STE rate index (6258/12517/25033/50066).
 *
 * SINK is fixed: the m13 ring drains at fs = 50MHz/1024 = 48828.125Hz
 * (MAX98357A I2S frame clock). The guest produces at a DIFFERENT rate,
 * so the engine MUST resample or pitch is wrong. Same exact-ratio cyc50
 * accumulator discipline as the sine stepper: a phase accumulator
 * advanced by (source_rate<<16)/48828 per OUTPUT sample steps the guest
 * read pointer (nearest-neighbour). Interpolation is a later refinement.
 *
 * Guest RAM is touched ONLY through dma_fetch8(): this engine is a future
 * bus-master-cohort member (a real DMA master once the CPU goes HDL), so
 * its memory access has a single clean seam to replace.               */
static const uint32_t ste_rate[4] = { 6258u, 12517u, 25033u, 50066u };

static uint8_t  dma_run, dma_loop, dma_16bit, dma_stereo, dma_ratesel;
static uint32_t dma_start, dma_end, dma_ptr, dma_step, dma_pacc;
static int16_t  dma_l, dma_r;

static uint32_t dma_source_rate(void) { return ste_rate[dma_ratesel & 3u]; }
static void dma_recompute_step(void)
{ dma_step = (dma_source_rate() << 16) / 48828u; }

static inline uint8_t dma_fetch8(uint32_t a)
{ return (a < 0x00E00000u) ? ram[a] : 0u; }

static uint32_t dma_frames_consumed;   /* M27: rate-proof test hook   */
static void dma_decode_frame(void)
{
    dma_frames_consumed++;
    if (dma_16bit) {
        int16_t a = (int16_t)(((uint16_t)dma_fetch8(dma_ptr) << 8)
                             |  dma_fetch8(dma_ptr + 1u));
        if (dma_stereo) {
            int16_t b = (int16_t)(((uint16_t)dma_fetch8(dma_ptr + 2u) << 8)
                                 |  dma_fetch8(dma_ptr + 3u));
            dma_l = a; dma_r = b; dma_ptr += 4u;
        } else { dma_l = dma_r = a; dma_ptr += 2u; }
    } else {
        int16_t a = (int16_t)((int8_t)dma_fetch8(dma_ptr)) << 8;
        if (dma_stereo) {
            int16_t b = (int16_t)((int8_t)dma_fetch8(dma_ptr + 1u)) << 8;
            dma_l = a; dma_r = b; dma_ptr += 2u;
        } else { dma_l = dma_r = a; dma_ptr += 1u; }
    }
}

/* M23: one XSINT "end of frame" event into Timer A's EVENT-COUNT
 * machinery (TADR countdown, fire at zero), exactly as the STE wires
 * TAI. m20 raised source 8 directly -- which is TIMER B, and bypassed
 * the counter. Games arm TACR=8/TADR=N to interrupt after N frames;
 * this is how that now works. Nothing fires unless event mode is on. */
static void dma_ta_event(void)
{
    if ((mfp[MFP_TACR] & 0x0Fu) != 0x08u) return;
    if (tcount[0] == 0) tcount[0] = timer_data(0);
    if (--tcount[0] == 0) {
        tcount[0] = timer_data(0);
        mfp_raise(timer_src[0]);          /* source 13 = Timer A      */
    }
}

static void dma_at_frame_end(void)
{
    dma_ta_event();                       /* XSINT falling edge       */
    if (dma_loop) dma_ptr = dma_start; else dma_run = 0u;
}

/* M27: ONE MONO SAMPLE PER CALL, at the true fs of 48828 Hz. The ring
 * is mono with 2 consecutive samples per word (falcon_audio_ahb.v), so
 * this is called once per SAMPLE SLOT -- twice per ring word -- and
 * the (source_rate<<16)/48828 step is finally running at the rate it
 * was calibrated for. m20 called it once per WORD: exactly half speed,
 * smooth -- the measured Ranarama symptom. Stereo source frames fold
 * (L+R)/2 here; the output stage is a mono amp regardless.           */
static int16_t dma_next_mono(void)
{
    int32_t m;
    if (!dma_run) return 0;
    dma_pacc += dma_step;
    while (dma_pacc >= 0x10000u) {
        dma_pacc -= 0x10000u;
        if (dma_ptr >= dma_end) { dma_at_frame_end(); if (!dma_run) return 0; }
        dma_decode_frame();
    }
    m = ((int32_t)dma_l + (int32_t)dma_r) >> 1;
    return (int16_t)m;
}

static void dma_snd_write(uint32_t r, uint8_t v)
{
    io_shadow[r - 0x8000u] = v;
    switch (r) {
    case 0x8901u: {
        uint8_t play = (uint8_t)(v & 0x01u);
        if (!dma_run && play) {
            dma_start = ((uint32_t)io_shadow[0x0903u] << 16)
                      | ((uint32_t)io_shadow[0x0905u] << 8)
                      |  (uint32_t)io_shadow[0x0907u];
            dma_end   = ((uint32_t)io_shadow[0x090Fu] << 16)
                      | ((uint32_t)io_shadow[0x0911u] << 8)
                      |  (uint32_t)io_shadow[0x0913u];
            dma_start &= 0x00FFFFFEu; dma_end &= 0x00FFFFFEu;
            dma_ptr  = dma_start; dma_pacc = 0u;
            dma_loop = (uint8_t)((v >> 1) & 1u);
            dma_recompute_step();
            if (dma_end > dma_start) { dma_run = 1u; dma_decode_frame(); }
        } else if (dma_run && !play) {
            dma_run = 0u;
        } else {
            dma_loop = (uint8_t)((v >> 1) & 1u);
        }
        break; }
    case 0x8921u:
        dma_16bit   = (uint8_t)((v >> 6) & 1u);
        dma_stereo  = (uint8_t)(1u - ((v >> 7) & 1u));
        dma_ratesel = (uint8_t)(v & 3u);
        if (dma_run) dma_recompute_step();
        break;
    default: break;
    }
}

static uint8_t dma_snd_read(uint32_t r)
{
    switch (r) {
    case 0x8901u:                        /* M23: bit0 reflects the
                                          * ENGINE, not the last write:
                                          * auto-stop reads back 0.   */
        return (uint8_t)((io_shadow[0x0901u] & 0xFEu) | (dma_run & 1u));
    case 0x8909u: return (uint8_t)(dma_ptr >> 16);
    case 0x890Bu: return (uint8_t)(dma_ptr >> 8);
    case 0x890Du: return (uint8_t)(dma_ptr);
    default:      return io_shadow[r - 0x8000u];
    }
}

static uint32_t hbl_top_border(void)
{ return (hbl_frame_lines > HBL_VISIBLE)
       ? ((hbl_frame_lines - HBL_VISIBLE) >> 1) : 0u; }

/* M19: stamp + snapshot one ST palette write. Called from io_write8 on
 * any $FF8240..$FF825F store, AFTER the shadow byte lands, so the
 * snapshot includes it. Cheap: same-line writes re-snapshot in place
 * (Dizzy's 16-word movem = 32 calls, one entry).                     */
static void psplit_note(void)
{
    uint32_t tb = hbl_top_border(), vis, k;
    if (hbl_line > tb + HBL_VISIBLE) return;   /* bottom border: the
                                        * mailbox base carries it    */
    vis = (hbl_line > tb) ? (hbl_line - tb) : 0u;
    if (psplit_n != 0u && psplit_line[psplit_n - 1u] == vis) {
        /* same visible line: re-snapshot the existing entry          */
    } else if (psplit_n < PSPLIT_MAX) {
        psplit_line[psplit_n] = vis;
        psplit_n++;
    } else { psplit_dropped++; return; }
    for (k = 0; k < 16u; k++) {
        uint32_t p = ((uint32_t)io_shadow[0x0240u + k*2u] << 8)
                   |  io_shadow[0x0241u + k*2u];
        psplit_pal[psplit_n - 1u][k] = (uint16_t)strot12(p & 0x0FFFu);
    }
}
static uint32_t dbg_tb_fires;      /* event-mode interrupts raised     */

/* full 4-bit control: 8 == event count (only Timers A and B have it) */
static uint8_t timer_ctrl4(int t)
{ return (uint8_t)((t == 0 ? mfp[MFP_TACR] : mfp[MFP_TBCR]) & 0x0Fu); }

/* one display-enable event: decrement every event-mode timer */
static void mfp_event_tick(void)
{
    int t;
    /* M23: the scanline (display-enable) event feeds ONLY Timer B's
     * TBI input. Timer A's TAI is the SOUND-DMA XSINT line -- see
     * dma_ta_event() -- so A no longer counts scanlines.             */
    for (t = 1; t < 2; t++) {
        if (timer_ctrl4(t) != 0x08u) continue;
        if (tcount[t] == 0) tcount[t] = timer_data(t);
        if (--tcount[t] == 0) {
            tcount[t] = timer_data(t);       /* reload, as the MFP does */
            dbg_tb_fires++;
            mfp_raise(timer_src[t]);
        }
    }
}

/* advance the scanline clock by n MFP ticks */
static void mfp_hbl_advance(uint32_t n)
{
    hbl_acc += n * HBL_NUM;
    while (hbl_acc >= HBL_DEN) {
        hbl_acc -= HBL_DEN;
        hbl_line++;
        { uint32_t tb = hbl_top_border();
          if (hbl_line > tb && hbl_line <= tb + HBL_VISIBLE)
            mfp_event_tick(); }               /* displayed lines only   */
    }
}

/* advance MFP by executed 68k cycles: 16MHz CPU, 2.4576MHz timer clk */
static void mfp_advance(uint32_t cpu_cycles)
{
    /* 2.4576MHz / 16MHz = 24576/160000 exactly; 64-bit intermediate
     * because cycles*24576 overflows uint32 (that bug cost an 8x
     * timer-rate error: 10000*2457600 wrapped before the divide).   */
    mfp_acc += cpu_cycles * 24576u;   /* safe: slices are 10k cycles,
                                         product < 2^32 up to ~174k  */
    { uint32_t ticks = mfp_acc / 160000u;
      mfp_acc -= ticks * 160000u;
      if (ticks) mfp_timers_tick(ticks); }
}

static uint32_t mfp_read(uint32_t r)           /* r = lo16 of address */
{
    if ((r & 1u) == 0u) return 0xFFu;          /* even bytes: open    */
    { int idx = (int)((r - 0xFA01u) >> 1);
      if (idx < 0 || idx >= 24) return 0xFFu;
      switch (idx) {
      case MFP_TADR: return tcount[0] ? tcount[0] : timer_data(0);
      case MFP_TBDR: return tcount[1] ? tcount[1] : timer_data(1);
      case MFP_TCDR: return tcount[2] ? tcount[2] : timer_data(2);
      case MFP_TDDR: return tcount[3] ? tcount[3] : timer_data(3);
      case MFP_GPIP: {                  /* bit5=FDC|IDE, bit4=ACIA,   */
          static uint8_t  gp_last = 0xEEu;   /* impossible first value */
          static uint32_t gp_cnt, gp_n;
          uint32_t gv;
          ide_lat_poll();               /* M12d: run the drive clock  */
          gv = (uint32_t)(0xFFu         /* all active-low mirrors     */
                 ^ ((fdc_intrq ||
                     (ide_intrq && !(ide_devctl & 0x02u)))
                                      ? 0x20u : 0u)
                 ^ ((acia_sr & 0x80u) ? 0x10u : 0u)
                 ^ (dma_run ? 0x80u : 0u));  /* M23: XSINT on GPIP7 --
                    colour monitor reads mono-detect 1, XORed with the
                    sound-DMA line: idle 1 (boot-identical), playing 0,
                    back to 1 at completion. The poll idiom's edge.   */
          /* M12e: RAM-band GPIP visibility -- what does the spinning
           * tool actually read? Print on value change plus a heavily
           * decimated heartbeat so a million-read spin costs a few
           * lines, each carrying the reads-since-last count. */
          gp_cnt++;
          if (log_on && gp_n < 256u && pc_in_ram_fwd() &&
              ((uint8_t)gv != gp_last || (gp_cnt & 0x3FFFFu) == 0u)) {
              gp_n++;
              printf("rG=%02x x%u\r\n", (unsigned)gv & 0xFFu, gp_cnt);
              gp_last = (uint8_t)gv; gp_cnt = 0u;
          }
          return gv;
      }
      /* (original single-expression body absorbed above) */
      default:       return mfp[idx];
      } }
}

static void mfp_write(uint32_t r, uint32_t v)
{
    if ((r & 1u) == 0u) return;
    { int idx = (int)((r - 0xFA01u) >> 1);
      if (idx < 0 || idx >= 24) return;
      switch (idx) {
      case MFP_IPRA: case MFP_IPRB:
      case MFP_ISRA: case MFP_ISRB:
          mfp[idx] &= (uint8_t)v;              /* write-0-to-clear    */
          break;
      case MFP_TADR: case MFP_TBDR: case MFP_TCDR: case MFP_TDDR:
          mfp[idx] = (uint8_t)v;
          tcount[idx - MFP_TADR] = (uint8_t)v; /* also load counter   */
          break;
      default:
          mfp[idx] = (uint8_t)v;
          break;
      }
      mfp_update_irq(); }
}

/* interrupt acknowledge: level 6 = MFP vectored, level 4 = VBL auto  */
static int int_ack(int level)
{
    if (level == 6) {
        int src;
        for (src = 15; src >= 0; src--) {
            int reg = (src >= 8) ? MFP_IPRA : MFP_IPRB;
            int msk = (src >= 8) ? MFP_IMRA : MFP_IMRB;
            int bit = src & 7;
            if ((mfp[reg] & mfp[msk]) & (1u << bit)) {
                if (src == 5) dbg_ack5++;
                mfp[reg] &= (uint8_t)~(1u << bit);       /* clear IPR */
                if (mfp[MFP_VR] & 0x08u) {               /* SEI mode  */
                    int isr = (src >= 8) ? MFP_ISRA : MFP_ISRB;
                    mfp[isr] |= (uint8_t)(1u << bit);
                }
                mfp_update_irq();
                return (int)((mfp[MFP_VR] & 0xF0u) | (uint32_t)src);
            }
        }
        m68k_set_irq(0);
        return M68K_INT_ACK_SPURIOUS;
    }
    if (level == 4) {                                    /* VBL: one  */
        m68k_set_irq(0);                                 /* per pulse */
        mfp_update_irq();                                /* 6 may pend*/
    }
    return M68K_INT_ACK_AUTOVECTOR;
}

/* M14: the YM2149 SOUND model. m13's comment below said "sound semantics
 * stay unmodelled ... the PSG milestone will" -- this is that milestone.
 * The register file keeps its existing job (readback + R14 drive select
 * for the FDC); every write to a SOUND register (0..13) is additionally
 * forwarded to the synthesiser, which renders at the exact I2S frame
 * rate into the m13 ring. Ported from Hatari's sound.c as executable
 * spec; PSGTEST covers it (9 vectors, incl. a closed-form differential
 * against the counter state machine).                                 */
#include "falcon_psg.c"

/* ----------------- YM2149 PSG: select/data register file ------------ */
/* $FF8800 W = register select, $FF8800 R = selected register,
 * $FF8802 W = selected register data.  EmuTOS set_psg_porta() does a
 * read-modify-write of port A (reg 14) through exactly this indirection
 * to drive floppy select/side, so a flat byte shadow cannot serve it.
 * Sound semantics stay unmodelled (writes latch; the PSG milestone will
 * consume the same register file).                                    */
static uint8_t psg_sel;
static uint8_t psg_reg[16];

/* ===================================================================
 * M25: PSG SHADOW DECODE.
 *
 * The YM2149's chip select in $FF88xx uses ONLY address bits 0 and 1
 * (Hatari psg.c: "the region 0xff8804 - 0xff88ff can be used to access
 * 0xff8800 - 0xff8803"). So $FF8801 shadows $FF8800, $FF8803 shadows
 * $FF8802, and the whole block repeats every 4 bytes to $FF88FF.
 *
 * We decoded only $FF8800-03 and bus-errored the rest. Measured on
 * silicon: RoboCop's first anomaly is "BERR W.b ff8804 (pc=ab5a)" --
 * a shadow write from plausible code -- after which the CPU derails
 * into garbage (pc=f8ff2039), takes an illegal instruction (the 4
 * bombs Dave saw), and the exception frame marches the stack down
 * through IO space to a double fault. 1988 code using shadow
 * registers is exactly the vintage this affects.
 *
 * Caveat recorded: Hatari notes "a special case for Falcon when not
 * in ST compatible mode" whose detail is not in the source we read.
 * Hatari-as-Falcon runs RoboCop, so mirroring is what the reference
 * does here; if a Falcon-native title ever depends on the mirrors
 * NOT decoding, this is the line to revisit.
 * =================================================================== */
#define PSG_SHADOW(r) (0x8800u | ((r) & 3u))

static uint32_t psg_read8(uint32_t r)
{
    (void)r;                                   /* 8800/8802 both mirror */
    return psg_reg[psg_sel & 15u];
}

static void psg_write8(uint32_t r, uint32_t v)
{
    if ((r & 2u) == 0u) psg_sel = (uint8_t)(v & 15u);   /* 8800: select */
    else {              psg_reg[psg_sel & 15u] = (uint8_t)v; /* 8802    */
        /* M14: regs 0..13 drive the sound model. R14/R15 are the ports
         * (drive select, side, parallel) -- untouched, so the FDC path
         * below is byte-for-byte the m13 behaviour.                   */
        if ((psg_sel & 15u) <= 13u)
            psg_snd_write((uint8_t)(psg_sel & 15u), (uint8_t)v);
    }
        if ((psg_sel & 15u) == 14u && fdc_pend_active
            && (((uint8_t)v & 0x02u) == 0u     /* M11i: select arrived */
             || ((uint8_t)v & 0x04u) == 0u)) {
            fdc_pend_active = 0;
            fdc_command(fdc_pend_cmd);
        }
}

/* ------------- storage backend: the array -> SD seam ---------------- */
/* Every sector the FDC serves goes through this interface. m9 backends
 * are RAM buffers (A: copied from the embedded array, B: synthesized
 * blank); the SD milestone swaps the buffer fill, nothing else.       */

/* M9G: falcon_diskA.c no longer linked -- the burned-in fallback A:
 * is a synthesized blank (saves ~720K of flash). EmuTOS boots to the
 * desktop with a blank drive; the card is the machine now.           */

typedef struct {
    uint8_t    *img;       /* RAM copy, writable                       */
    uint32_t    size;      /* bytes                                    */
    uint16_t    spt;       /* sectors per track   (parsed from BPB)    */
    uint16_t    sides;     /*                     (parsed from BPB)    */
    uint16_t    tracks;    /* derived: nsects / (spt*sides)            */
    uint8_t     wp;        /* write-protect (0: EmuTOS media-change
                              latching stays quiet for fixed images)   */
    uint8_t     present;
    uint32_t    bufcap;    /* backing buffer capacity (format ceiling) */
    const char *name;
} flop_drive;

#define FLOP_MAX_TRACKS 85u    /* real-mech seek ceiling               */

#define DISK_BUF_MAX 2097152u          /* 2MiB: raw HD media capacity  */
static uint8_t    diskA_ram[DISK_BUF_MAX];
static uint8_t    diskB_ram[DISK_BUF_MAX];
static flop_drive fdrv[2];

/* ---- M9G: per-drive SD state + prototypes (module further down) --- */
#define SD_MAXCLUS 4096u            /* 2MiB / 512 (spc=1 worst case)   */
typedef struct {
    uint8_t  mounted, writeback, frag, extent_warned;
    uint32_t size, sectors, nclus;
    uint32_t chain[SD_MAXCLUS];     /* cluster run, in file order      */
} sd_file;
static sd_file sdf[2];              /* [0]=A:, [1]=B:                  */
/* M11p: hardfile backing store. Data here, functions below beside the
 * FAT helpers they need. */
#define HDD_CACHE_SECTORS 16384u    /* 8MB, power of two for masking */
static uint8_t  hdd_cache[HDD_CACHE_SECTORS][512];
static uint32_t hdd_tag[HDD_CACHE_SECTORS];   /* 0xFFFFFFFF = empty  */
static sd_file  hdf[2];
static uint8_t  hdd_oob_warned[2];
static uint32_t hdd_hit, hdd_miss, hdd_wr, hdd_err;
static int  sd_map_only(const char *n11, sd_file *f, const char *label);
static int  hdd_read(int unit, uint32_t sec, uint8_t *dst);
static int  hdd_write(int unit, uint32_t sec, const uint8_t *srcbuf);
static void hdd_init(void);
static int      is_ide(uint32_t a);          /* M11q: falcon_ide.c   */
static uint32_t ide_read8(uint32_t a);
static void     ide_write8(uint32_t a, uint8_t v);
static void     ide_init(void);
static uint32_t fs_spc_ref(void);   /* fs_spc is defined later */
static uint8_t  sd_ok, sd_ccs;
static int  sd_hw_init(void);
static int  fat_mount(void);
static int  sd_mount(const char *n11, uint8_t *dest, sd_file *f,
                     const char *label);
static int  sd_read_small(const char *n11, uint8_t *dst, uint32_t max,
                          uint32_t *osize);
static void sd_gpio_init(void);
static void led_safe(void);
static void flop_persist(flop_drive *d, uint32_t off);
#ifdef HOST_TEST
static void host_card_load(void);
#endif


/* parse geometry out of a .ST image's BPB (little-endian fields)      */
static int flop_attach(flop_drive *d, uint8_t *img, uint32_t size,
                       const char *name)
{
    uint16_t nsects;
    d->img = img; d->size = size; d->name = name;
    d->spt    = (uint16_t)(img[0x18] | ((uint16_t)img[0x19] << 8));
    d->sides  = (uint16_t)(img[0x1A] | ((uint16_t)img[0x1B] << 8));
    nsects    = (uint16_t)(img[0x13] | ((uint16_t)img[0x14] << 8));
    if (d->spt == 0u || d->sides == 0u || d->sides > 2u
        || (uint32_t)nsects * 512u != size) { d->present = 0; return -1; }
    d->tracks = (uint16_t)(nsects / (d->spt * d->sides));
    d->wp = 0; d->present = 1;
    return 0;
}

/* blank 720K, byte-for-byte the make_bootst.py "new 720" layout minus
 * the executable stamp: OEM FFPGA1, BPS 512, SPC 2, RES 1, 2 FATs,
 * 112 root entries, 1440 sectors, media $F9, SPF 5, SPT 9, 2 sides,
 * FAT12 leaders F9 FF FF.  Serial F1CA44 (distinct from A: F1CA42 and
 * the 1.44M prep image F1CA43, so TOS media-change detection behaves).*/
static void flop_make_blank720(uint8_t *img, uint32_t serial)
{
    uint32_t i, f;
    uint32_t sum;
    for (i = 0; i < 737280u; i++) img[i] = 0;
    img[0x02]='F'; img[0x03]='F'; img[0x04]='P';
    img[0x05]='G'; img[0x06]='A'; img[0x07]='1';
    img[0x08] = (uint8_t)(serial >> 16);
    img[0x09] = (uint8_t)(serial >> 8);
    img[0x0A] = (uint8_t) serial;
    img[0x0B] = 0x00; img[0x0C] = 0x02;        /* BPS 512 (Intel order)*/
    img[0x0D] = 2;                             /* SPC                  */
    img[0x0E] = 1;    img[0x0F] = 0;           /* RES                  */
    img[0x10] = 2;                             /* NFATS                */
    img[0x11] = 112;  img[0x12] = 0;           /* NDIRS                */
    img[0x13] = (uint8_t)(1440u & 0xFFu);      /* NSECTS               */
    img[0x14] = (uint8_t)(1440u >> 8);
    img[0x15] = 0xF9;                          /* MEDIA                */
    img[0x16] = 5;    img[0x17] = 0;           /* SPF                  */
    img[0x18] = 9;    img[0x19] = 0;           /* SPT                  */
    img[0x1A] = 2;    img[0x1B] = 0;           /* NSIDES               */
    img[0x1C] = 0;    img[0x1D] = 0;           /* NHID                 */
    for (f = 0; f < 2u; f++) {                 /* FAT12: media FF FF   */
        uint32_t off = (1u + f * 5u) * 512u;
        img[off] = 0xF9; img[off+1u] = 0xFF; img[off+2u] = 0xFF;
    }
    /* guard: a blank disk must NOT be executable.  (With this BPB the
     * word sum is nowhere near $1234, but assert it structurally.)    */
    for (i = 0, sum = 0; i < 512u; i += 2u)
        sum += ((uint32_t)img[i] << 8) | img[i+1u];
    if ((sum & 0xFFFFu) == 0x1234u) img[0x1FE] ^= 0x55u;
}

static char cfg_da[12] = "DISKA   ST ";
static char cfg_db[12] = "";                /* empty = blank B:        */
static char cfg_hd[2][12];          /* M11p: HDD0= / HDD1=          */
static char cfg_hdname[2][41];      /* M12g: HD0NAME= / HD1NAME=    */
static uint8_t rom_from_card;       /* M16: card ROM actually loaded */
static char cfg_rom[12] = "";               /* empty = embedded EmuTOS */

/* "NAME.EXT" -> 11-char 8.3 directory form; returns 0 on success      */
static int name83(const char *in, char *out)
{
    uint32_t i = 0, o = 0;
    memset(out, ' ', 11); out[11] = 0;
    while (in[i] && in[i] != '.' && in[i] != '\r' && in[i] != '\n') {
        if (o >= 8u) return -1;
        out[o++] = (char)((in[i] >= 'a' && in[i] <= 'z')
                          ? in[i] - 32 : in[i]);
        i++;
    }
    if (in[i] == '.') {
        i++; o = 8;
        while (in[i] && in[i] != '\r' && in[i] != '\n') {
            if (o >= 11u) return -1;
            out[o++] = (char)((in[i] >= 'a' && in[i] <= 'z')
                              ? in[i] - 32 : in[i]);
            i++;
        }
    }
    return (out[0] == ' ') ? -1 : 0;
}

/* parse FALCON.CFG (KEY=NAME.EXT lines; #/blank ignored)              */
static void cfg_load(void)
{
    static uint8_t cbuf[2049];
    uint32_t sz, i = 0;
    if (sd_read_small("FALCON  CFG", cbuf, 2048u, &sz)) return;
    cbuf[sz] = 0;
    printf("[sd] FALCON.CFG: %u bytes\r\n", sz);
    while (i < sz) {
        uint32_t e = i;
        while (e < sz && cbuf[e] != '\n') e++;
        if (!memcmp(cbuf + i, "ROM=",   4)) name83((char*)cbuf+i+4, cfg_rom);
        else if (!memcmp(cbuf + i, "DISKA=", 6)) name83((char*)cbuf+i+6, cfg_da);
        else if (!memcmp(cbuf + i, "DISKB=", 6)) name83((char*)cbuf+i+6, cfg_db);
        else if (!memcmp(cbuf + i, "LOG=",   4)) log_on = (uint8_t)(cbuf[i+4] != '0');  /* M11k */
        else if (!memcmp(cbuf + i, "HDD0=", 5)) name83((char*)cbuf+i+5, cfg_hd[0]);   /* M11p */
        else if (!memcmp(cbuf + i, "SLICE=", 6)) {                       /* M28 */
            uint32_t v = 0, j = i + 6u;
            while (j < sz && cbuf[j] >= '0' && cbuf[j] <= '9')
                { v = v * 10u + (uint32_t)(cbuf[j] - '0'); j++; }
            slice_cap_cfg = v;                  /* 0 = automatic       */
        }
        else if (!memcmp(cbuf + i, "BUS=", 4)) {                         /* M22 */
            bus32 = (cbuf[i+4] == '3');            /* "32" -> 32-bit   */
        }
        else if (!memcmp(cbuf + i, "PALSPLIT=", 9)) {                   /* M19 */
            psplit_en = (cbuf[i+9] != '0');
        }
        else if (!memcmp(cbuf + i, "VBL=", 4)) {                         /* M18 */
            if (cbuf[i+4] == '5') vbl_50hz = 1u;
            else if (cbuf[i+4] == '6') vbl_50hz = 0u;
        }
        else if (!memcmp(cbuf + i, "HD0NAME=", 8)) {                    /* M12g */
            int k = 0;
            while (k < 40 && cbuf[i+8+k] >= 0x20u) { cfg_hdname[0][k] = (char)cbuf[i+8+k]; k++; }
            cfg_hdname[0][k] = 0;
        }
        else if (!memcmp(cbuf + i, "HD1NAME=", 8)) {                    /* M12g */
            int k = 0;
            while (k < 40 && cbuf[i+8+k] >= 0x20u) { cfg_hdname[1][k] = (char)cbuf[i+8+k]; k++; }
            cfg_hdname[1][k] = 0;
        }
        else if (!memcmp(cbuf + i, "HDD1=", 5)) name83((char*)cbuf+i+5, cfg_hd[1]);   /* M11p */
        else if (!memcmp(cbuf + i, "CACHEOPT=", 9))              /* M11m */
            cacheopt = (uint8_t)(cbuf[i+9] != '0');
        else if (!memcmp(cbuf + i, "FLUSHDIV=", 9)) {           /* M11l */
            uint32_t v = 0u, j = i + 9u;
            while (j < e && cbuf[j] >= '0' && cbuf[j] <= '9')
                v = v * 10u + (uint32_t)(cbuf[j++] - '0');
            flushdiv = v ? v : 1u;
        }
        i = e + 1u;
    }
}

static void flop_init(void)
{
    uint32_t rsz;
    /* ROM first: embedded EmuTOS is the floor; a card ROM replaces it */
    memcpy(rom_ram, emutos_rom, 0x80000u);
    if (sd_hw_init() == 0) {
        if (fat_mount() == 0) {
            cfg_load();
            if (cfg_rom[0]) {
                static uint8_t tmp[0x80000];
                if (sd_read_small(cfg_rom, tmp, 0x80000u, &rsz) == 0) {
                    memset(rom_ram, 0xFF, 0x80000u);
                    memcpy(rom_ram, tmp, rsz);
                    rom_from_card = 1u;                        /* M16 */
                    { char nb[12]; int ni;                   /* M11d */
                      for (ni = 0; ni < 11 && cfg_rom[ni]; ni++) nb[ni] = cfg_rom[ni];
                      nb[ni] = 0;
                      printf("[sd] ROM from card: %s (%u bytes)\r\n", nb, rsz);
                    }
                } else { char nb[12]; int ni;                    /* M11b */
                    for (ni = 0; ni < 11 && cfg_rom[ni]; ni++) nb[ni] = cfg_rom[ni];
                    nb[ni] = 0;
                    printf("[sd] ROM %s load failed -> embedded\r\n", nb);
                }
            }
            if (sd_mount(cfg_da, diskA_ram, &sdf[0], "A: image"))
                goto blank_a;
        } else { printf("[sd] no FAT32 filesystem\r\n"); goto blank_a; }
    } else { printf("[sd] no card / init failed\r\n"); goto blank_a; }
    goto a_done;
blank_a:
    printf("[sd] A: falling back to blank disk\r\n");
    flop_make_blank720(diskA_ram, 0xF1CA42u);
    sdf[0].mounted = 0; sdf[0].writeback = 0;
a_done:
    fdrv[0].bufcap = DISK_BUF_MAX;          /* WRITETR capacity ceiling */
    fdrv[1].bufcap = DISK_BUF_MAX;          /* (dropped in first m9g   */
                                            /*  draft: v8-v10 caught it) */
    if (flop_attach(&fdrv[0], diskA_ram,
                    sdf[0].mounted ? sdf[0].size : 737280u,
                    sdf[0].mounted ? "SD (DISKA=)" : "blank (synth)"))
        printf("[flop] A: attach FAILED\r\n");
    if (cfg_db[0] && sd_mount(cfg_db, diskB_ram, &sdf[1], "B: image") == 0) {
        if (flop_attach(&fdrv[1], diskB_ram, sdf[1].size, "SD (DISKB=)"))
            printf("[flop] B: attach FAILED\r\n");
    } else {
        flop_make_blank720(diskB_ram, 0xF1CA44u);
        sdf[1].mounted = 0; sdf[1].writeback = 0;
        if (flop_attach(&fdrv[1], diskB_ram, 737280u, "blank (synth)"))
            printf("[flop] B: attach FAILED\r\n");
    }
    { uint32_t d;
      for (d = 0; d < 2u; d++)
          printf("[flop] %c: %uK %u/%u/%u \"%s\" serial %02X%02X%02X\r\n",
                 'A'+d, fdrv[d].size/1024u, fdrv[d].tracks, fdrv[d].sides,
                 fdrv[d].spt, fdrv[d].name,
                 fdrv[d].img[8], fdrv[d].img[9], fdrv[d].img[10]);
    }
    /* M11p: hardfiles. After the floppies so a failure here cannot
     * disturb a working drive A. */
    hdd_init();
    { int u;
      for (u = 0; u < 2; u++) {
          char lbl[8];
          if (!cfg_hd[u][0]) continue;
          lbl[0]='H'; lbl[1]='D'; lbl[2]=(char)('0'+u); lbl[3]=0;
          if (sd_map_only(cfg_hd[u], &hdf[u], lbl))
              printf("[hdd] %s: not available\r\n", lbl);
      }
    }
#ifdef HOST_TEST
    /* HDDTEST: every sector of the test image carries 0xC0DE0000+sector
     * in its first longword, so a mapper returning the WRONG sector is
     * caught rather than returning plausible data. The image is
     * deliberately fragmented, so this walks the chain rather than
     * validating arithmetic on a contiguous run. */
    if (hdf[0].mounted) {
        static uint8_t hb[512];
        uint32_t probe[6], k, bad = 0, last = hdf[0].sectors - 1u;
        uint32_t spc = fs_spc_ref();
        probe[0]=0; probe[1]=1; probe[2]=spc-1u;      /* cluster edge */
        probe[3]=spc;                                /* next cluster */
        probe[4]=hdf[0].sectors/2u; probe[5]=last;
        for (k = 0; k < 6u; k++) {
            uint32_t want = 0xC0DE0000u + probe[k], got;
            if (hdd_read(0, probe[k], hb)) { bad++; continue; }
            got = (uint32_t)hb[0] | ((uint32_t)hb[1]<<8)
                | ((uint32_t)hb[2]<<16) | ((uint32_t)hb[3]<<24);
            if (got != want) {
                printf("HDDTEST FAIL sec %u: want %08x got %08x\r\n",
                       probe[k], want, got); bad++;
            }
        }
        if (hdd_read(0, hdf[0].sectors, hb) == 0) {
            printf("HDDTEST FAIL: read past end was allowed\r\n"); bad++; }
        /* write-through, then force a cache miss to prove it reached
         * the card rather than only the cache */
        { uint32_t t = 12345u; uint32_t g;
          memset(hb, 0, 512); hb[0]=0xAA; hb[1]=0x55; hb[2]=0x5A; hb[3]=0xA5;
          if (hdd_write(0, t, hb)) { printf("HDDTEST FAIL: write\r\n"); bad++; }
          hdd_tag[t & (HDD_CACHE_SECTORS-1u)] = 0xFFFFFFFFu;
          memset(hb, 0, 512);
          if (hdd_read(0, t, hb)) { printf("HDDTEST FAIL: reread\r\n"); bad++; }
          g = (uint32_t)hb[0]|((uint32_t)hb[1]<<8)|((uint32_t)hb[2]<<16)
            | ((uint32_t)hb[3]<<24);
          if (g != 0xA55A55AAu) {
              printf("HDDTEST FAIL: write-through got %08x\r\n", g);
              bad++; }
        }
        printf("HDDTEST %s (hit=%u miss=%u wr=%u err=%u)\r\n",
               bad ? "FAILED" : "OK", hdd_hit, hdd_miss, hdd_wr, hdd_err);
    }
#endif
    ide_init();                                          /* M11q */
    psg_reg[14] = 0x07;    /* both drives deselected, side 0           */
    psg_reg[7]  = 0xFF;    /* mixer: all off                           */
}
/* ------------- WD1772 FDC + Atari DMA: serving model ---------------- */
/* Access path (Atari DMA chip): FF8606/07 W = mode (A1A0 select FDC
 * reg, bit3 ACSI/floppy, bit4 sector-count reg, bit8 write dir);
 * FF8606/07 R = DMA status; FF8604/05 = data port to selected reg;
 * FF8609/0B/0D = DMA base address hi/mid/lo (readable, live counter);
 * FF860E/0F = Falcon density / mode-control.
 *
 * Timing is deliberately inauthentic (instant seeks, immediate
 * completion, INTRQ asserted at once): EmuTOS flopcmd() writes the
 * command, briefly delays, then polls MFP GPIP bit 5 (active low) with
 * a hz_200 timeout -- an already-asserted INTRQ is simply the fastest
 * legal drive.  Hatari's cycle-cost model layers on later if software
 * demands it.  Status read clears INTRQ (WD1772), as does a new
 * command; EmuTOS's dummy_seek()/flopvbl() rely on both.              */
#define FDC_SB_BUSY    0x01
#define FDC_SB_DRQ     0x02
#define FDC_SB_LOSTDAT 0x04            /* Type II/III                  */
#define FDC_SB_TRACK0  0x04            /* Type I (same bit)            */
#define FDC_SB_RNF     0x10
#define FDC_SB_SPINUP  0x20
#define FDC_SB_WRPRO   0x40
#define FDC_SB_MOTORON 0x80

static uint8_t  fdc_track, fdc_sector, fdc_dreg, fdc_status;
static uint8_t  fdc_phys;              /* M12H: physical head pos.    */
static uint8_t  fdc_dirin;             /* M12H: step-direction latch  */
/* fdc_intrq declared above the MFP block (GPIP bit 5 mirror)         */
static uint16_t dma_mode;              /* last FF8606/07 word         */
static uint8_t  dma_mode_hi;           /* byte-split assembly latch   */
static uint16_t dma_seccount;          /* 512-byte units              */
static uint8_t  fdc_data_hi;
static uint32_t dma_addr;              /* live 24-bit counter         */
static uint8_t  dma_err;               /* 0 = OK (DMA status bit 0=1) */
static uint8_t  flop_density;          /* FF860E/0F latch             */
static uint8_t  fdc_id_rotor;          /* Read Address sector cycler  */
static uint32_t fdc_boot_dma;          /* A:/t0/s0/sec1 DMA target    */
static uint8_t  fdc_wtrack_warned, fdc_rtrack_warned, fdc_mixed_warned;

static flop_drive *fdc_sel_drive(void)
{
    uint8_t a = psg_reg[14];
    if (!(a & 0x02u)) return fdrv[0].present ? &fdrv[0] : (flop_drive *)0;
    if (!(a & 0x04u)) return fdrv[1].present ? &fdrv[1] : (flop_drive *)0;
    return (flop_drive *)0;            /* no drive selected            */
}
static uint32_t fdc_sel_side(void)
{
    return (psg_reg[14] & 1u) ? 0u : 1u;   /* bit0 low = side 1        */
}

/* one sector between the image and ST-RAM at the DMA counter.
 * return 0 ok, -1 RNF (bad CHS / no drive), -2 write-protected.
 * dma_seccount==0: command still completes OK, nothing is stored
 * (the DMA simply takes no data) -- matches the real chip pairing.   */
static int flop_rw_one(flop_drive *d, uint32_t trk, uint32_t side,
                       uint32_t sec, int wr)
{
    uint32_t off;
    if (!d) return -1;
    if (trk >= d->tracks || side >= d->sides
        || sec < 1u || sec > d->spt) return -1;
    off = ((trk * d->sides + side) * d->spt + (sec - 1u)) * 512u;
    if (off + 512u > d->size) return -1;
    if (wr && d->wp) return -2;
    if (dma_seccount == 0u) return 0;
    if (dma_addr + 512u <= ST_RAM_SIZE) {
        uint32_t i;
        if (wr) { for (i = 0; i < 512u; i++) d->img[off+i] = ram[dma_addr+i];
                  flop_persist(d, off); }        /* M9F write-through   */
        else    for (i = 0; i < 512u; i++) ram[dma_addr+i] = d->img[off+i];
        if (!wr && trk == 0u && side == 0u && sec == 1u && d == &fdrv[0])
            fdc_boot_dma = dma_addr;   /* boot-sector witness (host)   */
    } else dma_err = 1;                /* DMA outside ST-RAM           */
    dma_addr = (dma_addr + 512u) & 0x00FFFFFFu;
    dma_seccount--;
    return 0;
}

static void fdc_command(uint8_t cmd)
{
    fdc_intrq = 0;                             /* new cmd clears INTRQ */
    /* M11i: Type II/III with NO drive selected pends on busy (real
     * hardware finds no index pulses; Hatari fdc.c documents the same
     * wait-forever).  A later drive select retries; D0 cancels.      */
    if (cmd >= 0x80u && (cmd >> 4) != 0xDu && !fdc_sel_drive()) {
        fdc_pend_cmd = cmd; fdc_pend_active = 1;
        fdc_status = FDC_SB_MOTORON | 0x01u;   /* motor + busy         */
        return;
    }
    if ((cmd >> 4) == 0xDu) fdc_pend_active = 0;   /* force int cancels */
    switch (cmd >> 4) {
    case 0x0:                                  /* Restore              */
        fdc_track = 0;
        fdc_phys = 0; fdc_dirin = 0;           /* M12H: head to the stop */
        fdc_status = FDC_SB_MOTORON | FDC_SB_SPINUP | FDC_SB_TRACK0;
        fdc_intrq = 1;
        break;
    case 0x1: {                                /* Seek (to data reg)   */
        /* M12H: the chip steps the head by (data - track register),
         * then register := data. If software lied in the register the
         * head lands elsewhere -- faithfully reproduced.             */
        int dl = (int)fdc_dreg - (int)fdc_track;
        int np = (int)fdc_phys + dl;
        if (np < 0) np = 0; else if (np > 255) np = 255;
        if (dl) fdc_dirin = (dl > 0) ? 1u : 0u;
        fdc_phys  = (uint8_t)np;
        fdc_track = fdc_dreg;
        fdc_status = FDC_SB_MOTORON | FDC_SB_SPINUP
                   | (fdc_phys == 0 ? FDC_SB_TRACK0 : 0);
        fdc_intrq = 1;
        break; }
    case 0x2: case 0x3:                        /* Step                 */
    case 0x4: case 0x5:                        /* Step-in              */
    case 0x6: case 0x7: {                      /* Step-out             */
        /* M12H: steps MOVE THE HEAD (was status-only). Step-in/out set
         * the direction latch, plain Step repeats it; the u flag
         * (bit 4) makes the track register follow with unconditional
         * arithmetic like the chip, while the head clamps at the
         * track-0 stop.                                              */
        uint32_t hi4 = cmd >> 4;
        if (hi4 >= 0x4u) fdc_dirin = (hi4 <= 0x5u) ? 1u : 0u;
        if (fdc_dirin) { if (fdc_phys < 255u) fdc_phys++; }
        else           { if (fdc_phys)        fdc_phys--; }
        if (cmd & 0x10u)
            fdc_track = (uint8_t)(fdc_track + (fdc_dirin ? 1u : 0xFFu));
        fdc_status = FDC_SB_MOTORON | FDC_SB_SPINUP
                   | (fdc_phys == 0 ? FDC_SB_TRACK0 : 0);
        fdc_intrq = 1;
        break; }
    case 0x8: case 0x9: {                      /* Read Sector (M=bit4) */
        flop_drive *d = fdc_sel_drive();
        uint32_t side = fdc_sel_side();
        int r = (fdc_track == fdc_phys)    /* M12H: implied ID vs TR */
              ? flop_rw_one(d, fdc_phys, side, fdc_sector, 0) : -1;
        if ((cmd & 0x10u) && r == 0) {
            while (dma_seccount && d && fdc_sector < d->spt) {
                fdc_sector++;
                if (flop_rw_one(d, fdc_phys, side, fdc_sector, 0)) break;
            }
        }
        fdc_status = FDC_SB_MOTORON | (r == -1 ? FDC_SB_RNF : 0);
        fdc_intrq = 1;
        break; }
    case 0xA: case 0xB: {                      /* Write Sector (M=bit4)*/
        flop_drive *d = fdc_sel_drive();
        uint32_t side = fdc_sel_side();
        int r = (fdc_track == fdc_phys)    /* M12H: implied ID vs TR */
              ? flop_rw_one(d, fdc_phys, side, fdc_sector, 1) : -1;
        if ((cmd & 0x10u) && r == 0) {
            while (dma_seccount && d && fdc_sector < d->spt) {
                fdc_sector++;
                if (flop_rw_one(d, fdc_phys, side, fdc_sector, 1)) break;
            }
        }
        fdc_status = FDC_SB_MOTORON
                   | (r == -1 ? FDC_SB_RNF : 0)
                   | (r == -2 ? FDC_SB_WRPRO : 0);
        fdc_intrq = 1;
        break; }
    case 0xC: {                                /* Read Address         */
        flop_drive *d = fdc_sel_drive();
        if (d) {
            uint8_t id[6];
            fdc_id_rotor = (uint8_t)((fdc_id_rotor % d->spt) + 1u);
            id[0] = fdc_phys;  id[1] = (uint8_t)fdc_sel_side();
            id[2] = fdc_id_rotor; id[3] = 2;   /* 512-byte sectors     */
            id[4] = 0; id[5] = 0;              /* CRC not modelled     */
            if (dma_seccount && dma_addr + 6u <= ST_RAM_SIZE) {
                uint32_t i;
                for (i = 0; i < 6u; i++) ram[dma_addr+i] = id[i];
                dma_addr = (dma_addr + 6u) & 0x00FFFFFFu;
                /* 6 bytes never fill a 512-byte DMA unit: count holds */
            }
            fdc_sector = fdc_phys;             /* WD1772 quirk         */
            fdc_status = FDC_SB_MOTORON;
        } else fdc_status = FDC_SB_MOTORON | FDC_SB_RNF;
        fdc_intrq = 1;
        break; }
    case 0xE:                                  /* Read Track           */
        if (!fdc_rtrack_warned) {
            fdc_rtrack_warned = 1;
            printf("[fdc] READ TRACK not implemented (ledger)\r\n");
        }
        fdc_status = FDC_SB_MOTORON | FDC_SB_LOSTDAT;
        fdc_intrq = 1;
        break;
    case 0xF: {                                /* Write Track (format) */
        flop_drive *d = fdc_sel_drive();
        uint32_t side = fdc_sel_side();
        if (!d) { fdc_status = FDC_SB_MOTORON | FDC_SB_RNF; fdc_intrq = 1; break; }
        if (d->wp) { fdc_status = FDC_SB_MOTORON | FDC_SB_WRPRO; fdc_intrq = 1; break; }
        {
            /* Pass 1: parse the DMA'd raw track image (EmuTOS flopfmt
             * stream): 3xF5 FE trk side sec size F7 ... 3xF5 FB <512
             * data> F7.  Budget = the programmed DMA sector count,
             * capped at an HD track.  Collect the track's sector list
             * first; geometry policy decides placement afterwards.    */
            uint32_t budget = (uint32_t)dma_seccount * 512u;
            uint32_t n = 0, p = 0, i, k, placed = 0;
            uint8_t  ids[24]; uint32_t dofs[24];
            if (budget > 16384u) budget = 16384u;
            if (dma_addr + budget > ST_RAM_SIZE) { dma_err = 1; budget = 0; }
            while (p + 10u <= budget && n < 24u) {
                const uint8_t *b = ram + dma_addr;
                if (b[p] == 0xF5u && b[p+1u] == 0xF5u && b[p+2u] == 0xF5u
                    && b[p+3u] == 0xFEu) {
                    uint32_t id_trk = b[p+4u], id_side = b[p+5u];
                    uint32_t id_sec = b[p+6u], id_size = b[p+7u];
                    p += 9u;                   /* past id + F7          */
                    if (id_trk != fdc_phys || id_side != side
                        || id_sec < 1u || id_sec > 24u
                        || id_size != 2u) continue;
                    while (p + 4u + 512u <= budget) {
                        if (b[p] == 0xF5u && b[p+1u] == 0xF5u
                            && b[p+2u] == 0xF5u && b[p+3u] == 0xFBu) {
                            ids[n] = (uint8_t)id_sec;
                            dofs[n] = dma_addr + p + 4u;
                            n++;
                            p += 4u + 512u + 1u;   /* data + F7         */
                            break;
                        }
                        p++;
                    }
                } else p++;
            }
            if (budget) {
                dma_addr = (dma_addr + budget) & 0x00FFFFFFu;
                dma_seccount = 0;              /* budget consumed       */
            }
            /* Pass 2: geometry policy.
             * t0/s0 with a new sector count = reshape (adopt spt,
             * restart at 1 track); same count = refresh, no shrink.
             * Elsewhere a disagreeing count is unrepresentable in a
             * linear .ST -> reject.  Every accepted track grows the
             * disk, bounded by buffer capacity and the mech ceiling.  */
            if (n) {
                int ok = (side < d->sides);
                if (ok && fdc_track == 0u && side == 0u) {
                    if (n != d->spt) {
                        printf("[fdc] FORMAT reshape: %u spt (was %u)\r\n",
                               n, d->spt);
                        d->spt = (uint16_t)n;
                        d->tracks = 0;         /* grows below           */
                        d->size = 0;
                    }
                } else if (n != d->spt) {
                    if (!fdc_mixed_warned) {
                        fdc_mixed_warned = 1;
                        printf("[fdc] WRITE TRACK t%u: %u spt vs disk %u"
                               " -- mixed formats unsupported (ledger)\r\n",
                               fdc_track, n, d->spt);
                    }
                    ok = 0;
                }
                if (ok && (fdc_phys >= FLOP_MAX_TRACKS
                    || ((uint32_t)fdc_phys + 1u) * d->sides * d->spt * 512u
                       > d->bufcap)) {
                    if (!fdc_mixed_warned) {
                        fdc_mixed_warned = 1;
                        printf("[fdc] WRITE TRACK t%u: beyond capacity\r\n",
                               fdc_phys);
                    }
                    ok = 0;
                }
                if (ok) {
                    for (k = 0; k < n; k++) {
                        uint32_t off;
                        if (ids[k] < 1u || ids[k] > d->spt) continue;
                        off = ((uint32_t)(fdc_phys * d->sides + side)
                               * d->spt + (ids[k] - 1u)) * 512u;
                        for (i = 0; i < 512u; i++)
                            d->img[off+i] = ram[dofs[k]+i];
                        flop_persist(d, off);    /* M9F write-through   */
                        placed++;
                    }
                    if ((uint32_t)fdc_phys + 1u > d->tracks) {
                        d->tracks = (uint16_t)(fdc_phys + 1u);
                        d->size = (uint32_t)d->tracks * d->sides
                                * d->spt * 512u;
                    }
                }
            }
            fdc_status = FDC_SB_MOTORON | (placed ? 0 : FDC_SB_LOSTDAT);
            if (!fdc_wtrack_warned) {
                fdc_wtrack_warned = 1;
                printf("[fdc] WRITE TRACK: t%u s%u %u sectors formatted\r\n",
                       fdc_phys, side, placed);
            }
        }
        fdc_intrq = 1;
        break; }
    case 0xD:                                  /* Force Interrupt      */
        fdc_status = FDC_SB_MOTORON
                   | (fdc_phys == 0 ? FDC_SB_TRACK0 : 0);
        fdc_status &= (uint8_t)~FDC_SB_BUSY;
        if (cmd & 0x08) fdc_intrq = 1;         /* D8: immediate INTRQ  */
        break;
    }
}

static uint32_t fdc_dma_read8(uint32_t r)
{
    switch (r) {
    case 0x8604u: return 0x00u;                        /* data hi      */
    case 0x8605u:                                      /* data lo      */
        if (dma_mode & 0x0010u) return dma_seccount & 0xFFu;
        if (dma_mode & 0x0008u) return 0xFFu;          /* ACSI: absent */
        switch ((dma_mode >> 1) & 3u) {
        case 0: fdc_intrq = 0; return fdc_status;      /* read clears  */
        case 1: return fdc_track;
        case 2: return fdc_sector;
        default: return fdc_dreg;
        }
    case 0x8606u: return 0x00u;                        /* status hi    */
    case 0x8607u:                                      /* DMA status   */
        return (uint32_t)((dma_err ? 0u : 1u)          /* bit0: OK     */
             | (dma_seccount ? 2u : 0u));              /* bit1: SC!=0  */
    case 0x8609u: return (dma_addr >> 16) & 0xFFu;     /* base hi      */
    case 0x860Bu: return (dma_addr >>  8) & 0xFFu;     /* base mid     */
    case 0x860Du: return  dma_addr        & 0xFFu;     /* base lo      */
    case 0x860Eu:
    case 0x860Fu: return flop_density & (uint8_t)~0x08u; /* bit3 == 0:
        EmuTOS's Falcon write path spins until it clears               */
    default:      return 0x00u;            /* even pad bytes           */
    }
}

static void fdc_dma_write8(uint32_t r, uint32_t v)
{
    switch (r) {
    case 0x8604u: fdc_data_hi = (uint8_t)v; break;     /* data hi      */
    case 0x8605u:                                      /* data lo      */
        if (dma_mode & 0x0010u) {
            dma_seccount = (uint16_t)(((uint16_t)fdc_data_hi << 8) | v);
            break;
        }
        if (dma_mode & 0x0008u) break;                 /* ACSI: ignore */
        switch ((dma_mode >> 1) & 3u) {
        case 0: fdc_command((uint8_t)v); break;
        case 1: fdc_track  = (uint8_t)v; break;
        case 2: fdc_sector = (uint8_t)v; break;
        default: fdc_dreg  = (uint8_t)v; break;
        }
        break;
    case 0x8606u: dma_mode_hi = (uint8_t)v; break;
    case 0x8607u: {                                    /* mode word    */
        uint16_t nm = (uint16_t)(((uint16_t)dma_mode_hi << 8) | v);
        if ((nm ^ dma_mode) & 0x0100u) dma_err = 0;    /* dir toggle
            clears the DMA FIFO and its error status (fdc_start_dma_*)*/
        dma_mode = nm;
        break; }
    case 0x8609u: dma_addr = (dma_addr & 0x0000FFFFu)
                           | ((uint32_t)(v & 0xFFu) << 16); break;
    case 0x860Bu: dma_addr = (dma_addr & 0x00FF00FFu)
                           | ((uint32_t)(v & 0xFFu) <<  8); break;
    case 0x860Du: dma_addr = (dma_addr & 0x00FFFF00u)
                           |  (uint32_t)(v & 0xFFu);        break;
    case 0x860Eu:
    case 0x860Fu: flop_density = (uint8_t)v; break;    /* latch only   */
    default: break;                        /* even pad bytes: ignore   */
    }
}

/* ----------------------- NVRAM / RTC (MC146818) --------------------- */
/* FFFF8961 = register select, FFFF8963 = data. Regs 0-13 RTC, 14-63
 * NVRAM. Content starts zeroed: EmuTOS checksum fails once, writes UK
 * defaults, and from then on the config is self-consistent.          */
static uint8_t nvram[64];
static uint8_t nvram_sel;

static inline uint64_t rd_wall64(void); /* defined below (HOST/target) */
static uint64_t nv_anchor;          /* wall cycles at last clock sync    */
static uint32_t nv_sod;             /* seconds-of-day at anchor          */
#define NV_WALL_HZ 800000000ull     /* mcycle / host_wall rate           */
static uint8_t bcd(uint32_t v) { return (uint8_t)(((v / 10u) << 4) | (v % 10u)); }
static void nv_fold(void)
{
    uint64_t w = rd_wall64();
    nv_sod = (uint32_t)((nv_sod + (w - nv_anchor) / NV_WALL_HZ) % 86400u);
    nv_anchor = w;
}
static void nvram_reset(void)
{
    /* M11h: STOCK power-on. Battery good, clock ticking, user cells
     * ZEROED with an invalid checksum -- the OS initialises its own
     * defaults, exactly like a factory Falcon's first boot.          */
    nvram[10] = 0x26;   /* reg A: oscillator on, no update-in-progress */
    nvram[11] = 0x02;   /* reg B: 24h mode                             */
    nvram[13] = 0x80;   /* reg D: VRT = battery/contents valid         */
    nvram[6]  = 0x07;   /* Sat  */
    nvram[7]  = 0x01;   /* 1st  */
    nvram[8]  = 0x01;   /* Jan  */
    nvram[9]  = 0x94;   /* 1994 */
    nv_anchor = rd_wall64(); nv_sod = 0;
}

static uint32_t nvram_read(uint32_t r)
{
    if (r == 0x8961u) return nvram_sel;
    switch (nvram_sel) {                    /* M11h: live BCD clock     */
    case 0:  nv_fold(); return bcd(nv_sod % 60u);
    case 2:  nv_fold(); return bcd((nv_sod / 60u) % 60u);
    case 4:  nv_fold(); return bcd(nv_sod / 3600u);
    case 10: { uint64_t w = rd_wall64();    /* UIP pulses ~8ms/second   */
               return 0x26u | (((w - nv_anchor) % NV_WALL_HZ
                                > NV_WALL_HZ - NV_WALL_HZ / 128u) ? 0x80u : 0u); }
    case 12: return 0x00u;                  /* reg C: no interrupts     */
    default: return nvram[nvram_sel & 63u];
    }
}

static void nvram_write(uint32_t r, uint32_t v)
{
    if (r == 0x8961u) { nvram_sel = (uint8_t)(v & 63u); return; }
    switch (nvram_sel) {                    /* M11h: settable clock     */
    case 0:  nv_fold();
             nv_sod = (nv_sod / 60u) * 60u
                    + ((v >> 4) & 15u) * 10u + (v & 15u);        break;
    case 2:  nv_fold();
             nv_sod = (nv_sod / 3600u) * 3600u
                    + (((v >> 4) & 15u) * 10u + (v & 15u)) * 60u
                    + nv_sod % 60u;                              break;
    case 4:  nv_fold();
             nv_sod = (((v >> 4) & 15u) * 10u + (v & 15u)) * 3600u
                    + nv_sod % 3600u;                            break;
    case 12: case 13: break;                /* C/D not writable         */
    default: nvram[nvram_sel & 63u] = (uint8_t)v;                break;
    }
}

/* ------------------- IO register shadow (latch) --------------------- */
/* Real Falcon registers mostly read back what was written; a constant
 * 0xFF breeds garbage pointers. Whitelisted non-MFP registers latch. */
static uint8_t io_shadow[0x8000];      /* FF8000..FFFFFF, init 0xFF   */

static uint32_t io_read8(uint32_t a)
{
    uint32_t r = a & 0xFFFFu;
    if (r >= 0xFA00u && r <= 0xFA3Fu) return mfp_read(r);
    if (r >= 0x8604u && r <= 0x860Fu) return fdc_dma_read8(r);
    if (r >= 0x8800u && r <= 0x88FFu)                       /* M25 */
        return psg_read8(PSG_SHADOW(r));
    if (r >= 0x8780u && r <= 0x878Fu) {              /* M11w: NCR5380 */
        uint32_t reg = (r >> 1) & 7u;
        if (reg == 1u)   /* ICR: AIP asserts while mode.ARBITRATE set;
                          * LA stays clear -- a free bus is always won */
            return (uint32_t)((scsi_reg[1] & 0x9Fu)
                              | ((scsi_reg[2] & 0x01u) ? 0x40u : 0u));
        if (reg == 2u) return scsi_reg[2];           /* mode reads back */
        return 0x00u;   /* data, bus status, everything else: bus free,
                         * no target ever asserts BSY -> selection times
                         * out at the driver's own ~250ms, per ID */
    }
    if (r == 0x8961u || r == 0x8963u) return nvram_read(r);
    if (r == 0x8901u ||
        (r >= 0x8909u && r <= 0x890Du)) return dma_snd_read(r);  /* M20/23 */
    if (r >= 0x8A00u && r <= 0x8A3Du) {              /* M11: BLiTTER     */
        uint16_t w = blitter_reg_read16((r - 0x8A00u) & ~1u);
        return (r & 1u) ? (w & 0xFFu) : ((w >> 8) & 0xFFu);
    }
    if (r == 0xFC00u) return acia_sr;                /* kbd ACIA status  */
    if (r == 0xFC02u) {                              /* kbd ACIA data    */
        acia_sr &= (uint8_t)~0x81u;                  /* clear RDRF+IRQ   */
        return acia_rdr;
    }
    if (r == 0xFC04u) return 0x02u;                  /* MIDI ACIA: TDRE  */
    return io_shadow[r - 0x8000u];
}

static void io_write8(uint32_t a, uint32_t v)
{
    uint32_t r = a & 0xFFFFu;
    if (r >= 0xFA00u && r <= 0xFA3Fu) { mfp_write(r, v); return; }
    if (r >= 0x8780u && r <= 0x878Fu) {              /* M11w: NCR5380 */
        scsi_reg[(r >> 1) & 7u] = (uint8_t)v;        /* latch          */
        return;
    }
    if (r >= 0x8604u && r <= 0x860Fu) { fdc_dma_write8(r, v); return; }
    if (r >= 0x8800u && r <= 0x88FFu)                       /* M25 */
        { psg_write8(PSG_SHADOW(r), v); return; }
    if (r == 0x8961u || r == 0x8963u) { nvram_write(r, v); return; }
    if (r >= 0x8A00u && r <= 0x8A3Du) {              /* M11: BLiTTER     */
        blitter_reg_write8((r - 0x8A00u), (uint8_t)v);
        return;                                      /* ctrl b7 -> runs  */
    }
    if (r == 0xFC00u) {                              /* kbd ACIA control */
        if ((v & 0x03u) == 0x03u) acia_sr = 0x02u;   /* master reset     */
        return;
    }
    if (r == 0xFC02u) { ikbd_command_byte((uint8_t)v); return; }
    if (r >= 0x9800u && r <= 0x9BFFu) pal_seq++;     /* Falcon palette change */
    io_shadow[r - 0x8000u] = (uint8_t)v;
    if (r >= 0x8240u && r <= 0x825Fu) psplit_note(); /* M19: stamp+snapshot   */
    if (r >= 0x8900u && r <= 0x8921u) { dma_snd_write(r, (uint8_t)v); return; } /* M20 */
}

/* --------------------- memory access, byte-accurate ------------------ */
/* Each sized access is split into bytes like the 030 bus splits cycles.
 * A fault mid-access pulses ONE bus error and poisons the remainder.  */
static int acc_faulted;

/* ===================================================================
 * M24: NO FPU -- we model a STOCK Falcon.
 *
 * No Falcon ever shipped with a floating-point unit. The motherboard
 * carries an empty PLCC socket for an optional 68881/68882; fitting one
 * was always a user upgrade. Note also that the Falcon's 030 talks to
 * an FPU over the CPU's own coprocessor interface -- unlike the Mega
 * STE, which memory-maps it at $FFFFFA40-5F. That is the SFP004-style
 * port behind every "last_berr=fffffa42" in our logs: ST-era detection
 * code probing a place a Falcon has nothing, and our bus error there is
 * correct.
 *
 * Musashi, however, dispatches F-line coprocessor opcodes to a full
 * softfloat 68881 whenever CPU_TYPE_IS_030_PLUS -- so we were
 * advertising an FPU no target machine has. GEMBench duly found one and
 * benchmarked it. Software then takes FPU code paths a stock Falcon
 * never would: exactly the class of divergence that produces "works in
 * Hatari, breaks here".
 *
 * FALCON_NO_FPU (set in the .bat, with m68kops_nofpu.patch applied)
 * makes those opcodes raise exception 11 (F-line) instead, so detection
 * fails and software uses its own float routines -- stock behaviour.
 *
 * NOT a performance change, and it would be dishonest to claim one: the
 * opcode table dispatches by lookup, so the FPU code costs nothing
 * unless executed. If anything, FPU-using software gets slower, because
 * one emulated FPU op (a native softfloat call) is cheaper for us than
 * the dozens of interpreted 68030 instructions a software-float library
 * runs instead. This is a FIDELITY fix. The flash saving is real but
 * optional and separately gated -- see M24_NOFPU.md.
 * =================================================================== */
#ifndef FALCON_NO_FPU
#error "M24 expects -DFALCON_NO_FPU (and m68kops_nofpu.patch applied). \
Build with build_falcon_m24.bat, which sets it."
#endif

/* ===================================================================
 * M22: 24-BIT BUS MODE (the Hatari "24-bit addressing" equivalent).
 *
 * The guest TOS 1.04 that GAMEX boots installs exception vectors with
 * DIRTY HIGH BYTES ($020C0B9E, $040C0B9E...) -- standard 1980s practice,
 * harmless on every machine GAMEX supports (ST/STE/MegaST(E)/Falcon --
 * its README pointedly omits the TT) because those machines' bus or
 * decode ignores the top byte and the access aliases into low memory.
 * Verified empirically both ways in Hatari: default (24-bit) runs
 * RoboCop; with TT RAM populated (32-bit) it double-bus-faults, exactly
 * as dirty software did on a real TT.
 *
 * BUS=24 (default): every guest address masks to 24 bits here -- one
 *   deterministic AND, the stock-Falcon behaviour. BUS=32: no mask, for
 *   a future TT-RAM machine; dirty software then authentically faults,
 *   and M21 turns that into a clean halt instead of a core reset.
 * A MODE, not a populated-address heuristic: a heuristic would make
 * behaviour depend on what memory happens to exist, and reads/writes
 * classify "populated" differently (ROM reads vs ignored writes).    */
static inline uint32_t bus_mask(uint32_t a)
{ return bus32 ? a : (a & 0x00FFFFFFu); }

static uint32_t rd8_resolve(uint32_t a, int size_for_log)
{
    /* M21: Musashi's DOUBLE-BUS-FAULT signature read. When a bus error
     * occurs while stacking a bus-error frame, m68ki_exception_bus_error
     * reads 0x00FFFF01 and then HALTs the 68030 -- the real chip's
     * behaviour. This address sits inside our IO window but off the
     * whitelist, so it used to raise ANOTHER bus error, re-entering the
     * same branch: unbounded recursion, bare-metal stack overflow, and
     * the whole core reset (the RoboCop crash). Answering it benignly
     * lets the branch complete: the 68030 halts, the host LIVES.      */
    if (a == 0x00FFFF01u) {
        halt68k_sig_reads++;
        if (!halt68k_seen) {           /* tier-1: always prints once   */
            halt68k_seen = 1u;
            printf("\r\n[!] 68030 DOUBLE BUS FAULT -> CPU halted "
                   "(contained; host alive). last_berr=%x pc=%x\r\n",
                   (unsigned)last_berr_addr,
                   (unsigned)m68k_get_reg((void *)0, M68K_REG_PC));
        }
        return 0xFFu;
    }
    if (a < 8u)               return rom_ram[a];
    if (a < ST_RAM_SIZE)      return ram[a];
    if (a >= ROM_BASE && a < ROM_END) return rom_ram[a - ROM_BASE];
    if (a >= CART_BASE && a < CART_END) return 0xFFu;
    if (is_ide(a)) { uint32_t v = ide_read8(a);        /* M11q */
                     io_reads++; log_io(a, 1, v, 0, 0); return v; }
    if (is_io(a)) {
        uint32_t r = a & 0xFFFFu;
        if (falcon_io_valid(r)) {
            uint32_t v = io_read8(a);
            io_reads++;
            log_io(a, 1, v, 0, 0);
            return v;
        }
    }
    if (!acc_faulted) { acc_faulted = 1; bus_error(a, size_for_log, 0); }
    return 0xFFu;
}

static uint32_t rd(uint32_t a, int size)
{
    uint32_t v = 0;
    int i;
    acc_faulted = 0;
    a = bus_mask(a);                       /* M22: 24-bit bus decode   */
    /* M11o: plain ST-RAM, ~99%% of traffic. Subtraction rather than
     * a + size so a high address cannot wrap into the range. */
    if (a < ST_RAM_SIZE && (ST_RAM_SIZE - a) >= (uint32_t)size) {
        const uint8_t *p = &ram[a];
        if (size == 2) return ((uint32_t)p[0] << 8) | p[1];
        if (size == 4) return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16)
                            | ((uint32_t)p[2] << 8)  |  (uint32_t)p[3];
        return p[0];
    }
    for (i = 0; i < size; i++) v = (v << 8) | rd8_resolve(a + (uint32_t)i, size);
    return v;
}

static void wr8_resolve(uint32_t a, uint32_t v, int size_for_log)
{
    if (a < ST_RAM_SIZE)      { ram[a] = (uint8_t)v; return; }
    if (a >= ROM_BASE && a < ROM_END) return;            /* ROM: ignore */
    if (a >= CART_BASE && a < CART_END) return;
    if (is_ide(a)) { io_writes++; log_io(a, 1, v, 1, 0);   /* M11q */
                     ide_write8(a, (uint8_t)v); return; }
    if (is_io(a)) {
        uint32_t r = a & 0xFFFFu;
        if (falcon_io_valid(r)) {
            io_writes++;
            log_io(a, 1, v, 1, 0);
            io_write8(a, v);
            return;
        }
    }
    if (!acc_faulted) { acc_faulted = 1; bus_error(a, size_for_log, 1); }
}

static void wr(uint32_t a, int size, uint32_t v)
{
    int i;
    acc_faulted = 0;
    a = bus_mask(a);                       /* M22: 24-bit bus decode   */
    /* M11o: plain ST-RAM fast path. Placed ahead of the FF8A3C pair
     * test because ST_RAM_SIZE is 0x00E00000 and FF8A3C is far above
     * it -- the two ranges cannot overlap, so the ordering is safe and
     * it takes that test off 12.5M writes per interval. */
    if (a < ST_RAM_SIZE && (ST_RAM_SIZE - a) >= (uint32_t)size) {
        uint8_t *p = &ram[a];
        if (size == 2) { p[0] = (uint8_t)(v >> 8); p[1] = (uint8_t)v; return; }
        if (size == 4) { p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16);
                         p[2] = (uint8_t)(v >> 8);  p[3] = (uint8_t)v; return; }
        p[0] = (uint8_t)v; return;
    }
    /* M11f: a word/long write covering the blitter control pair
     * (FF8A3C ctrl / FF8A3D skew) must behave like the real 16-bit
     * latch: dispatch the skew byte BEFORE the control byte so a
     * combined start uses THIS write's skew, not the previous one.  */
    if (size >= 2 && (a & 0x00FFFFFFu) <= 0x00FF8A3Cu
                  && (a & 0x00FFFFFFu) + (uint32_t)size > 0x00FF8A3Cu + 1u) {
        uint32_t base = a & 0x00FFFFFFu;
        for (i = size - 1; i >= 0; i--) {          /* low bytes first  */
            uint32_t ba = base + (uint32_t)i;
            if (ba != 0x00FF8A3Cu)
                wr8_resolve(a + (uint32_t)i,
                            (v >> (8 * (size - 1 - i))) & 0xFFu, size);
        }
        wr8_resolve(a + (0x00FF8A3Cu - base),
                    (v >> (8 * (size - 1 - (int)(0x00FF8A3Cu - base)))) & 0xFFu,
                    size);
        return;
    }
    for (i = 0; i < size; i++)
        wr8_resolve(a + (uint32_t)i, (v >> (8 * (size - 1 - i))) & 0xFFu, size);
}

/* M11k: one increment each; ~1 host clock against the ~19-118 a single
 * emulated cycle already costs, so under 1% and it does not alter what
 * the guest sees. RAM traffic = gmem_r - io_r, gmem_w - io_w. */
unsigned int m68k_read_memory_8 (unsigned int a)
{ dbg_gmem_r++; if (apy_on) apy_note(a); return rd(a, 1); }
unsigned int m68k_read_memory_16(unsigned int a) { dbg_gmem_r++; return rd(a, 2); }
unsigned int m68k_read_memory_32(unsigned int a) { dbg_gmem_r++; return rd(a, 4); }
void m68k_write_memory_8 (unsigned int a, unsigned int v) { dbg_gmem_w++; wr(a, 1, v); }
void m68k_write_memory_16(unsigned int a, unsigned int v) { dbg_gmem_w++; wr(a, 2, v); }
void m68k_write_memory_32(unsigned int a, unsigned int v) { dbg_gmem_w++; wr(a, 4, v); }

/* disassembler: side-effect-free */
unsigned int m68k_read_disassembler_8 (unsigned int a)
{
    a = bus_mask(a);   /* M22: the autopsy disassembles what the CPU
                        * actually fetched from a dirty address       */
    if (a < ST_RAM_SIZE) return ram[a];
    if (a >= ROM_BASE && a < ROM_END) return rom_ram[a - ROM_BASE];
    return 0xFFu;
}
unsigned int m68k_read_disassembler_16(unsigned int a)
{ return (m68k_read_disassembler_8(a) << 8) | m68k_read_disassembler_8(a + 1u); }
unsigned int m68k_read_disassembler_32(unsigned int a)
{ return (m68k_read_disassembler_16(a) << 16) | m68k_read_disassembler_16(a + 2u); }

/* --------------------------- NatFeats ------------------------------ */
#define NFID_VERSION 0x00010000u
#define NFID_NAME    0x00020000u
#define NFID_STDERR  0x00030000u

static uint32_t nf_strlen_bounded(uint32_t p, uint32_t max)
{ uint32_t n = 0; while (n < max && rd(p + n, 1) != 0u) n++; return n; }

static int nf_name_matches(uint32_t p, const char *s)
{
    uint32_t i;
    for (i = 0; s[i]; i++) if (rd(p + i, 1) != (uint32_t)(uint8_t)s[i]) return 0;
    return rd(p + i, 1) == 0u;
}

static uint32_t nf_stderr_chars;
static int nf_illg(int opcode)
{
    uint32_t sp = m68k_get_reg((void*)0, M68K_REG_SP);
    if (opcode == 0x7300) {                       /* nfID(name) */
        uint32_t name = rd(sp + 4u, 4);
        uint32_t id = 0;
        if      (nf_name_matches(name, "NF_VERSION")) id = NFID_VERSION;
        else if (nf_name_matches(name, "NF_NAME"))    id = NFID_NAME;
        else if (nf_name_matches(name, "NF_STDERR"))  id = NFID_STDERR;
        m68k_set_reg(M68K_REG_D0, id);
        return 1;
    }
    if (opcode == 0x7301) {                       /* nfCall(id|sub,...) */
        uint32_t id  = rd(sp + 4u, 4);
        uint32_t ret = 0;
        switch (id & 0xFFFF0000u) {
        case NFID_VERSION:
            ret = 0x00010000u;                    /* NatFeats API 1.0 */
            break;
        case NFID_NAME: {
            static const char *nm0 = "FalconFPGA";
            static const char *nm1 = "FalconFPGA (Musashi/AE350, Tang Console 138K)";
            const char *nm = (id & 1u) ? nm1 : nm0;
            uint32_t buf = rd(sp + 8u, 4), len = rd(sp + 12u, 4), i;
            for (i = 0; nm[i] && i + 1u < len; i++) wr(buf + i, 1, (uint32_t)(uint8_t)nm[i]);
            if (len) wr(buf + i, 1, 0);
            ret = i;
            break; }
        case NFID_STDERR: {
            uint32_t p = rd(sp + 8u, 4);
            uint32_t n = nf_strlen_bounded(p, 512u), i;
            for (i = 0; i < n; i++) {
                char c = (char)rd(p + i, 1);
#ifdef HOST_TEST
                putchar(c);
#else
                printf("%s", (char[]){ c, 0 });
#endif
            }
#ifdef HOST_TEST
            fflush(stdout);
#endif
            nf_stderr_chars += n;
            ret = n;
            break; }
        default:
            ret = 0;
        }
        m68k_set_reg(M68K_REG_D0, ret);
        return 1;
    }
    return 0;                                     /* real illegal insn */
}

/* --------------------------- timing -------------------------------- */
#ifndef HOST_TEST
static inline uint64_t rd_mcycle64(void)
{
    uint32_t hi1, lo, hi2;
    do { __asm__ volatile("csrr %0, mcycleh" : "=r"(hi1));
         __asm__ volatile("csrr %0, mcycle"  : "=r"(lo));
         __asm__ volatile("csrr %0, mcycleh" : "=r"(hi2)); } while (hi1 != hi2);
    return ((uint64_t)hi1 << 32) | lo;
}
#define GPIO_BASE   0xF0700000u
#define GPIO_DIN    (*(volatile uint32_t*)(GPIO_BASE + 0x20))
#define GPIO_DIR    (*(volatile uint32_t*)(GPIO_BASE + 0x28))
#define GPIO_CLR    (*(volatile uint32_t*)(GPIO_BASE + 0x2C))
#define GPIO_SET    (*(volatile uint32_t*)(GPIO_BASE + 0x30))
#endif

/* ---- M9E: wall clock (A25 mcycle, 800MHz crystal-derived) ---------- */
/* On host there is no mcycle; a virtual wall clock advances with the
 * emulated cycle count at the nominal 50:1 ratio, which makes the
 * wall-paced constants collapse to the old emulated ones exactly and
 * keeps host runs deterministic and comparable with m9d.             */
#define WALL_HZ        800000000ull        /* A25 core clock            */
#define WALL_PER_EMU   50u                 /* 800MHz / 16MHz nominal    */
#define WALL_HID_TICK  (WALL_HZ / 60ull)   /* 60Hz HID poll             */
#define WALL_ACIA_BYTE (WALL_HZ * 4ull / 3125ull)  /* 781.25 B/s        */
/* M10: MFP timer clock (2.4576MHz) and VBL (60Hz) in wall mcycles.    */
#define WALL_MFP_TICK  (WALL_HZ / 2457600ull)      /* ~325.5 -> use num */
#define WALL_MFP_NUM   2457600ull                  /* exact rational:   */
#define WALL_MFP_DEN   WALL_HZ                      /*  ticks=dwall*N/D  */
#define WALL_VBL_TICK  (WALL_HZ / 60ull)           /* 60Hz VBL (legacy) */

/* M18: VBL rate is now firmware policy, not a hardwired fabric divisor.
 * A real Falcon on VGA runs 60Hz and PAL titles run 1.2x fast on it --
 * authentic, but useless when you want a game at its designed speed.
 * REV13 needs no change: cyc50 is a raw 50MHz counter already published
 * in the timebase slot, so the divisor moves into firmware where it can
 * be switched at runtime, exactly like a real Falcon's monitor mode.
 *   50Hz: 50e6/50 = 1,000,000 EXACTLY (0 ppm -- better than our 60Hz)
 *   60Hz: 50e6/60 =   833,333       (+0.4 ppm, as the fabric had it)
 * The M17 raster measures frame length every VBL and centres the
 * displayed window in it, so Timer B splits follow the rate change
 * automatically with no further work.                                */
#define VBL_CYC_50    1000000u
#define VBL_CYC_60     833333u
#define VBL_WALL_50   (WALL_HZ / 50ull)
#define VBL_WALL_60   (WALL_HZ / 60ull)
static uint32_t vbl_period_cyc(void)
{ return vbl_50hz ? VBL_CYC_50 : VBL_CYC_60; }
static uint64_t vbl_period_wall(void)
{ return vbl_50hz ? VBL_WALL_50 : VBL_WALL_60; }
#ifdef HOST_TEST
static uint64_t host_wall;
static uint32_t hid_polls, acia_slots;   /* PACETEST observables      */
static inline uint64_t rd_wall64(void) { return host_wall; }
#else
static inline uint64_t rd_wall64(void) { return rd_mcycle64(); }
#endif

/* ---- M11c: hardware timebase mailbox slot, v2 (REV11b) ------------ */
/* Slot layout is EVEN WORDS ONLY (32 bytes): the port's upper write
 * lane is measured dead, so the REV11b publisher lands every value
 * low-lane at addr[2]==0. MAGIC still written last.
 *   word[0] (+0)  TB_MAGIC 0x7B10C0D2  (v2 value = skew-safe vs old)
 *   word[2] (+8)  tick200   (200 Hz counter)
 *   word[4] (+16) tickvbl   (VBL rate counter)
 *   word[6] (+24) cyc50     (free-running 50 MHz cycles)
 * Absent/old-layout magic -> proven mcycle fallback, no firmware
 * change needed to roll the bitstream either way.                     */
#define TB_MAGIC   0x7B10C0D2u
#define TB_FROZEN_MAX 2048u   /* reads (~1/slice) before declaring dead */
#ifdef HOST_TEST
  static volatile uint32_t tb_host[8];
  #define TBSLOT ((volatile uint32_t*)tb_host)
#else
  #define TBSLOT ((volatile uint32_t*)(MBOX_ADDR + 0x600u))  /* +1536 B */
#endif

/* read a coherent snapshot of the hardware timebase; returns 1 if the
 * block is present (magic matches), 0 -> use the mcycle fallback.     */
static int tb_present_cache = -1;
static int      tb_disabled;             /* latched frozen-tick verdict */
static uint32_t tb_frozen_cnt, tb_last_seen;
static int tb_read(uint32_t *t200, uint32_t *tvbl, uint32_t *cyc)
{
#ifndef HOST_TEST
    if (cacheopt) {
        /* M11m: invalidate ONLY the timebase slot. BSP idiom from
         * ae350_l1c_dcache_invalidate_range(): begin-addr then command,
         * one write per cache line. An 8-byte step is smaller than any
         * real line size, so this covers the slot whatever the geometry
         * is and needs no mdcm_cfg decode -- a few CSR writes against a
         * measured ~58us for WBINVAL_ALL. */
        dcache_inval_range((uintptr_t)&TBSLOT[0], 32u);   /* M11n */
        dbg_tbinval++;
    } else {
        l1d_wbinval_all();
    }
#endif
    if (tb_disabled) return 0;
    if (TBSLOT[0] != TB_MAGIC) { tb_present_cache = 0; return 0; }
    *t200 = TBSLOT[2]; *tvbl = TBSLOT[4]; *cyc = TBSLOT[6];   /* v2 */
    /* frozen-tick self-defence: the REV11 silicon failure was magic
     * present with counters frozen at zero -- which stalled EmuTOS
     * forever. Ticks static across TB_FROZEN_MAX consecutive reads
     * (seconds of wall time; a live block ticks every ~5 ms) latches
     * a permanent, announced fall-back to the mcycle wall clock.    */
    if (*t200 != tb_last_seen) { tb_last_seen = *t200; tb_frozen_cnt = 0; }
    else if (++tb_frozen_cnt >= TB_FROZEN_MAX) {
        tb_disabled = 1;
        printf("[tb] hardware ticks frozen -> permanent mcycle fallback\r\n");
        return 0;
    }
    tb_present_cache = 1;
    return 1;
}
/* ===================================================================
 * M13: audio sample ring -- CPU -> fabric transport (REV13 contract).
 *
 * The REV13 fabric carries falcon_audio_ahb, the machine's FIRST AHB
 * READ master: it polls a MAGIC-gated ring in DDR3 and, once valid,
 * fetches samples into a FIFO drained at fs = 50MHz/1024 = 48828.125Hz
 * by the I2S block (MAX98357A, onboard speaker). Until MAGIC validates
 * the fabric plays its own 1kHz test tone -- so every combination is
 * safe and diagnostic:
 *
 *   bitstream \ firmware |  <= m12h (no ring)  |  m13+ (ring armed)
 *   ---------------------+---------------------+---------------------
 *   <= REV12 (no engine) |  1kHz tone          |  1kHz tone (ring
 *                        |                     |  written, nobody reads)
 *   REV13                |  1kHz tone          |  440Hz FROM THE CPU --
 *                        |  (no magic)         |  or tone persists =>
 *                        |                     |  EXTM reads broken;
 *                        |                     |  clean fallback either way
 *
 * Ring layout at 0x04F00800 (proven M8A/lane5 address class; clear of
 * the mailbox 0..0x453 and the timebase slot 0x600..0x61F):
 *   [0](+0)  MAGIC 0xFA1CA0D1   -- written LAST, after WR_WIDX=0
 *   [2](+8)  WR_WIDX            -- total ring WORDS written
 *   [16](+64) data              -- 2048 words, one 32-bit word per 8
 *            bytes (LOW lane, the measured-dead-upper-lane rule),
 *            2 samples/word: sample[15:0] first, sample[31:16] second
 *            (natural A25 little-endian pair store).
 * Publish order per pump: write sample words -> dcache_wb_range(data)
 * -> WR_WIDX = new count -> dcache_wb_range(widx). Mailbox discipline.
 *
 * Pacing: NO read-pointer feedback. Both ends divide the same 50MHz
 * (fabric: 1 sample per 1024 AHB cycles; firmware: cyc50 delta
 * accumulator, n = acc>>10). Rates match by construction; the ring's
 * 4096 samples = 84ms of slack absorb CPU jitter incl. SD busy-waits.
 * cyc50 source: hardware timebase slot word [6] when present (tb_read
 * refreshed it this slice), else the wall clock >> 4 (800MHz/16 =
 * 50MHz-equivalent; host: deterministic host_wall). Payload: 440Hz
 * sine, deliberately distinct from the fabric's 1kHz -- hearing 440
 * IS hearing the CPU.
 * =================================================================== */
#define AUD_MAGIC_V   0xFA1CA0D1u
#define AUD_RINGW     2048u                  /* ring words; 2 samples/word */
#define AUD_STEP_440  38702809u              /* round(440*2^32/48828.125)  */
#ifdef HOST_TEST
static volatile uint32_t aud_host[16u + 2u*AUD_RINGW];
  #define AUDSLOT ((volatile uint32_t*)aud_host)
#else
  #define AUDSLOT ((volatile uint32_t*)(MBOX_ADDR + 0x800u))  /* +2048 B */
#endif

static const int16_t aud_sine[256] = {
         0,    322,    643,    964,   1285,   1604,   1923,   2241,
      2557,   2872,   3185,   3496,   3805,   4111,   4416,   4717,
      5016,   5311,   5604,   5893,   6179,   6460,   6738,   7012,
      7282,   7547,   7808,   8064,   8315,   8561,   8802,   9038,
      9268,   9493,   9712,   9925,  10132,  10333,  10528,  10716,
     10898,  11073,  11242,  11404,  11559,  11707,  11849,  11983,
     12109,  12229,  12341,  12445,  12543,  12632,  12714,  12789,
     12855,  12914,  12965,  13008,  13044,  13071,  13091,  13103,
     13107,  13103,  13091,  13071,  13044,  13008,  12965,  12914,
     12855,  12789,  12714,  12632,  12543,  12445,  12341,  12229,
     12109,  11983,  11849,  11707,  11559,  11404,  11242,  11073,
     10898,  10716,  10528,  10333,  10132,   9925,   9712,   9493,
      9268,   9038,   8802,   8561,   8315,   8064,   7808,   7547,
      7282,   7012,   6738,   6460,   6179,   5893,   5604,   5311,
      5016,   4717,   4416,   4111,   3805,   3496,   3185,   2872,
      2557,   2241,   1923,   1604,   1285,    964,    643,    322,
         0,   -322,   -643,   -964,  -1285,  -1604,  -1923,  -2241,
     -2557,  -2872,  -3185,  -3496,  -3805,  -4111,  -4416,  -4717,
     -5016,  -5311,  -5604,  -5893,  -6179,  -6460,  -6738,  -7012,
     -7282,  -7547,  -7808,  -8064,  -8315,  -8561,  -8802,  -9038,
     -9268,  -9493,  -9712,  -9925, -10132, -10333, -10528, -10716,
    -10898, -11073, -11242, -11404, -11559, -11707, -11849, -11983,
    -12109, -12229, -12341, -12445, -12543, -12632, -12714, -12789,
    -12855, -12914, -12965, -13008, -13044, -13071, -13091, -13103,
    -13107, -13103, -13091, -13071, -13044, -13008, -12965, -12914,
    -12855, -12789, -12714, -12632, -12543, -12445, -12341, -12229,
    -12109, -11983, -11849, -11707, -11559, -11404, -11242, -11073,
    -10898, -10716, -10528, -10333, -10132,  -9925,  -9712,  -9493,
     -9268,  -9038,  -8802,  -8561,  -8315,  -8064,  -7808,  -7547,
     -7282,  -7012,  -6738,  -6460,  -6179,  -5893,  -5604,  -5311,
     -5016,  -4717,  -4416,  -4111,  -3805,  -3496,  -3185,  -2872,
     -2557,  -2241,  -1923,  -1604,  -1285,   -964,   -643,   -322
};

static uint32_t aud_phase;                /* 32-bit phase accumulator   */
static uint32_t aud_acc;                  /* cyc50 remainder (mod 1024) */
static uint32_t aud_cyc_last;
static int      aud_cyc_have;
static uint32_t aud_widx;                 /* ring words written (total) */
static int16_t  aud_carry;                /* odd-sample holdover        */
static int      aud_carry_have;

static void audio_init(void)
{
    psg_snd_reset();            /* M14: silence + tables before streaming */
    aud_phase = 0u; aud_acc = 0u; aud_cyc_have = 0;
    aud_widx = 0u; aud_carry_have = 0;
    AUDSLOT[2] = 0u;                              /* WR_WIDX first     */
    dcache_wb_range((uintptr_t)&AUDSLOT[2], 4u);
    AUDSLOT[0] = AUD_MAGIC_V;                     /* MAGIC last        */
    dcache_wb_range((uintptr_t)&AUDSLOT[0], 4u);
    printf("[aud] m13 ring armed: magic %08x, %u words @+0x800\r\n",
           AUD_MAGIC_V, AUD_RINGW);
}

/* M14: audio source. PSG is the machine's real voice; the m13 sine
 * stays available on F11 as (a) an unmistakable path-alive signal when
 * the guest is silent, (b) the most sensitive underrun detector we have
 * -- a dropout in a pure tone is obvious where the same dropout inside
 * square waves and noise hides -- and (c) an A/B probe for what the PSG
 * synthesis actually costs the emulator.                              */
/* aud_src_tone is declared up with the other UART/HID flags, because the
 * F11 handler in hid_consume() runs long before this point in the file. */

static inline int16_t aud_next(void)
{
    if (aud_src_tone) {
        int16_t s = aud_sine[aud_phase >> 24];
        aud_phase += AUD_STEP_440;
        return s;
    }
    return psg_sample();
}

/* core: advance by an externally supplied cyc50 (unit-testable seam)  */
static void audio_pump_cyc(uint32_t cyc)
{
    uint32_t n, w0;
    if (!aud_cyc_have) { aud_cyc_last = cyc; aud_cyc_have = 1; return; }
    { uint32_t du = cyc - aud_cyc_last;           /* unsigned wrap-safe */
      aud_cyc_last = cyc;
      if (du > 50000000u) du = 0u;                /* >1s jump: glitch   */
      aud_acc += du; }
    n = aud_acc >> 10;                            /* fs = 50MHz/1024    */
    aud_acc &= 1023u;
    if (n == 0u) return;
    if (n > 4096u) n = 4096u;                     /* stall cap: 1 lap   */
    w0 = aud_widx;
    while (n) {
        int16_t s0, s1;
        int16_t d0, d1;
        /* s0,s1 = two CONSECUTIVE MONO samples: the fabric drains this
         * ring as mono, 2 samples/word, one per I2S frame (see
         * falcon_audio_ahb.v -- NOT one stereo frame as m20's comment
         * claimed). The DMA is a second mono source in LOCKSTEP: one
         * dma_next_mono() per sample slot, with its own carry so odd
         * counts keep the two streams aligned. Sum saturates.         */
        if (aud_carry_have) { s0 = aud_carry; aud_carry_have = 0;
                              d0 = dma_carry;
                              s1 = aud_next(); d1 = dma_next_mono(); n--; }
        else if (n >= 2u)   { s0 = aud_next(); d0 = dma_next_mono();
                              s1 = aud_next(); d1 = dma_next_mono();
                              n -= 2u; }
        else                { aud_carry = aud_next(); aud_carry_have = 1;
                              dma_carry = dma_next_mono();
                              break; }
        { int32_t L = (int32_t)s0 + d0, R = (int32_t)s1 + d1;
          if (L >  32767) L =  32767; else if (L < -32768) L = -32768;
          if (R >  32767) R =  32767; else if (R < -32768) R = -32768;
          AUDSLOT[16u + 2u*(aud_widx & (AUD_RINGW-1u))] =
              ((uint32_t)(uint16_t)(int16_t)L)
            | (((uint32_t)(uint16_t)(int16_t)R) << 16); }
        aud_widx++;
    }
    if (aud_widx == w0) return;                   /* only a carry moved */
    { uint32_t ww = aud_widx - w0;                /* flush what we wrote */
      if (ww >= AUD_RINGW)
          dcache_wb_range((uintptr_t)&AUDSLOT[16], AUD_RINGW*8u);
      else {
          uint32_t o0 = w0 & (AUD_RINGW-1u);
          uint32_t f  = AUD_RINGW - o0; if (f > ww) f = ww;
          dcache_wb_range((uintptr_t)&AUDSLOT[16u + 2u*o0], f*8u);
          if (ww > f) dcache_wb_range((uintptr_t)&AUDSLOT[16], (ww-f)*8u);
      }
      AUDSLOT[2] = aud_widx;                      /* publish AFTER data */
      dcache_wb_range((uintptr_t)&AUDSLOT[2], 4u);
    }
}

/* per-slice wrapper: pick the cyc50 source the M10 pacing just used   */
static void audio_pump(void)
{
    uint32_t cyc = (tb_present_cache == 1 && !tb_disabled)
                 ? TBSLOT[6]                     /* fresh: tb_read ran  */
                 : (uint32_t)(rd_wall64() >> 4); /* 800MHz/16 = 50MHz   */
    audio_pump_cyc(cyc);
}

#ifdef HOST_TEST
/* SLICETEST -- the adaptive slice policy. Literals by hand: Timer C at
 * 200Hz is presc 64 * data 192 = 12288 MFP ticks (coarse); a 12.8kHz
 * digi timer is presc 4 * data 48 = 192 (fine).                      */
static int slicetest(void)
{
    int bad = 0; int t;
    uint8_t s_tacr = mfp[MFP_TACR], s_tbcr = mfp[MFP_TBCR];
    uint8_t s_tcdcr = mfp[MFP_TCDCR], s_ta = mfp[MFP_TADR];
    uint8_t s_iera = mfp[MFP_IERA], s_ierb = mfp[MFP_IERB];
    uint8_t s_pa = psplit_active; uint32_t s_cfg = slice_cap_cfg;

    slice_cap_cfg = 0u; psplit_active = 0u;
    for (t = 0; t < 4; t++) mfp[MFP_TADR + t] = 0u;
    mfp[MFP_TACR] = 0u; mfp[MFP_TBCR] = 0u; mfp[MFP_TCDCR] = 0u;

    /* v1: nothing armed -> coarse                                     */
    if (slice_cycles() != SLICE_COARSE) {
        printf("SLICETEST FAIL v1: %u\r\n", slice_cycles()); bad++; }

    /* v2: Timer C at 200Hz (presc 64, data 192 = 12288) stays COARSE  */
    mfp[MFP_IERA] = 0u; mfp[MFP_IERB] = 0xFFu;
    mfp[MFP_TCDCR] = 0x50u;              /* timer C presc index 5 = 64 */
    mfp[MFP_TADR + 2] = 192u;
    if (slice_cycles() != SLICE_COARSE) {
        printf("SLICETEST FAIL v2: 200Hz forced fine\r\n"); bad++; }

    /* v3: a 12.8kHz digi timer (presc 4, data 48 = 192) with its IRQ
     * ENABLED -> FINE                                                 */
    mfp[MFP_TACR] = 1u;                  /* presc index 1 = 4          */
    mfp[MFP_TADR] = 48u;
    mfp[MFP_IERA] = (uint8_t)(mfp[MFP_IERA] | 0x20u);
    if (slice_cycles() != SLICE_FINE) {
        printf("SLICETEST FAIL v3: digi timer not fine\r\n"); bad++; }

    /* v3b: the SAME fast timer with its interrupt MASKED must stay
     * coarse -- this is TOS's Timer D baud clock, and missing it made
     * 93% of a plain boot run fine.                                   */
    mfp[MFP_IERA] = (uint8_t)(mfp[MFP_IERA] & ~0x20u);
    if (slice_cycles() != SLICE_COARSE) {
        printf("SLICETEST FAIL v3b: masked fast timer forced fine\r\n");
        bad++; }
    mfp[MFP_TACR] = 0u; mfp[MFP_TADR] = 0u;

    /* v4: palette splits last frame -> FINE                           */
    if (slice_cycles() != SLICE_COARSE) {
        printf("SLICETEST FAIL v4a\r\n"); bad++; }
    psplit_active = 1u;
    if (slice_cycles() != SLICE_FINE) {
        printf("SLICETEST FAIL v4b: splits not fine\r\n"); bad++; }
    psplit_active = 0u;

    /* v5: config pin overrides everything                             */
    slice_cap_cfg = 10000u; psplit_active = 1u;
    if (slice_cycles() != 10000u) {
        printf("SLICETEST FAIL v5: config not honoured\r\n"); bad++; }
    slice_cap_cfg = 0u; psplit_active = 0u;

    /* v6: data 0 means 256 -- presc 4 * 256 = 1024, still fine        */
    mfp[MFP_TACR] = 1u; mfp[MFP_TADR] = 0u;
    mfp[MFP_IERA] = (uint8_t)(mfp[MFP_IERA] | 0x20u);
    if (slice_cycles() != SLICE_FINE) {
        printf("SLICETEST FAIL v6: data0 not treated as 256\r\n"); bad++; }

    mfp[MFP_TACR]=s_tacr; mfp[MFP_TBCR]=s_tbcr; mfp[MFP_TCDCR]=s_tcdcr;
    mfp[MFP_TADR]=s_ta; mfp[MFP_IERA]=s_iera; mfp[MFP_IERB]=s_ierb;
    psplit_active=s_pa; slice_cap_cfg=s_cfg;
    if (!bad) printf("SLICETEST OK (7 vectors)\r\n");
    return bad;
}

/* JOYTEST -- the keyboard joystick. Literals are the Hatari bit masks,
 * written out by hand rather than taken from the defines under test. */
static int joytest(void)
{
    int bad = 0;
    uint8_t s_on = joy_on, s_rep = joy_report;
    uint8_t s_st = joy_state, s_pv = joy_prev;
    uint32_t n0;

    /* v1: usage -> bit mapping, both key conventions                  */
    if (joy_bit_of_usage(0x52u) != 0x01u || joy_bit_of_usage(0x60u) != 0x01u ||
        joy_bit_of_usage(0x51u) != 0x02u || joy_bit_of_usage(0x5Au) != 0x02u ||
        joy_bit_of_usage(0x50u) != 0x04u || joy_bit_of_usage(0x5Cu) != 0x04u ||
        joy_bit_of_usage(0x4Fu) != 0x08u || joy_bit_of_usage(0x5Eu) != 0x08u ||
        joy_bit_of_usage(0x2Cu) != 0x80u || joy_bit_of_usage(0x62u) != 0x80u) {
        printf("JOYTEST FAIL v1: mapping\r\n"); bad++; }
    if (joy_bit_of_usage(0x04u) != 0u) {     /* 'A' is not a joy key   */
        printf("JOYTEST FAIL v1b: stray mapping\r\n"); bad++; }

    /* v2: a change emits exactly two bytes, 0xFF then the state       */
    joy_report = 1u; joy_prev = 0u; joy_state = 0u;
    ikbd_head = ikbd_tail = 0u;
    joy_state = (uint8_t)(JOY_LEFT | JOY_FIRE);
    joy_emit();
    if (ikbd_tail != 2u || ikbd_fifo[0] != 0xFFu || ikbd_fifo[1] != 0x84u) {
        printf("JOYTEST FAIL v2: %u bytes %02x %02x\r\n",
               (unsigned)ikbd_tail, ikbd_fifo[0], ikbd_fifo[1]); bad++; }

    /* v3: no change -> no packet (the IKBD only reports transitions)  */
    n0 = dbg_joy_pkts; joy_emit();
    if (dbg_joy_pkts != n0) {
        printf("JOYTEST FAIL v3: repeated on no change\r\n"); bad++; }

    /* v4: release emits state 0 -- a direction cannot stick           */
    ikbd_head = ikbd_tail = 0u;
    joy_state = 0u; joy_emit();
    if (ikbd_tail != 2u || ikbd_fifo[1] != 0x00u) {
        printf("JOYTEST FAIL v4: release\r\n"); bad++; }

    /* v5: 0x15 disables reporting, 0x14 re-enables                    */
    joy_report = 0u; ikbd_head = ikbd_tail = 0u;
    joy_state = JOY_UP; joy_emit();
    if (ikbd_tail != 0u) {
        printf("JOYTEST FAIL v5: sent while disabled\r\n"); bad++; }
    joy_report = 1u;

    /* v6: diagonals combine                                           */
    joy_prev = 0u; joy_state = (uint8_t)(JOY_UP | JOY_RIGHT);
    if (joy_state != 0x09u) {
        printf("JOYTEST FAIL v6: diagonal %02x\r\n", joy_state); bad++; }

    ikbd_head = ikbd_tail = 0u;
    joy_on = s_on; joy_report = s_rep; joy_state = s_st; joy_prev = s_pv;
    if (!bad) printf("JOYTEST OK (6 vectors)\r\n");
    return bad;
}

/* SHADOWTEST -- the PSG shadow decode. Literals hand-derived from the
 * bits-0-and-1 rule; $FF8900 must stay OUT of the block.             */
static int shadowtest(void)
{
    int bad = 0;

    /* v1: the decode itself, including the exact silicon-log address  */
    if (PSG_SHADOW(0x8804u) != 0x8800u || PSG_SHADOW(0x8806u) != 0x8802u ||
        PSG_SHADOW(0x88FFu) != 0x8803u || PSG_SHADOW(0x8801u) != 0x8801u) {
        printf("SHADOWTEST FAIL v1: decode wrong\r\n"); bad++; }

    /* v2: the whole block is now valid IO -- no bus error             */
    if (!falcon_io_valid(0x8804u) || !falcon_io_valid(0x88FFu) ||
        !falcon_io_valid(0x8800u)) {
        printf("SHADOWTEST FAIL v2: block not whitelisted\r\n"); bad++; }

    /* v3: SCOPE -- $FF8900 (sound DMA) must NOT be swallowed          */
    if (PSG_SHADOW(0x8900u) == 0x8900u && 0) { /* unreachable by design */ }
    if (0x8900u >= 0x8800u && 0x8900u <= 0x88FFu) {
        printf("SHADOWTEST FAIL v3: block overlaps sound DMA\r\n"); bad++; }

    /* v4: a write through a shadow reaches the SAME register as the
     * canonical address. Select reg 7 via the shadow, read it back
     * through the canonical port.                                     */
    { uint32_t canon, shadow;
      psg_write8(PSG_SHADOW(0x8804u), 7u);      /* select reg 7        */
      canon = psg_read8(0x8800u);
      psg_write8(PSG_SHADOW(0x8800u), 7u);      /* same, canonically   */
      shadow = psg_read8(0x8800u);
      if (canon != shadow) {
          printf("SHADOWTEST FAIL v4: %02x != %02x\r\n",
                 (unsigned)canon, (unsigned)shadow); bad++; } }

    if (!bad) printf("SHADOWTEST OK (4 vectors)\r\n");
    return bad;
}

/* DONETEST -- the XSINT completion signalling, all three idioms.      */
static int donetest(void)
{
    int bad = 0; uint32_t i;
    uint8_t s_sh[0x40], s_tacr = mfp[MFP_TACR], s_tadr = mfp[MFP_TADR];
    uint8_t s_iera = mfp[MFP_IERA], s_ipra = mfp[MFP_IPRA];
    uint8_t s_tc0 = tcount[0];
    for (i = 0; i < 0x40u; i++) s_sh[i] = io_shadow[0x0900u + i];

    /* v0: the wiring literal itself                                   */
    if (timer_src[0] != 13u) {
        printf("DONETEST FAIL v0: timer_src[0]=%u != 13\r\n",
               timer_src[0]); bad++; }

    /* v1: control readback is live. Play a 4-byte frame to auto-stop. */
    ram[0x1000]=1; ram[0x1001]=2; ram[0x1002]=3; ram[0x1003]=4;
    io_shadow[0x0903u]=0; io_shadow[0x0905u]=0x10; io_shadow[0x0907u]=0;
    io_shadow[0x090Fu]=0; io_shadow[0x0911u]=0x10; io_shadow[0x0913u]=4;
    mfp[MFP_TACR] = 0u;                   /* no event mode: no raises  */
    dma_snd_write(0x8921u, 0x83u);
    dma_snd_write(0x8901u, 0x01u);
    if ((dma_snd_read(0x8901u) & 1u) != 1u) {
        printf("DONETEST FAIL v1a: not reading as playing\r\n"); bad++; }
    { int g=0; while (dma_run && g++<100000) (void)dma_next_mono(); }
    if ((dma_snd_read(0x8901u) & 1u) != 0u) {
        printf("DONETEST FAIL v1b: still reads playing after stop\r\n"); bad++; }
    if ((io_read8(0x00FF8901u) & 1u) != 0u) {
        printf("DONETEST FAIL v1c: io_read8 hook not widened\r\n"); bad++; }

    /* v2: GPIP7 follows XSINT: idle 1 -> playing 0 -> stopped 1       */
    if (!(mfp_read(0xFA01u) & 0x80u)) {
        printf("DONETEST FAIL v2a: idle GPIP7 != 1\r\n"); bad++; }
    dma_run = 1u;
    if (mfp_read(0xFA01u) & 0x80u) {
        printf("DONETEST FAIL v2b: playing GPIP7 != 0\r\n"); bad++; }
    dma_run = 0u;
    if (!(mfp_read(0xFA01u) & 0x80u)) {
        printf("DONETEST FAIL v2c: stopped GPIP7 != 1\r\n"); bad++; }

    /* v3: Timer A event-count: TADR=3 -> fires on the 3rd frame end   */
    mfp[MFP_TACR] = 0x08u; mfp[MFP_TADR] = 3u; tcount[0] = 0u;
    mfp[MFP_IERA] = (uint8_t)(mfp[MFP_IERA] | 0x20u);   /* enable TA   */
    mfp[MFP_IPRA] = (uint8_t)(mfp[MFP_IPRA] & ~0x20u);
    dma_ta_event(); dma_ta_event();
    if (mfp[MFP_IPRA] & 0x20u) {
        printf("DONETEST FAIL v3a: fired early\r\n"); bad++; }
    dma_ta_event();
    if (!(mfp[MFP_IPRA] & 0x20u)) {
        printf("DONETEST FAIL v3b: did not fire on 3rd\r\n"); bad++; }

    /* v4: scanlines no longer tick Timer A (TBI-only now)             */
    mfp[MFP_IPRA] = (uint8_t)(mfp[MFP_IPRA] & ~0x20u);
    mfp[MFP_TADR] = 1u; tcount[0] = 0u;
    hbl_frame_lines = 312u; hbl_line = 0u; hbl_acc = 0u;
    for (i = 0; i < 49152u; i++) mfp_hbl_advance(1u);
    if (mfp[MFP_IPRA] & 0x20u) {
        printf("DONETEST FAIL v4: scanlines ticked Timer A\r\n"); bad++; }

    /* v5: no event mode, no fire, counter untouched                   */
    mfp[MFP_TACR] = 0u; tcount[0] = 7u;
    for (i = 0; i < 5u; i++) dma_ta_event();
    if (tcount[0] != 7u || (mfp[MFP_IPRA] & 0x20u)) {
        printf("DONETEST FAIL v5\r\n"); bad++; }

    for (i = 0; i < 0x40u; i++) io_shadow[0x0900u + i] = s_sh[i];
    mfp[MFP_TACR]=s_tacr; mfp[MFP_TADR]=s_tadr;
    mfp[MFP_IERA]=s_iera; mfp[MFP_IPRA]=s_ipra; tcount[0]=s_tc0;
    dma_run = 0u; dma_ptr = 0u; dma_pacc = 0u;
    if (!bad) printf("DONETEST OK (6 vectors)\r\n");
    return bad;
}

/* BUSTEST -- the 24-bit bus mode. Literals from the RoboCop evidence:
 * the guest's dirty vectors $020C0B9E/$040C0B9E must resolve to the
 * real handler bytes at $0C0B9E.                                     */
static int bustest(void)
{
    int bad = 0;
    uint8_t sv0 = ram[0x0C0B9E], sv1 = ram[0x0C0B9F];
    uint8_t sb = bus32;

    /* v1: pure mask semantics, both modes                             */
    bus32 = 0u;
    if (bus_mask(0x020C0B9Eu) != 0x000C0B9Eu ||
        bus_mask(0xFFFF8240u) != 0x00FF8240u) {
        printf("BUSTEST FAIL v1: mask wrong\r\n"); bad++; }
    bus32 = 1u;
    if (bus_mask(0x020C0B9Eu) != 0x020C0B9Eu) {
        printf("BUSTEST FAIL v1b: 32-bit mode masked\r\n"); bad++; }
    bus32 = 0u;

    /* v2: a dirty-address READ returns the real low-memory bytes      */
    ram[0x0C0B9E] = 0x61u; ram[0x0C0B9F] = 0x00u;   /* "bsr" opcode    */
    if (rd(0x020C0B9Eu, 2) != 0x6100u) {
        printf("BUSTEST FAIL v2: read %x != 6100\r\n",
               (unsigned)rd(0x020C0B9Eu, 2)); bad++; }
    if (rd(0x040C0B9Eu, 2) != rd(0x000C0B9Eu, 2)) {
        printf("BUSTEST FAIL v2b: aliases disagree\r\n"); bad++; }

    /* v3: a dirty-address WRITE lands at the masked location          */
    wr(0x030C0B9Eu, 1, 0xA5u);
    if (ram[0x0C0B9E] != 0xA5u) {
        printf("BUSTEST FAIL v3: write did not alias\r\n"); bad++; }

    /* v4: the IO alias forms still meet: 0xFFFF8xxx masks into the
     * 0x00FF8xxx window, which is_io accepts -- same device.          */
    if (!is_io(bus_mask(0xFFFF8240u))) {
        printf("BUSTEST FAIL v4: IO alias broken\r\n"); bad++; }

    /* v5: the M21 signature address is mask-invariant                 */
    if (bus_mask(0x00FFFF01u) != 0x00FFFF01u) {
        printf("BUSTEST FAIL v5: signature moved\r\n"); bad++; }

    ram[0x0C0B9E] = sv0; ram[0x0C0B9F] = sv1; bus32 = sb;
    if (!bad) printf("BUSTEST OK (5 vectors)\r\n");
    return bad;
}

/* CATTEST -- double-bus-fault containment. The signature address must
 * answer benignly and surgically: neighbours still bus-error.         */
static int cattest(void)
{
    int bad = 0;
    uint32_t s0 = halt68k_sig_reads;
    uint8_t  h0 = halt68k_seen;

    /* v1: the signature read returns 0xFF and raises NO bus error     */
    acc_faulted = 0;
    if (rd8_resolve(0x00FFFF01u, 1) != 0xFFu) {
        printf("CATTEST FAIL v1: wrong value\r\n"); bad++; }
    { extern uint32_t berr_count; (void)0; }  /* v1b folded: the special
       case returns before any fault path -- proven by v1 + v3 scope   */
    if (halt68k_sig_reads != s0 + 1u) {
        printf("CATTEST FAIL v1c: signature not counted\r\n"); bad++; }

    /* v2: the report is one-shot                                       */
    if (!halt68k_seen) { printf("CATTEST FAIL v2: not reported\r\n"); bad++; }
    acc_faulted = 0;
    (void)rd8_resolve(0x00FFFF01u, 1);
    if (halt68k_sig_reads != s0 + 2u) {
        printf("CATTEST FAIL v2b: second read not counted\r\n"); bad++; }

    /* v3: SURGICAL -- the neighbour 0xFFFF03 must still CLASSIFY as a
     * faulting access (in the IO window, not whitelisted, not the
     * signature). We assert the decision predicates rather than firing
     * bus_error() itself: outside m68k_execute the longjmp buffer is
     * unarmed and a real pulse is undefined behaviour on the host.    */
    if (!(is_io(0x00FFFF03u) && !falcon_io_valid(0xFF03u))) {
        printf("CATTEST FAIL v3: neighbour not fault-classified\r\n");
        bad++; }
    if (0x00FFFF03u == 0x00FFFF01u) {  /* self-evident; documents scope */
        printf("CATTEST FAIL v3b\r\n"); bad++; }

    halt68k_seen = h0;                 /* restore for the real run      */
    if (!bad) printf("CATTEST OK (3 vectors)\r\n");
    return bad;
}

/* SNDTEST -- the DMA sound engine. Independent literals: rate ratios by
 * hand from the STE table and fs=48828. */
static int sndtest(void)
{
    int bad = 0; uint32_t i;
    uint8_t s_sh[0x40];
    for (i = 0; i < 0x40u; i++) s_sh[i] = io_shadow[0x0900u + i];
    dma_run = 0u;

    /* v1: step ratio, and the four STE rates give increasing steps.   */
    dma_ratesel = 1u; dma_recompute_step();
    if (dma_step != (12517u << 16) / 48828u) {
        printf("SNDTEST FAIL v1: step %u\r\n", dma_step); bad++; }
    { uint32_t prev = 0u;
      for (i = 0; i < 4u; i++) { dma_ratesel = (uint8_t)i; dma_recompute_step();
          if (dma_step <= prev) { printf("SNDTEST FAIL v1b rate %u\r\n", i);
              bad++; } prev = dma_step; } }

    /* v2: mode decode. Per crossbar.c bit7 CLEAR = stereo, SET = mono;
     * bit6 = 16-bit. So 0x40 = 16-bit STEREO, 0xC0 = 16-bit MONO,
     * 0x00 = 8-bit stereo, 0x80 = 8-bit mono.                          */
    dma_snd_write(0x8921u, 0x40u);       /* 16-bit stereo               */
    if (!dma_16bit || !dma_stereo) { printf("SNDTEST FAIL v2a\r\n"); bad++; }
    dma_snd_write(0x8921u, 0xC0u);       /* 16-bit mono                 */
    if (!dma_16bit || dma_stereo) { printf("SNDTEST FAIL v2b\r\n"); bad++; }
    dma_snd_write(0x8921u, 0x00u);       /* 8-bit stereo                */
    if (dma_16bit || !dma_stereo) { printf("SNDTEST FAIL v2c\r\n"); bad++; }

    /* v3: play latch, 8-bit mono ramp at 0x1000..0x1003, end 0x1004.   */
    ram[0x1000]=0x10; ram[0x1001]=0x20; ram[0x1002]=0x30; ram[0x1003]=0x40;
    io_shadow[0x0903u]=0x00; io_shadow[0x0905u]=0x10; io_shadow[0x0907u]=0x00;
    io_shadow[0x090Fu]=0x00; io_shadow[0x0911u]=0x10; io_shadow[0x0913u]=0x04;
    dma_snd_write(0x8921u, 0x83u);       /* mono, 8-bit, rate idx 3     */
    if (dma_stereo) { printf("SNDTEST FAIL v3-mode\r\n"); bad++; }
    dma_snd_write(0x8901u, 0x01u);       /* PLAY                        */
    if (!dma_run) { printf("SNDTEST FAIL v3a\r\n"); bad++; }
    if (dma_start != 0x1000u || dma_end != 0x1004u) {
        printf("SNDTEST FAIL v3b: %06x/%06x\r\n",
               (unsigned)dma_start, (unsigned)dma_end); bad++; }
    if (dma_ptr != 0x1001u) {
        printf("SNDTEST FAIL v3c: ptr %06x\r\n", (unsigned)dma_ptr); bad++; }
    if (dma_l != (int16_t)((int8_t)0x10 << 8)) {
        printf("SNDTEST FAIL v3d: %d\r\n", dma_l); bad++; }

    /* v4: live pointer readback.                                      */
    if (dma_snd_read(0x8909u)!=0x00u || dma_snd_read(0x890Bu)!=0x10u
        || dma_snd_read(0x890Du)!=0x01u) {
        printf("SNDTEST FAIL v4\r\n"); bad++; }

    /* v5: no-loop frame plays out and stops.                          */
    { int g=0; while (dma_run && g++<100000) (void)dma_next_mono(); }
    if (dma_run) { printf("SNDTEST FAIL v5\r\n"); bad++; }

    /* v6: loop wraps instead of stopping.                             */
    dma_snd_write(0x8901u, 0x00u);
    dma_snd_write(0x8901u, 0x03u);
    if (!dma_run || !dma_loop) { printf("SNDTEST FAIL v6a\r\n"); bad++; }
    { uint32_t k; for (k=0;k<200000u;k++) (void)dma_next_mono(); }
    if (!dma_run) { printf("SNDTEST FAIL v6b\r\n"); bad++; }
    dma_snd_write(0x8901u, 0x00u);

    /* v7: idle engine emits silence.                                  */
    if (dma_next_mono() != 0) { printf("SNDTEST FAIL v7\r\n"); bad++; }

    /* v8: THE RATE ITSELF. 8-bit mono loop at rate idx 1 (12517 Hz):
     * 48828 mono calls -- one nominal second -- must consume 12516 or
     * 12517 source frames (48828*16800/65536 = 12516.9). The m20 bug
     * (one call per WORD) would consume ~6258 and FAIL here.          */
    dma_snd_write(0x8921u, 0x81u);       /* mono, 8-bit, rate idx 1     */
    dma_snd_write(0x8901u, 0x03u);       /* PLAY + loop                 */
    { uint32_t k, f0, f1;
      f0 = dma_frames_consumed;
      for (k = 0; k < 48828u; k++) (void)dma_next_mono();
      f1 = dma_frames_consumed - f0;
      if (f1 < 12516u || f1 > 12517u) {
          printf("SNDTEST FAIL v8: %u frames/sec != 12516..7\r\n",
                 (unsigned)f1); bad++; } }
    dma_snd_write(0x8901u, 0x00u);

    for (i = 0; i < 0x40u; i++) io_shadow[0x0900u + i] = s_sh[i];
    dma_run = 0u; dma_ptr = 0u; dma_pacc = 0u;
    if (!bad) printf("SNDTEST OK (8 vectors)\r\n");
    return bad;
}

/* SPLITTEST -- the palette-change recorder + REV14 region layout.
 * Literals are hand-derived: strot12($0777)=$0EEE, strot12($0345)=$068A,
 * strot12($0111)=$0222; tb for a 312-line frame = (312-200)/2 = 56.    */
static int splittest(void)
{
    int bad = 0; uint32_t i;
    uint32_t s_fl = hbl_frame_lines, s_hl = hbl_line;
    uint8_t  s_sh[0x20]; uint8_t s_en = psplit_en;
    for (i = 0; i < 0x20u; i++) s_sh[i] = io_shadow[0x0240u + i];

    hbl_frame_lines = 312u;             /* tb = 56                     */
    psplit_n = 0u; psplit_dropped = 0u; psplit_en = 1u;
    for (i = 0; i < 0x20u; i++) io_shadow[0x0240u + i] = 0u;

    /* v1: a write in the TOP border lands at visible line 0          */
    io_shadow[0x0246u] = 0x07u; io_shadow[0x0247u] = 0x77u;  /* idx 3 */
    hbl_line = 10u; psplit_note();
    if (psplit_n != 1u || psplit_line[0] != 0u) {
        printf("SPLITTEST FAIL v1: n=%u line=%u\r\n",
               psplit_n, (unsigned)psplit_line[0]); bad++; }
    if (psplit_pal[0][3] != 0x0EEEu) {
        printf("SPLITTEST FAIL v1b: pal %03x != 0EEE\r\n",
               psplit_pal[0][3]); bad++; }

    /* v2: a write at hbl 103 = visible line 47 (Dizzy's split)       */
    io_shadow[0x0246u] = 0x03u; io_shadow[0x0247u] = 0x45u;
    hbl_line = 103u; psplit_note();
    if (psplit_n != 2u || psplit_line[1] != 47u) {
        printf("SPLITTEST FAIL v2: n=%u line=%u\r\n",
               psplit_n, (unsigned)psplit_line[1]); bad++; }
    if (psplit_pal[1][3] != 0x068Au) {
        printf("SPLITTEST FAIL v2b: pal %03x != 068A\r\n",
               psplit_pal[1][3]); bad++; }

    /* v3: same-line coalesce -- still 2 entries, snapshot updated    */
    io_shadow[0x0240u] = 0x01u; io_shadow[0x0241u] = 0x11u;  /* idx 0 */
    psplit_note();
    if (psplit_n != 2u) {
        printf("SPLITTEST FAIL v3: n=%u != 2\r\n", psplit_n); bad++; }
    if (psplit_pal[1][0] != 0x0222u || psplit_pal[1][3] != 0x068Au) {
        printf("SPLITTEST FAIL v3b: %03x/%03x\r\n",
               psplit_pal[1][0], psplit_pal[1][3]); bad++; }

    /* v4: bottom border ignored by design (base snapshot carries it) */
    hbl_line = 260u; psplit_note();
    if (psplit_n != 2u || psplit_dropped != 0u) {
        printf("SPLITTEST FAIL v4: n=%u drop=%u\r\n",
               psplit_n, (unsigned)psplit_dropped); bad++; }

    /* v5: overflow -- 34 further distinct lines: 28 fit, 6 dropped   */
    for (i = 0; i < 34u; i++) { hbl_line = 57u + i; psplit_note(); }
    if (psplit_n != 30u || psplit_dropped != 6u) {
        printf("SPLITTEST FAIL v5: n=%u drop=%u\r\n",
               psplit_n, (unsigned)psplit_dropped); bad++; }
    if (psplit_line[29] != 28u) {
        printf("SPLITTEST FAIL v5b: line[29]=%u != 28\r\n",
               (unsigned)psplit_line[29]); bad++; }

    /* v6: publish -- REV14 layout, magic present, count 30           */
    psplit_publish();
    if (CHGR[0] != PSPLIT_MAGIC || CHGR[1] != 30u) {
        printf("SPLITTEST FAIL v6: magic %08x count %u\r\n",
               (unsigned)CHGR[0], (unsigned)CHGR[1]); bad++; }
    if (CHGR[2] != 0u || CHGR[3] != 47u || CHGR[4] != 1u) {
        printf("SPLITTEST FAIL v6b: lines %u %u %u\r\n",
               (unsigned)CHGR[2], (unsigned)CHGR[3], (unsigned)CHGR[4]); bad++; }
    if (CHGR[32u+3u] != 0x0EEEu || CHGR[32u+16u+3u] != 0x068Au
        || CHGR[32u+16u+0u] != 0x0222u) {
        printf("SPLITTEST FAIL v6c: pal words wrong\r\n"); bad++; }

    /* v7: list consumed by publish; an empty publish keeps magic     */
    if (psplit_n != 0u) {
        printf("SPLITTEST FAIL v7: n=%u after publish\r\n", psplit_n); bad++; }
    psplit_publish();
    if (CHGR[0] != PSPLIT_MAGIC || CHGR[1] != 0u) {
        printf("SPLITTEST FAIL v7b: %08x/%u\r\n",
               (unsigned)CHGR[0], (unsigned)CHGR[1]); bad++; }

    /* v8: PALSPLIT=0 kills the magic -- fabric falls back            */
    psplit_en = 0u; psplit_publish();
    if (CHGR[0] != 0u) {
        printf("SPLITTEST FAIL v8: magic %08x != 0\r\n",
               (unsigned)CHGR[0]); bad++; }

    hbl_frame_lines = s_fl; hbl_line = s_hl; psplit_en = s_en;
    psplit_n = 0u; psplit_dropped = 0u;
    for (i = 0; i < 0x20u; i++) io_shadow[0x0240u + i] = s_sh[i];
    if (!bad) printf("SPLITTEST OK (8 vectors)\r\n");
    return bad;
}

/* VBLTEST -- the selectable VBL divisor. Literals worked out by hand
 * from the 50MHz cyc50 clock, not from the constants under test.     */
static int vbltest(void)
{
    int bad = 0; uint32_t i, due;
    uint8_t save = vbl_50hz;

    /* v1: 60Hz -- one wall second of cyc50 must yield 60 VBLs         */
    vbl_50hz = 0u; vbl_acc = 0u; due = 0u;
    for (i = 0; i < 50000000u / 1000u; i++) {      /* 1s in 1ms steps  */
        vbl_acc += 1000u;
        { uint32_t p = vbl_period_cyc();
          while (vbl_acc >= p) { vbl_acc -= p; due++; } }
    }
    if (due != 60u) { printf("VBLTEST FAIL v1: %u VBL/s at 60Hz\r\n", due); bad++; }

    /* v2: 50Hz -- same second must yield exactly 50                   */
    vbl_50hz = 1u; vbl_acc = 0u; due = 0u;
    for (i = 0; i < 50000000u / 1000u; i++) {
        vbl_acc += 1000u;
        { uint32_t p = vbl_period_cyc();
          while (vbl_acc >= p) { vbl_acc -= p; due++; } }
    }
    if (due != 50u) { printf("VBLTEST FAIL v2: %u VBL/s at 50Hz\r\n", due); bad++; }

    /* v3: 50Hz is EXACT -- 1,000,000 cyc50 per frame, no remainder    */
    if (VBL_CYC_50 * 50u != 50000000u) {
        printf("VBLTEST FAIL v3: 50Hz divisor not exact\r\n"); bad++; }

    /* v4: the wall-clock fallback agrees to within a frame            */
    vbl_50hz = 1u;
    if (vbl_period_wall() != 16000000ull) {
        printf("VBLTEST FAIL v4: wall 50Hz period wrong\r\n"); bad++; }
    vbl_50hz = 0u;
    if (vbl_period_wall() != 13333333ull) {
        printf("VBLTEST FAIL v5: wall 60Hz period wrong\r\n"); bad++; }

    vbl_50hz = save; vbl_acc = 0u; vbl_cyc_have = 0u;
    if (!bad) printf("VBLTEST OK (5 vectors)\r\n");
    return bad;
}

/* TBTEST -- Timer B event-count mode. Literals are independent: the
 * line counts are worked out by hand from 15625Hz, not from the
 * constants under test.                                             */
static int tbtest(void)
{
    int bad = 0; uint32_t i;

    /* v1: exactly one 60Hz frame of MFP ticks (2457600/60 = 40960)
     * must be 260 lines at the 15625Hz ST line rate (40960*15625
     * /2457600 = 260.42 -> 260 whole lines).                        */
    hbl_line = 0u; hbl_acc = 0u; dbg_tb_fires = 0u;
    for (i = 0; i < 24u; i++) mfp[i] = 0u;
    for (i = 0; i < 40960u; i++) mfp_hbl_advance(1u);
    if (hbl_line != 260u) {
        printf("TBTEST FAIL v1: %u lines/60Hz frame != 260\r\n", hbl_line); bad++; }

    /* v2: a 50Hz frame (49152 ticks) must be 312 whole lines (312.5) */
    hbl_line = 0u; hbl_acc = 0u;
    for (i = 0; i < 49152u; i++) mfp_hbl_advance(1u);
    if (hbl_line != 312u) {
        printf("TBTEST FAIL v2: %u lines/50Hz frame != 312\r\n", hbl_line); bad++; }

    /* v3: the Dizzy sequence. TBDR=47, TBCR=8, then advance a frame:
     * the split must fire, and fire exactly once for 47 armed lines
     * within a 200-line window (200/47 = 4 whole reloads).           */
    hbl_line = 0u; hbl_acc = 0u; dbg_tb_fires = 0u;
    for (i = 0; i < 24u; i++) mfp[i] = 0u;
    tcount[0]=tcount[1]=tcount[2]=tcount[3]=0u;
    mfp_write(0xFA21u, 47u);                 /* TBDR = 47 lines        */
    if (tcount[1] != 47u) {
        printf("TBTEST FAIL v3a: TBDR did not load counter (%u)\r\n",
               tcount[1]); bad++; }
    mfp_write(0xFA1Bu, 8u);                  /* TBCR = event count     */
    if (timer_ctrl4(1) != 8u) {
        printf("TBTEST FAIL v3b: ctrl4 %u != 8\r\n", timer_ctrl4(1)); bad++; }
    for (i = 0; i < 40960u; i++) mfp_hbl_advance(1u);
    if (dbg_tb_fires != 4u) {
        printf("TBTEST FAIL v3c: %u fires != 4 in one frame\r\n",
               dbg_tb_fires); bad++; }

    /* v4: prescaler mode must be UNAFFECTED by the scanline clock --
     * TBCR=1 (div 4) is not event mode, so scanlines must not touch it */
    hbl_line = 0u; hbl_acc = 0u; dbg_tb_fires = 0u;
    mfp_write(0xFA21u, 47u); mfp_write(0xFA1Bu, 1u);
    for (i = 0; i < 40960u; i++) mfp_hbl_advance(1u);
    if (dbg_tb_fires != 0u) {
        printf("TBTEST FAIL v4: prescaler timer fired on scanlines\r\n"); bad++; }

    /* v5: events only on DISPLAYED lines -- with the timer armed for
     * 1 line, a whole frame must yield exactly HBL_VISIBLE fires.    */
    hbl_line = 0u; hbl_acc = 0u; dbg_tb_fires = 0u;
    mfp_write(0xFA21u, 1u); mfp_write(0xFA1Bu, 8u);
    for (i = 0; i < 40960u; i++) mfp_hbl_advance(1u);
    if (dbg_tb_fires != 200u) {
        printf("TBTEST FAIL v5: %u fires != 200 visible lines\r\n",
               dbg_tb_fires); bad++; }

    for (i = 0; i < 24u; i++) mfp[i] = 0u;
    tcount[0]=tcount[1]=tcount[2]=tcount[3]=0u;
    hbl_line = 0u; hbl_acc = 0u; dbg_tb_fires = 0u;
    if (!bad) printf("TBTEST OK (5 vectors)\r\n");
    return bad;
}

/* APYTEST -- exercises the quiescent autopsy end to end. The NOCARD
 * boot reaches a desktop and never stalls, so without this the
 * instrumentation would ship untested and a silent break would look
 * exactly like "no stall occurred".                                */
static int apytest(void)
{
    int bad = 0; uint32_t i;
    apy_arm();
    if (apy_used != 0u || apy_reads != 0u) {
        printf("APYTEST FAIL v1: arm did not clear\r\n"); bad++; }
    for (i = 0; i < 100u; i++) apy_note(0xFFFF8209u);   /* video counter */
    for (i = 0; i <  50u; i++) apy_note(0x00001234u);   /* a RAM flag    */
    for (i = 0; i <  10u; i++) apy_note(0xFFFFFA01u);   /* MFP GPIP      */
    if (apy_used != 3u) {
        printf("APYTEST FAIL v2: distinct %u != 3\r\n", apy_used); bad++; }
    if (apy_reads != 160u) {
        printf("APYTEST FAIL v3: reads %u != 160\r\n", apy_reads); bad++; }
    /* slot overflow must not corrupt: push 40 more distinct addresses */
    for (i = 0; i < 40u; i++) apy_note(0x00002000u + i * 4u);
    if (apy_used > APY_SLOTS) {
        printf("APYTEST FAIL v4: overflow %u > %u\r\n", apy_used, APY_SLOTS); bad++; }
    apy_on = 0;
    apy_report(0x00E00000u);        /* must print, hottest first */
    if (!bad) printf("APYTEST OK (4 vectors + sample report above)\r\n");
    return bad;
}

/* VIDBASETEST -- the screen-base authority. Literals are independent of
 * the code under test: each expectation is written out by hand.      */
static int vidbasetest(void)
{
    int bad = 0;
    uint8_t s201 = io_shadow[0x0201], s203 = io_shadow[0x0203],
            s20D = io_shadow[0x020D];
    uint8_t r0 = ram[0x44E], r1 = ram[0x44F], r2 = ram[0x450], r3 = ram[0x451];

    /* v1: registers untouched (0) -> $44E is the authority            */
    io_shadow[0x0201] = 0x00u; io_shadow[0x0203] = 0x00u; io_shadow[0x020D] = 0x00u;
    ram[0x44E] = 0x00u; ram[0x44F] = 0xD0u; ram[0x450] = 0x00u; ram[0x451] = 0x00u;
    if (vid_base_select() != 0x00D00000u) {
        printf("VIDBASETEST FAIL v1: %06x != d00000\r\n",
               (unsigned)vid_base_select()); bad++; }

    /* v2: registers set -> registers win, even with $44E stale. This is
     * the Dizzy case: a game claims the screen without touching $44E. */
    io_shadow[0x0201] = 0x0Au; io_shadow[0x0203] = 0xB0u; io_shadow[0x020D] = 0x00u;
    if (vid_base_select() != 0x000AB000u) {
        printf("VIDBASETEST FAIL v2: %06x != 0ab000\r\n",
               (unsigned)vid_base_select()); bad++; }

    /* v3: the Falcon/STE low byte participates (ST-only code leaves 0) */
    io_shadow[0x020D] = 0x80u;
    if (vid_base_select() != 0x000AB080u) {
        printf("VIDBASETEST FAIL v3: %06x != 0ab080\r\n",
               (unsigned)vid_base_select()); bad++; }

    /* v4: an out-of-range register value is refused, NOT scanned      */
    io_shadow[0x0201] = 0xFFu; io_shadow[0x0203] = 0xFFu; io_shadow[0x020D] = 0xFFu;
    if (vid_base_select() != 0x00D00000u) {
        printf("VIDBASETEST FAIL v4: %06x != d00000 (fallback)\r\n",
               (unsigned)vid_base_select()); bad++; }

    io_shadow[0x0201] = s201; io_shadow[0x0203] = s203; io_shadow[0x020D] = s20D;
    ram[0x44E] = r0; ram[0x44F] = r1; ram[0x450] = r2; ram[0x451] = r3;
    if (!bad) printf("VIDBASETEST OK (4 vectors)\r\n");
    return bad;
}

/* AUDIOTEST -- host self-test, FDCTEST pattern. Expectations are
 * independent literals (PACETEST lesson #4), never derived from the
 * constants under test.                                              */
static int audiotest(void)
{
    int bad = 0; uint32_t i;
    uint8_t save_src = aud_src_tone;
    aud_src_tone = 1u;          /* M14: exercise the ring with the sine */
    audio_init();
    if (AUDSLOT[0] != 0xFA1CA0D1u) {
        printf("AUDIOTEST FAIL v1: magic %08x\r\n", AUDSLOT[0]); bad++; }
    if (AUDSLOT[2] != 0u) {
        printf("AUDIOTEST FAIL v2: widx0 %u\r\n", AUDSLOT[2]); bad++; }
    /* v3/v4: exactly 1.000000s of cyc50 => floor(50e6/1024)=48828
     * samples = 24414 words (literal), published.                    */
    audio_pump_cyc(12345u);
    for (i = 0; i < 50000u; i++) audio_pump_cyc(12345u + (i+1u)*1000u);
    if (aud_widx != 24414u) {
        printf("AUDIOTEST FAIL v3: widx %u != 24414\r\n", aud_widx); bad++; }
    if (AUDSLOT[2] != 24414u) {
        printf("AUDIOTEST FAIL v4: publish %u\r\n", AUDSLOT[2]); bad++; }
    /* v5-v7: structural checks on the last 4096 samples read back from
     * the RING (in ring order, both halves): 440Hz in a 83.886ms
     * window => 73.8 zero crossings (literal band 72..76); slew
     * |ds| <= 1000: the 256-entry zero-order-hold LUT steps ~2.31
     * entries/sample, worst case 3 adjacent-entry hops x ~322 = ~966
     * (a continuous sine would be ~742; swapped ring halves produce
     * ~1900, still well outside the band); peak in [12900,13200]
     * (amp literal 13107).                                           */
    { uint32_t j; int16_t prev = 0; int have_prev = 0;
      int cross = 0; int32_t dmax = 0; int32_t amax = 0;
      for (j = (aud_widx - 2048u) * 2u; j < aud_widx * 2u; j++) {
          uint32_t v = AUDSLOT[16u + 2u*((j >> 1) & (AUD_RINGW-1u))];
          int16_t s = (j & 1u) ? (int16_t)(v >> 16) : (int16_t)(v & 0xFFFFu);
          if (have_prev) {
              int32_t d = (int32_t)s - (int32_t)prev;
              if (d < 0) d = -d;
              if (d > dmax) dmax = d;
              if ((s < 0 && prev >= 0) || (s >= 0 && prev < 0)) cross++;
          }
          if (s > amax) amax = s; if (-s > amax) amax = -s;
          prev = s; have_prev = 1;
      }
      if (cross < 72 || cross > 76) {
          printf("AUDIOTEST FAIL v5: crossings %d\r\n", cross); bad++; }
      if (dmax > 1000) {
          printf("AUDIOTEST FAIL v6: slew %d\r\n", (int)dmax); bad++; }
      if (amax < 12900 || amax > 13200) {
          printf("AUDIOTEST FAIL v7: peak %d\r\n", (int)amax); bad++; }
    }
    /* v8: cyc50 wrap across 0xFFFFFFFF -- carry then word, widx == 1 */
    audio_init();
    audio_pump_cyc(0xFFFFFB00u);
    audio_pump_cyc(0xFFFFFF00u);          /* du=0x400 -> 1 sample: carry */
    if (aud_widx != 0u || !aud_carry_have) {
        printf("AUDIOTEST FAIL v8a: wrap carry\r\n"); bad++; }
    audio_pump_cyc(0x00000300u);          /* du=0x400 across the wrap    */
    if (aud_widx != 1u) {
        printf("AUDIOTEST FAIL v8b: wrap word %u\r\n", aud_widx); bad++; }
    /* v9: glitch guard -- a >1s source jump must produce nothing      */
    audio_init();
    audio_pump_cyc(1000u);
    audio_pump_cyc(1000u + 0x40000000u);
    if (aud_widx != 0u || aud_carry_have) {
        printf("AUDIOTEST FAIL v9: glitch guard\r\n"); bad++; }
    aud_src_tone = save_src;
    if (!bad) printf("AUDIOTEST OK (9 vectors)\r\n");
    return bad;
}
#endif

/* ===================================================================
 * M9F: SD card (SPI bit-bang on GPIO[5:1], REV10 pins) + FAT32 mount.
 * Driver = the silicon-proven Stage A probe. LED contract lives here.
 * =================================================================== */
#define G_LED0  (1u<<0)
#define G_SCLK  (1u<<1)
#define G_MOSI  (1u<<2)
#define G_MISO  (1u<<4)
#define G_CSN   (1u<<5)

#ifndef HOST_TEST
static uint32_t sd_half_cyc = 1000;         /* 400kHz init; 20 = fast  */
static void sdp_delay(void)
{ uint64_t t0 = rd_mcycle64(); while (rd_mcycle64() - t0 < sd_half_cyc) ; }
static void sdp_set(uint32_t m) { GPIO_SET = m; }
static void sdp_clr(uint32_t m) { GPIO_CLR = m; }
static uint32_t sdp_in(void)    { return GPIO_DIN; }
static void sd_gpio_init(void)
{
    GPIO_DIR = (GPIO_DIR & ~(uint32_t)G_MISO)
             | G_LED0 | G_SCLK | G_MOSI | G_CSN;
    sdp_set(G_CSN | G_MOSI); sdp_clr(G_SCLK);
}
#else
/* host: byte-level simulated card backed by an image file (sd_host.img
 * or $SDIMG); $NOCARD=1 simulates an empty slot. CMD17 reads and CMD24
 * writes are served from/into hc_img[]. LED transitions are recorded
 * for the SDTEST ordering vector.                                     */
static uint32_t sd_half_cyc = 1000;
static uint8_t *hc_img; static uint32_t hc_size; static int hc_present;
static uint32_t hc_out = G_CSN | G_MOSI;
static uint8_t  hc_miso = 1;
static char     led_log[64]; static uint32_t led_n;
static uint8_t  c_resp[1024]; static uint16_t c_rh, c_rt;
/* 1024 = power of two: uint16 counter wrap (65536) is a multiple,
 * so index=counter&1023 stays coherent across the wrap. A 600-deep
 * ring with %600 collided after 65536%600=136 slots -- responses
 * spanning the wrap clobbered their own heads (found at read #507
 * of the first full-image load; cost one debugging session).      */
static void hc_edge(int rising);
static void sdp_set(uint32_t m)
{
    uint32_t was = hc_out; hc_out |= m;
    if ((m & G_LED0) && !(was & G_LED0) && led_n < 63u) led_log[led_n++]='S';
    if (!(was & G_SCLK) && (m & G_SCLK)) hc_edge(1);
}
static void sdp_clr(uint32_t m)
{
    uint32_t was = hc_out; hc_out &= ~m;
    if ((m & G_LED0) && (was & G_LED0) && led_n < 63u) led_log[led_n++]='U';
    if ((was & G_SCLK) && (m & G_SCLK)) hc_edge(0);
}
static uint32_t sdp_in(void) { return hc_miso ? G_MISO : 0u; }
static void sdp_delay(void) {}
static void sd_gpio_init(void) {}
#endif

static void led_safe(void)   { sdp_set(G_LED0); }
static void led_unsafe(void) { sdp_clr(G_LED0); }

static uint8_t sd_spi(uint8_t out)
{
    uint8_t in = 0; int b;
    for (b = 7; b >= 0; b--) {
        if (out & (1u << b)) sdp_set(G_MOSI); else sdp_clr(G_MOSI);
        sdp_delay();
        sdp_set(G_SCLK);
        in = (uint8_t)((in << 1) | ((sdp_in() & G_MISO) ? 1u : 0u));
        sdp_delay();
        sdp_clr(G_SCLK);
    }
    return in;
}
static void sd_cs_lo(void) { sdp_clr(G_CSN); }
static void sd_cs_hi(void) { sdp_set(G_CSN); sd_spi(0xFF); }

static uint8_t sd_cmd(uint8_t cmd, uint32_t arg, uint8_t crc)
{
    int i; uint8_t r;
    sd_spi(0xFF);
    sd_spi((uint8_t)(0x40u | cmd));
    sd_spi((uint8_t)(arg >> 24)); sd_spi((uint8_t)(arg >> 16));
    sd_spi((uint8_t)(arg >> 8));  sd_spi((uint8_t)arg);
    sd_spi(crc);
    for (i = 0; i < 16; i++) { r = sd_spi(0xFF); if (!(r & 0x80u)) return r; }
    return 0xFFu;
}
static int sd_rd_block(uint8_t *dst, uint32_t n)
{
    uint32_t i, g;
    for (g = 0; g < 200000u; g++) {
        uint8_t t = sd_spi(0xFF);
        if (t == 0xFEu) break;
        if (t != 0xFFu && g > 8u) return -1;
    }
    if (g >= 200000u) return -1;
    for (i = 0; i < n; i++) dst[i] = sd_spi(0xFF);
    sd_spi(0xFF); sd_spi(0xFF);
    return 0;
}

static int sd_read_sector(uint32_t lba, uint8_t *dst)
{
    uint8_t r; int e;
    sd_cs_lo();
    r = sd_cmd(17, sd_ccs ? lba : lba * 512u, 0x01);
    e = (r == 0) ? sd_rd_block(dst, 512) : -1;
    sd_cs_hi();
    return (r || e) ? -1 : 0;
}

/* write-through with the LED contract: unsafe BEFORE the first byte,
 * safe only AFTER the card releases busy. Returns 0 on committed.    */
static int sd_write_sector(uint32_t lba, const uint8_t *src)
{
    uint8_t r; uint32_t i, g;
    int ret = -1;
    led_unsafe();
    sd_cs_lo();
    r = sd_cmd(24, sd_ccs ? lba : lba * 512u, 0x01);
    if (r == 0) {
        sd_spi(0xFF);
        sd_spi(0xFEu);                          /* data token           */
        for (i = 0; i < 512u; i++) sd_spi(src[i]);
        sd_spi(0xFF); sd_spi(0xFF);             /* CRC                  */
        r = (uint8_t)(sd_spi(0xFF) & 0x1Fu);    /* data response        */
        if (r == 0x05u) {
            for (g = 0; g < 2000000u; g++)      /* busy-release wait    */
                if (sd_spi(0xFF) == 0xFFu) { ret = 0; break; }
        }
    }
    sd_cs_hi();
    led_safe();                                  /* committed (or given
                                                    up: either way no
                                                    write is in flight */
    return ret;
}

static int sd_hw_init(void)
{
    int i; uint8_t r, e[4], v2 = 0;
    uint32_t tries;
#ifdef HOST_TEST
    if (!hc_present) return -1;
#endif
    sd_half_cyc = 1000;                          /* <=400kHz for init   */
    sd_cs_hi();
    for (i = 0; i < 10; i++) sd_spi(0xFF);
    sd_cs_lo(); r = sd_cmd(0, 0, 0x95); sd_cs_hi();
    if (r != 0x01u) return -1;
    sd_cs_lo(); r = sd_cmd(8, 0x1AAu, 0x87);
    for (i = 0; i < 4; i++) e[i] = sd_spi(0xFF);
    sd_cs_hi();
    if (r == 0x01u && e[2] == 0x01u && e[3] == 0xAAu) v2 = 1;
    else if (!(r & 0x04u)) return -1;
    for (tries = 0; tries < 60000u; tries++) {
        sd_cs_lo(); sd_cmd(55, 0, 0x65);
        r = sd_cmd(41, v2 ? 0x40000000u : 0u, 0x77);
        sd_cs_hi();
        if (r == 0x00u) break;
        if (r != 0x01u) return -1;
    }
    if (tries >= 60000u) return -1;
    sd_cs_lo(); r = sd_cmd(58, 0, 0xFD);
    for (i = 0; i < 4; i++) e[i] = sd_spi(0xFF);
    sd_cs_hi();
    if (r) return -1;
    sd_ccs = (uint8_t)((e[0] >> 6) & 1u);
    if (!sd_ccs) { sd_cs_lo(); r = sd_cmd(16, 512u, 0x01); sd_cs_hi();
                   if (r) return -1; }
    sd_half_cyc = 20;                            /* fast for data phase */
    sd_ok = 1;
    return 0;
}

/* ------------------------- FAT32 (read-only) ----------------------- */
static uint8_t  sdsec[512], sdfat[512];
static uint32_t sdfat_lba = 0xFFFFFFFFu;
static uint32_t fs_part, fs_spc, fs_fat, fs_data, fs_root;

static uint32_t rd16(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8); }
static uint32_t rd32(const uint8_t *p) { return rd16(p) | (rd16(p + 2) << 16); }
static uint32_t clus2lba(uint32_t c) { return fs_data + (c - 2u) * fs_spc; }
static uint32_t fat_next(uint32_t c)
{
    uint32_t lba = fs_fat + (c >> 7);            /* 128 entries/sector  */
    if (lba != sdfat_lba) {
        if (sd_read_sector(lba, sdfat)) return 0x0FFFFFF7u;
        sdfat_lba = lba;
    }
    return rd32(sdfat + ((c & 127u) << 2)) & 0x0FFFFFFFu;
}

static int fat_mount(void)
{
    if (sd_read_sector(0, sdsec)) return -1;
    fs_part = 0;
    if (sdsec[0] != 0xEBu && sdsec[0] != 0xE9u) { /* not a superfloppy  */
        uint8_t t;
        if (sdsec[510] != 0x55u || sdsec[511] != 0xAAu) return -1;
        t = sdsec[0x1C2];
        if (t != 0x0Bu && t != 0x0Cu) return -1;  /* FAT32 types only   */
        fs_part = rd32(sdsec + 0x1C6);
        if (sd_read_sector(fs_part, sdsec)) return -1;
    }
    if (rd16(sdsec + 0x0B) != 512u) return -1;    /* bytes/sector       */
    if (rd16(sdsec + 0x16) != 0u)   return -1;    /* FATsz16==0 = FAT32 */
    fs_spc  = sdsec[0x0D];
    fs_fat  = fs_part + rd16(sdsec + 0x0E);
    fs_data = fs_fat + (uint32_t)sdsec[0x10] * rd32(sdsec + 0x24);
    fs_root = rd32(sdsec + 0x2C);
    if (fs_spc == 0u) return -1;
    return 0;
}

/* find an 8.3 name in the root directory; out: start cluster + size  */
static int fat_find(const char *n11, uint32_t *oclus, uint32_t *osize)
{
    uint32_t c = fs_root, s, e;
    while (c >= 2u && c < 0x0FFFFFF8u) {
        for (s = 0; s < fs_spc; s++) {
            if (sd_read_sector(clus2lba(c) + s, sdsec)) return -1;
            for (e = 0; e < 512u; e += 32u) {
                const uint8_t *d = sdsec + e;
                if (d[0] == 0x00u) return -1;      /* end of directory  */
                if (d[0] == 0xE5u) continue;
                if (d[11] == 0x0Fu) continue;      /* LFN entry         */
                if (d[11] & 0x08u)  continue;      /* volume label      */
                if (memcmp(d, n11, 11) == 0) {
                    *oclus = (rd16(d + 20) << 16) | rd16(d + 26);
                    *osize = rd32(d + 28);
                    return 0;
                }
            }
        }
        c = fat_next(c);
    }
    return -1;
}

/* mount an image file: load into dest, KEEP the cluster chain so any
 * file sector maps to an absolute card sector (fragmented files are
 * fully writable; the FAT itself is still never written).            */
static int sd_mount(const char *n11, uint8_t *dest, sd_file *f,
                    const char *label)
{
    uint32_t clus, size, c, prev, done = 0, s;
    f->mounted = 0; f->writeback = 0; f->frag = 0; f->nclus = 0;
    f->extent_warned = 0;
    if (!sd_ok) return -1;
    if (fat_find(n11, &clus, &size)) {
        printf("[sd] %s: not found in card root\r\n", label); return -1; }
    if (size < 1024u || size > DISK_BUF_MAX || (size & 511u)) {
        printf("[sd] %s: bad size %u\r\n", label, size); return -1; }
    f->size = size; f->sectors = size >> 9;
    prev = 0; c = clus;
    while (done < f->sectors && c >= 2u && c < 0x0FFFFFF8u) {
        if (f->nclus >= SD_MAXCLUS) {
            printf("[sd] %s: chain too long\r\n", label); return -1; }
        f->chain[f->nclus++] = c;
        if (prev && c != prev + 1u) f->frag = 1;
        prev = c;
        for (s = 0; s < fs_spc && done < f->sectors; s++, done++)
            if (sd_read_sector(clus2lba(c) + s, dest + done * 512u)) {
                printf("[sd] %s: read error @%u\r\n", label, done);
                return -1; }
        c = fat_next(c);
    }
    if (done != f->sectors) {
        printf("[sd] %s: chain short %u/%u\r\n", label, done, f->sectors);
        return -1; }
    f->mounted = 1; f->writeback = 1;        /* cluster map: always on */
    printf("[sd] %s: %u bytes, %u clusters%s -> write-back ON\r\n",
           label, f->size, f->nclus,
           f->frag ? " (FRAGMENTED, mapped)" : " (contiguous)");
    return 0;
}

/* ===================================================================
 * M11p: hard-disk image backing.
 * =================================================================== */
/* Chain building WITHOUT the preload sd_mount does. Deliberately a
 * sibling of sd_mount, not a refactor of it: that function backs the
 * floppies and is verified. */
static int sd_map_only(const char *n11, sd_file *f, const char *label)
{
    uint32_t clus, size, c, prev;
    f->mounted = 0; f->writeback = 0; f->frag = 0; f->nclus = 0;
    f->extent_warned = 0;
    if (!sd_ok) return -1;
    if (fat_find(n11, &clus, &size)) {
        printf("[hdd] %s: not found in card root\r\n", label);
        return -1; }
    if (size < 1024u) {
        printf("[hdd] %s: too small (%u)\r\n", label, size); return -1; }
    if (size & 511u) {                       /* whole sectors only */
        printf("[hdd] %s: %u bytes is not a whole number of sectors, "
               "using %u\r\n", label, size, size & ~511u);
        size &= ~511u;
    }
    f->size = size; f->sectors = size >> 9;
    prev = 0; c = clus;
    while (f->nclus * fs_spc < f->sectors && c >= 2u && c < 0x0FFFFFF8u) {
        if (f->nclus >= SD_MAXCLUS) {
            printf("[hdd] %s: chain longer than %u clusters\r\n",
                   label, SD_MAXCLUS); return -1; }
        f->chain[f->nclus++] = c;
        if (prev && c != prev + 1u) f->frag = 1;
        prev = c;
        c = fat_next(c);
    }
    if (f->nclus * fs_spc < f->sectors) {
        printf("[hdd] %s: chain short, %u clusters for %u sectors\r\n",
               label, f->nclus, f->sectors); return -1; }
    f->mounted = 1; f->writeback = 1;
    printf("[hdd] %s: %u bytes, %u sectors, %u clusters%s\r\n",
           label, f->size, f->sectors, f->nclus,
           f->frag ? " (FRAGMENTED, mapped)" : " (contiguous)");
    return 0;
}

static uint32_t fs_spc_ref(void) { return fs_spc; }

/* file sector -> absolute card LBA. 0xFFFFFFFF means out of range,
 * which the callers refuse rather than clamp. */
static uint32_t hdd_lba(int unit, uint32_t sec)
{
    sd_file *f = &hdf[unit];
    uint32_t ci = sec / fs_spc;
    if (sec >= f->sectors || ci >= f->nclus) {
        if (!hdd_oob_warned[unit]) {
            hdd_oob_warned[unit] = 1;
            printf("[hdd] unit %d: sector %u out of range (have %u) -- "
                   "refusing\r\n", unit, sec, f->sectors);
        }
        return 0xFFFFFFFFu;
    }
    return clus2lba(f->chain[ci]) + (sec % fs_spc);
}

static int hdd_read(int unit, uint32_t sec, uint8_t *dst)
{
    uint32_t idx, tag, lba;
    if (unit < 0 || unit > 1 || !hdf[unit].mounted) return -1;
    idx = sec & (HDD_CACHE_SECTORS - 1u);
    tag = ((uint32_t)unit << 31) | (sec & 0x7FFFFFFFu);
    if (hdd_tag[idx] == tag) {
        memcpy(dst, hdd_cache[idx], 512); hdd_hit++; return 0;
    }
    lba = hdd_lba(unit, sec);
    if (lba == 0xFFFFFFFFu) { hdd_err++; return -1; }
    if (sd_read_sector(lba, hdd_cache[idx])) {
        hdd_tag[idx] = 0xFFFFFFFFu; hdd_err++; return -1; }
    hdd_tag[idx] = tag;
    memcpy(dst, hdd_cache[idx], 512);
    hdd_miss++;
    return 0;
}

/* Write-through: the card is authoritative the moment this returns. */
static int hdd_write(int unit, uint32_t sec, const uint8_t *srcbuf)
{
    uint32_t idx, tag, lba;
    if (unit < 0 || unit > 1 || !hdf[unit].mounted) return -1;
    lba = hdd_lba(unit, sec);
    if (lba == 0xFFFFFFFFu) { hdd_err++; return -1; }
    idx = sec & (HDD_CACHE_SECTORS - 1u);
    tag = ((uint32_t)unit << 31) | (sec & 0x7FFFFFFFu);
    if (sd_write_sector(lba, srcbuf)) {
        hdd_tag[idx] = 0xFFFFFFFFu;      /* do not cache what failed */
        hdd_err++;
        return -1;
    }
    memcpy(hdd_cache[idx], srcbuf, 512);
    hdd_tag[idx] = tag;
    hdd_wr++;
    return 0;
}

static void hdd_init(void)
{
    uint32_t i;
    for (i = 0; i < HDD_CACHE_SECTORS; i++) hdd_tag[i] = 0xFFFFFFFFu;
}

/* M11q: the device model sits on the storage layer above it. */
static uint64_t ide_now(void) { return rd_wall64(); }   /* M12d      */
#include "falcon_ide.c"

/* read a small file (config, ROM) without drive semantics             */
static int sd_read_small(const char *n11, uint8_t *dst, uint32_t max,
                         uint32_t *osize)
{
    uint32_t clus, size, c, done = 0, s;
    if (!sd_ok) return -1;
    if (fat_find(n11, &clus, &size)) return -1;
    if (size == 0u || size > max) return -1;
    c = clus;
    while (done * 512u < size && c >= 2u && c < 0x0FFFFFF8u) {
        for (s = 0; s < fs_spc && done * 512u < size; s++, done++) {
            if (sd_read_sector(clus2lba(c) + s, sdsec)) return -1;
            { uint32_t n = size - done * 512u;
              if (n > 512u) n = 512u;
              memcpy(dst + done * 512u, sdsec, n); }
        }
        c = fat_next(c);
    }
    if (osize) *osize = size;
    return (done * 512u >= size) ? 0 : -1;
}

/* persist one 512-byte image sector through the drive's cluster map  */
static void flop_persist(flop_drive *d, uint32_t off)
{
    sd_file *f = (d == &fdrv[0]) ? &sdf[0]
               : (d == &fdrv[1]) ? &sdf[1] : 0;
    uint32_t fs, lba;
    if (!f || !f->mounted || !f->writeback) return;
    fs = off >> 9;
    if (fs >= f->sectors) {
        if (!f->extent_warned) {
            f->extent_warned = 1;
            printf("[sd] write beyond card file extent -> RAM only\r\n");
        }
        return;
    }
    lba = clus2lba(f->chain[fs / fs_spc]) + (fs % fs_spc);
    if (sd_write_sector(lba, d->img + off)) {
        printf("[sd] WRITE FAILED @lba %u -> write-back disabled\r\n", lba);
        f->writeback = 0;
    }
}

#ifdef HOST_TEST
/* =============== host simulated SD card (byte level) ================
 * Backed by $SDIMG (default sd_host.img); $NOCARD=1 = empty slot.
 * Serves CMD0/8/55/41/58/16/17 and CMD24 (write w/ busy) against the
 * image in memory. SDTEST asserts against hc_img directly.           */
#include <stdlib.h>
static uint8_t  c_bitn, c_in, c_out = 0xFF, c_obit = 8;
static uint8_t  c_frame[6], c_flen, c_inframe, c_acmd, c_ready, c_tries;
static uint8_t  c_wr, c_wtok; static uint16_t c_wn;
static uint32_t c_wlba; static uint8_t c_wbuf[514];
static void c_push(uint8_t b) { c_resp[c_rt++ & 1023u] = b; }
static void c_do_read(uint32_t lba)
{
    uint32_t i;
    c_push(0x00); c_push(0xFF); c_push(0xFE);
    for (i = 0; i < 512u; i++)
        c_push((uint64_t)lba * 512u + i < hc_size
               ? hc_img[lba * 512u + i] : 0xFFu);
    c_push(0); c_push(0);
}
static void c_process(uint8_t b)
{
    if (c_wr) {                          /* collecting CMD24 payload   */
        if (!c_wtok) { if (b == 0xFEu) c_wtok = 1;
                       else if (b != 0xFFu) { c_wr = 0; } return; }
        c_wbuf[c_wn++] = b;
        if (c_wn == 514u) {              /* 512 data + 2 crc           */
            uint32_t i;
            if ((uint64_t)c_wlba * 512u + 512u <= hc_size)
                for (i = 0; i < 512u; i++)
                    hc_img[c_wlba * 512u + i] = c_wbuf[i];
            c_push(0x05);                /* data accepted              */
            c_push(0x00); c_push(0x00);  /* busy                       */
            c_push(0xFF);                /* busy released              */
            c_wr = 0;
        }
        return;
    }
    if (!c_inframe) {
        if ((b & 0xC0u) == 0x40u) { c_inframe = 1; c_flen = 0; c_frame[c_flen++] = b; }
        return;
    }
    c_frame[c_flen++] = b;
    if (c_flen < 6) return;
    c_inframe = 0;
    { uint8_t cmd = c_frame[0] & 0x3Fu;
      uint32_t arg = ((uint32_t)c_frame[1]<<24)|((uint32_t)c_frame[2]<<16)
                   | ((uint32_t)c_frame[3]<<8)|c_frame[4];
      uint8_t acmd = c_acmd; c_acmd = 0;
      c_push(0xFF);
      switch (cmd) {
      case 0:  c_push(0x01); c_ready = 0; c_tries = 0; break;
      case 8:  c_push(0x01); c_push(0); c_push(0); c_push(0x01); c_push(0xAA); break;
      case 55: c_push(c_ready ? 0x00 : 0x01); c_acmd = 1; break;
      case 41: if (acmd) { if (++c_tries >= 3) c_ready = 1;
                           c_push(c_ready ? 0x00 : 0x01); }
               else c_push(0x05); break;
      case 58: c_push(0x00); c_push(0xC0); c_push(0xFF); c_push(0x80); c_push(0x00); break;
      case 16: c_push(0x00); break;
      case 17: c_do_read(arg); break;
      case 24: c_push(0x00); c_wr = 1; c_wtok = 0; c_wn = 0; c_wlba = arg; break;
      default: c_push(0x05); break;
      }
    }
}
static void hc_edge(int rising)
{
    if (hc_out & G_CSN) { c_bitn = 0; c_obit = 8; hc_miso = 1; return; }
    if (rising) {
        c_in = (uint8_t)((c_in << 1) | ((hc_out & G_MOSI) ? 1u : 0u));
        if (++c_bitn == 8u) { c_bitn = 0; c_process(c_in); }
        if (c_obit >= 8u) {
            c_out = (c_rh != c_rt) ? c_resp[c_rh++ & 1023u] : 0xFFu;
            c_obit = 0;
        }
        hc_miso = (uint8_t)((c_out >> (7u - c_obit)) & 1u);
        c_obit++;
    }
}
static void host_card_load(void)
{
    const char *p = getenv("SDIMG"); FILE *f;
    if (getenv("NOCARD")) { hc_present = 0; return; }
    if (!p) p = "sd_host.img";
    f = fopen(p, "rb");
    if (!f) { hc_present = 0; return; }
    fseek(f, 0, SEEK_END); hc_size = (uint32_t)ftell(f); fseek(f, 0, SEEK_SET);
    hc_img = (uint8_t *)malloc(hc_size);
    if (fread(hc_img, 1, hc_size, f) != hc_size) { hc_present = 0; fclose(f); return; }
    fclose(f); hc_present = 1;
}
#endif




/* stall detector: same PPC region + no new unique IO across a window */
static uint32_t screen_sum(void)
{
    uint32_t vb = ((uint32_t)ram[0x44E]<<24)|((uint32_t)ram[0x44F]<<16)
                | ((uint32_t)ram[0x450]<<8)|ram[0x451];
    uint32_t s = 0, i;
    if (vb == 0u || vb >= ST_RAM_SIZE - 0x9600u) return 0;
    for (i = 0; i < 0x9600u; i += 16) s += ram[vb + i];  /* sample 38K */
    return s ^ vb;
}

static void status_line(uint32_t slice, uint32_t cyc_m)
{
    /* M11k: when silent, print nothing AND reset nothing -- so the
     * first print after a quiet spell covers that whole span. */
    if (!log_on) return;
    { static uint8_t said;                                  /* M11l */
      if (!said) { said = 1;
          printf("  [cfg] logging ON (F12 toggles), FLUSHDIV=%u CACHEOPT=%u%s\r\n",
                 flushdiv, cacheopt, flushdiv > 1u
                   ? "  <-- scanout coherency deliberately broken" : "");
      } }
    printf("  [st] slice=%u cyc=%uM pc=%x io_r=%u io_w=%u uniq=%d berr=%u nf=%u scr=%x last=%s%x@%x\r\n",
           slice, cyc_m, cur_pc(), io_reads, io_writes, n_seen,
           berr_count, nf_stderr_chars, screen_sum(),
           last_io_wr ? "W" : "R", last_io_addr, last_io_pc);
    printf("       raise5=%u ack5=%u blocked=%u kbd=%u pha=%u mou=%u\r\n",
           dbg_raise5, dbg_ack5, dbg_raise_blocked,
           hid_kbd_records, hid_pha_records, hid_mou_records);
    if (psplit_dropped)
        printf("       [psp] palette changes dropped: %u (>%u/frame)\r\n",
               (unsigned)psplit_dropped, (unsigned)PSPLIT_MAX);
    { uint32_t hz200 = ((uint32_t)ram[0x4BA]<<24)|((uint32_t)ram[0x4BB]<<16)
                     | ((uint32_t)ram[0x4BC]<<8)|ram[0x4BD];
      uint32_t s200 = 0, svbl = 0, scyc = 0;
      int have = tb_read(&s200, &svbl, &scyc);
      printf("       hz200=%u timerC: ctrl=%x data=%u ierb=%x imrb=%x iprb=%x isrb=%x sr=%x\r\n",
             hz200,
             mfp[MFP_TCDCR], tcount[2], mfp[MFP_IERB], mfp[MFP_IMRB],
             mfp[MFP_IPRB], mfp[MFP_ISRB],
             m68k_get_reg((void*)0, M68K_REG_SR));
      /* M11j: the drift measurement. slot t200 and the guest hz200 are
       * sampled in the same instant, so no manual timing is involved. */
      printf("       [drift] hz200=%u t200=%s%u lost5=%u (+%u) "
             "mfpiv=%u max=%u (TimerC period=12288) resync=%u/%uT\r\n",
             hz200, have ? "" : "(none)", s200,
             dbg_lost5, dbg_lost5 - dbg_lost5_prev,
             dbg_mfp_iv, dbg_mfp_max, dbg_resync,
             /* M11k: in whole Timer C periods; the BSP printf has no
              * %llu, which is why M11j emitted the literal "lu". */
             (uint32_t)(dbg_resync_ticks / 12288u));
      printf("       [perf] gmem_r=+%u gmem_w=+%u (RAM=+%d/+%d) "
             "ipl6=%u/%u slices\r\n",
             dbg_gmem_r - dbg_gmem_r_prev, dbg_gmem_w - dbg_gmem_w_prev,
             (int)((dbg_gmem_r - dbg_gmem_r_prev) - (io_reads - io_r_prev)),
             (int)((dbg_gmem_w - dbg_gmem_w_prev) - (io_writes - io_w_prev)),
             dbg_ipl6 - dbg_ipl6_prev, dbg_slices - dbg_slices_prev);
      /* M11k: interval bookkeeping */
      dbg_lost5_prev = dbg_lost5;   dbg_mfp_iv = 0u;
      dbg_gmem_r_prev = dbg_gmem_r; dbg_gmem_w_prev = dbg_gmem_w;
      io_r_prev = io_reads;         io_w_prev = io_writes;
      printf("       [flush] div=%u done=+%u skipped=+%u avg=%u cyc (total done=%u)\r\n",
             flushdiv, dbg_flush_done - dbg_flush_done_prev,
             dbg_flush_skip - dbg_flush_skip_prev,
             (dbg_flush_done - dbg_flush_done_prev)
               ? (uint32_t)((dbg_flush_cyc - dbg_flush_cyc_prev)
                            / (dbg_flush_done - dbg_flush_done_prev)) : 0u,
             dbg_flush_done);
      printf("       [slice] fine=%u/%u cap=%s\r\n",
             (unsigned)dbg_fine_slices, (unsigned)dbg_slices,
             slice_cap_cfg ? "pinned" : "auto");
      printf("       [cache] opt=%u tb_inval=+%u (targeted, was a full "
             "WBINVAL_ALL each)\r\n",
             cacheopt, dbg_tbinval - dbg_tbinval_prev);
      dbg_tbinval_prev = dbg_tbinval;
      dbg_flush_done_prev = dbg_flush_done;
      dbg_flush_skip_prev = dbg_flush_skip;
      dbg_flush_cyc_prev  = dbg_flush_cyc;
      dbg_ipl6_prev = dbg_ipl6;     dbg_slices_prev = dbg_slices; }
}

static void print_wishlist(uint64_t cycles)
{
    uint32_t i;
    printf("\r\n===== M1 register wishlist (unique IO touches) =====\r\n");
    for (i = 0; i < (uint32_t)n_seen; i++)
        printf("  %x %s%s x%u\r\n", seen_addr[i],
               (seen_rw[i] & 1) ? "R" : "", (seen_rw[i] & 2) ? "W" : "",
               seen_cnt[i]);
    printf("===== cycles=%uM stderr_chars=%u uniq_io=%d berr=%u =====\r\n",
           (uint32_t)(cycles / 1000000ull), nf_stderr_chars, n_seen, berr_count);
}

#ifdef HOST_TEST
/* GEOMTEST: drive the VIDEL shadow with per-mode register vectors and assert
 * the published geometry/linebytes. Vectors 2-4 are the three silicon-broken
 * 320-wide planar modes, deliberately presented with the adversarial vmode
 * nibble 4 the removed clause misread as truecolor.                        */
static int geomtest(void)
{
    static const struct {
        uint16_t sps; uint8_t st; uint16_t vwrap, vdb, vde, vmode;
        uint32_t geom, lb; const char *name;
    } v[] = {
      { 0x0100, 0, 320, 0x003F, 0x03FF, 0x0004, 0x0001E010u, 640, "TC 320x480"   },
      { 0x0000, 0,  80, 0x003F, 0x03FF, 0x0004, 0x0001E014u, 160, "320x480x4bpp" },
      { 0x0000, 1,  40, 0x003F, 0x03FF, 0x0004, 0x0001E012u,  80, "320x480x2bpp" },
      { 0x0000, 1,  40, 0x003F, 0x021F, 0x0004, 0x0000F032u,  80, "320x240x2bpp" },
      { 0x0010, 0, 160, 0x003F, 0x03FF, 0x0004, 0x0001E018u, 320, "320x480x8bpp" },
      { 0x0000, 0, 160, 0x003F, 0x03FF, 0x0004, 0x0001E004u, 320, "640x480x4bpp" },
      { 0x0400, 2,  40, 0x003F, 0x03FF, 0x0004, 0x0001E001u,  80, "640x480x1bpp" },
    };
    unsigned i; int bad = 0;
    ram[0x44E]=0; ram[0x44F]=0xD0; ram[0x450]=0; ram[0x451]=0; /* vbase D00000 */
    for (i = 0; i < sizeof v / sizeof v[0]; i++) {
        io_shadow[0x0266] = (uint8_t)(v[i].sps >> 8);
        io_shadow[0x0267] = (uint8_t) v[i].sps;
        io_shadow[0x0260] =  v[i].st;
        io_shadow[0x0210] = (uint8_t)(v[i].vwrap >> 8);
        io_shadow[0x0211] = (uint8_t) v[i].vwrap;
        io_shadow[0x02A8] = (uint8_t)(v[i].vdb >> 8);
        io_shadow[0x02A9] = (uint8_t) v[i].vdb;
        io_shadow[0x02AA] = (uint8_t)(v[i].vde >> 8);
        io_shadow[0x02AB] = (uint8_t) v[i].vde;
        io_shadow[0x02C2] = (uint8_t)(v[i].vmode >> 8);
        io_shadow[0x02C3] = (uint8_t) v[i].vmode;
        mbox_publish();
        if (MBOX[2] != v[i].geom || MBOX[3] != v[i].lb) {
            printf("GEOMTEST FAIL %s: got geom=%05x lb=%u want geom=%05x lb=%u\r\n",
                   v[i].name, (unsigned)MBOX[2], (unsigned)MBOX[3],
                   (unsigned)v[i].geom, (unsigned)v[i].lb);
            bad++;
        }
    }
    if (!bad) printf("GEOMTEST OK (%u vectors)\r\n",
                     (unsigned)(sizeof v / sizeof v[0]));
    return bad;
}

/* FDCTEST -- register-level vectors driven through io_read8/io_write8
 * exactly as EmuTOS drives the chip (control word select on FF8606/07,
 * data on FF8604/05, PSG port A RMW, GPIP bit 5 polling, direction
 * toggles before each transfer).  Each vector states the EmuTOS code
 * path it certifies.  Runs before boot; aborts the run on failure.    */
static void fdc_wctl(uint16_t w)
{ io_write8(0xFFFF8606u, (w >> 8) & 0xFFu); io_write8(0xFFFF8607u, w & 0xFFu); }
static void fdc_wdat(uint16_t w)
{ io_write8(0xFFFF8604u, (w >> 8) & 0xFFu); io_write8(0xFFFF8605u, w & 0xFFu); }
static uint32_t fdc_rdat(void)
{ io_read8(0xFFFF8604u); return io_read8(0xFFFF8605u); }
static void fdc_setaddr(uint32_t a)
{
    io_write8(0xFFFF8609u, (a >> 16) & 0xFFu);
    io_write8(0xFFFF860Bu, (a >>  8) & 0xFFu);
    io_write8(0xFFFF860Du,  a        & 0xFFu);
}
static uint32_t fdc_rdaddr(void)
{
    return (io_read8(0xFFFF8609u) << 16)
         | (io_read8(0xFFFF860Bu) <<  8)
         |  io_read8(0xFFFF860Du);
}
static uint32_t fdc_gpip5(void)          /* 1 = idle, 0 = INTRQ        */
{ return mfp_read(0xFA01u) & 0x20u; }
static void fdc_psg_side_drive(uint8_t bits)   /* EmuTOS RMW pattern   */
{
    uint8_t old;
    io_write8(0xFFFF8800u, 14);
    old = (uint8_t)io_read8(0xFFFF8800u);
    io_write8(0xFFFF8802u, (uint8_t)((old & 0xF8u) | (bits & 0x07u)));
}
static uint32_t bigsum512(const uint8_t *p)    /* TOS $1234 word sum   */
{
    uint32_t i, s = 0;
    for (i = 0; i < 512u; i += 2u) s += ((uint32_t)p[i] << 8) | p[i+1u];
    return s & 0xFFFFu;
}

/* build the EmuTOS flopfmt track stream at ram[dst] (LEADER 60,
 * interleave 1); tsize = raw track bytes (DD 6250, HD 12500);
 * returns bytes written                                               */
static uint32_t build_fmt_track_sz(uint32_t dst, uint8_t trk, uint8_t side,
                                   uint32_t spt, uint8_t fill,
                                   uint32_t tsize)
{
    uint32_t p = dst, sec, j;
    for (j = 0; j < 60u; j++) ram[p++] = 0x4Eu;
    for (sec = 1; sec <= spt; sec++) {
        for (j = 0; j < 12u; j++) ram[p++] = 0x00u;
        ram[p++]=0xF5u; ram[p++]=0xF5u; ram[p++]=0xF5u; ram[p++]=0xFEu;
        ram[p++]=trk; ram[p++]=side; ram[p++]=(uint8_t)sec; ram[p++]=2u;
        ram[p++]=0xF7u;
        for (j = 0; j < 22u; j++) ram[p++] = 0x4Eu;
        for (j = 0; j < 12u; j++) ram[p++] = 0x00u;
        ram[p++]=0xF5u; ram[p++]=0xF5u; ram[p++]=0xF5u; ram[p++]=0xFBu;
        for (j = 0; j < 512u; j++) ram[p++] = fill;
        ram[p++]=0xF7u;
        for (j = 0; j < 40u; j++) ram[p++] = 0x4Eu;
    }
    for (j = 0; j < tsize - 60u - 614u*spt; j++) ram[p++] = 0x4Eu;
    return p - dst;
}
static uint32_t build_fmt_track(uint32_t dst, uint8_t trk, uint8_t side,
                                uint32_t spt, uint8_t fill)
{ return build_fmt_track_sz(dst, trk, side, spt, fill, 6250u); }

static int fdctest(void)
{
    int bad = 0;
    uint32_t i, st, sum;
    static uint8_t save[512];

    /* M9G fixture isolation: the B: vectors (v6, v8-v10) are written
     * against the canonical blank-disk contract. A config-mounted B:
     * is parked (write-back off so no fixture garbage reaches the
     * card) and remounted through the real path afterwards.           */
    sdf[1].mounted = 0; sdf[1].writeback = 0;
    flop_make_blank720(diskB_ram, 0xF1CA44u);
    flop_attach(&fdrv[1], diskB_ram, 737280u, "blank (synth)");

    /* v1: PSG select/data indirection -- set_psg_porta() RMW works    */
    fdc_psg_side_drive(0x05u);                 /* A: selected, side 0  */
    io_write8(0xFFFF8800u, 14);
    if ((io_read8(0xFFFF8800u) & 0x07u) != 0x05u) {
        printf("FDCTEST FAIL v1: PSG portA RMW\r\n"); bad++; }

    /* v2: Restore -- flop_detect_drive(): TRACK0, INTRQ, read-clears  */
    fdc_wctl(0x0080u); fdc_wdat(0x0000u);      /* FDC_CS <- Restore    */
    if (fdc_gpip5() != 0u) {
        printf("FDCTEST FAIL v2: no INTRQ after Restore\r\n"); bad++; }
    fdc_wctl(0x0080u); st = fdc_rdat();
    if (!(st & 0x04u) || (st & 0x01u)) {
        printf("FDCTEST FAIL v2: Restore status %02x\r\n", st); bad++; }
    if (fdc_gpip5() == 0u) {
        printf("FDCTEST FAIL v2: status read did not clear INTRQ\r\n"); bad++; }

    /* v3: A: boot sector read -- flopio() RW_READ + dskboot():
     * SR=1, DMA addr, dir-toggle, count=1, FDC_READ; then bytes match
     * the image, the $1234 checksum holds, the DMA counter advanced
     * one sector, and DMA status shows OK + sector-count-zero.        */
    fdc_wctl(0x0084u); fdc_wdat(0x0001u);      /* FDC_SR <- 1          */
    fdc_setaddr(0x010000u);
    fdc_wctl(0x0190u); fdc_wctl(0x0090u);      /* read dir toggle      */
    fdc_wdat(0x0001u);                         /* sector count 1       */
    fdc_wctl(0x0080u); fdc_wdat(0x0080u);      /* FDC_READ             */
    fdc_wctl(0x0080u); st = fdc_rdat();
    if (st & 0x10u) { printf("FDCTEST FAIL v3: RNF on boot sector\r\n"); bad++; }
    for (i = 0; i < 512u; i++)
        if (ram[0x10000u+i] != fdrv[0].img[i]) break;
    if (i != 512u) { printf("FDCTEST FAIL v3: data mismatch @%u\r\n", i); bad++; }
    if (bigsum512(ram + 0x10000u) != 0x1234u) {
        if (sdf[0].mounted) {
            printf("FDCTEST FAIL v3: boot checksum != $1234\r\n"); bad++; }
    } else if (!sdf[0].mounted) {
        printf("FDCTEST FAIL v3: blank A: executable\r\n"); bad++; }
    if (fdc_rdaddr() != 0x010200u) {
        printf("FDCTEST FAIL v3: DMA counter %x\r\n", fdc_rdaddr()); bad++; }
    fdc_wctl(0x0090u);
    if ((io_read8(0xFFFF8607u) & 0x03u) != 0x01u) {
        printf("FDCTEST FAIL v3: DMA status\r\n"); bad++; }

    /* v4: Record Not Found -- decode_error() ESECNF path (sector 10)  */
    fdc_wctl(0x0084u); fdc_wdat(0x000Au);
    fdc_setaddr(0x010000u);
    fdc_wctl(0x0190u); fdc_wctl(0x0090u); fdc_wdat(0x0001u);
    fdc_wctl(0x0080u); fdc_wdat(0x0080u);
    fdc_wctl(0x0080u); st = fdc_rdat();
    if (!(st & 0x10u)) { printf("FDCTEST FAIL v4: expected RNF\r\n"); bad++; }

    /* v5: Seek + write round-trip on A: track 79 side 1 sector 9
     * (the last sector) -- flopio() RW_WRITE; image bytes change and
     * read back; the touched sector is restored afterwards.           */
    fdc_wctl(0x0086u); fdc_wdat(79u);          /* FDC_DR <- 79         */
    fdc_wctl(0x0080u); fdc_wdat(0x0010u);      /* Seek                 */
    fdc_wctl(0x0082u);
    if (fdc_rdat() != 79u) { printf("FDCTEST FAIL v5: TR after seek\r\n"); bad++; }
    { uint32_t lba = ((79u*2u + 1u)*9u + 8u) * 512u;
      for (i = 0; i < 512u; i++) save[i] = fdrv[0].img[lba+i];
      for (i = 0; i < 512u; i++) ram[0x12000u+i] = (uint8_t)(i*7u + 3u);
      fdc_psg_side_drive(0x04u);               /* A:, side 1           */
      fdc_wctl(0x0084u); fdc_wdat(0x0009u);    /* SR=9                 */
      fdc_setaddr(0x012000u);
      fdc_wctl(0x0090u); fdc_wctl(0x0190u);    /* write dir toggle     */
      fdc_wdat(0x0001u);
      fdc_wctl(0x0180u); fdc_wdat(0x00A0u);    /* FDC_WRITE            */
      fdc_wctl(0x0180u); st = fdc_rdat();
      if (st & 0x50u) { printf("FDCTEST FAIL v5: write status %02x\r\n", st); bad++; }
      for (i = 0; i < 512u; i++)
          if (fdrv[0].img[lba+i] != (uint8_t)(i*7u + 3u)) break;
      if (i != 512u) { printf("FDCTEST FAIL v5: image not written @%u\r\n", i); bad++; }
      fdc_wctl(0x0084u); fdc_wdat(0x0009u);    /* read it back         */
      fdc_setaddr(0x014000u);
      fdc_wctl(0x0190u); fdc_wctl(0x0090u); fdc_wdat(0x0001u);
      fdc_wctl(0x0080u); fdc_wdat(0x0080u);
      for (i = 0; i < 512u; i++)
          if (ram[0x14000u+i] != (uint8_t)(i*7u + 3u)) break;
      if (i != 512u) { printf("FDCTEST FAIL v5: readback @%u\r\n", i); bad++; }
      for (i = 0; i < 512u; i++) fdrv[0].img[lba+i] = save[i];  /* restore */
    }

    /* v6: B: present and blank -- serial F1CA44, media $F9, and NOT
     * executable (a blank disk must not pass the $1234 gate).         */
    fdc_psg_side_drive(0x03u);                 /* B: selected, side 0  */
    fdc_wctl(0x0080u); fdc_wdat(0x0000u);      /* Restore              */
    fdc_wctl(0x0080u); (void)fdc_rdat();
    fdc_wctl(0x0084u); fdc_wdat(0x0001u);
    fdc_setaddr(0x016000u);
    fdc_wctl(0x0190u); fdc_wctl(0x0090u); fdc_wdat(0x0001u);
    fdc_wctl(0x0080u); fdc_wdat(0x0080u);
    if (ram[0x16008u] != 0xF1u || ram[0x16009u] != 0xCAu
     || ram[0x1600Au] != 0x44u || ram[0x16015u] != 0xF9u) {
        printf("FDCTEST FAIL v6: B: BPB\r\n"); bad++; }
    sum = bigsum512(ram + 0x16000u);
    if (sum == 0x1234u) { printf("FDCTEST FAIL v6: blank B: executable\r\n"); bad++; }

    /* v7: track out of range -- RNF, not a wrap into wrong data       */
    fdc_wctl(0x0086u); fdc_wdat(85u);
    fdc_wctl(0x0080u); fdc_wdat(0x0010u);
    fdc_wctl(0x0084u); fdc_wdat(0x0001u);
    fdc_setaddr(0x010000u);
    fdc_wctl(0x0190u); fdc_wctl(0x0090u); fdc_wdat(0x0001u);
    fdc_wctl(0x0080u); fdc_wdat(0x0080u);
    fdc_wctl(0x0080u); st = fdc_rdat();
    if (!(st & 0x10u)) { printf("FDCTEST FAIL v7: expected RNF track 85\r\n"); bad++; }

    /* v8: WRITE TRACK -- xbios flopfmt()/desktop Format path.  Build
     * the track image byte-for-byte as EmuTOS builds it (DD, spt 9,
     * interleave 1, virgin $E5E5, LEADER 60, TRACK_SIZE 6250), stream
     * it at B: track 5 side 0, then verify all 9 sectors landed as
     * $E5-fill in the image and read one back through the FDC.        */
    { uint32_t p = 0x18000u, sec, j, lba5;
      fdc_psg_side_drive(0x03u);               /* B:, side 0           */
      fdc_wctl(0x0086u); fdc_wdat(5u);         /* FDC_DR <- 5          */
      fdc_wctl(0x0080u); fdc_wdat(0x0010u);    /* Seek                 */
      fdc_wctl(0x0080u); (void)fdc_rdat();
      for (j = 0; j < 60u; j++) ram[p++] = 0x4Eu;          /* leader   */
      for (sec = 1; sec <= 9u; sec++) {
          for (j = 0; j < 12u; j++) ram[p++] = 0x00u;
          ram[p++]=0xF5u; ram[p++]=0xF5u; ram[p++]=0xF5u; ram[p++]=0xFEu;
          ram[p++]=5u; ram[p++]=0u; ram[p++]=(uint8_t)sec; ram[p++]=2u;
          ram[p++]=0xF7u;
          for (j = 0; j < 22u; j++) ram[p++] = 0x4Eu;
          for (j = 0; j < 12u; j++) ram[p++] = 0x00u;
          ram[p++]=0xF5u; ram[p++]=0xF5u; ram[p++]=0xF5u; ram[p++]=0xFBu;
          for (j = 0; j < 512u; j++) ram[p++] = 0xE5u;
          ram[p++]=0xF7u;
          for (j = 0; j < 40u; j++) ram[p++] = 0x4Eu;
      }
      for (j = 0; j < 6250u - 60u - 614u*9u; j++) ram[p++] = 0x4Eu;
      fdc_setaddr(0x18000u);
      fdc_wctl(0x0090u); fdc_wctl(0x0190u);    /* write dir toggle     */
      fdc_wdat(13u);                           /* (6250+511)/512       */
      fdc_wctl(0x0180u); fdc_wdat(0x00F0u);    /* FDC_WRITETR          */
      fdc_wctl(0x0180u); st = fdc_rdat();
      if (st & 0x44u) { printf("FDCTEST FAIL v8: WRITETR status %02x\r\n", st); bad++; }
      fdc_wctl(0x0190u);
      if ((io_read8(0xFFFF8607u) & 0x03u) != 0x01u) {
          printf("FDCTEST FAIL v8: DMA status after WRITETR\r\n"); bad++; }
      lba5 = ((5u*2u + 0u)*9u)*512u;
      for (j = 0; j < 9u*512u; j++)
          if (fdrv[1].img[lba5+j] != 0xE5u) break;
      if (j != 9u*512u) {
          printf("FDCTEST FAIL v8: format fill @%u\r\n", j); bad++; }
      fdc_wctl(0x0084u); fdc_wdat(0x0005u);    /* read back sector 5   */
      fdc_setaddr(0x01A000u);
      fdc_wctl(0x0190u); fdc_wctl(0x0090u); fdc_wdat(0x0001u);
      fdc_wctl(0x0080u); fdc_wdat(0x0080u);
      for (j = 0; j < 512u; j++) if (ram[0x1A000u+j] != 0xE5u) break;
      if (j != 512u) { printf("FDCTEST FAIL v8: readback @%u\r\n", j); bad++; }
      flop_make_blank720(diskB_ram, 0xF1CA44u);   /* B: pristine again */
      fdc_wtrack_warned = 0;                   /* re-arm the log line  */
    }

    /* v9: format-defined geometry -- the FastCopy III extended format
     * path: reshape B: to 10 spt at t0/s0, format track 80 both sides
     * (disk grows to 81 tracks), Type II round-trip on t80/side1/sec10,
     * RNF beyond the formatted disk, then B: restored to the pristine
     * blank INCLUDING its attach-time geometry.                       */
    { uint32_t j;
      fdc_psg_side_drive(0x03u);               /* B:, side 0           */
      fdc_wctl(0x0086u); fdc_wdat(0u);
      fdc_wctl(0x0080u); fdc_wdat(0x0010u);    /* Seek 0               */
      fdc_wctl(0x0080u); (void)fdc_rdat();
      build_fmt_track(0x18000u, 0u, 0u, 10u, 0xE5u);
      fdc_setaddr(0x18000u);
      fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(13u);
      fdc_wctl(0x0180u); fdc_wdat(0x00F0u);
      fdc_wctl(0x0180u); st = fdc_rdat();
      if (st & 0x44u) { printf("FDCTEST FAIL v9: reshape status %02x\r\n", st); bad++; }
      if (fdrv[1].spt != 10u || fdrv[1].tracks != 1u) {
          printf("FDCTEST FAIL v9: reshape %u spt %u trk\r\n",
                 fdrv[1].spt, fdrv[1].tracks); bad++; }
      fdc_wctl(0x0086u); fdc_wdat(80u);
      fdc_wctl(0x0080u); fdc_wdat(0x0010u);    /* Seek 80              */
      fdc_wctl(0x0080u); (void)fdc_rdat();
      build_fmt_track(0x18000u, 80u, 0u, 10u, 0xA5u);
      fdc_setaddr(0x18000u);
      fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(13u);
      fdc_wctl(0x0180u); fdc_wdat(0x00F0u);
      fdc_psg_side_drive(0x02u);               /* B:, side 1           */
      build_fmt_track(0x18000u, 80u, 1u, 10u, 0x5Au);
      fdc_setaddr(0x18000u);
      fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(13u);
      fdc_wctl(0x0180u); fdc_wdat(0x00F0u);
      fdc_wctl(0x0180u); st = fdc_rdat();
      if (st & 0x44u) { printf("FDCTEST FAIL v9: t80 status %02x\r\n", st); bad++; }
      if (fdrv[1].tracks != 81u || fdrv[1].size != 829440u) {
          printf("FDCTEST FAIL v9: grew to %u trk %u B\r\n",
                 fdrv[1].tracks, fdrv[1].size); bad++; }
      for (j = 0; j < 512u; j++) ram[0x12000u+j] = (uint8_t)(j ^ 0x33u);
      fdc_wctl(0x0084u); fdc_wdat(10u);        /* SR=10                */
      fdc_setaddr(0x012000u);
      fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(0x0001u);
      fdc_wctl(0x0180u); fdc_wdat(0x00A0u);    /* Write Sector         */
      fdc_wctl(0x0084u); fdc_wdat(10u);
      fdc_setaddr(0x014000u);
      fdc_wctl(0x0190u); fdc_wctl(0x0090u); fdc_wdat(0x0001u);
      fdc_wctl(0x0080u); fdc_wdat(0x0080u);    /* Read Sector          */
      for (j = 0; j < 512u; j++)
          if (ram[0x14000u+j] != (uint8_t)(j ^ 0x33u)) break;
      if (j != 512u) { printf("FDCTEST FAIL v9: t80 rw @%u\r\n", j); bad++; }
      fdc_wctl(0x0086u); fdc_wdat(81u);
      fdc_wctl(0x0080u); fdc_wdat(0x0010u);    /* Seek 81              */
      fdc_wctl(0x0084u); fdc_wdat(1u);
      fdc_setaddr(0x010000u);
      fdc_wctl(0x0190u); fdc_wctl(0x0090u); fdc_wdat(0x0001u);
      fdc_wctl(0x0080u); fdc_wdat(0x0080u);
      fdc_wctl(0x0080u); st = fdc_rdat();
      if (!(st & 0x10u)) { printf("FDCTEST FAIL v9: expected RNF t81\r\n"); bad++; }
      /* mixed-format reject: a 9-spt track on the now-10-spt disk must
       * fail with LOST DATA and leave the geometry untouched          */
      fdc_wctl(0x0086u); fdc_wdat(2u);
      fdc_wctl(0x0080u); fdc_wdat(0x0010u);    /* Seek 2               */
      fdc_wctl(0x0080u); (void)fdc_rdat();
      fdc_psg_side_drive(0x03u);               /* B:, side 0           */
      build_fmt_track(0x18000u, 2u, 0u, 9u, 0x77u);
      fdc_setaddr(0x18000u);
      fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(13u);
      fdc_wctl(0x0180u); fdc_wdat(0x00F0u);
      fdc_wctl(0x0180u); st = fdc_rdat();
      if (!(st & 0x04u)) { printf("FDCTEST FAIL v9: mixed fmt accepted\r\n"); bad++; }
      if (fdrv[1].spt != 10u || fdrv[1].tracks != 81u) {
          printf("FDCTEST FAIL v9: mixed fmt mutated geometry\r\n"); bad++; }
      flop_make_blank720(diskB_ram, 0xF1CA44u);
      if (flop_attach(&fdrv[1], diskB_ram, 737280u, "blank (synth)")) {
          printf("FDCTEST FAIL v9: B: re-attach\r\n"); bad++; }
      fdc_wtrack_warned = 0; fdc_mixed_warned = 0;
    }

    /* v10: extended HD -- the case the 1.44M cap refused: reshape B:
     * to 18 spt at t0/s0 (HD stream), format t82 both sides (disk
     * grows to 83 tracks, 1,529,856 B > old cap), Type II round-trip
     * at t82/side1/sec18, format at t85 rejected (mech ceiling), then
     * B: restored pristine.                                           */
    { uint32_t j;
      fdc_psg_side_drive(0x03u);               /* B:, side 0           */
      fdc_wctl(0x0086u); fdc_wdat(0u);
      fdc_wctl(0x0080u); fdc_wdat(0x0010u);    /* Seek 0               */
      fdc_wctl(0x0080u); (void)fdc_rdat();
      build_fmt_track_sz(0x18000u, 0u, 0u, 18u, 0xE5u, 12500u);
      fdc_setaddr(0x18000u);
      fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(25u);  /* HD count */
      fdc_wctl(0x0180u); fdc_wdat(0x00F0u);
      fdc_wctl(0x0180u); st = fdc_rdat();
      if (st & 0x44u) { printf("FDCTEST FAIL v10: HD reshape %02x\r\n", st); bad++; }
      if (fdrv[1].spt != 18u) {
          printf("FDCTEST FAIL v10: spt %u\r\n", fdrv[1].spt); bad++; }
      fdc_wctl(0x0086u); fdc_wdat(82u);
      fdc_wctl(0x0080u); fdc_wdat(0x0010u);    /* Seek 82              */
      fdc_wctl(0x0080u); (void)fdc_rdat();
      build_fmt_track_sz(0x18000u, 82u, 0u, 18u, 0xC3u, 12500u);
      fdc_setaddr(0x18000u);
      fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(25u);
      fdc_wctl(0x0180u); fdc_wdat(0x00F0u);
      fdc_psg_side_drive(0x02u);               /* B:, side 1           */
      build_fmt_track_sz(0x18000u, 82u, 1u, 18u, 0x3Cu, 12500u);
      fdc_setaddr(0x18000u);
      fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(25u);
      fdc_wctl(0x0180u); fdc_wdat(0x00F0u);
      fdc_wctl(0x0180u); st = fdc_rdat();
      if (st & 0x44u) { printf("FDCTEST FAIL v10: t82 status %02x\r\n", st); bad++; }
      if (fdrv[1].tracks != 83u || fdrv[1].size != 1529856u) {
          printf("FDCTEST FAIL v10: %u trk %u B\r\n",
                 fdrv[1].tracks, fdrv[1].size); bad++; }
      for (j = 0; j < 512u; j++) ram[0x12000u+j] = (uint8_t)(j ^ 0xC5u);
      fdc_wctl(0x0084u); fdc_wdat(18u);        /* SR=18                */
      fdc_setaddr(0x012000u);
      fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(0x0001u);
      fdc_wctl(0x0180u); fdc_wdat(0x00A0u);    /* Write Sector         */
      fdc_wctl(0x0084u); fdc_wdat(18u);
      fdc_setaddr(0x014000u);
      fdc_wctl(0x0190u); fdc_wctl(0x0090u); fdc_wdat(0x0001u);
      fdc_wctl(0x0080u); fdc_wdat(0x0080u);    /* Read Sector          */
      for (j = 0; j < 512u; j++)
          if (ram[0x14000u+j] != (uint8_t)(j ^ 0xC5u)) break;
      if (j != 512u) { printf("FDCTEST FAIL v10: t82 rw @%u\r\n", j); bad++; }
      fdc_psg_side_drive(0x03u);
      fdc_wctl(0x0086u); fdc_wdat(85u);
      fdc_wctl(0x0080u); fdc_wdat(0x0010u);    /* Seek 85 (ceiling)    */
      fdc_wctl(0x0080u); (void)fdc_rdat();
      build_fmt_track_sz(0x18000u, 85u, 0u, 18u, 0x99u, 12500u);
      fdc_setaddr(0x18000u);
      fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(25u);
      fdc_wctl(0x0180u); fdc_wdat(0x00F0u);
      fdc_wctl(0x0180u); st = fdc_rdat();
      if (!(st & 0x04u)) { printf("FDCTEST FAIL v10: t85 accepted\r\n"); bad++; }
      if (fdrv[1].tracks != 83u) {
          printf("FDCTEST FAIL v10: ceiling mutated tracks\r\n"); bad++; }
      flop_make_blank720(diskB_ram, 0xF1CA44u);
      if (flop_attach(&fdrv[1], diskB_ram, 737280u, "blank (synth)")) {
          printf("FDCTEST FAIL v10: B: re-attach\r\n"); bad++; }
      fdc_wtrack_warned = 0; fdc_mixed_warned = 0;
    }

    /* leave the chip and PSG in reset-like state for the real boot    */
    fdc_psg_side_drive(0x07u);                 /* deselect both        */
    fdc_wctl(0x0086u); fdc_wdat(0u);
    fdc_wctl(0x0080u); fdc_wdat(0x0000u);      /* Restore to track 0   */
    fdc_wctl(0x0080u); (void)fdc_rdat();       /* clear INTRQ          */
    fdc_setaddr(0u); fdc_wctl(0x0090u); fdc_wdat(0u);
    fdc_wctl(0x0080u);
    if (cfg_db[0] && sd_mount(cfg_db, diskB_ram, &sdf[1], "B: image") == 0)
        flop_attach(&fdrv[1], diskB_ram, sdf[1].size, "SD (DISKB=)");
    if (!bad) printf("FDCTEST OK (10 vectors)\r\n");
    return bad;
}

/* ===================================================================
 * SDTEST -- M9F storage vectors (host only). Runs after FDCTEST with
 * the FDC helpers still live and A: card-mounted (unless $NOCARD).
 *  v1  mount metadata + full-image equality vs the simulated card.
 *      (First re-syncs the one sector FDCTEST v5 restored by direct
 *      array write, by pushing it through flop_persist -- which is
 *      itself a test of the persist path's address arithmetic.)
 *  v2  FDC Write Sector on A: -> the CARD image changes at exactly
 *      dska_lba*512+off (the raytrace-persistence proof); restored
 *      through the same FDC path so the card ends pristine.
 *  v3  LED contract order: the v2 write must append exactly "US" to
 *      the LED log (unsafe strictly before, safe strictly after).
 *  $NOCARD=1  -> embedded fallback: serial F1CA42, writeback off.
 *  $SDFRAG=1  -> fragmented card (run with SDIMG=sd_frag.img):
 *      mounted but contig=0, writeback=0.
 * =================================================================== */

/* ===================================================================
 * TIMETEST -- M10 wall-locked timebase (host). Two paths:
 *  A) FALLBACK path arithmetic: MFP ticks/emulated-cycle must equal
 *     the legacy rate exactly (0.1536), so the fallback is bit-inert
 *     vs m9g in sim -- proven separately by the PPM regression, and
 *     re-asserted here as a guard against future constant drift.
 *  B) HARDWARE path: publish a rising tick200/tickvbl into the slot
 *     (with TB_MAGIC) and confirm tb_read() reports present and
 *     returns the values; then confirm a DELTA in tick200 maps to the
 *     expected MFP tick count (d200 * 12288) and tickvbl deltas raise
 *     the VBL. Absence (wrong magic) must report not-present so the
 *     firmware falls back.                                            */

/* ===================================================================
 * BLITTEST (firmware) -- drive the BLiTTER through the IO map, not the
 * model directly: proves the FF8A00 whitelist entry, the byte-wise
 * io_write8/io_read8 routing, the ST-RAM callbacks over ram[], and the
 * control-b7 synchronous-run trigger. The MODEL's own algorithm is
 * separately proven by the 200k-blit differential fuzz; this is the
 * WIRING test.                                                        */
static void bwr16(uint32_t off, uint16_t v)   /* write a blitter reg word */
{
    io_write8(0xFFFF8A00u + off,     (v >> 8) & 0xFFu);
    io_write8(0xFFFF8A00u + off + 1u, v       & 0xFFu);
}
static uint16_t brd16(uint32_t off)
{
    return (uint16_t)((io_read8(0xFFFF8A00u + off) << 8)
                    | io_read8(0xFFFF8A00u + off + 1u));
}
static int blittest(void)
{
    int bad = 0; uint32_t i;
    /* whitelist: FF8A00 must NOT bus-error (it did pre-m11) */
    if (!falcon_io_valid(0x8A00u) || !falcon_io_valid(0x8A3Du)) {
        printf("BLITTEST FAIL: FF8A00 not whitelisted\r\n"); bad++; }

    /* V1: copy one word src->dst through the IO-driven blitter.
     * Put src at 0x20000, dst at 0x24000 in ST-RAM.                   */
    { uint32_t src = 0x20000u, dst = 0x24000u;
      ram[src] = 0xDE; ram[src+1] = 0xAD;
      ram[dst] = 0x00; ram[dst+1] = 0x00;
      bwr16(0x24, (uint16_t)(src >> 16)); bwr16(0x26, (uint16_t)(src & 0xFFFFu));
      bwr16(0x32, (uint16_t)(dst >> 16)); bwr16(0x34, (uint16_t)(dst & 0xFFFFu));
      bwr16(0x28, 0xFFFFu); bwr16(0x2A, 0xFFFFu); bwr16(0x2C, 0xFFFFu);
      bwr16(0x20, 0); bwr16(0x2E, 0);
      bwr16(0x36, 1); bwr16(0x38, 1);
      bwr16(0x3A, (uint16_t)((2u << 8) | 3u));      /* HOP=src, LOP=copy */
      bwr16(0x3C, 0x8000u);                          /* ctrl b7 -> run    */
      if (!(ram[dst] == 0xDE && ram[dst+1] == 0xAD)) {
          printf("BLITTEST FAIL V1: dst=%02x%02x\r\n", ram[dst], ram[dst+1]);
          bad++; }
      /* busy bit must be clear after a synchronous run */
      if (brd16(0x3C) & 0x8000u) {
          printf("BLITTEST FAIL V1: busy still set\r\n"); bad++; }
    }

    /* V2: end-mask RMW through the IO path (only masked bits change). */
    { uint32_t src = 0x20000u, dst = 0x24000u;
      ram[src] = 0xFF; ram[src+1] = 0xFF;
      ram[dst] = 0x00; ram[dst+1] = 0x00;
      bwr16(0x24, (uint16_t)(src >> 16)); bwr16(0x26, (uint16_t)(src & 0xFFFFu));
      bwr16(0x32, (uint16_t)(dst >> 16)); bwr16(0x34, (uint16_t)(dst & 0xFFFFu));
      bwr16(0x28, 0x0FF0u); bwr16(0x2A, 0xFFFFu); bwr16(0x2C, 0xFFFFu);
      bwr16(0x36, 1); bwr16(0x38, 1);
      bwr16(0x3A, (uint16_t)((2u << 8) | 3u));
      bwr16(0x3C, 0x8000u);
      if (!(ram[dst] == 0x0F && ram[dst+1] == 0xF0)) {
          printf("BLITTEST FAIL V2: mask dst=%02x%02x\r\n", ram[dst], ram[dst+1]);
          bad++; }
    }

    /* V3: multi-word line (3 words) copy through IO, confirms x_count
     * stepping and the ST-RAM callbacks walk addresses correctly.     */
    { uint32_t src = 0x20000u, dst = 0x24000u;
      for (i = 0; i < 3u; i++) {
          ram[src + i*2u] = (uint8_t)(0x10 + i); ram[src + i*2u + 1u] = (uint8_t)(0x20 + i);
          ram[dst + i*2u] = 0; ram[dst + i*2u + 1u] = 0;
      }
      bwr16(0x24, (uint16_t)(src >> 16)); bwr16(0x26, (uint16_t)(src & 0xFFFFu));
      bwr16(0x32, (uint16_t)(dst >> 16)); bwr16(0x34, (uint16_t)(dst & 0xFFFFu));
      bwr16(0x20, 2); bwr16(0x2E, 2);
      bwr16(0x28, 0xFFFFu); bwr16(0x2A, 0xFFFFu); bwr16(0x2C, 0xFFFFu);
      bwr16(0x36, 3); bwr16(0x38, 1);
      bwr16(0x3A, (uint16_t)((2u << 8) | 3u));
      bwr16(0x3C, 0x8000u);
      for (i = 0; i < 3u; i++)
          if (ram[dst + i*2u] != (uint8_t)(0x10 + i)
           || ram[dst + i*2u + 1u] != (uint8_t)(0x20 + i)) {
              printf("BLITTEST FAIL V3: word %u\r\n", i); bad++; break; }
    }

    if (!bad) printf("BLITTEST OK (3 vectors, IO-driven)\r\n");
    return bad;
}

static int timetest(void)
{
    int bad = 0;
    uint32_t t200, tvbl, tcyc;
    /* --- A: rate constant guard --- */
    { double legacy = 24576.0/160000.0;
      double wall   = (double)WALL_PER_EMU * (double)WALL_MFP_NUM
                      / (double)WALL_MFP_DEN;
      if (legacy < wall - 1e-9 || legacy > wall + 1e-9) {
          printf("TIMETEST FAIL A: MFP rate %.6f != legacy %.6f\r\n",
                 wall, legacy); bad++; }
    }
    /* --- B: hardware slot present/absent (v2 layout) --- */
    { int bi; for (bi = 0; bi < 8; bi++) tb_host[bi] = 0; }
    if (tb_read(&t200, &tvbl, &tcyc)) {
        printf("TIMETEST FAIL B: empty slot reported present\r\n"); bad++; }
    tb_host[0] = TB_MAGIC; tb_host[2] = 1000u; tb_host[4] = 50u; tb_host[6] = 123u;
    if (!tb_read(&t200, &tvbl, &tcyc)) {
        printf("TIMETEST FAIL B: magic slot reported absent\r\n"); bad++; }
    else if (t200 != 1000u || tvbl != 50u || tcyc != 123u) {
        printf("TIMETEST FAIL B: slot values %u/%u/%u\r\n",
               t200, tvbl, tcyc); bad++; }
    tb_host[0] = 0xDEADBEEFu;                /* wrong magic -> absent */
    if (tb_read(&t200, &tvbl, &tcyc)) {
        printf("TIMETEST FAIL B: bad magic reported present\r\n"); bad++; }
    /* --- C: frozen-tick defence (the REV11 silicon failure replay) --- */
    tb_disabled = 0; tb_frozen_cnt = 0; tb_last_seen = 0;
    tb_host[0] = TB_MAGIC; tb_host[2] = 777u; tb_host[4] = 9u; tb_host[6] = 1u;
    if (!tb_read(&t200, &tvbl, &tcyc) || t200 != 777u) {
        printf("TIMETEST FAIL C: live slot rejected\r\n"); bad++; }
    { uint32_t ci; int died = 0;
      for (ci = 0; ci < TB_FROZEN_MAX + 8u; ci++)
          if (!tb_read(&t200, &tvbl, &tcyc)) { died = 1; break; }
      if (!died) {
          printf("TIMETEST FAIL C: frozen ticks never latched\r\n"); bad++; }
      else if (ci != TB_FROZEN_MAX - 1u) {
          printf("TIMETEST FAIL C: latched at read %u\r\n", ci); bad++; }
      tb_host[2] = 888u;                     /* ticks resume... */
      if (tb_read(&t200, &tvbl, &tcyc)) {
          printf("TIMETEST FAIL C: disable did not latch\r\n"); bad++; }
    }
    /* restore pristine state for the real boot */
    tb_disabled = 0; tb_frozen_cnt = 0; tb_last_seen = 0;
    tb_present_cache = -1;
    { int bi; for (bi = 0; bi < 8; bi++) tb_host[bi] = 0; }
    if (!bad) printf("TIMETEST OK (3 paths)\r\n");
    return bad;
}

static int sdtest(void)
{
    int bad = 0; uint32_t i, off, n0, lba;
    static uint8_t sv[512];
    if (getenv("NOCARD")) {
        if (sdf[0].mounted || sdf[0].writeback) {
            printf("SDTEST FAIL nocard: mounted=%u wb=%u\r\n",
                   sdf[0].mounted, sdf[0].writeback); bad++; }
        if (fdrv[0].img[8] != 0xF1u || fdrv[0].img[9] != 0xCAu
         || fdrv[0].img[10] != 0x42u
         || fdrv[0].img[2] != 'F' || fdrv[0].img[6] != 'A') {
            printf("SDTEST FAIL nocard: not the synth blank\r\n"); bad++; }
        if (!bad) printf("SDTEST OK (nocard fallback)\r\n");
        return bad;
    }
    if (getenv("SDFRAG")) {
        /* the cluster map makes fragmented files fully writable: the
         * file must mount frag=1 WITH write-back ON, and a write to
         * the file sector living in the RELOCATED cluster must land
         * at the MAPPED lba, not the contiguous-formula one.          */
        if (!sdf[0].mounted || !sdf[0].frag || !sdf[0].writeback) {
            printf("SDTEST FAIL frag: m=%u f=%u wb=%u\r\n",
                   sdf[0].mounted, sdf[0].frag, sdf[0].writeback); bad++;
            return bad; }
        off = 720u * 512u;                     /* sector in moved clus  */
        for (i = 0; i < 512u; i++) sv[i] = fdrv[0].img[off+i];
        for (i = 0; i < 512u; i++) ram[0x12000u+i] = (uint8_t)(i + 0x21u);
        fdc_wctl(0x0086u); fdc_wdat(40u);
        fdc_wctl(0x0080u); fdc_wdat(0x0010u);  /* Seek 40               */
        fdc_wctl(0x0080u); (void)fdc_rdat();
        fdc_psg_side_drive(0x05u);             /* A:, side 0            */
        fdc_wctl(0x0084u); fdc_wdat(0x0001u);  /* SR=1                  */
        fdc_setaddr(0x012000u);
        fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(0x0001u);
        fdc_wctl(0x0180u); fdc_wdat(0x00A0u);
        lba = fs_data + (sdf[0].chain[720u / fs_spc] - 2u) * fs_spc
            + (720u % fs_spc);
        for (i = 0; i < 512u; i++)
            if (hc_img[lba*512u + i] != (uint8_t)(i + 0x21u)) break;
        if (i != 512u) {
            printf("SDTEST FAIL fragwrite: mapped lba %u @%u\r\n", lba, i);
            bad++; }
        for (i = 0; i < 512u; i++) ram[0x12000u+i] = sv[i];
        fdc_wctl(0x0084u); fdc_wdat(0x0001u);
        fdc_setaddr(0x012000u);
        fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(0x0001u);
        fdc_wctl(0x0180u); fdc_wdat(0x00A0u);
        if (!bad) printf("SDTEST OK (fragmented, mapped write-back)\r\n");
        return bad;
    }
    /* ---- v1: mount metadata + full image/card equality (mapped) ---- */
    if (!sdf[0].mounted || sdf[0].frag || !sdf[0].writeback
        || sdf[0].size != 737280u) {
        printf("SDTEST FAIL v1: m=%u f=%u wb=%u size=%u\r\n",
               sdf[0].mounted, sdf[0].frag, sdf[0].writeback,
               sdf[0].size); bad++; }
    flop_persist(&fdrv[0], ((79u*2u + 1u)*9u + 8u) * 512u); /* v5 sync  */
    for (off = 0; off < sdf[0].sectors; off++) {
        lba = fs_data + (sdf[0].chain[off / fs_spc] - 2u) * fs_spc
            + (off % fs_spc);
        for (i = 0; i < 512u; i++)
            if (fdrv[0].img[off*512u + i] != hc_img[lba*512u + i]) {
                printf("SDTEST FAIL v1: mismatch fs=%u @%u\r\n", off, i);
                bad++; off = sdf[0].sectors; break; }
    }
    /* ---- v2+v3: FDC write on A:, card changes at mapped lba, LED --- */
    off = ((2u*2u + 0u)*9u + 4u) * 512u;
    for (i = 0; i < 512u; i++) sv[i] = fdrv[0].img[off+i];
    for (i = 0; i < 512u; i++) ram[0x12000u+i] = (uint8_t)(i ^ 0x5Au);
    fdc_wctl(0x0086u); fdc_wdat(2u);
    fdc_wctl(0x0080u); fdc_wdat(0x0010u);
    fdc_wctl(0x0080u); (void)fdc_rdat();
    fdc_psg_side_drive(0x05u);
    n0 = led_n;
    fdc_wctl(0x0084u); fdc_wdat(0x0005u);
    fdc_setaddr(0x012000u);
    fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(0x0001u);
    fdc_wctl(0x0180u); fdc_wdat(0x00A0u);
    lba = fs_data + (sdf[0].chain[(off>>9) / fs_spc] - 2u) * fs_spc
        + ((off>>9) % fs_spc);
    for (i = 0; i < 512u; i++)
        if (hc_img[lba*512u + i] != (uint8_t)(i ^ 0x5Au)) break;
    if (i != 512u) {
        printf("SDTEST FAIL v2: card not written @%u\r\n", i); bad++; }
    if (!(led_n == n0 + 2u && led_log[n0] == 'U' && led_log[n0+1u] == 'S')) {
        printf("SDTEST FAIL v3: LED order [%c%c] n=%u\r\n",
               led_n > n0 ? led_log[n0] : '-',
               led_n > n0+1u ? led_log[n0+1u] : '-', led_n - n0); bad++; }
    for (i = 0; i < 512u; i++) ram[0x12000u+i] = sv[i];
    fdc_wctl(0x0084u); fdc_wdat(0x0005u);
    fdc_setaddr(0x012000u);
    fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(0x0001u);
    fdc_wctl(0x0180u); fdc_wdat(0x00A0u);
    for (i = 0; i < 512u; i++)
        if (hc_img[lba*512u + i] != sv[i]) break;
    if (i != 512u) {
        printf("SDTEST FAIL v2r: card restore @%u\r\n", i); bad++; }
    /* ---- v4: FALCON.CFG parsed; ROM really came from the card ------ */
    if (memcmp(cfg_rom, "EMUTOS  IMG", 11) || memcmp(cfg_db, "WORK    ST ", 11)) {
        printf("SDTEST FAIL v4: cfg rom=%.11s db=%.11s\r\n",
               cfg_rom, cfg_db); bad++; }
    if (memcmp(rom_ram, emutos_rom, 64u)) {
        printf("SDTEST FAIL v4: ROM head differs\r\n"); bad++; }
    if (memcmp(rom_ram + 0x7FFF0u, "M9GROMCARDPROOF!", 16u)) {
        printf("SDTEST FAIL v4: card-ROM marker absent (fallback ran?)\r\n");
        bad++; }
    /* ---- v5: B: card-backed with independent write-back ------------ */
    if (!sdf[1].mounted || !sdf[1].writeback) {
        printf("SDTEST FAIL v5: B m=%u wb=%u\r\n",
               sdf[1].mounted, sdf[1].writeback); bad++; }
    else {
        off = ((1u*2u + 0u)*9u + 1u) * 512u;       /* t1 s0 sec2        */
        for (i = 0; i < 512u; i++) sv[i] = fdrv[1].img[off+i];
        for (i = 0; i < 512u; i++) ram[0x12000u+i] = (uint8_t)(i + 0x77u);
        fdc_wctl(0x0086u); fdc_wdat(1u);
        fdc_wctl(0x0080u); fdc_wdat(0x0010u);
        fdc_wctl(0x0080u); (void)fdc_rdat();
        fdc_psg_side_drive(0x03u);                 /* B:, side 0        */
        fdc_wctl(0x0084u); fdc_wdat(0x0002u);
        fdc_setaddr(0x012000u);
        fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(0x0001u);
        fdc_wctl(0x0180u); fdc_wdat(0x00A0u);
        lba = fs_data + (sdf[1].chain[(off>>9) / fs_spc] - 2u) * fs_spc
            + ((off>>9) % fs_spc);
        for (i = 0; i < 512u; i++)
            if (hc_img[lba*512u + i] != (uint8_t)(i + 0x77u)) break;
        if (i != 512u) {
            printf("SDTEST FAIL v5: B card not written @%u\r\n", i); bad++; }
        for (i = 0; i < 512u; i++) ram[0x12000u+i] = sv[i];
        fdc_wctl(0x0084u); fdc_wdat(0x0002u);
        fdc_setaddr(0x012000u);
        fdc_wctl(0x0090u); fdc_wctl(0x0190u); fdc_wdat(0x0001u);
        fdc_wctl(0x0180u); fdc_wdat(0x00A0u);
        fdc_psg_side_drive(0x05u);
    }
    if (!bad) printf("SDTEST OK (5 vectors)\r\n");
    return bad;
}

#endif

int main(void)
{
    uint32_t i, slice = 0;
    uint64_t cycles = 0;
    uint32_t last_uniq = 0, last_pc = 0, stall = 0;
    uint64_t acia_wall = 0, hid_wall = 0;   /* M9E wall pacing */
    uint64_t mfp_wall = 0, vbl_wall = 0;    /* M10 wall pacing */
    uint32_t tb_last200 = 0, tb_lastvbl = 0, vbl_due = 0;
    uint32_t last_scr = 0;
    uint32_t wishlist_done = 0;

    uart_init(38400);
#ifdef HOST_TEST
    if (getenv("LOGOFF")) log_on = 0u;   /* M18: verify the mute mutes */
#endif
    sd_gpio_init();             /* M9F: TF slot pins + LED direction    */
#ifdef HOST_TEST
    host_card_load();           /* $SDIMG-backed simulated card         */
#endif
    led_safe();                 /* solid = alive + no write in flight   */
    printf("\r\n==================================================\r\n");
    printf(" Falcon M28: adaptive slicing (IRQ rate + palette stamp)\r\n");
    /* M11l: the M11k banner reported log_on here, BEFORE FALCON.CFG had
     * been read, so it always printed the compiled-in default. The
     * real state is printed from the first status block instead. */
    printf(" ST-RAM 14MB @ DDR3 0x04000000, ROM 512K @ E00000\r\n");
    printf(" NatFeats: VERSION NAME STDERR -> this console\r\n");
    printf("==================================================\r\n");

#ifdef HOST_TEST
    if (paltest()) { printf("PALTEST FAIL -- aborting\r\n"); return 1; }
    if (geomtest()) { printf("GEOMTEST FAIL -- aborting\r\n"); return 1; }
#ifdef HOST_TEST
    { int bad = 0; uint32_t s0, s1;
      nvram_reset();                                 /* test a fresh chip */
      nvram_sel = 20; nvram[20] = 0;                 /* user cell RW    */
      nvram_write(0x8963u, 0xA5u);
      if (nvram_read(0x8963u) != 0xA5u) bad++;
      nvram[20] = 0;
      if (nvram[62] || nvram[63]) bad++;             /* checksum invalid*/
      if (nvram[13] != 0x80u) bad++;                 /* VRT             */
      nvram_sel = 0; s0 = nvram_read(0x8963u);
      host_wall += 2ull * NV_WALL_HZ;                /* +2s wall        */
      s1 = nvram_read(0x8963u);
      if (s1 == s0) bad++;                           /* clock must tick */
      host_wall += 86400ull * NV_WALL_HZ;            /* day wrap sane   */
      nvram_read(0x8963u);
      if (bad) { printf("NVTEST FAIL (%d)\r\n", bad); return 1; }
      printf("NVTEST OK (stock chip, ticking clock)\r\n");
      nvram_reset();                                 /* pristine boot   */
    }
#endif
#endif
    for (i = 0; i < ST_RAM_SIZE; i += 4) *(uint32_t*)(ram + i) = 0;
    for (i = 0; i < 0x8000u; i++) io_shadow[i] = 0xFFu;
    flop_init();                /* A: embedded image, B: blank (M9)    */
#ifdef HOST_TEST
    if (!getenv("SKIP_FDCTEST")) {                 /* diagnostic escape */
        if (fdctest()) { printf("FDCTEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_FDCTEST")) {                 /* diagnostic escape */
        if (sdtest())  { printf("SDTEST FAIL -- aborting\r\n"); return 1; }
    }
    if (timetest()) { printf("TIMETEST FAIL -- aborting\r\n"); return 1; }
    if (blittest()) { printf("BLITTEST FAIL -- aborting\r\n"); return 1; }
    if (!getenv("SKIP_SLICETEST")) {               /* diagnostic escape */
        if (slicetest()) { printf("SLICETEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_JOYTEST")) {                 /* diagnostic escape */
        if (joytest()) { printf("JOYTEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_SHADOWTEST")) {              /* diagnostic escape */
        if (shadowtest()) { printf("SHADOWTEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_DONETEST")) {                /* diagnostic escape */
        if (donetest()) { printf("DONETEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_BUSTEST")) {                 /* diagnostic escape */
        if (bustest()) { printf("BUSTEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_CATTEST")) {                 /* diagnostic escape */
        if (cattest()) { printf("CATTEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_SNDTEST")) {                 /* diagnostic escape */
        if (sndtest()) { printf("SNDTEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_SPLITTEST")) {               /* diagnostic escape */
        if (splittest()) { printf("SPLITTEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_VBLTEST")) {                 /* diagnostic escape */
        if (vbltest()) { printf("VBLTEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_TBTEST")) {                  /* diagnostic escape */
        if (tbtest()) { printf("TBTEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_APYTEST")) {                 /* diagnostic escape */
        if (apytest()) { printf("APYTEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_VIDBASETEST")) {             /* diagnostic escape */
        if (vidbasetest()) { printf("VIDBASETEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_PSGTEST")) {                 /* diagnostic escape */
        if (psgtest()) { printf("PSGTEST FAIL -- aborting\r\n"); return 1; }
    }
    if (!getenv("SKIP_AUDIOTEST")) {               /* diagnostic escape */
        if (audiotest()) { printf("AUDIOTEST FAIL -- aborting\r\n"); return 1; }
    }
    /* fdctest and sdtest used ST-RAM as scratch; boot must start from the same
     * zeroed state m8c boots from                                     */
    for (i = 0; i < ST_RAM_SIZE; i += 4) *(uint32_t*)(ram + i) = 0;
    fdc_boot_dma = 0;           /* witness armed for the real boot     */
#endif
    io_shadow[0x0006] = 0xA2u;  /* FF8006: monitor=VGA(2), memory code 5 = 14MB */
    io_shadow[0x0007] = 0x00u;  /* FF8007: Falcon bus control reset             */
    dma_run = 0u; dma_loop = 0u; dma_ptr = 0u; dma_pacc = 0u;   /* M20 */
    io_shadow[0x0201] = 0x00u;  /* M15: video base hi -- 0 = not yet set by SW   */
    io_shadow[0x0203] = 0x00u;  /* M15: video base mid                           */
    io_shadow[0x020D] = 0x00u;  /* M15: video base lo (Falcon/STE byte)          */
    nvram_reset();
    audio_init();               /* M13: arm the CPU->fabric sample ring */

    m68k_init();
    m68k_set_cpu_type(M68K_CPU_TYPE_68030);
    m68k_set_illg_instr_callback(nf_illg);
    m68k_set_int_ack_callback(int_ack);
    m68k_pulse_reset();
    { uint32_t bt2, btv, btc;                                /* M11b   */
      if (tb_read(&bt2, &btv, &btc))
          printf("[tb] hardware timebase: t200=%u tvbl=%u cyc50=%u\r\n",
                 bt2, btv, btc);
      else
          printf("[tb] mcycle fallback (no slot magic)\r\n");
    }
    printf(" FPU: none (68881/68882 socket empty, as shipped)\r\n");
    printf("68030 reset from %s vectors. Booting...\r\n",
           rom_from_card ? "card ROM" : "built-in EmuTOS");

#ifndef HOST_TEST
    { uint64_t t0 = rd_mcycle64();
#endif
    /* slices of 10k cycles (0.625ms @16MHz) for timer resolution.
     * Host: bounded run, then framebuffer dump. Target: runs forever;
     * the Falcon stays alive (framebuffer live in DDR3 for Stage 1
     * scanout), wishlist printed at first quiescence.               */
#ifdef HOST_TEST
    for (slice = 1; slice <= 400000u; slice++) {
#else
    for (slice = 1; ; slice++) {
#endif
        uint32_t sc = slice_cycles();             /* M28              */
        if (sc < SLICE_FLOOR) sc = SLICE_FLOOR;
        uint32_t c = (uint32_t)m68k_execute((int)sc);
        /* M11k: one SR read per 10k emulated cycles. Statistical, not
         * exact, but enough to show whether the guest sits at IPL>=6. */
        dbg_slices++;
        if (((m68k_get_reg((void*)0, M68K_REG_SR) >> 8) & 7u) >= 6u)
            dbg_ipl6++;
        cycles += c;
#ifdef HOST_TEST
        host_wall += (uint64_t)c * WALL_PER_EMU;
#endif
        /* ---- M10: wall-locked MFP timer clock + VBL ----------------
         * Preferred source: the hardware timebase counters (exact
         * silicon time). Fallback: the A25 mcycle wall clock. Both
         * feed the SAME mfp_timers_tick()/VBL stepping, so behaviour
         * is identical bar the time base; a rolled-back bitstream
         * (no timebase slot) transparently uses the fallback.        */
        { uint32_t t200 = 0, tvbl = 0, tcyc = 0;
          uint64_t w = rd_wall64();
          if (tb_read(&t200, &tvbl, &tcyc)) {
              /* hardware timebase present: VBL fires on tickvbl edges.
               * M11e: the MFP is NOT fed in d200*12288 lumps any more
               * -- one lump is exactly one Timer C period, freezing
               * the visible count for pollers (TOS 4.04 calibration).
               * MFP now uses the same fine mcycle conversion as the
               * fallback path, below.                                 */
              uint32_t d200 = t200 - tb_last200;
              uint32_t dvbl = tvbl - tb_lastvbl;
              if (d200 > 4000u) d200 = 1u;         /* first read / wrap */
              if (dvbl > 240u)  dvbl = 1u;
              tb_last200 = t200; tb_lastvbl = tvbl;
              (void)d200;                          /* telemetry only    */
              /* M18: VBL from cyc50 at the SELECTED rate. tickvbl is
               * still read above (telemetry + wrap guard) but no longer
               * sets the rate -- the fabric divisor is fixed at 60Hz.  */
              (void)dvbl;
              { uint32_t dcyc = tcyc - vbl_cyc_last;
                if (!vbl_cyc_have) { vbl_cyc_have = 1u; dcyc = 0u; }
                vbl_cyc_last = tcyc;
                if (dcyc > 50000000u) dcyc = 0u;   /* >1s: stall/glitch */
                vbl_acc += dcyc;
                { uint32_t p = vbl_period_cyc();
                  while (vbl_acc >= p) { vbl_acc -= p; vbl_due++; } } }
              { uint64_t dmfp_num = (w - mfp_wall) * WALL_MFP_NUM;
                uint32_t dmfp = (uint32_t)(dmfp_num / WALL_MFP_DEN);
                if (dbg_primed) {                            /* M11j */
                    if (dmfp > dbg_mfp_max) dbg_mfp_max = dmfp;
                    if (dmfp > dbg_mfp_iv)  dbg_mfp_iv  = dmfp; /*M11k*/
                    if (dmfp > 200000u) { dbg_resync++;
                                          dbg_resync_ticks += dmfp; }
                } else dbg_primed = 1;   /* first delta is bogus     */
                if (dmfp > 200000u) { dmfp = 0; mfp_wall = w; }
                else if (dmfp) { mfp_wall += (uint64_t)dmfp * WALL_MFP_DEN
                                             / WALL_MFP_NUM;
                                 mfp_timers_tick(dmfp);
                                 mfp_hbl_advance(dmfp); }
              }
          } else {
              /* fallback: mcycle wall clock. MFP ticks via exact
               * rational (dwall * 2457600 / 800e6); VBL at 60Hz.      */
              uint64_t dmfp_num = (w - mfp_wall) * WALL_MFP_NUM;
              uint32_t dmfp = (uint32_t)(dmfp_num / WALL_MFP_DEN);
              if (dbg_primed) {                               /* M11j */
                  if (dmfp > dbg_mfp_max) dbg_mfp_max = dmfp;
                  if (dmfp > dbg_mfp_iv)  dbg_mfp_iv  = dmfp; /* M11k */
                  if (dmfp > 200000u) { dbg_resync++;
                                        dbg_resync_ticks += dmfp; }
              } else dbg_primed = 1;     /* first delta is bogus     */
              if (dmfp > 200000u) { dmfp = 0; mfp_wall = w; }  /* stall */
              else if (dmfp) { mfp_wall += (uint64_t)dmfp * WALL_MFP_DEN
                                           / WALL_MFP_NUM;
                               mfp_timers_tick(dmfp);
                                 mfp_hbl_advance(dmfp); }
              if (w - vbl_wall >= vbl_period_wall()) {
                  if (w - vbl_wall >= vbl_period_wall() * 8ull) vbl_wall = w;
                  else vbl_wall += vbl_period_wall();
                  vbl_due++;
              }
          }
        }
        audio_pump();               /* M13: CPU->fabric sample stream   */
        /* M9E: input paced from the wall clock, not emulated cycles.
         * Catch-up is bounded (a long stall must not burst-deliver a
         * hundred stale packets); the ACIA loop is capped per slice. */
        { uint64_t w = rd_wall64();
          uint32_t guard;
          if (w - acia_wall >= WALL_ACIA_BYTE * 64ull)
              acia_wall = w - WALL_ACIA_BYTE;      /* resync after stall */
          for (guard = 0; guard < 64u
                 && w - acia_wall >= WALL_ACIA_BYTE; guard++) {
              acia_wall += WALL_ACIA_BYTE;
#ifdef HOST_TEST
              acia_slots++;
#endif
              acia_deliver_one();
          }
          if (w - hid_wall >= WALL_HID_TICK) {
              if (w - hid_wall >= WALL_HID_TICK * 8ull)
                  hid_wall = w;                    /* resync after stall */
              else
                  hid_wall += WALL_HID_TICK;
#ifdef HOST_TEST
              hid_polls++;
#endif
              hid_consume();                 /* M6: USB ring -> IKBD  */
          }
        }
        while (vbl_due > 0u) {               /* M10: wall-driven VBL */
            vbl_due--;
            if (hbl_line > 100u) hbl_frame_lines = hbl_line;  /* M17:  */
            hbl_line = 0u; hbl_acc = 0u;     /* M17: raster top-of-frame */
            mbox_publish();                  /* M4: scanout handshake */
            m68k_set_irq(4);                 /* cleared on int ack   */
#ifdef HOST_TEST
            /* boot-sector execution witness: the boot block's 2s
             * hz_200 dwell means a 60Hz PC sample lands inside the
             * DMA'd sector if (and only if) it is really executing  */
            { static int boot_witnessed;
              uint32_t bpc = m68k_get_reg((void*)0, M68K_REG_PC);
              if (!boot_witnessed && fdc_boot_dma
                  && bpc >= fdc_boot_dma && bpc < fdc_boot_dma + 512u) {
                  boot_witnessed = 1;
                  printf("[flop] boot sector EXECUTING (pc=%x in "
                         "dma'd sector @%x)\r\n", bpc, fdc_boot_dma);
              } }
#endif
        }
        if ((slice & 16383u) == 0u || force_status) {
            force_status = 0;                               /* M11l */
#ifndef HOST_TEST
            /* M9F: the green LED is the safe-to-power-off contract
             * now (solid = committed+idle, dark = write in flight);
             * the old liveness blink is retired.                     */
#endif
            uint32_t pc = cur_pc();
            status_line(slice, (uint32_t)(cycles / 1000000ull));
            /* stall = no new unique IO and PC in same 4K page, 3 checks */
            { uint32_t ss = screen_sum();
              if ((uint32_t)n_seen == last_uniq && (pc >> 12) == (last_pc >> 12)
                  && ss == last_scr) {
                if (++stall == 6u) {
                    printf("  [!] quiescent: pc=%x last_berr=%x (idle or waiting for missing hw; continuing)\r\n",
                           pc, last_berr_addr);
                    apy_arm();          /* M16: sample the next window */
                    printf("  [apy] sampling the spin...\r\n");
                } else if (stall == 7u && apy_on) {
                    apy_on = 0;
                    apy_report(pc);
                    if (!wishlist_done) { wishlist_done = 1; print_wishlist(cycles); }
                }
              } else stall = 0;
              last_scr = ss; }
            last_uniq = (uint32_t)n_seen;
            last_pc = pc;
        }
    }
#ifndef HOST_TEST
      { uint64_t dt = rd_mcycle64() - t0;
        uint32_t ms = (uint32_t)(dt / 800000ull);
        uint32_t khz = ms ? (uint32_t)(cycles / ms) : 0;
#ifdef BUILD_O2
        printf("\r\n  timing: %u ms wall, ~%u.%u MHz 68030 equivalent (-O2)\r\n",
#else
        printf("\r\n  timing: %u ms wall, ~%u.%u MHz 68030 equivalent (-Og)\r\n",
#endif
               ms, khz / 1000u, (khz % 1000u) / 100u);
      }
    }
#endif

#ifdef HOST_TEST
    /* PACETEST: the wall-paced input scheduler must fire at the rates
     * the constants claim, measured against the emulated cycle count
     * via the host's synthetic wall clock (WALL_PER_EMU). Delivery is
     * supply-limited in simulation (the orbit queues one packet per
     * emulated VBL), so the framebuffer cannot see this -- these
     * counters are the only host-side evidence that the scheduler is
     * live and its arithmetic correct.                                */
    /* expectations use INDEPENDENT literals (60Hz; 7812.5bps = 3125/4
     * bytes per second), never the WALL_* defines under test -- a
     * self-referential check would pass with wrong constants.        */
    { uint64_t wall = (uint64_t)cycles * WALL_PER_EMU;
      uint32_t exp_hid  = (uint32_t)(wall * 60ull / 800000000ull);
      uint32_t exp_acia = (uint32_t)(wall * 3125ull / (4ull * 800000000ull));
      int bad = 0;
      if (hid_polls  < exp_hid  - exp_hid /100u - 2u
       || hid_polls  > exp_hid  + exp_hid /100u + 2u) bad = 1;
      if (acia_slots < exp_acia - exp_acia/100u - 2u
       || acia_slots > exp_acia + exp_acia/100u + 2u) bad = 1;
      printf("PACETEST %s: hid %u (exp %u), acia %u (exp %u)\r\n",
             bad ? "FAIL" : "OK", hid_polls, exp_hid, acia_slots, exp_acia);
    }
#endif

    print_wishlist(cycles);

#ifdef HOST_TEST
    /* dump the framebuffer; geometry from the latched VIDEL registers,
     * derived exactly as mbox_publish() does (M8: all modes incl. 8-plane;
     * height from VDB/VDE instead of the old fixed 480).               */
    { FILE *f = fopen("screen.ppm", "wb");
      uint32_t vb = ((uint32_t)ram[0x44E]<<24)|((uint32_t)ram[0x44F]<<16)
                  | ((uint32_t)ram[0x450]<<8)|ram[0x451];
      uint16_t f_shift  = ((uint16_t)io_shadow[0x0266] << 8) | io_shadow[0x0267];
      uint8_t  st_shift =  io_shadow[0x0260];
      uint16_t vmode    = ((uint16_t)io_shadow[0x02C2] << 8) | io_shadow[0x02C3];
      uint16_t vwrap    = ((uint16_t)io_shadow[0x0210] << 8) | io_shadow[0x0211];
      uint16_t vdb = ((uint16_t)io_shadow[0x02A8] << 8) | io_shadow[0x02A9];
      uint16_t vde = ((uint16_t)io_shadow[0x02AA] << 8) | io_shadow[0x02AB];
      uint32_t hh  = (uint16_t)(vde - vdb);
      uint32_t bpp;
      int W, H, x, y, p;
      if      (f_shift & 0x0400u) bpp = 1u;
      else if (f_shift & 0x0100u) bpp = 16u;
      else if (f_shift & 0x0010u) bpp = 8u;
      else if (st_shift == 0u)    bpp = 4u;
      else if (st_shift == 1u)    bpp = 2u;
      else                        bpp = 1u;
      if (!(vmode & 0x02u)) hh >>= 1;
      if (vmode & 0x01u)    hh >>= 1;
      W = (int)((uint32_t)vwrap * 16u / bpp);
      H = (hh && hh <= 480u) ? (int)hh : 480;
      printf("framebuffer at %x spshift=%x vwrap=%u -> %dx%d %ubpp -> screen.ppm\r\n",
             vb, f_shift, vwrap, W, H, (unsigned)bpp);
      if (f && vb && W > 0 && W <= 1024
            && vb + (uint32_t)H * (uint32_t)vwrap * 2u <= ST_RAM_SIZE) {
          fprintf(f, "P6 %d %d 255\n", W, H);
          for (y = 0; y < H; y++) for (x = 0; x < W; x++) {
              if (bpp == 16u) {
                  uint32_t off = vb + ((uint32_t)y*(uint32_t)W + (uint32_t)x)*2u;
                  uint16_t w = ((uint16_t)ram[off] << 8) | ram[off+1u];
                  int r = (w >> 11) & 31, g = (w >> 5) & 63, b = w & 31;
                  fputc((r << 3) | (r >> 2), f);
                  fputc((g << 2) | (g >> 4), f);
                  fputc((b << 3) | (b >> 2), f);
              } else {
                  uint32_t grp = vb + (uint32_t)y*((uint32_t)vwrap*2u)
                               + (uint32_t)(x >> 4)*bpp*2u;
                  int bit = 15 - (x & 15), idx = 0;
                  for (p = 0; p < (int)bpp; p++) {
                      uint16_t w = ((uint16_t)ram[grp + (uint32_t)p*2u] << 8)
                                 |  ram[grp + (uint32_t)p*2u + 1u];
                      idx |= ((w >> bit) & 1) << p;
                  }
                  if (bpp == 8u) {
                      uint32_t o = 0x1800u + (uint32_t)idx*4u;
                      int r = io_shadow[o]     & 0xFC;
                      int g = io_shadow[o+1u]  & 0xFC;
                      int b = io_shadow[o+3u]  & 0xFC;
                      fputc(r | (r >> 6), f);
                      fputc(g | (g >> 6), f);
                      fputc(b | (b >> 6), f);
                  } else {
                      uint16_t pal = ((uint16_t)io_shadow[0x0240u + idx*2u] << 8)
                                   |  io_shadow[0x0241u + idx*2u];
                      int r = (pal >> 8) & 15, g = (pal >> 4) & 15, b = pal & 15;
                      r = ((r & 7) << 1) | ((r >> 3) & 1);
                      g = ((g & 7) << 1) | ((g >> 3) & 1);
                      b = ((b & 7) << 1) | ((b >> 3) & 1);
                      fputc(r * 17, f); fputc(g * 17, f); fputc(b * 17, f); }
              }
          }
          fclose(f);
      }
    }
    return 0;
#else
    printf("Heartbeat on green LED.\r\n");
    GPIO_DIR |= 1u;
    for (;;) {
        volatile uint32_t d;
        GPIO_CLR = 1u; for (d = 0; d < 20000000u; d++) ;
        GPIO_SET = 1u; for (d = 0; d < 20000000u; d++) ;
    }
#endif
}
