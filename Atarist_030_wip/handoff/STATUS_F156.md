# F156 status (speed, merged to main 9 Nov 2026)

**Date:** 2026-11-09. **Commit:** a54a611 (fix), docs after it. **Tag:** `bank-2026-11-09-f156` (main).

## What happened
- F147/F148: two-word opcode delivery after an I-cache restart. Sims passed; board hung from TT-RAM with the I-cache on.
- F149-F154 (Grok chat): guards on Q_HIT2/RESTART_PEND and an ADR_SKEW diagnostic. None fixed it; F154 gave a black
  screen. Address skew was ruled out.
- F155 (a356d19): known-good restore (tree = 0f101e0, two-word off). Board matched F145.
- Root cause (db9354c, `sim/speed/irq/run_lt_tt.sh`): an interrupt's RTE refills the pipe from the I-cache with two
  words in one OPCODE_RDY strobe. The exception handler's PIPE_STATUS counted strobes (needs 3), so REFILL_PIPE never
  ended. See FINDING_F155_ICACHE_HANG.md.
- F156 (a54a611): PIPE_STATUS counts words; OPCODE_RDY_2 wired to the handler; F147_TWO_WORD := true.

## Numbers
- Build (Gowin V1.9.12.03): clk_cpu030 20.401 MHz, clk32_core 34.731 MHz, 46537 LUT + 5352 ALU, timing_pairs rc=0.
- Sim (manual / F155 / F156): bsr_rts 15/29/28, jsr_rts 13/29/28.5, dbf_loop8 54/72/69.5, delay_loop8 72/94/90.5,
  Bcc not taken 6/9/7, BRA taken 6/7/7. Nothing faster than MC68030UM section 11.
- Board: LOOPTEST TT I-cache 1307189 -> 1428571, I+D 1418439 (ST-RAM and TT caches-off unchanged). FrontBench TT-RAM
  1237 (F155 1234, jitter about +-6). Linux BogoMIPS 2.13, about 8.6 MHz-equivalent (previous 1.79).

## Board notes
- Gowin V1.9.12.03 only. Programmer cable on linserver scans at location 5777 (rescan each time).
- Capture on Gaming-Laptop needs `-ss 3` (first frame is black). `lxa.st` is the autoboot Linux image.

## Next, in order
1. Issue loop: register-to-register ops 3 clocks against the manual's 2.
2. Taken-branch / change-of-flow restart: 11 against 6 before the speed work (BRA 7, BSR+RTS 28 against 15 now).
Still open: SD write path bug (F132 on `sd-write`, awaiting review), NetBSD, `sdram64` rebase.
