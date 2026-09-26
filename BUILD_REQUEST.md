# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

Poll rule: every wake, read only the plain `HANDOFF`, `CHANGED`, and `READ` lines in `CONTEXT.md`. Do not decode the block.

Decode only if `CHANGED` is 1 and (`ACTION` is BUILD, BUILD_AND_FLASH, PREPARE, or SIMULATE, or `READ` is 1). If `CHANGED` is 0, do not decode. After a decode, set `CHANGED` and `READ` to 0 and echo `HANDOFF_SEEN`. An idle poll writes nothing.

Run only if ACTION is BUILD/BUILD_AND_FLASH/PREPARE/SIMULATE and this REQUEST_ID is not already in BUILD_REPORT.md.

```
REQUEST_ID: 20260926-hdmi2
ACTION: SIMULATE
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD: gw_sh build_tc138k.tcl; echo GW_EXIT:$?; bash sim/run_hdmi_sim.sh; echo SIM_EXIT:$?
WHAT_CHANGED: Dropped set_option -co-place_io_registers. Gowin 1.9.12.03 rejects it. It was 0, so the build is unchanged. Ignore 20260926-hdmi1 if you already failed it on that line. CONTEXT.md unchanged. Do not decode it.
CHECK: Do both, even if the first fails. Do not flash. Do not push a bitstream, a vvp, or anything under impl/. Do not install packages.
1. Gowin build of misterynano_tc138k with build_tc138k.tcl. Report PASS or FAIL, errors with file:line, and the bitstream size in bytes only.
2. HDMI pin sim. Copy the HDMI_EDGES line and the HDMI_SIM line into the report. PASS means the encoder toggled. FAIL compile means paste the iverilog error. SIM_TOOL_MISSING means iverilog is not on this box; say so and stop. Do not try another simulator.
This sim is the HDMI encoder with a free-running pixel clock and the logic serializer. It is not the Gowin PLL and not OSER10. It does not prove the placed pins on the board.
```
