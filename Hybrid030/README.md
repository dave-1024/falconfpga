# Hybrid030

Frozen hybrid scaffold: Musashi on the AE350 plus the REV11b HDL fabric.

| Path | Role |
|---|---|
| [HOWTO.md](HOWTO.md) | **SD card** — FAT32, `FALCON.CFG`, green LED |
| `hybrid_falcon030/` | Gowin project + Verilog (`Falcon030.gprj`, `src/`) |
| `hybrid_musashi/` | C guest + `build_falcon_m28.bat` |

## Board

**No Tang SDRAM module.** Guest RAM is the DDR3 on the 138K SOM, through the AE350. The plug-in module in J9 is not used here.

That module **is** required for `misterynano_tc138k/`, `rigsdram/`, and every HDL build after this hybrid. Do not flash those with J9 empty.

Not the destination CPU. That is `rigsdram/` then the Nano splice. Not a product. No support.
