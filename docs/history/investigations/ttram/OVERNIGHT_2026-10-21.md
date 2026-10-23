# Overnight 2026-10-21: TT-RAM caches-on fault (all times BST)

## Root cause (found)
The I-cache DATA_RAM was inferred by Gowin as a block RAM (SDPB, synchronous read, no write-through), with the read
address retimed onto the F_ADR register input. When a prefetch fill wrote a long and the queue looked up that same
long in the next clock (a taken branch to a 4n+2 target inside it), the block RAM returned the OLD long, while
VALID and TAG already reported a hit. In TTM1 this put `3F3C` (move.w #2,-(sp), from 010003CE) in place of
`5888` at 010001CE, which caused the SP −2 slip and then EXC 2. RTL cannot show this because it has an
asynchronous read.
Fix [C10] 71624aa: a write-to-read forwarding register in WF68K30L_ICACHE (no switch). FALCON_LESSONS + BUGS updated.

## Results table
| Test | Build | Result | Meaning |
|---|---|---|---|
| Alignment sweep TTP00..12 | tt17 | pads 0/4/8/12 FAIL, 2/6 PASS | depends on long alignment of the loop |
| STR ring (TTXD3) | tt17s 9c413fa | decoder got 3F3C at 010001CE; IC_TAKE 1 clk after the PF_DONE fill of 1CC | stale long from the same index, other tag |
| Netlist check | tt17 .vg | DATA_RAM = SDPB, ADB = F_ADR next-state | block-RAM read-during-write |
| C9 registered fill | bb0c706 | killed before build, reverted 26c3d0a | would not remove the collision |
| C10 RTL regression p_spr WS0/WS2 | 71624aa | byte-identical to the baseline | no RTL change |
| C10 build tt19 | 71624aa | clk32 34.482 MHz, clk_cpu030 21.232 MHz, worst −1.723 ns, LUT 41708 + 5124 ALU | ≥17 MHz OK |
| op53 + boot | tt19 | GEM desktop | works |
| TTM1 caches ON (3919) | tt19 | T1..T6 all 0, OFF all 0 | **FIXED** |
| TTM I-only (0019) / D-only (3909) | tt19 | all 0 | pass |
| TTP sweep | tt19 | not read: the HDMI/OSD went black (video loss); the reflash restored it | retry |
| 5 cold boots | tt19 | grabs mostly black; the OSD is black too | build-specific HDMI dropouts, so tt19 is rejected as the final build |
| tt17 reflash, 5 boots x 3 grabs | tt17 | 14/15 desktop | video stable, so the dropouts are tt19-specific |
| tt20 = C10 without TT_RING/STR debug | 71624aa | clk32 33.381 MHz, clk_cpu030 22.424 MHz, worst −4.887 ns, LUT 41127 + 5036 ALU | release config |
| 5 cold boots | tt20 | all reach the desktop (15 grabs: 13 desktop, last 2 black = capture) | OK |
| TTM1 caches ON / OFF | tt20 | all 0 | **PASS** |
| FrontBench flags 7 caches ON 920 s | tt20 | runs the whole time; at 900 s: 72 frames / **1362 lastcount** | **GOAL MET** (ST-RAM 990, TT caches off 1169) |

## Commits (tt-ram, local + linserver, not pushed)
- 71624aa [C10] fix
- bb0c706 / 26c3d0a: C9 and its revert
- 22bcfd2: docs

## Not done / superseded
- 12/16 MHz builds and the BSRAM trace: superseded by the root cause (12 MHz is infeasible anyway, not phase-locked to clk32).
- tl.st and td.st variants: not run.

## Final state
- The board is on **tt20** (st_helper_hdn_tt20_71624aa_p3.fs, C10 without debug rings). It is verified: boots, TTM1 passes, FrontBench runs.
- Video: /workspace/frontbench/frontbench_tt20_ttram_cacheon_720p.mp4 (1280x720 H.264 yuv420p +faststart, 920 s) and _clip.mp4 (25 s at 875–900 s). Originals are in linserver ~/cap/.
- tt19 (the same fix plus the debug rings) showed HDMI dropouts, so do not use it. Debug rings should be built separately when needed.
- Next: the worst slack is −4.9 ns on the known cross-clock SP write-back path (MOVEM_INH_WR → AR_IN → ADR_EFF_I). It was not touched tonight; clk_cpu030 Fmax is 22.4 MHz (≥17 MHz OK). Check other inferred arrays for block-RAM read-during-write (D-cache is distributed RAM; the core's other SDPBs are outside the CPU).
