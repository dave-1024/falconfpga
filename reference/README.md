# reference/: older trees kept for comparison

None of these is the live core. The live work is the Falcon core on branch [`falcon`](https://github.com/dave-1024/falconfpga/tree/falcon), in [`Falcon030_rtl/`](https://github.com/dave-1024/falconfpga/tree/falcon/Falcon030_rtl). The ST/STE 68030 core in [`Atarist_030_wip/`](../Atarist_030_wip/) is retired for now. Each tree below builds on its own and
uses only paths inside its own folder.

| Folder | What it is | Why it is kept |
|---|---|---|
| [`rigsdram/`](rigsdram/) | The 68030 (wf68k30L) on an ST bus with the external SDRAM module in J9 (Sept 2026). | Known-good "oracle" for 030 + SDRAM behaviour. Do not rebuild without a reason. |
| [`misterynano_tc138k/`](misterynano_tc138k/) | Stock [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano) ST (fx68k 68000) for the Tang Console 138K. | Reference for the stock ST core on this board (diffs, reset, video). |
| [`Hybrid030/`](Hybrid030/) | The first approach: Musashi 68030 emulator on the AE350 RISC-V plus FPGA fabric. | Frozen history; source of a few copied files. |
