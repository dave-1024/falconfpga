# GUI build — tick these two boxes first

Open `Falcon030.gprj` in the Gowin IDE and the project does **not** remember these ticks. A CLI build with `build_hybrid.tcl` sets them. The GUI does not. If you skip this, Place & Route fails on the flash pins, or it finishes and the AE350 never boots.

## Tick these. Leave the rest alone.

1. Open **Configuration** (Project menu, or the Configuration button on the toolbar).
2. In the left tree: **Place & Route → Dual-Purpose Pin**.
3. Tick **Use MSPI as regular IO**.
4. Tick **Use CPU as regular IO**.
5. Leave the other four **unticked**: Use JTAG as regular IO, Use SSPI as regular IO, Use READY as regular IO, Use DONE as regular IO.
6. Apply, then OK. Then build.

Those two release the six flash balls (`FLASH_SPI_*` in `src/tang_console_ae350_stage0.cst`). They are the AE350 instruction-fetch path. Without the ticks they stay dedicated configuration pins.

Do not copy the MiSTeryNano set. That tree ticks all six. This one does not.

## Also check, once

- Top module is `falcon_top`. Not a PLL wrapper.
- Device is `GW5AST-LV138PG484AC1/I0`, version **C**.
- Use `C:\Dev\Gowin\Gowin_V1.9.12.03_x64`. Not `Gowin_V1.9.12_x64`.

Bitstream is `impl/pnr/Falcon030.fs`. Flash that at `0x0`. This fabric does not use the Tang SDRAM plug-in.

## CLI instead

From this directory, the script sets the same two ticks and leaves the other four off:

```
C:\Dev\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe build_hybrid.tcl
```
