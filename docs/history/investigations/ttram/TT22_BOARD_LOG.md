# tt22 board log (e0e6d5b, st_helper_hdn_tt22_e0e6d5b_t8unlk_p3.fs) - 22 Oct 2026, BST
- Flash: SHA ok, scan loc 4369, op53 rc=0 (132 s), reload ALLDONE. Board on tt22.
- 5 cold boots: 5/5 desktop (15/15 grabs identical). /workspace/frontbench/tt22/boot_*.png
- GEMBENCH 6.31 (gb608.st, ST medium, caches ON, from ST-RAM), All Tests started 09:40:43 via key a, done by 09:52:
  Dialog 23.775 55%, VDI Text 32.600 44%, Effects 41.895 51%, Small 45.755 49%, Graphics 43.170 64%, Window 20.395 49%,
  IntDiv 6.160 510%, Float ---, RAM 35.770 101%, ROM 71.560 104%, Blit 22.720 15%, Scroll 27.020 35%, Justified 26.210 44%,
  Enquire 20.405 101%, ALT RAM 35.245 206%; Display 46%, CPU 182%, Average 91%. System box: TOS 2.06 / GEMDOS 0.20 (EmuTOS), BLiTTER NP, 68030, CACHE D=ON I=ON.
  PNG /workspace/frontbench/gembench_tt22.png
- up.py: 'h0' line not supported by the helper (fixed: always 'h <hex>'). Upload ~31 B/s, so 720K images are impractical; built an 18 KB image blts.st (bm/mkst_small.py).
- Blitmode(-1) = $0000 -> TOS sees no blitter (bit1=0).
- BLTTEST (AUTO, after BLITMODE): EmuTOS Panic Illegal Instruction pc=003F7FAC (on the stack) sr=2308, before its title printed. Not analysed.
- First GEMBENCH PNG got overwritten by a black re-grab. GEMBENCH rerun (started 10:45:55, gb608.st, medium res): same results within noise (ROM 71.565). Good PNG: /workspace/frontbench/gembench_tt22_ok.png (also copied to gembench_tt22.png), mean RGB 207,214,205.
- TTM1 (ttm1.st) ON 3919 + OFF 0808: T1..T6 all 0 -> PASS.
- ttmid.st: I-only 0019 + OFF and D-only 3909 + OFF: all 0 -> PASS.
- TTW: CACR 3919/0919/2919/0808/3919 cachedmis 0 memmis 0 -> PASS.  TTE: 3919 and 0808 0 mismatches -> PASS.
- TTP sweep: P00, P02, P06, P08, P12 ON+OFF all 0; P04 OFF half seen all 0 (ON half scrolled off) -> PASS (tt17 failed pads 0/4/8/12).
- Rebuilt BLTTEST.PRG (5936 B) put on bt2.st (18 KB, CRC c5a15bfe). Upload pending (tailscale SOCKS to linserver dropping since ~11:00).
- Rebuilt BLTTEST (5936 B) from AUTO of bt2.st (upload CRC c5a15bfe ok), low res, so lines are cut at 40 columns:
  "TOS Blitmode(-1) = $00"; test $01 (1 word HOG) bad words 0; $02 (7 words shared) bad words 0; $03 (13x9 HOG) bad words 0;
  then it HANGS at test $04 (13x9 shared + CPU busy traffic): screen unchanged from +30 s to +180 s. Tests 5-13 not reached.
  => the blitter copies correctly in HOG and in shared mode with an idle CPU, but bus sharing with an active 030 deadlocks. Grabs: /workspace/frontbench/tt22/blttest2_{1,3,6}.png
  No serial capture: the ST's MFP serial port has no known host tty on linserver.
- 11:19 BST FrontBench flags 7 (tts.st, SEL key 0) + 920 s ffmpeg started -> ~/cap/frontbench_tt22_ttram_cacheon.mp4
- FrontBench flags 7, caches ON, TT-RAM, 920 s: lastcount 1360 (210 frames) at the end (tt20: 1362). Videos: /workspace/frontbench/frontbench_tt22_ttram_cacheon_720p.mp4 and _clip.mp4 (875-900 s); last frame tt22/fb22_900.png.
- Board left on tt22, running FrontBench (tts.st). tt20 reflash not needed.
