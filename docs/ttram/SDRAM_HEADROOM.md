# SDRAM headroom study (ST-RAM + TT-RAM on one module)

Read-only study, 2026-10-22, branch `tt-ram`. Nothing was built, flashed or committed.
Sources: `Atarist_030_wip/hdl/tang/mega138kpro/sdram.v` (the controller), `hdl/cpu030/cpu030_st_bridge.v` (TT
decode and termination), `docs/TTRAM_DESIGN.md`, `hdl/tang/console138k/atarist_st_helper.sdc`.
The tt20 timing reports on linserver were **not checked**: the box has no ssh client, so linserver couldn't be reached.

## Plain-English summary

- The memory chip runs at **32 MHz**, the same clock as the ST chipset. The 68030 runs at **16 MHz**, exactly half of
  that and locked to it. (The 22.4 MHz "Fmax" in the build reports is only how fast the design *could* go.)
- The ST side owns the memory on a fixed beat: every 250 ns (8 memory clocks) the ST chipset may make one access.
  TT-RAM squeezes **one 32-bit long per 250 ns** into the 6 clocks the ST leaves free in each beat. The ST side never
  notices, which is why the ST timing stays cycle-exact.
- A TT-RAM **read** costs on average about **6½ CPU clocks** (about 3½ wait states; 2 to 6 depending on where in the
  beat it arrives). A **write** costs about **4 CPU clocks** (about 1 wait state) because it's posted. A real 68030 with
  fast RAM does a long in 2 clocks, and a whole 16-byte cache line in 5.
