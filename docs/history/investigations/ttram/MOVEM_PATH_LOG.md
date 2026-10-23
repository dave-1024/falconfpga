# movem-path progress log (22 Oct 2026, BST)

| Build | Commit | clk32 Fmax | clk_cpu030 Fmax | Worst slack | Worst path | LUT + ALU |
|---|---|---|---|---|---|---|
| tt20 | 71624aa | 33.38 | 22.42 | -4.887 (cpu030_n->cpu030) | SLICE_CNT_N->WR_EARLY->ALU_INIT->USE_DREG->AR_IN_1->ADR_EFF_I | 41127 + 5036 |
| tt21 | aef9a48 [T7] | 34.36 | 20.40 | -1.010 (cpu030_n->cpu030) | DSACK_In->WR_EARLY->F3_EARLY->NEXT_FETCH_STATE->AR_WR_1->AR_IN_1->ADR_EFF_I | 41092 + 5040 |
| tt22 | e0e6d5b [T8] | 34.26 | 19.92 | **+1.031** (clk32 blitter bltState->val_reg); CPU half-cycle +2.879 (HALT_In->PC_I) | all timed tables positive | 41087 + 5036 |

- Sims for T7 and T8: run_rtl.sh PASS; cmp_full 25 progs x WS 0/1/2/3/7 = 125/125 SAME (bus log identical); movemx to DONE
  WS0 733780 / WS3 1271408 clk SAME; clock-sampled asserts T7/T8 never fired.
- D-cache arrays: RAM16SDP4 (distributed) in tt20/21/22; I-cache DATA_RAM SDPB (C10 covers it), I-cache tags RAM16SDP4.
- tt22 bitstream: linserver ~/fpga_bitstreams/st_helper_hdn_tt22_e0e6d5b_t8unlk_p3.fs
  SHA256 2ad22bc0e242c392c4630e28b2d312b190890ae38d411d1cd602d47111c55575. NOT flashed.
- Access: /workspace/tools/pyssh/lsh.py (paramiko over tailscale SOCKS 1055). Sims: GHDL_PREFIX=/workspace/tools/ghdl/lib/ghdl.
