# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260926-hdmi1
ACTION: SIMULATE
RESULT: FAIL
GOWIN_VERSION: NOT_RUN
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD: gw_sh build_tc138k.tcl; echo GW_EXIT:$?; bash sim/run_hdmi_sim.sh; echo SIM_EXIT:$?

GW:
  GW_RESULT: FAIL (not run - Gowin toolchain not installed on the box)
  GW_EXIT: 127
  ERRORS: gowin-sh: command not found (wrapper /usr/local/bin/gowin-sh missing; no gw_sh on the box,
          only an unextracted Gowin_V1.9.12.03_linux.tar.gz). No HDL errors, because synthesis never started.
  LICENCE: not reached, so no licence retries
  LUT/FF/BSRAM/DSP, Fmax/hold: NOT_RUN
  BITSTREAM_SIZE: NOT_PRODUCED by this run. impl/pnr/atarist_tc138k.fs already on disk is stale
                  (36538618 bytes, dated 2026-09-26 12:13 BST, from an earlier build) and is not this request's result.

SIM:
  SIM_TOOL_MISSING iverilog
  HDMI_SIM NOT_RUN
  HDMI_EDGES: not printed (sim did not run)
  SIM_EXIT: 2
  No iverilog/vvp binary found anywhere on the box (find / -name iverilog/vvp: none),
  so PATH was not changed. Nothing installed, no other simulator tried.

NOTES:
  The HDMI sim is the encoder with a free-running pixel clock and the logic serializer
  (TMDS_BY_LOGIC). It is not the Gowin PLL and not OSER10. It does not prove the placed pins on the board.
  CONTEXT.md CHANGED is 0: not decoded, not edited.
  Nothing flashed. No bitstream, vvp, logs, or impl/ committed.
```
