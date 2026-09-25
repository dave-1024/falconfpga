# BUILD_REQUEST

OWNER: Grok chat. Grok bot: read only.

```
REQUEST_ID: 20260925-mn1
ACTION: PREPARE
PROJECT: misterynano_tc138k
TOP: top
DEVICE: GW5AST-LV138PG484AC1/I0
DEVICE_VERSION: C
REPLICATE_RESOURCES: TRUE
WHAT_CHANGED:
  NOT a Gowin / rigsdram build. Do NOT run gw_sh. Do NOT touch rigsdram/.
  Fill misterynano_tc138k/ with stock Console-138K HDL so David can pull and build later.

  1. git pull origin main.
  2. Clone upstream if needed:
       git clone --depth 1 https://github.com/MiSTle-Dev/MiSTeryNano.git %TEMP%\MiSTeryNano
     Fallback: https://github.com/harbaum/MiSTeryNano.git
  3. From upstream src/, copy EVERY path listed in
     misterynano_tc138k/atarist_tc138k.gprj into misterynano_tc138k/
     keeping the same relative paths (tang/console138k/top.sv, atarist/...,
     fx68k/microrom.mem, ikbd/rom/ikbd.hex, misc/atarist_xml.hex, …).
     Also copy fx68k/LICENSE and fx68k/fx68k.txt if present.
  4. Do NOT copy nano20k/primer/mega/console60k TOPS, firmware, images,
     or other .gprj/.tcl files. Keep our README, .gitignore, gprj, and
     build_tc138k.tcl (already Version C).
  5. Confirm every gprj path exists under misterynano_tc138k/.
  6. git add misterynano_tc138k
     git commit -m "Add misterynano_tc138k Console 138K HDL from upstream"
     git push origin main
  7. Write BUILD_REPORT.md REQUEST_ID 20260925-mn1 RESULT PASS or FAIL.
     List file count added. If clone fails, quote the error.
CHECK:
  tang/console138k/top.sv, fx68k/fx68k.sv, fx68k/microrom.mem,
  misterynano.sv, tang/mega138kpro/sdram.v all present.
  rigsdram/ untouched.
```
