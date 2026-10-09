# TF536 / TF534 / ST536: how they drive the ST bus, compared with our F63 bridge

Read-only research, 8 Oct 2026 (evening, BST). Nothing in the repo, on the laptop or on the board was touched.

## Sources

- TF536 RTL (Stephen J. Leary), https://github.com/terriblefire/tf536, commit 31adbc6, tag v2.1.
  - `rtl/clocks.v`, `rtl/main_top.v`, `rtl/bus.v`, `rtl/bus_delay.v`, `rtl/sdram.v`.
  - This is the Amiga A500/CDTV build. Its README sends Atari users to exxos's ST536, and the ST536 CPLD source is not public (only JEDs on the forum and ST536 page).
- TF534/TF530 Atari firmware (S. Leary + Anders Granlund), https://github.com/agranlund/tf534, commit 2f1f5a6.
  - `rtl/bus_top.v`, `rtl/bus_delay.v`, `rtl/fastram.v`, built with `-define ATARI`. Our bridge already follows this design.
- agranlund's TF536 Atari firmware thread (binaries only): https://www.exxosforum.co.uk/forum/viewtopic.php?f=93&t=3442
- ST536 thread (all 75 pages read, no login): https://www.exxosforum.co.uk/forum/viewtopic.php?t=3992
- ST536 product page: https://www.exxosforum.co.uk/atari/last/ST536/index.htm

## 1. CPU clocks

- **TF536:** a 100 MHz oscillator feeds the CPLD, and the CPU runs at 50 MHz (`clocks.v`: `CLK50MI` toggles on `CLK100M`). The SDRAM runs at 100 MHz.
- **Clock switching (the key trick, `clocks.v` + `main_top.v:358-382`):**
  - `SPEED_D <= ~AS30 & ram_decode & GAYLE_IDE & GAYLE_ACCESS | CPUSPACE | ~BGACK_INT | ~RESET` (`main_top.v:367`).
  - While the 030's AS is asserted for a motherboard cycle (anything except fast RAM, IDE or Gayle), the CPU clock becomes the inverted, phase-delayed motherboard clock: `CLK50MI <= ~CLK7M_D[CLOCK_PHASE-1]`.
  - The switch waits for a stable clock level (`can_change`), so it is glitch-free.
  - As soon as AS30 negates, the CPU is back on 50 MHz.
  - So **the CPU computes between bus cycles at 50 MHz, and only the bus cycle itself runs at the 7/8 MHz bus clock, in phase with it.**
- **The thread confirms the Atari TF536 firmware did the same:**
  - exxos, p60985 (start=150): "stock firmware switches to 8mhz a lot".
  - The ST536 page lists "ST536r5A2 ... Clock switching - Only 50MHz on alt-ram (same as original TF536 firmware)".
- **Later ST536 firmware (exxos):** runs the 030 at 50 MHz all the time with an asynchronous DTACK handshake.
  - exxos, p83164 (start=410): "The only time I saw 116% ST-RAM speed was when running the CPU at 50Mhz all the time", but that broke DMA.
- **TF534 Atari:** asynchronous, with the CPU at 25–50 MHz (README: "doesnt work under 25Mhz").
- **Ours:** 16 MHz, locked 2:1 to clk_32, all the time (`cpu030_st_bridge.v:47-55`, `CPU_DIV 2`). The core only closes at about 17 MHz (clk_cpu030 17.035 MHz, `ST_HELPER.md:800`).

## 2. ST bus interface

### TF534 Atari (`agranlund/tf534 rtl/bus_top.v`)

- **Start (`bus_top.v:162-206`):**
  - `AS20DLY` is AS30 delayed by one CPU clock.
  - `CANSTART` needs one falling CLK7M edge since the previous ST AS ended.
  - The ST AS/UDS/LDS (`AS_INT`) are then asserted on the next CLK7M rising edge, with the comment "the 68030 asserts them one half clock early". The S0/S1 half of the 68000 cycle is effectively skipped.
  - Writes assert DS one ST clock later (`bus_top.v:216-221`).
