# AE350 / DDR3 / AHB errata

These are not bugs in this project's HDL. They were measured on the Andes **AE350** and the Gowin **DDR3** IP on this Tang Console 138K SOM, during the hybrid bring-up in July 2026. They are still in force on any path that uses that RISC-V fabric.

They do **not** apply to `misterynano_tc138k/` or `rigsdram/`. Those trees do not use the SOM DDR3 IP. They use the plug-in SDRAM module.

## Not published elsewhere

As of September 2026 these faults were not in Gowin's IP notes, not in Sipeed's board documentation, and not in Sipeed's public repositories. They were not found described anywhere else on the public web either. This file is the write-up so the next person does not have to find them the same way.

There is no vendor workaround in those docs. Using the IP as documented does not work for the dead lanes.

This project did **not** fix the IP. It stopped using the dead parts, and reached DDR3 through the Extended AHB master with 32-bit even-word transfers. That is an avoidance, not a repair.

A real fix is to **write your own DDR3 controller** instead of the Gowin IP, or wait until Gowin learns of the faults and ships an updated IP. No such update existed when this was written.

## Where the measurement was written

There is no separate probe log in git. The original note is the revision header of the bring-up top, `ae350_stage0_top.v` (the comment names the module `ae350_falcon_top`). A file referred to as the bug ledger is cited from `falcon_ahb_mux.v` ("bug-ledger family: never completes", ledger #9). That ledger is not in the repo.

**REV 2, 11 July 2026.** Shared DDR3 lanes were cut from 64-bit to 32-bit after the 64-bit read lane's upper half was measured broken. Symptom: `fb_base` latched address-independent garbage while `magic[31:0]` validated. 32-bit is the width Gowin's own `DDR3_Shared` example validates.

**REV 6, 14 July 2026.** HID writes moved off shared DDR3 write lane 4 onto the Extended AHB master. Lane 4 was tied off. `wr_done` never arrived, including on an isolated, exclusively granted, example-verbatim copy. `falcon_wprobe` returned zero signatures in every candidate address zone. Lane 5, the scanout read, was left on the DDR3 IP.

The same facts are repeated in `hybrid_falcon030/src/falcon_hid_ahb.v` and `falcon_timebase_ahb.v`.

## Do not use

**1. Shared DDR3 write lane 4 is dead.**

The fabric write port into the shared DDR3 (lane 4) never completes. Do not use that port. The replacement used here is the AE350 **Extended AHB** master.

**2. The upper half of a 64-bit DDR3 read is dead.**

Use 32-bit lanes only. Do not consume the upper 32 bits of a 64-bit DDR3 read. The 11 July symptom was garbage in the upper half while the low 32 bits of the same word were valid.

**3. The upper 32 bits of Extended AHB `HWDATA` are dead.**

A 64-bit AHB write does not land in the upper half. The silicon-proven pattern is:

- `HSIZE` = 32-bit (value 2)
- address 8-byte aligned (`addr[2] == 0`, an even word)
- payload in `HWDATA[31:0]` only
- the other word of a pair at **+8**, never at +4

Odd-word writes were measured not to land, even with the data in the low lane. REV11 wrote `tick200` at +4 and `cyc50` at +12. Those values never arrived. REV11b moved the slot to even words only: +0, +8, +16, +24.

The same rule is applied to reads on this port: trust `HRDATA[31:0]` only, even-word addresses only.

Records: `falcon_hid_ahb.v`, `falcon_timebase_ahb.v` (**FAULT 2**), `falcon_audio_ahb.v`, `Falcon030_top.v`, `hybrid_musashi/falcon_m28.c`.

## Same IP, also measured, not a dead lane

These are from the scanout bring-up in `falcon_video.v`. They are the same unpublished class of fault. A replacement controller is the real fix for these too.

- A DDR3 read burst whose length is not a multiple of 4 words wedges the read engine, at any address. A 117-beat mailbox burst did this. Lengths that had worked were 20, 40 and 160. Pad to a multiple of 4 and ignore the spare beats.
- Issuing the next read one cycle after the previous burst's last beat does not complete. The lane model in simulation accepts it. Silicon does not. The working shape is a gap of about 20 us with `rd_en` / `rd_go` idle, then a new request.
- `WBINVAL_ALL` at 60 Hz spends the memory bandwidth. Flush a range with `CCTL`, not the whole cache. This one has a software workaround. The dead lanes do not.

## What a later fabric master must do

If a new block writes DDR3 through the AE350, and the Gowin IP is still the one with these faults:

- do not instantiate the shared DDR3 write lane
- do not use a 64-bit read lane
- one 32-bit AHB transfer at an even word address
- data in the low 32 bits
- a second word at +8, after the first transfer completes
- do not place payload at +4 or +12
- a read burst length is a multiple of 4 words, and the next burst is not issued on the following cycle

`tb_mux_atomic.v` already fails a test that writes an odd word address. That check is the rule, not a suggestion.

If the design actually needs the dead lanes, do not keep poking the IP. Replace the DDR3 controller, or wait for a Gowin update that says these lanes work.
