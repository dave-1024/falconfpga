# BUILD_REPORT

OWNER: Grok bot. Grok chat: read only (may reset to this template after reading).

```
REQUEST_ID: 20260925-mn2
ACTION: BUILD
RESULT: FAIL
GOWIN_VERSION: V1.9.12.03 (gw_sh, headless, Linux)
PROJECT: misterynano_tc138k
WORKDIR: misterynano_tc138k
BUILD_CMD: gw_sh build_tc138k.tcl (run via headless env wrapper; no repo changes)
TOP: top
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPO COMMIT BUILT: f72b220

STAGE REACHED: GowinSynthesis (HDL elaboration). Failed in ~1.4 s. PnR not run.
LICENCE: OK (no licence errors, no retries needed)

ERRORS:
  1. tang/console138k/top.sv:243  ERROR (EX3990) : Cannot find port 'clk' on this module
     -> instance `misterynano misterynano ( .clk ( clk ), ...` ; module 'misterynano'
        declared at misterynano.sv:9 has no 'clk' port (ports start flash_clk, reset, user, clk32, por ...).
  (only error; synthesis stopped -> "run all" failed at build_tc138k.tcl line 146)

  Note: our top.sv and misterynano.sv are identical (ignoring CRLF) to upstream
  MiSTle-Dev/MiSTeryNano @ c8e4601, so the mismatch is upstream. Upstream main
  misterynano.sv also has no 'clk' input. Likely fix (NOT applied, no HDL iteration):
  remove the `.clk ( clk ),` line from top.sv:243, or add a clk port to misterynano.

WARNINGS OF NOTE:
  atarist/atarist.v:907      EX2987 'old_flg' must be declared automatic/static
  fdc1772/fdc1772.v:261      EX3069 Potential always loop found
  misc/sysctrl.v:322         EX2987 'rtc_index' must be declared automatic/static
  tang/console138k/top.sv:210 EX3073 Port 'stick_lx' unconnected
  tang/console138k/top.sv:308 EX3073 Port 'jtagsel' unconnected

RESOURCES (LUT/FF/BSRAM/DSP): NOT_AVAILABLE (synthesis failed)
FMAX / SETUP / HOLD:          NOT_AVAILABLE (PnR not run)

CHECK:
  1. PnR complete / impl/pnr/atarist_tc138k.fs   FAIL - PnR not run, no .fs generated (0 bytes, file absent)
  2. device_version C / use_jtag_as_gpio 1       tcl: set_device ... -device_version C and
                                                 set_option -use_jtag_as_gpio 1 confirmed.
                                                 log: "current device: GW5AST-138C GW5AST-LV138PG484AC1/I0".
                                                 use_jtag_as_gpio not echoed in log (applies at bitgen, not reached).
  3. BUILD_REPORT ERRORS/LUT/FF/BSRAM/DSP/Fmax/.fs  errors listed; resources/Fmax/.fs n/a (synth fail)
  4. FAIL on first error with file:line          top.sv:243 EX3990; no HDL iteration done

NOTES:
  rigsdram/ untouched. impl/ and logs untracked (impl/ in .gitignore; log kept outside repo).
```