- **Hold:** every ST-side register has `AS30` as an asynchronous preset (`bus_top.v:187-199`, `249-255`, `267-272`).
  - The ST cycle stays open until the 030 ends its own cycle.
  - Data goes straight through the bus buffers (no capture register), so read data is valid whenever the 030 latches it.
- **DTACK to DSACK (`bus_top.v:249-279`, `bus_delay.v`):**
  - DTACK is latched on the CLK falling edge (S4→S5), then passes `DTACK_S6` (rise), `DTACK_S7` (fall), one ripple flip-flop (`DELAYS = 1` under ATARI) and two CPU clocks.
  - That gives `DSACK1` roughly at ST S7 + 40 ns at 50 MHz, after which the 030 latches on its next falling edge.
  - DSACK therefore arrives *later* than ours. They hit the slots because the 030 needs only a few 20 ns clocks to put out its next AS.

### TF536 v2.1 (`terriblefire/tf536 rtl/main_top.v:335-391`)

`bus.v` is no longer instantiated. The motherboard cycle is clocked directly:

- `AS_RESYNC` waits two CLK7M rising edges after the clock switch.
- After that, `AS_D/UDS_D/LDS_D` follow AS30/DS30, sampled at 100 MHz.
- `DTACK_D` follows DTACK at 100 MHz, and `DSACK = {DTACK_D..., 1}`.
- With the CPU running on the bus clock at this point, its DSACK sample and data latch fall on 68000-like edges.

### Bus sizing

- Both cards answer motherboard cycles as a 16-bit port: DSACK1 only, DSACK0 high (`tf534 bus_top.v:345`, `tf536 main_top.v:391`).
- The 030 does its own dynamic bus sizing. A long word is two ST cycles.
- **Ours does the same:** `cpu_dsackn = 2'b01` (`cpu030_st_bridge.v:270`).
- STERM, burst and 32-bit access are only for fast RAM.

### Caches

- The TF536 drives **CIIN low on every access that is not fast RAM** (`tf536 rtl/sdram.v:259` `assign CIIN = ~ACCESS;`, and `tf534 rtl/fastram.v:60`).
- agranlund confirms this, p84495 (start=640): "...to be in sync with the TF536 which asserted CIIN on st-ram access."
- So in David's photo ("CACHE D=ON I=ON, Ran from ST-RAM") the caches could not hold any ST-RAM or ROM code or data. The ~100% RAM/ROM was reached **without cache help**, purely from bus efficiency.
  - Caveat: we don't know exactly which firmware produced that photo. exxos's later ST536 builds experimented with caching ST-RAM, and his ST536 page says some scores went *down* with it.
- **Ours:** `CACHES 0` (`cpu030_st_bridge.v:184`), so we are on the same footing. Caches are not needed to reach ~100%.

## 3. Benchmark figures

| Card | Source | RAM | ROM | Display | CPU | Integer Division | Blitting (no blitter) |
|---|---|---|---|---|---|---|---|
| TF536, GEMBENCH 6.32 | David's photo | 99% | 101% | 103% | 211% | 942% (3.340 s) | 92% |
| ST536 (TF536r3/r5), NemBench 2.1 | exxos p60795 (start=100) | linear 32-bit ST-RAM read 3.919 MB/s (~73%), write 3.919 MB/s (~60%), copy 1.964 MB/s | | | | | |
| ST536, CPU at 50 MHz all the time | exxos p83164 (start=410) | 116% ST-RAM | | | | | |

- The NemBench 3.919 MB/s is **98% of the ST bus maximum** (2 bytes per 500 ns = 4.0 MB/s). On ST-RAM their bus hits almost every slot.
- terriblefire, p61525 (start=250), on why ROM can't go faster: "The 030s dont work any faster than that... they cant latch before S4.. some wont latch reliably until S5/S6."
- **Ours (F63, `ST_HELPER.md:807-822`):** RAM 61%, ROM 69%, Display 37%, CPU 137%, Integer Division 611%, Blitting 13%.

