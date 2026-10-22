# Blitter shared-mode hang diagnosis (worktree /workspace/wt_blit, branch blitfix-shared off movem-path 0e8a2dc)
- netlist: /workspace/blsim/wf030_e0e6.vg (fresh wf030_syn.tcl of e0e6d5b core)
- test ROM: sim/st/prog_blt.s (BLTTEST test 4 replica, code in ST-RAM $4000, CACR/SR/MFPT via ASFLAGS --defsym); run_bus.sh gained $ASFLAGS
- runs rA..rG (cph 15625, TTRAM): caches on/off, IPL7/3/1 (HBL ints fired 0x68-0x71 times): ALL PASS, checksum d090 correct, 1 CPU loop
- MFP timer A ints never fired in sim (setup or sim MFP clock) - not pursued
- next: cph 46875 phase; check board-only defines (BRIDGE_EARLY_AS etc)
- FOUND: board build defines BRIDGE_EARLY_AS + WF030_FAST_HANDOFF (build_st_helper_hdn.tcl:41,45); sims rA-rG had neither. Rerun rH (caches on, SR 2100) / rI (caches off, 2700) with them.
- rJ (MFP ta, ph15625), rK (HBL+MFP, ph46875) with EARLY_AS; tb_bus got MFP/BLT-own monitor
- rJ/rK (EARLY_AS+FAST_HANDOFF, ph 15625 and 46875, caches on, HBL ints): PASS; monitor shows 4 blitter ownership windows (64-cycle timeout -> CPU -> re-grant) working
- MFP timer A never counts in sim (ctrl=1 dat=14 ier/imr set, no T_O_PULSE): vectored MFP IACK during a shared blit NOT covered
- CONCLUSION so far: no RTL repro; blitter/bridge BR/BG/BGACK handover + timeout/re-request correct in sim
## Board run (David approved), 22 Oct 13:17+
- BLTMASK.PRG (tests/blitter/bltmask.s): medium res, pass1 T4 masked, pass2 all masked, pass3 T4 unmasked; markers "> run $nn masked ... blit done"
- bm1.st (mkst_small, 2 sides): ran twice: only title, "00", pass headers, "0000" -> text beyond ~0x5e4 (image sector 9 = track0 side1) reads as zeros on the ST. SD copy verified correct (get 4608). Grabs /workspace/frontbench/tt22/bm1, bm1b
- NOTE: old BLTTEST tests table at 0x536; entries from test 6 and beyond lie past that boundary -> the earlier "hang at test 4" result is suspect
- retry bm1s.st single-sided (NH=1), CRC 6bbf7932
- bm1s (NH=1) same result. Fix: vars/stack to .bss (build_bss.sh), file first on disk (mkst_small_t0.py) -> PRG within track 0 sectors 4-8: bm2.st crc 1c0dd8c2
## 14:05 steering (David): standard images only
- INVALID: all results from 18 KB images (blts/bt2/bm1/bm1s/bm2), INCLUDING the tt22 "BLTTEST hangs at test 4". On those
  images the ST got zeros for file data from image sector 9 on (BLTTEST's test table entries 6+ sat past it).
- bm2 upload killed. Uploader slowness was up.py itself (sp.read(200) waits 2 s timeout per 64 B line) ->
  /workspace/bm/up2.py (same protocol, polls in_waiting): 720K in ~3.7 min (~3.4 KB/s).
- bm720.st = standard 720K (tttest/mkst2.py, same generator as the working tt*.st images), AUTO/BLTMASK.PRG (bss build), crc 23ff8430
- bm720 run 1 (BLTMASK 1.0): Blitmode $00; PASS1 test 4 MASKED: PASS (0 bad words, 0 cpu errs). PASS2 hung inside print
  ("> run $" shown, digits not) = in Bconout(AUX) after Cconws -> serial TX stall, not a blit. Grabs frontbench/tt22/bm720/s3,s6,s12
- BLTMASK 1.1: print to screen only (NOAUX). bm720b.st
- bm720b run (BLTMASK 1.1, screen only), finished < 80 s, NO HANG anywhere:
  PASS1 T4 masked PASS; PASS2 all masked: 04,05 PASS, 06 FAIL (bad words ~$09), 07 FAIL (~$03), 08-0D PASS (01-03 scrolled off);
  PASS3 T4 UNMASKED PASS; RESULT fail $02. cpu errs 0 everywhere. Grabs frontbench/tt22/bm720b/s4,s10,s16 (medium-res grab is blended but readable)
- => shared mode with an active 030 works on tt22, masked and unmasked. MFP theory not supported. The old "hang at test 4" = 18K image
  load fault + AUX Bconout stall. Open: tests 6/7 (NFSR cases) mismatch - model vs hardware, unverified; AUX output stall after a masked blit.
- Board: tts.st remounted + cold boot -> TTSEL prompt (restore_tts.png). tt22 core untouched.