- A 16-byte cache line (4 longs) therefore costs about **26 CPU clocks** today, against 5 on a TT with burst.
- **Faster is possible without touching ST timing,** provided the ST commands stay at exactly the same moments:
  1. *Cheapest:* let TT-RAM start at more points in the beat while the ST CPU half is idle. That saves about
     1–2 CPU clocks per long.
  2. *Bigger:* run the memory chip at 64 MHz (or 96–100 MHz) and replay the ST commands at the same real times. TT then
     gets more and earlier slots. A read drops to about 3½–4 CPU clocks.
  3. *With 2 (or more):* add **STERM** (the 030's fast 2-clock ending) and **burst line fills**. A cache line could drop
     from about 26 to about **6–8 CPU clocks**. Burst fills are impossible at 32 MHz: 8 words don't fit in the free 6-clock window.
- Gaps for David: which speed grade the chips on the Tang SDRAM X2 module are (-6 / -6I / -7); whether the Gowin PLL can
  make 64/96/160 MHz locked to 32 MHz (needs a VCO that is a multiple of 32 MHz); and the SDRAM pin timing at the higher
  clock (to be read from the timing report on linserver).

## 1. What the controller does now

| Item | Value | Evidence |
|---|---|---|
| SDRAM clock | `clk` = clk32_core = 50 MHz × 16/25 = **32.0 MHz** (VCO 800 MHz / 25); `sd_clk = ~clk` (inverted, board phase per TTRAM_DESIGN §9) | `sdram.v:35,63`; `atarist_st_helper.sdc:13,32` |
| clk_cpu030 | 50 × 8/25 = **16.0 MHz** = clk32 / 2, same VCO, phase 0 (plus an inverted copy for the falling-edge logic) | `sdc:38,45` |
| CKE / CS | CKE tied high, CS always asserted in logic (`sd_cs = 0`); on the module both chips share the bus, with CS via an inverter | `sdram.v:64,112` |
| Mode | **CAS latency 2**, **burst length 1**, sequential, **single-access writes** (NO_WRITE_BURST = 1), tRCD = 1 clock (31 ns ≥ 15 ns) | `sdram.v:66-73` |
| Page policy | Auto-precharge on every access (A10 = 1 on the column command) | `sdram.v:235,270,284` |
| Refresh | The chipset drives `refresh`; on the ST RAS edge with refresh set, one AUTO REFRESH (all banks) is issued instead of an access. Rate = the GSTMCU's refresh slots (not re-derived here; W9825G6KH needs 8192 per 64 ms = one per 7.8 µs). TT accesses always end with auto-precharge before g0, so the banks are idle when a refresh comes | `sdram.v:216-224`; TTRAM_DESIGN §4 |
| Banks | Bank 0 = ST-RAM; banks 1–2 = TT-RAM 16 MB; bank 3 free. A long = two adjacent columns in one row | TTRAM_DESIGN §3; `sdram.v:258-261` |

### Arbitration and the TT slot
- **ST side (video/shifter, ST CPU slots, DMA, blitter)** is arbitrated entirely by the GSTMCU, as on the real ST. Video RAS
  on time0 rising, CPU/DMA/blitter RAS on time0 falling, exactly 8 clk32 (250 ns) apart, so every ST start lands on g0
  (or g7 with the F63 early read start). sdram.v just obeys the RAS edge. Nothing in sdram.v arbitrates the ST masters.
- **TT-RAM** is a second, lower-priority client inside sdram.v. `tg` tracks the 8-clock grid (resynchronised on every
  ST start), and a TT access may start **only at g2**, and only if the ST state machine is idle or in phase (states 0/2/3)
  (`sdram.v:146-160`). So TT gets **one long per 250 ns slot** in both halves (video and CPU), whether or not the ST used the slot.
  Peak TT bandwidth = 4 bytes / 250 ns = **16 MB/s**, with no contention from video.
- Data-bus discipline: ST commands at g7/g0/g1, ST read data g2–g4, TT commands g2–g5, TT write data g5–g6 (moved there by
  [C7] to avoid the ST read's tOH), TT read data g5–g6 captured g6/g7 (`sdram.v:141-143,265-290`).

### A TT-RAM long today (clk32 = 31.25 ns, clk_cpu = 62.5 ns)
**Read** (bridge [C5]: no early DSACK; [C8]: DSACK through clk_cpu flops):
1. E0, the first clk32 edge with AS low: the bridge registers `tt_req` (`cpu030_st_bridge.v:~405-416`).
2. Wait for the next g2 with `tt_req` seen: **0–7 clk32, average about 3.5**.
3. g2 ACT, g3 READ w0, g4 READ w1 + AP and `tt_ack`, then w0 at g6, `tt_dout` loaded at g7 (`sdram.v:259-274`).
4. Bridge: `tt_ack` seen, then a 3-edge pipe (`t_rp`), then `t_rd` and `t_dsack` (about 6 clk32 after ACT).
5. `t_dsack_c` on the next clk_cpu rising edge (0.5–2 clk32), the 030 samples DSACK on a falling edge, and latches data one
   clk_cpu later.

**Derived total for AS low to the data latch:** about 1 + 3.5 + 6 + 1.5 + 1 + 2 ≈ **13–15 clk32 average, about 6.5–7.5 clk_cpu**
(range about 5–10.5). A 68030 asynchronous cycle with no waits is 3 clocks (DSACK by S2), so this is **about 3.5 wait states
on average (about 2–7)**.
**Write:** acked when sdram.v accepts it at g2 (posted), so ≈ 1 + 3.5 + 1 + 1.5 + 1 ≈ **8 clk32 ≈ 4 clk_cpu ≈ 1 wait state**.
A TT access that follows a write waits for `tt_busy` (one more slot in the worst case).

**Measured (simulation, from TTRAM_DESIGN §6):** v1 AS→DSACK 13 clk32 average (max 15); with L1/L2 the whole TT cycle was
11.6 clk32 average (about 5.8 clk_cpu, about 4 waits). C5 then removed the early read ack (+3 clk32) and C8 added the
clk_cpu flop, which is why the current read estimate is about 13–15. There is no board measurement of per-access latency;
FrontBench 990 (ST-RAM) / 1169 (TT, caches off) / 1362 (TT, caches on) is the only board figure.

**Cache line (16 bytes) today:** no burst (CBREQ held negated), so the I-cache fills one long per prefetch and the D-cache
one long (plus fill words) per miss. That's 4 × about 6.5 ≈ **26 clk_cpu per line**, as separate bus cycles.

## 2. Headroom

### SDRAM chip (W9825G6KH, datasheet values)
| Grade | Max clock CL3 | Max clock CL2 | tRCD / tRP | tRC |
|---|---|---|---|---|
| -5 | 200 MHz | 133 MHz | 15 ns | 55–60 ns |
| -6 / -6I | 166 MHz | 133 MHz | 15 ns | 60 ns |
| -7 | 143 MHz | 100 MHz (approx.) | 15–20 ns | 60–65 ns |
The module's grade is **not stated in the repo**: it's a gap for David to read off the chips. Any grade allows 100 MHz CL2 and
133 MHz CL2/CL3 on the -6, so the chip isn't the limit. The limit is the FPGA side: the shared 16-bit bus with two chips
(more load), the board routing, and Gowin I/O timing. MiSTer-style SDRAM on Gowin boards commonly runs 64–100 MHz. Treat
**64 MHz as low risk and 96–100 MHz as needing a pin-timing check**.

### Clock choice (must stay phase-locked to clk32 so the ST grid is exact)
The current VCO is 800 MHz, which gives 32 = /25 and 16 = /50, but 64/96 MHz are not integer divisions of 800. A **960 MHz VCO**
gives 32 (/30), 16 (/60), 64 (/15), 96 (/10) and 160 (/6). Whether the 138K PLL accepts 960 MHz on that output set, and the
HDMI/AE350 clocks sharing that PLL, has to be checked in the Gowin IP generator. **Gap**: not verified.

### ST cycle-accuracy constraint (applies to every option)
Bank 0 ACT/CAS/data must stay at the same **absolute times** relative to the GSTMCU RAS edges (g0/g7, data at the same
clk32 edge where the ST captures it). At 2× or 3× clock, the ST sequence is replayed with each step at the matching
sub-clock, and `dout` is still handed over on the clk32 edge the chipset uses now. The existing checks stay the
acceptance tests: `sim/ttram/tb_ttram.v` (contention model) and the `prog_bus.s` ST bus trace being **byte-identical**
with TT on and off (TTRAM_DESIGN §8b).

### Options with estimated cost (clk_cpu = 16 MHz; 68030 reference: async 3 clk, STERM 2 clk, burst line 2-1-1-1 = 5 clk)
| Option | Change | Read per long | 16-byte line | ST risk | Effort |
|---|---|---|---|---|---|
| 0. Today | — | about 6.5–7.5 clk | about 26 clk (4 single cycles) | none | — |
| A. More TT start points at 32 MHz (CPU-half free while the 030 waits on TT; TTRAM_DESIGN §6c) | start at g2–g5 when no ST CPU/DMA/blitter request is pending | about 5.5–6 | about 22–24 | low (needs a "bridge idle, no BR/BGACK" signal) | small |
| A'. Restore an early read ack safely (data valid by the 030's latch edge, the [C5] lesson) | timing-proven early DSACK | −1.5 clk | −6 | none to ST | small, but needs care (C5 crash) |
| B. SDRAM at 64 MHz, ST replayed at the same times | TT sequence 5 clk64 (78 ns); 2 TT starts per 250 ns; grid wait halves | about 4–4.5 | about 16–18 | medium (rewrite the state machine; CL2 at 64 MHz is fine) | medium |
| B+C. 64 MHz + STERM (sync 32-bit, 2-clock minimum) | bridge drives STERM when the data is ready; still waits for a TT slot | about 3–4 (2 clk plus slot wait) | about 12–14 | medium | medium (core STERM path exists: `bus_interface:709`; needs CBACK/STERM pins wired in the bridge) |
| B+C+D. 64 MHz + STERM + burst line fill (CBREQ/CBACK; IBE/DBE) | 8 READ commands back to back at BL1 (no mode change, ST keeps BL1), 1 ACT, CL2: 1+1+2+8 = 12 clk64 = 187 ns, fits the free about 6-clk32 (187 ns) window **exactly**: no margin | first long about 3–4, then 1 each | **about 6–8 clk** | medium-high (window is tight, refresh and ST-write turnaround) | large |
| E. SDRAM at 96–100 MHz + C + D | line burst about 120 ns; a TT slot can also open in the video half without waiting for g2 | about 2–3 | **about 5–6 (≈ real 68030)** | higher (pin timing, two chips on one bus) | large |
| ✗ Burst at 32 MHz | 12 clk32 > 6 free clk32 per slot | — | — | **would steal ST slots: not allowed** | — |

Notes:
- The 68030 burst needs a 32-bit port and CBACK. It works with DSACK or STERM; 2-1-1-1 needs STERM. Without burst, STERM alone
  still halves the minimum cycle. The core's burst side is **not implemented** (CBREQn tied off, `wf68k30L_top.vhd:1111`;
  see CACHE_AUDIT.md), so option D also needs core work and simulation against the MC68030UM burst timing.
