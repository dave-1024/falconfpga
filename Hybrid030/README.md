# Hybrid030

Frozen hybrid scaffold: Musashi on the AE350 plus the REV11b HDL fabric.

| Path | Role |
|---|---|
| [HOWTO.md](HOWTO.md) | **SD card** — FAT32, `FALCON.CFG`, green LED |
| [AE350_ERRATA.md](AE350_ERRATA.md) | measured DDR3 / AHB dead lanes. Not our bugs. |
| `hybrid_falcon030/` | Gowin project + Verilog (`Falcon030.gprj`, `src/`) |
| `hybrid_musashi/` | C guest + `build_falcon_m28.bat` |

## SOM DDR3 — unpublished faults

The Gowin DDR3 IP on this SOM, used with the AE350, has dead lanes. These are not bugs in the HDL here. As of September 2026 they were not in Gowin's IP notes, not in Sipeed's board docs, and not in Sipeed's public repositories. They were not found described anywhere else either.

- Shared DDR3 **write lane 4** never completes, including on the vendor example granted alone. Tied off 14 July 2026. `falcon_wprobe` returned nothing.
- The **upper half of a 64-bit DDR3 read** is dead. Measured 11 July 2026: `fb_base` latched address-independent garbage while `magic[31:0]` validated. Lanes were cut to 32-bit, the width Gowin's own `DDR3_Shared` example validates.
- The **upper 32 bits of Extended AHB `HWDATA`** are dead. 32-bit transfers, even-word addresses, payload at +0 and +8. A write at +4 does not land.

There is no published workaround. Using the IP as documented does not work for those lanes. This tree did not fix the IP. It stopped using the dead parts. A real fix is to **write your own DDR3 controller**, or wait until Gowin learns of the faults and ships an updated IP. No such update existed when this was written.

The original note is the revision header of the bring-up top, `ae350_stage0_top.v`. Detail: [AE350_ERRATA.md](AE350_ERRATA.md).

## Board

**No Tang SDRAM module.** Guest RAM is the DDR3 on the 138K SOM, through the AE350. The plug-in module in J9 is not used here.

That module **is** required for `misterynano_tc138k/`, `rigsdram/`, and every HDL build after this hybrid. Do not flash those with J9 empty.

Not the destination CPU. That is `rigsdram/` then the Nano splice. Not a product. No support.