## 4. Why we get 61/69% and they get ~100%: concrete differences

**1. Time between bus cycles (the main cause).**
- **The slot arithmetic:**
  - Our bridge already ends the ST cycle on its own and can begin the next S0 straight after S7 (`cpu030_st_bridge.v:477-487`, `518-540`; F61 live start `298-311`).
  - Back-to-back requests do get 500 ns spacing (`ST_HELPER.md:795`).
  - To catch the next RAM slot, the 030's next AS must be low no more than about 1 clk_cpu (62.5 ns) after it negates AS.
  - The WF68K30L leaves 156–281 ns, which is 2.5–4.5 clocks at 16 MHz (`ST_HELPER.md:797`, `827`).
  - The next S0 then lands about 125–250 ns late, and the MMU holds the cycle until the following slot, so the access costs 1000 ns.
- **How the TF cards avoid it:** they spend those few internal clocks at 50 MHz (20 ns each), so the same 3–4 idle clocks cost 60–80 ns and the next AS is ready in time.
  - TF536 v2.1: clock switching, fast between cycles and bus clock during cycles (`clocks.v`, `main_top.v:367`).
  - TF534: asynchronous 50 MHz.
- A real 68030 also overlaps prefetch with execution, so it rarely has idle clocks. This is the gap that F62/F62b (prefetch) attacks.

**2. CPU clock vs core speed.**
- Their idle clocks are cheap because the CPU clock is 3× ours, but **only between cycles**: the bus cycle itself runs at the bus clock (TF536) or is held to it (TF534).
- Our core only closes timing at about 17 MHz. Running it faster outside ST cycles (Gowin DCS-style clock switching, as the TF536 does) would only help if the core closed timing at 32+ MHz.
- So the levers are:
  - fewer idle clocks in the core (F62b, flush-flag fix);
  - a faster core.

**3. DSACK/data timing: not the cause.**
- Ours gives DSACK at S4 en2 and takes the data at S6 en1 (`cpu030_st_bridge.v:466-471`), which is *earlier* than the TF534 (DSACK after S7, `bus_top.v:249-279`).
- The TF hold-until-AS30-negates scheme isn't needed, because we capture the data.

**4. Start granularity: not the cause.**
- Both start on an 8 MHz edge (TF534: next CLK7M rise with CANSTART, `bus_top.v:165-206`; ours: en1 with the live request path, `cpu030_st_bridge.v:524-540`).

**5. Bus sizing: same on both.**
- 16-bit port with DSACK1 only. A long word is two ST cycles, back to back in the 030.
- Worth checking on our bench: does the WF68K30L put idle clocks *between the two word halves* of a sized long transfer? If it does, every long access loses a slot by itself. This can be measured in `cpu030/sim/st` by binning AS→AS gaps by "second half of the same operand" vs "new operand".

**6. Caches: not a factor.**
- The TF536 has CIIN on all ST-RAM/ROM, so neither side benefits.

**7. No tricks we would have to call hacks.**
- Neither the TF534 nor the TF536 posts writes, merges cycles or pipelines ST cycles.
- The only extra trick is clock switching, which gives fast internal execution with slow, phase-locked bus cycles.

**8. Outlier to look at: Blitting 13% (ours) vs 92% (TF536).**
- With the blitter absent or disabled, this is a CPU/RAM-bound software blit. It sits far below our RAM 61%, so something more than bus slots is costing time there.
- It could be a slow instruction path or an exception-heavy path in the core, such as line-A or a specific addressing mode. It would be worth profiling with the DIAG overlay's row f (program fetch address) during that test.

## 5. Practical targets taken from the reference

- **Pass mark:** NemBench linear ST-RAM read at about 3.9 MB/s, i.e. ≥ 95% of the 4 MB/s bus maximum. That means one word per 500 ns slot, with the core issuing back-to-back AS (≤ 1 idle clk_cpu).
- **Bench metric:** the AS→AS spacing histogram in `cpu030/sim/st`. The goal is for (almost) all RAM cycles to be 500 ns apart, against today's 625/750/875/1000 ns.
