# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

```
REQUEST_ID: 20260924-3b
ACTION: BUILD
PROJECT: rigsdram
TOP: RIGSDRAM_TOP
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE
CPU_TARGET_MHZ: 16.0
WHAT_CHANGED:
  H48-3 VHDL is already on main (u_lock_meta DFF). Do NOT re-apply 3.patch.
  Apply only patches/H48_20260924-3b.patch (deletes lock_meta_s0/RESET
  false_path that caused TA2003). Then BUILD.
  If u_lock_meta/D also TA2003, delete that line too and rebuild once.
  AUTO_WARM=0. No PLL change. No wf68k30L.
CHECK:
  1. PnR completes. Bitstream written.
  2. Fmax table clk_ref / clk50 / core_clk. FAIL if core_clk Fmax < 16.0.
  3. Hold: no fabric RESET/SET/CE from state_1_s0. lock_meta D path may
     be false-pathed; note whether the constraint Actived.
  4. BUILD_REPORT. Do not flash.
```
