# cpu030: WF68K30L (68030) in place of fx68k (first integration, Atarist_030_wip)

Status: first integration test, **not yet run on hardware**. No add-ons (no
TT-RAM, IDE, SPI or autoconfig): the 68030 simply replaces the 68000 on the ST
bus. CPU and chipset run at stock speed: the 030 is clocked at 8 MHz, locked to
the ST bus.

Switching back to fx68k: comment out `` `define CPU_030 `` at the top of
`atarist/atarist.v`. The fx68k files stay in the build. The `clk_cpu` port is
then unused.

## Files

| File | Origin / licence |
|---|---|
| `wf68k30L_*.vhd` (9 files) | WF68K30L IP core, (C) Wolfgang Foerster / Inventronik, CERN OHL 1.2. Unmodified copies of `rigsdram/src/wf68k30L_*.vhd` at commit 73ea60b (the audited core with the rigsdram fixes); byte-identical, sha256-checked. |
| `cpu030_st_bridge.v` | New for FalconFPGA. GPL-2.0-only, modelled on TerribleFire's TF534 (C) Stephen J. Leary: `rtl/bus_top.v`, `arb.v`, `m6800.v`, `bus_delay.v`, ATARI build. |
| `LICENSE-GPL2-TF534` | GPL v2 text, copied from the TF534 source tree. |
| `sim/` | Test benches, the test program and scripts (no ROMs, netlists or vvp files). |

Licence note: the bridge is GPL-2-only (as TF534), while fx68k and MiSTeryNano
are GPL-3. Combining GPL-2-only with GPL-3 code in one bitstream is a licence
compatibility question for the project owner to decide.

## Design

The bridge (`cpu030_st_bridge`) has fx68k's port names, plus `clk_cpu`.

### CPU domain (`clk_cpu`, both edges used by the core)

- **Request capture.** On the first rising `clk_cpu` edge that sees ASn low,
  the bridge latches A23:0, SIZE, RW, FC and D31:16 and toggles `req_t`. For the
  030 this is the S1/S2 boundary. `c_open` stays high until a rising edge sees
  ASn high (S5 or idle).
- **Termination gating.** DSACKn, AVECn and BERRn are only driven while `c_open`
  is high and the clk_32 tag equals `req_t`. So a termination can never reach
  the next cycle, whatever the clock ratio.
- **Reset.** RESET_INn and HALT_INn are held low together for 128 clk_cpu
  cycles after the ST reset or power-up ends (the core needs at least 16).
  RESET_OUT (the RESET instruction) goes out as `oRESETn`, like fx68k's
  (peripheral reset), and is not fed back into the CPU.
- **Arbitration pins.** STERMn, BRn and BGACKn on the core are tied high.

### ST domain (`clk_32`)

- **Handshake in.** `req_t` passes through a SYNC_STAGES (2) synchroniser.
- **One 68000 bus cycle per request,** with fx68k's phase timing on
  mhz8_en1/en2:
  - The phases step IDLE, S0, S2, S4 (with wait states), S6 on en1.
  - AS and read UDS/LDS go low leaving S0, and write UDS/LDS go low leaving S2.
  - DTACK and BERR are sampled on en2; VPA, BR and BGACK on en1.
  - AS and DS go high at S6 en2, where the data is latched.
- **E clock and VPA cycles.** E is generated like on a 68000: 10 en2 periods,
  6 low and 4 high. VMA is asserted on VPA, and a VPA cycle ends at the E
  falling edge. This covers the ACIAs and autovectored IACK.
- **Bus sizing.** The bus is always answered as a 16-bit port (DSACKn=01).
  - UDS is active when A0 = 0. LDS is active when A0 = 1 or SIZE is not byte
    (TF534's equations).
  - The 030 splits longs and misaligned accesses into several cycles by itself.
  - Write data is D31:16, and the 030 already duplicates the odd byte onto
    D23:16. Read data goes to D31:16 (and is mirrored on D15:0).
- **Addressing.** Only A23:1 is decoded (A31:24 ignored), so the 24-bit
  aliasing matches a real ST.
- **CPU space (FC=7).**
  - A19:16=F is IACK and runs a real ST IACK cycle: the MFP answers with DTACK
    and a vector on D7:0, and the MCU answers VBL/HBL with VPA, which the
    bridge turns into AVECn.
  - Any other CPU-space cycle (breakpoint, coprocessor, MMU) gets BERR at once,
    without an ST cycle.
- **BR/BG/BGACK.** These work like the 68000:
  - BG changes on en1, and no grant is given while a cycle is in S0 or while
    the 030 asserts RMCn.
  - The CPU starts no new cycle while BR or BGACK is asserted.
- **Termination back to the 030.** The data and the termination (DSACK, AVEC
  or BERR) are registered at S6 en2, together with the request tag.

### Clocking

`clk_cpu030` is PLL `pll_hdmi` CLKOUT5 = VCO 800 MHz / 100 = 8 MHz. That is the
same VCO as clk32 (/25) at phase 0, so the two clocks are related, and the
SDC has it as a generated clock in the core clock group. PnR moved
`ds2_p1/clk_spi` (DualShock SPI, slow) to a long-wire clock to keep 8/8
primary clocks.

### Faster CPU clock later ("accelerated ST")

Because of the request/acknowledge handshake, the ST side does not depend on
the CPU clock. For a faster clock that stays locked to the PLL, only ODIV5 and
the SDC line change. For a truly asynchronous CPU clock:
- register the tag and termination through a 2-flop synchroniser in the
  clk_cpu domain before the gating (currently the core samples them directly
  with its own falling-edge flops);
- keep SYNC_STAGES >= 2.

## Known limitations of this first version

- Every 030 bus cycle costs about 1.3 to 1.5 us on the 8 MHz ST bus (a 68000
  needs 0.5 us). The 030 at 8 MHz with no cache is therefore slower than the
  68000 for bus-bound code. Raising clk_cpu reduces the CPU-side overhead.
- Read-modify-write (TAS/CAS): grants are blocked while RMCn is low, but the
  ST-side AS is released between the read and the write.
- The core has no MMU, FPU or caches. All $Fxxx opcodes take a Line-F trap.
  TOS 3.x/4.x (which use PMOVE) will not work; EmuTOS or TOS 1.04 are the
  targets.
- There is no address error on odd word accesses: the 030 does misaligned
  accesses. ST software that relies on 68000 address errors, or on 68000
  stack frames, behaves differently.