- Keeping rows open (no auto-precharge) between TT accesses would save the ACT on sequential reads. But it must precharge
  before every g0 refresh, so its gain is small next to B.
- A Falcon target has a 16-bit ST bus and no burst. Options C, D and E are TT/fast-RAM speed work and don't change
  ST/Falcon-side timing.

## 3. Recommended order
1. Measure first (CACHE_AUDIT.md §measurement, method B: loop timing from TT-RAM with caches on/off and I/D only). That shows
   how much of FrontBench is miss latency.
2. Option A (small, ST-safe), plus a carefully proven A', on the existing 32 MHz grid.
3. PLL feasibility check (960 MHz VCO), then option B in simulation with the byte-identical ST trace as the gate.
4. STERM (C), then burst (D) together with the core's CBREQ/CBACK work.

## 4. Gaps / not verified
- The SDRAM speed grade on the Tang SDRAM X2 module.
- The tt20 timing report (SDRAM pin and clk32 paths): linserver wasn't reachable from the box (no ssh client).
- The GSTMCU refresh interval in clocks (not re-derived).
- The PLL VCO/divider options on the GW5AST-138 for a 960 MHz VCO with the existing outputs.
- All cycle numbers above are derived from the RTL, plus the older simulation in TTRAM_DESIGN §6. They should be confirmed
  with a cycle counter or a bench run on the current (C5/C8/C10) tree.

## Update 2026-10-22: chip speed grade confirmed
David photographed the module: both chips are **W9825G6KH-6** (date code 2541H). Rated 133 MHz at CL2, 166 MHz at CL3. The chip speed is not the limit; Gowin I/O timing and the shared two-chip bus are.
