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
| 5 cold boots | tt19 | (pending) | |
| FrontBench flags 7 caches ON 900 s | tt19 | (pending) | |

## Commits (tt-ram, local + linserver, not pushed)
- 71624aa [C10] fix
- bb0c706 / 26c3d0a: C9 and its revert
- 22bcfd2: docs

## Not done / superseded
- 12/16 MHz builds and the BSRAM trace: superseded by the root cause (12 MHz is infeasible anyway, not phase-locked to clk32).
- tl.st and td.st variants: not run.
