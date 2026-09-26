# AE350 / DDR3 / AHB errata

These are not bugs in this project's HDL. They were measured on the Andes **AE350** and the Gowin **DDR3** IP on this Tang Console 138K SOM, during the hybrid bring-up in July 2026. They are still in force on any path that uses that RISC-V fabric.

They do **not** apply to `misterynano_tc138k/` or `rigsdram/`. Those trees do not use the SOM DDR3 IP. They use the plug-in SDRAM module.

There is no separate probe log in git. The measurements are the file headers named below. A short locked list also lives in `CONTEXT.md`.

## Do not use

**1. Shared DDR3 write lane 4 is dead.**

The fabric write port into the shared DDR3 (lane 4) never completes. `wr_done` does not arrive, including on an isolated, exclusively granted copy of the vendor example. `falcon_wprobe` returned no signature in any address zone. Dated 13–14 July 2026.

Do not use that port. The replacement used here is the AE350 **Extended AHB** master. Lane 5, the read side used by scanout, was left on the DDR3 IP.

Record: `hybrid_falcon030/src/falcon_hid_ahb.v`, file header.

**2. The upper half of a 64-bit DDR3 read is dead.**

Use 32-bit lanes only. Do not consume the upper 32 bits of a 64-bit DDR3 read.

**3. The upper 32 bits of Extended AHB `HWDATA` are dead.**

A 64-bit AHB write does not land in the upper half. The silicon-proven pattern is:

- `HSIZE` = 32-bit (value 2)
- address 8-byte aligned (`addr[2] == 0`, an even word)
- payload in `HWDATA[31:0]` only
- the other word of a pair at **+8**, never at +4

Odd-word writes were measured not to land, even with the data in the low lane. REV11 wrote `tick200` at +4 and `cyc50` at +12. Those values never arrived. REV11b moved the slot to even words only: +0, +8, +16, +24.

The same rule is applied to reads on this port: trust `HRDATA[31:0]` only, even-word addresses only. Do not assume a read of the upper half works just because the write rule was the one that was probed.

Records: `falcon_hid_ahb.v` (the measurement), `falcon_timebase_ahb.v` (**FAULT 2**, the lane rule), `falcon_audio_ahb.v` (the read-side copy of the rule), `Falcon030_top.v`, `hybrid_musashi/falcon_m28.c`.

## Related, same IP, not a dead lane

`WBINVAL_ALL` at 60 Hz spends the memory bandwidth. Flush a range with `CCTL`, not the whole cache, on the video/audio tick.

## What a later fabric master must do

If a new block writes DDR3 through the AE350:

- do not instantiate the shared DDR3 write lane
- one 32-bit AHB transfer at an even word address
- data in the low 32 bits
- a second word at +8, after the first transfer completes
- do not place payload at +4 or +12

`tb_mux_atomic.v` already fails a test that writes an odd word address. That check is the rule, not a suggestion.
