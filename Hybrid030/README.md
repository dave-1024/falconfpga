# Hybrid030

Frozen hybrid scaffold: Musashi on the AE350 plus the REV11b HDL fabric.

| Path | Role |
|---|---|
| [HOWTO.md](HOWTO.md) | **SD card** — FAT32, `FALCON.CFG`, green LED |
| `hybrid_falcon030/` | Gowin project + Verilog (`Falcon030.gprj`, `src/`) |
| `hybrid_musashi/` | C guest + `build_falcon_m28.bat` |

Not the destination CPU. That is `rigsdram/` then the Nano splice. Not a product. No support.
