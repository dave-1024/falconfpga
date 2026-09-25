// ============================================================================
// ae350_falcon_top.v -- Tang Console 138K: FalconFPGA Tier C
//
// REV 11b (2026-07-24): arbitration + lane fix after the REV11 silicon
//   wedge (slot froze at {MAGIC,0,0,.}, hz200=0, EmuTOS hung pre-splash;
//   isolated by REV10-revert). Three RTL changes, all Icarus-proven with
//   a new random-wait/lane-rule bench (tb_mux_atomic.v) that FAILS the
//   REV11 design four different ways and PASSES this one:
//   * falcon_ahb_mux: burst-atomic grant (no mid-burst release), parked
//     master sees ready=0 (never forced-1), outstanding-data tear guard.
//   * falcon_timebase_ahb: grant-gated (req/gnt, cannot free-run), slot
//     re-laid on EVEN word addresses only per the measured dead upper
//     lane (+0 MAGIC, +8 t200, +16 tvbl, +24 cyc50), MAGIC value bumped
//     to 7B10C0D2 so old-layout firmware (m10/m10b/m11b) cleanly falls
//     back to mcycle on this bitstream; m10c/m11c adopt the new layout.
//     Whole-burst watchdog (512 < HID's 1023) + err_count.
//   * top: tb_gnt / tb_err_count wiring below.
// REV 11 (2026-07-23): m10 hardware timebase (falcon_timebase_ahb +
//   falcon_ahb_mux on the Extended AHB Master port, HID strict priority)
//   PLUS SD REMERGE. The timebase branch predated REV10, so this file had
//   lost the TF-slot SPI ports (REV10, silicon-proven under SD Stage A /
//   m9f / m9g). Re-applied here from the REV10 contract: LED/KEY narrowed
//   to [0:0], four SD SPI ports added, 6-bit GPIO concat
//   {SD_DAT3,SD_DAT0,KEY,SD_CMD,SD_CLK,LED}, SD_DAT1/SD_DAT2 pads present
//   and z-driven (pull-up-only). Bit order cross-checked against TWO
//   independent silicon-proven sources: sd_probe.c G_* defines
//   (LED0=0,SCLK=1,MOSI=2,KEY0=3,MISO=4,CSN=5) and the ae350_stage0.cst
//   REV10 header comment. Everything else byte-identical to the
//   Icarus-verified m10 top (md5 edee9c92df01ea517451f065f2a15052).
// REV 9 (2026-07-16): M8A experiment -- mailbox relocated to 0x04F00000
//   (proven lane5 address class; 68k 0xF00000 is IO-shadowed so this DDR3
//   is free). Param-only; falcon_video v6.1 logic unchanged, no regate.
//   MUST flash with falcon_m8a.bin -- either half stale fails safe to bars
//   (addresses differ), status strip still renders.
// REV 8 (2026-07-16): Stage 3 -- falcon_video v6: mailbox v3 (277 words at
//   0x03FF_F800, MAGIC 0xFA1C0DE6, 256-colour Falcon palette + height field).
//   Parameter-only change in this file; no IP touched -> no regen, no
//   constraint audit, no bisection build required.
// REV 6 (2026-07-14): HID event delivery moved from the shared-DDR3 write
// lane (lane4) to the AE350's EXTENDED AHB MASTER port. Reason: lane4 is
// non-functional on this IP -- wr_done never arrives, even example-verbatim,
// isolated, and under exclusive bus grant (falcon_wprobe returned zero
// signatures in every candidate address zone, 2026-07-14). The AHB port is
// the documented route for a fabric master into the SoC address map, and it
// reaches DDR3 through the same Bus Matrix the CPU has been using all along
// -- so AHB traffic concurrent with lane5 scanout bursts is already proven
// (the A25 has done it continuously since Tier C).
//   - lane4: TIED OFF again (dead port, no consumer)
//   - lane5: unchanged, still feeds the scanout
//   - falcon_video.v: UNCHANGED from v5 (hardware-verified); its lane4
//     arbiter simply never grants, because lane4_req is tied low.
// REV 3 (2026-07-12): m6 fabric USB HID. Two usb_hid_host instances on the
// Console's USB2 host ports (pins from the working NESTang Console port),
// 12MHz from a new gowin_pll_usb, events written via lane4 (its first real
// job) to the DDR3 ring at 0x03FE0000 for falcon_m6.c. Lane4 tie-offs gone.
// REV 2 (2026-07-11): shared-DDR3 lanes reconfigured 64 -> 32-bit after the
// 64-bit read lane's upper half was measured broken on hardware (fb_base
// latched address-independent garbage while magic [31:0] validated).
// 32-bit is the width Gowin's own DDR3_Shared example validates.
// = the verified bisection top (ae350_stage0_top rev 2026-07-11) with the
// lane5 tie-offs replaced by falcon_video, plus the Tier B HDMI output path
// (PLL 126MHz -> CLKDIV/5 -> 25.2MHz pixel, TMDS -> OSER10 -> ELVDS_OBUF).
// Everything AE350/DDR3/reset-chain is UNCHANGED from the bisection build
// that booted EmuTOS identically to pre-regeneration. Lane4 stays tied off.
//
// Instance names u_gowin_pll_ae350 / u_gowin_pll_ddr3 / u_RiscV_AE350_SOC_Top
// are preserved EXACTLY: the cst INS_LOC placement paths depend on them.
//
// Expected behaviour:
//   - power-up -> colour bars (video path alive, mailbox not yet validated)
//   - m4 firmware boots EmuTOS, publishes mailbox, CCTL-flushes at ~60Hz
//   - bars -> live truecolor desktop, drawn by the 68030 out of DDR3
//   Bars persisting after firmware boot = mailbox contract mismatch
//   (MBOX_ADDR/MAGIC parameters vs falcon_m4.c) or lane address semantics
//   differ from byte addressing -- both diagnosable, neither hangs anything.
// ============================================================================

module falcon_top
(
    input CLK,                   // V22, 50 MHz from SOM oscillator
    input RSTN,                  // AA13, dock S1 button, active-low

    inout [0:0] LED,             // LED[0]=V13 (green; GPIO[0]; m9f safe-to-power-off contract)
    inout [0:0] KEY,             // KEY[0]=AB13 (dock S2; GPIO[3])

    // TF (microSD) slot, SPI mode -- REV10 pads (old LED[1]/LED[2]/KEY[1]/
    // KEY[2] diagnostics re-LOC'd). GPIO map per sd_probe.c + cst:
    //   GPIO[1]=SD_CLK, GPIO[2]=SD_CMD(MOSI), GPIO[4]=SD_DAT0(MISO),
    //   GPIO[5]=SD_DAT3(CS_n). DAT1/DAT2 pull-up-only, unused in SPI mode.
    inout SD_CLK,                // V15
    inout SD_CMD,                // Y16   MOSI
    inout SD_DAT0,               // AA15  MISO
    inout SD_DAT3,               // W15   CS_n
    inout SD_DAT1,               // AB15  pull-up only
    inout SD_DAT2,               // W14   pull-up only

    output UART2_TXD,            // U15
    input  UART2_RXD,            // V14

    inout FLASH_SPI_CSN,         // T19
    inout FLASH_SPI_MISO,        // R22
    inout FLASH_SPI_MOSI,        // P22
    inout FLASH_SPI_CLK,         // L12
    inout FLASH_SPI_HOLDN,       // R21
    inout FLASH_SPI_WPN,         // P21

    output [2:0]  DDR3_BANK,
    output DDR3_CS_N,
    output DDR3_RAS_N,
    output DDR3_CAS_N,
    output DDR3_WE_N,
    output DDR3_CK,
    output DDR3_CK_N,
    output DDR3_CKE,
    output DDR3_RESET_N,
    output DDR3_ODT,
    output [13:0] DDR3_ADDR,
    output [1:0]  DDR3_DM,
    inout  [15:0] DDR3_DQ,
    inout  [1:0]  DDR3_DQS,
    inout  [1:0]  DDR3_DQS_N,

    input  TCK_IN,               // E21
    input  TMS_IN,               // E22
    input  TRST_IN,              // F19
    input  TDI_IN,               // D22
    output TDO_OUT,              // D21

    // USB2 host ports (NESTang Console pin map; board carries pulldowns)
    inout  usb1_dp,              // H13
    inout  usb1_dn,              // G13
    inout  usb2_dp,              // M15
    inout  usb2_dn,              // M16

    // HDMI (Tier B verified pins)
    output tmds_clk_p,           // G15
    output tmds_clk_n,           // G16
    output [2:0] tmds_d_p,       // J14 J15 K17
    output [2:0] tmds_d_n,       // H14 H15 J17

    // --- REV12: onboard audio -- MAX98357A I2S DAC+amp (BANK5) ---
    output i2s_bclk,             // Y17
    output i2s_lrck,             // AB17
    output i2s_din,              // AA16
    output pa_en                 // MAX98357A SD_MODE (amp on); confirm ball
);

// SD_DAT1/SD_DAT2: pads must exist for the cst (AB15/W14, PULL_MODE=UP)
// but carry no signal in SPI mode -- explicitly high-Z so only the
// pull-ups act and the pads cannot be swept.
assign SD_DAT1 = 1'bz;
assign SD_DAT2 = 1'bz;

wire CORE_CLK;
wire DDR_CLK;
wire AHB_CLK;
wire APB_CLK;
wire RTC_CLK;

wire DDR3_MEMORY_CLK;
wire DDR3_CLK_IN;
wire DDR3_RW_CLK;                // 50 MHz shared-DDR3 lane clock
wire DDR3_LOCK;
wire DDR3_STOP;

// --- PLL 1: AE350 system clocks (PLL_R[0] via cst -- mandatory). ---
gowin_pll_ae350 u_gowin_pll_ae350 (
    .clkin(CLK),
    .init_clk(CLK),
    .clkout0(DDR_CLK),           // 50 MHz
    .clkout1(CORE_CLK),          // 800 MHz
    .clkout2(AHB_CLK),           // 50 MHz
    .clkout3(APB_CLK),           // 50 MHz
    .clkout4(RTC_CLK)            // 10 MHz
);

// --- PLL 2: DDR3 clocks (PLL_L[0] via cst). ---
gowin_pll_ddr3 u_gowin_pll_ddr3 (
    .clkin(CLK),
    .init_clk(CLK),
    .enclk0(1'b1),
    .enclk1(1'b1),
    .enclk2(DDR3_STOP),
    .clkout0(DDR3_CLK_IN),       // 50 MHz
    .clkout1(DDR3_RW_CLK),       // 50 MHz -> clk_lane4/clk_lane5 + falcon_video
    .clkout2(DDR3_MEMORY_CLK),   // 200 MHz
    .lock(DDR3_LOCK)
);

// --- PLL 3: HDMI serial clock (Tier B recipe: 50 -> 126 MHz). ---
//     Regenerate gowin_pll_hdmi inside THIS project (IP Core Generator ->
//     Hard Module -> Clock -> PLL, CLKIN 50, one CLKOUT 126, module name
//     exactly gowin_pll_hdmi). Version-C primitive has init_clk.
wire hclk5;
gowin_pll_hdmi u_gowin_pll_hdmi (
    .clkin(CLK),
    .init_clk(CLK),
    .clkout0(hclk5)               // 126 MHz
);

// --- PLL 4: USB HID clock. NEW IP: IP Core Generator -> PLL, CLKIN 50,
//     one CLKOUT = 12 MHz, module name exactly gowin_pll_usb. VERIFY the
//     generated _tmp.v port names (clkout0 vs clkout) before building --
//     same lesson as the HDMI PLL.
wire clk12;
gowin_pll_usb u_gowin_pll_usb (
    .clkin(CLK),
    .init_clk(CLK),
    .clkout0(clk12)              // 12 MHz
);

wire clk_pixel;
CLKDIV #(.DIV_MODE(5)) u_div5 (
    .HCLKIN(hclk5), .CLKOUT(clk_pixel), .RESETN(1'b1)
);

// pixel-domain power-on reset (Tier B pattern)
reg [7:0] por = 8'd0;
always @(posedge clk_pixel) if (!por[7]) por <= por + 8'd1;
wire pix_rst = ~por[7];

// --- Reset sequencing (reference-exact, unchanged). ---
wire ae350_rstn;
wire ddr3_rstn;
wire ddr3_init_completed;

key_debounce u_key_debounce_ddr3
(
    .out(ddr3_rstn),
    .in(RSTN),
    .clk(CLK),
    .rstn(1'b1)
);

key_debounce u_key_debounce_ae350
(
    .out(ae350_rstn),
    .in(ddr3_init_completed),
    .clk(CLK),
    .rstn(1'b1)
);

// --- falcon_hid_ahb: USB HID -> DDR3 event ring over the Extended AHB
//     Master port (fabric = master, SoC = slave). Sim-verified against a
//     spec-derived AHB slave model with random wait states; mutation-proven
//     (data-hold, transfer size, and record-ordering faults all caught).
// Shared Extended-AHB port (to SoC). Driven by the mux.
wire [31:0] extm_haddr;
wire [2:0]  extm_hburst, extm_hsize;
wire [3:0]  extm_hprot;
wire        extm_hsel, extm_hwrite;
wire [1:0]  extm_htrans;
wire [63:0] extm_hwdata, extm_hrdata;
wire        extm_hreadyout, extm_hresp;
wire [7:0]  hid_err_count;               // AHB errors + watchdog aborts

// HID master (priority) -- its own signal set, muxed below.
wire [31:0] hid_haddr;   wire [2:0] hid_hburst, hid_hsize;
wire [3:0]  hid_hprot;   wire hid_hsel, hid_hwrite; wire [1:0] hid_htrans;
wire [63:0] hid_hwdata;  wire hid_hreadyout, hid_hresp;
// Timebase master -- its own signal set.
// REV13: tb_* is now the SUB-MUX's upstream side (so the falcon_ahb_mux
// instantiation below stays byte-identical). The timebase itself moves to
// tba_* (sub-mux child A, priority); the audio fetch engine is aud_*
// (child B). falcon_ahb_mux and falcon_timebase_ahb are both unmodified.
wire [31:0] tb_haddr;    wire [2:0] tb_hburst, tb_hsize;
wire [3:0]  tb_hprot;    wire tb_hsel, tb_hwrite; wire [1:0] tb_htrans;
wire [63:0] tb_hwdata;   wire tb_hreadyout, tb_hresp; wire tb_busy;
wire        tb_gnt;                       // REV11b: mux grant to publisher
wire [7:0]  tb_err_count;                 // REV11b: publisher watchdog aborts
// REV13 child A: timebase <-> sub-mux
wire [31:0] tba_haddr;   wire [2:0] tba_hburst, tba_hsize;
wire [3:0]  tba_hprot;   wire tba_hsel, tba_hwrite; wire [1:0] tba_htrans;
wire [63:0] tba_hwdata;  wire tba_hreadyout, tba_hresp;
wire        tba_busy, tba_gnt;
// REV13 child B: audio fetch engine <-> sub-mux
wire [31:0] aud_haddr;   wire [2:0] aud_hburst, aud_hsize;
wire [3:0]  aud_hprot;   wire aud_hsel, aud_hwrite; wire [1:0] aud_htrans;
wire [63:0] aud_hwdata;  wire aud_hreadyout, aud_hresp;
wire        aud_busy, aud_gnt;
wire [7:0]  aud_err_count;
wire signed [15:0] aud_pcm;               // fetched sample -> I2S
wire        aud_magic_ok;                 // ring validated -> tone off
wire        samp_stb;                     // I2S frame tick -> fetch engine

// falcon_video's lane4 arbiter is inert in this build: nothing requests it.
wire lane4_gnt;

// AHB reset: the SoC's own reset chain gates the CPU on DDR3 init, and the
// HID master must not issue transactions before the memory system is up.
wire extm_hresetn = ae350_rstn & ddr3_init_completed;

falcon_hid_ahb u_falcon_hid (
    .clk12(clk12),
    .usb1_dp(usb1_dp), .usb1_dn(usb1_dn),
    .usb2_dp(usb2_dp), .usb2_dn(usb2_dn),
    .hclk(AHB_CLK), .hresetn(extm_hresetn),
    .haddr(hid_haddr), .hburst(hid_hburst), .hprot(hid_hprot),
    .hsel(hid_hsel), .hsize(hid_hsize), .htrans(hid_htrans),
    .hwdata(hid_hwdata), .hwrite(hid_hwrite),
    .hrdata(extm_hrdata), .hreadyout(hid_hreadyout), .hresp(hid_hresp),
    .err_count(hid_err_count)
);

// --- M10 timebase publisher (own AHB master, muxed with HID) ---
falcon_timebase_ahb #(
    .SLOT_BASE(32'h04F0_0600), .TB_MAGIC(32'h7B10_C0D2),  // v2 layout
    .PERIOD_200(32'd250000),   // 50e6/200  = 0.0 ppm
    .PERIOD_VBL(32'd833333),   // 50e6/60   = +0.4 ppm
    .PUBLISH_DIV(32'd50000)    // publish snapshot @1 kHz
) u_timebase (
    .hclk(AHB_CLK), .hresetn(extm_hresetn),
    .cfg_we(1'b0), .cfg_sel(1'b0), .cfg_val(32'd0),   // runtime trim unused
    .haddr(tba_haddr), .hburst(tba_hburst), .hprot(tba_hprot),
    .hsel(tba_hsel), .hsize(tba_hsize), .htrans(tba_htrans),
    .hwdata(tba_hwdata), .hwrite(tba_hwrite),
    .hreadyout(tba_hreadyout), .hresp(tba_hresp),
    .gnt(tba_gnt), .busy(tba_busy), .err_count(tb_err_count)
);

// --- REV13: audio sample fetch engine (first fabric AHB READ master).
//     Magic-gated: until m13 firmware plants the ring MAGIC at
//     0x04F00800, aud_magic_ok stays low and the I2S block keeps the
//     test tone. Ring contract + sim evidence: AUDIO_STEP1_NOTES.md.
falcon_audio_ahb u_audio_fetch (
    .hclk(AHB_CLK), .hresetn(extm_hresetn),
    .haddr(aud_haddr), .hburst(aud_hburst), .hprot(aud_hprot),
    .hsel(aud_hsel), .hsize(aud_hsize), .htrans(aud_htrans),
    .hwdata(aud_hwdata), .hwrite(aud_hwrite),
    .hrdata(extm_hrdata), .hreadyout(aud_hreadyout), .hresp(aud_hresp),
    .gnt(aud_gnt), .busy(aud_busy), .err_count(aud_err_count),
    .samp_stb(samp_stb), .pcm(aud_pcm), .magic_ok(aud_magic_ok)
);

// --- REV13: 2:1 burst-atomic sub-mux -- timebase (priority) + audio
//     share the untouched falcon_ahb_mux t-port. One child job per
//     upstream grant; HID stall bound unchanged (<= ~516 < 1023).
falcon_audio_submux u_audio_submux (
    .hclk(AHB_CLK), .hresetn(extm_hresetn),
    .a_haddr(tba_haddr), .a_hburst(tba_hburst), .a_hprot(tba_hprot),
    .a_hsel(tba_hsel), .a_hsize(tba_hsize), .a_htrans(tba_htrans),
    .a_hwdata(tba_hwdata), .a_hwrite(tba_hwrite),
    .a_busy(tba_busy), .a_gnt(tba_gnt),
    .a_hreadyout(tba_hreadyout), .a_hresp(tba_hresp),
    .b_haddr(aud_haddr), .b_hburst(aud_hburst), .b_hprot(aud_hprot),
    .b_hsel(aud_hsel), .b_hsize(aud_hsize), .b_htrans(aud_htrans),
    .b_hwdata(aud_hwdata), .b_hwrite(aud_hwrite),
    .b_busy(aud_busy), .b_gnt(aud_gnt),
    .b_hreadyout(aud_hreadyout), .b_hresp(aud_hresp),
    .t_haddr(tb_haddr), .t_hburst(tb_hburst), .t_hprot(tb_hprot),
    .t_hsel(tb_hsel), .t_hsize(tb_hsize), .t_htrans(tb_htrans),
    .t_hwdata(tb_hwdata), .t_hwrite(tb_hwrite),
    .t_busy(tb_busy), .t_gnt(tb_gnt),
    .t_hreadyout(tb_hreadyout), .t_hresp(tb_hresp)
);

// --- AHB write-master mux: HID priority, timebase fills idle gaps ---
// REV13: the t-port is now fed by falcon_audio_submux (timebase +
// audio fetch engine); this instantiation is byte-identical to REV11b.
falcon_ahb_mux u_ahb_mux (
    .hclk(AHB_CLK), .hresetn(extm_hresetn),
    .h_haddr(hid_haddr), .h_hburst(hid_hburst), .h_hprot(hid_hprot),
    .h_hsel(hid_hsel), .h_hsize(hid_hsize), .h_htrans(hid_htrans),
    .h_hwdata(hid_hwdata), .h_hwrite(hid_hwrite),
    .t_haddr(tb_haddr), .t_hburst(tb_hburst), .t_hprot(tb_hprot),
    .t_hsel(tb_hsel), .t_hsize(tb_hsize), .t_htrans(tb_htrans),
    .t_hwdata(tb_hwdata), .t_hwrite(tb_hwrite),
    .t_busy(tb_busy), .t_gnt(tb_gnt),
    .haddr(extm_haddr), .hburst(extm_hburst), .hprot(extm_hprot),
    .hsel(extm_hsel), .hsize(extm_hsize), .htrans(extm_htrans),
    .hwdata(extm_hwdata), .hwrite(extm_hwrite),
    .hreadyout(extm_hreadyout), .hresp(extm_hresp),
    .h_hreadyout(hid_hreadyout), .h_hresp(hid_hresp),
    .t_hreadyout(tb_hreadyout), .t_hresp(tb_hresp)
);

// --- falcon_video: lane5 scanout (sim-verified 307200/307200) ---
wire [31:0] addr_lane5;
wire        rd_go_lane5, rd_en_lane5;
wire [7:0]  burstcount_lane5;
wire        rd_rdy_lane5, rd_valid_lane5;
wire [31:0] rd_data_lane5;

wire de, hs, vs, magic_ok;
wire [7:0] vr, vg, vb;

falcon_video #(
    .MBOX_ADDR(32'h04F0_0000),   // MUST match falcon_m8a.c (M8A: proven region)
    .MAGIC    (32'hFA1C_0DE6)    // MUST match falcon_m8a.c (v3, unchanged)
) u_falcon_video (
    .clk_pixel(clk_pixel), .rst(pix_rst),
    .clk_rw(DDR3_RW_CLK), .ddr3_init(ddr3_init_completed),
    .addr_lane5(addr_lane5), .rd_go_lane5(rd_go_lane5),
    .rd_en_lane5(rd_en_lane5), .burstcount_lane5(burstcount_lane5),
    .rd_rdy_lane5(rd_rdy_lane5), .rd_valid_lane5(rd_valid_lane5),
    .rd_data_lane5(rd_data_lane5),
    .de(de), .hsync(hs), .vsync(vs), .vr(vr), .vg(vg), .vb(vb),
    .magic_ok_pix(magic_ok),
    .lane4_req(1'b0), .lane4_gnt(lane4_gnt)   // arbiter present but inert
);

// --- TMDS encode + serialise (Tier B verified path, unchanged) ---
wire [9:0] tmds_ch0, tmds_ch1, tmds_ch2;
tmds_encoder enc_b (.clk(clk_pixel), .de(de), .ctrl({vs,hs}), .din(vb), .dout(tmds_ch0));
tmds_encoder enc_g (.clk(clk_pixel), .de(de), .ctrl(2'b00),   .din(vg), .dout(tmds_ch1));
tmds_encoder enc_r (.clk(clk_pixel), .de(de), .ctrl(2'b00),   .din(vr), .dout(tmds_ch2));

wire [2:0] ser_out;
OSER10 ser0 (.Q(ser_out[0]),
    .D0(tmds_ch0[0]), .D1(tmds_ch0[1]), .D2(tmds_ch0[2]), .D3(tmds_ch0[3]),
    .D4(tmds_ch0[4]), .D5(tmds_ch0[5]), .D6(tmds_ch0[6]), .D7(tmds_ch0[7]),
    .D8(tmds_ch0[8]), .D9(tmds_ch0[9]), .PCLK(clk_pixel), .FCLK(hclk5), .RESET(pix_rst));
OSER10 ser1 (.Q(ser_out[1]),
    .D0(tmds_ch1[0]), .D1(tmds_ch1[1]), .D2(tmds_ch1[2]), .D3(tmds_ch1[3]),
    .D4(tmds_ch1[4]), .D5(tmds_ch1[5]), .D6(tmds_ch1[6]), .D7(tmds_ch1[7]),
    .D8(tmds_ch1[8]), .D9(tmds_ch1[9]), .PCLK(clk_pixel), .FCLK(hclk5), .RESET(pix_rst));
OSER10 ser2 (.Q(ser_out[2]),
    .D0(tmds_ch2[0]), .D1(tmds_ch2[1]), .D2(tmds_ch2[2]), .D3(tmds_ch2[3]),
    .D4(tmds_ch2[4]), .D5(tmds_ch2[5]), .D6(tmds_ch2[6]), .D7(tmds_ch2[7]),
    .D8(tmds_ch2[8]), .D9(tmds_ch2[9]), .PCLK(clk_pixel), .FCLK(hclk5), .RESET(pix_rst));

ELVDS_OBUF tmds_bufds [3:0] (
    .I({clk_pixel, ser_out}),
    .O({tmds_clk_p, tmds_d_p}),
    .OB({tmds_clk_n, tmds_d_n})
);

// --- The AE350 SOC: identical to the bisection build except lane5 lives. ---
RiscV_AE350_SOC_Top u_RiscV_AE350_SOC_Top
(
    .FLASH_SPI_CSN(FLASH_SPI_CSN),
    .FLASH_SPI_MISO(FLASH_SPI_MISO),
    .FLASH_SPI_MOSI(FLASH_SPI_MOSI),
    .FLASH_SPI_CLK(FLASH_SPI_CLK),
    .FLASH_SPI_HOLDN(FLASH_SPI_HOLDN),
    .FLASH_SPI_WPN(FLASH_SPI_WPN),

    .DDR3_MEMORY_CLK(DDR3_MEMORY_CLK),
    .DDR3_CLK_IN(DDR3_CLK_IN),
    .DDR3_RSTN(ddr3_rstn),
    .DDR3_LOCK(DDR3_LOCK),
    .DDR3_STOP(DDR3_STOP),
    .DDR3_INIT(ddr3_init_completed),
    .DDR3_BANK(DDR3_BANK),
    .DDR3_CS_N(DDR3_CS_N),
    .DDR3_RAS_N(DDR3_RAS_N),
    .DDR3_CAS_N(DDR3_CAS_N),
    .DDR3_WE_N(DDR3_WE_N),
    .DDR3_CK(DDR3_CK),
    .DDR3_CK_N(DDR3_CK_N),
    .DDR3_CKE(DDR3_CKE),
    .DDR3_RESET_N(DDR3_RESET_N),
    .DDR3_ODT(DDR3_ODT),
    .DDR3_ADDR(DDR3_ADDR),
    .DDR3_DM(DDR3_DM),
    .DDR3_DQ(DDR3_DQ),
    .DDR3_DQS(DDR3_DQS),
    .DDR3_DQS_N(DDR3_DQS_N),

    // --- write lane (lane4): TIED OFF. Non-functional on this IP; the
    //     HID ring is written over the Extended AHB Master port instead.
    .clk_lane4(DDR3_RW_CLK),
    .addr_lane4(32'd0),
    .wr_mask_lane4(4'd0),
    .wr_data_lane4(32'd0),
    .wr_en_lane4(1'b0),
    .wr_go_lane4(1'b0),
    .burstcount_lane4(8'd0),
    .wr_wait_lane4(),
    .wr_done_lane4(),

    // --- read lane (lane5): the scanout ---
    .clk_lane5(DDR3_RW_CLK),
    .addr_lane5(addr_lane5),
    .rd_en_lane5(rd_en_lane5),
    .rd_go_lane5(rd_go_lane5),
    .burstcount_lane5(burstcount_lane5),
    .rd_valid_lane5(rd_valid_lane5),
    .rd_data_lane5(rd_data_lane5),
    .rd_rdy_lane5(rd_rdy_lane5),

    // --- Extended AHB Master: fabric is the master, SoC is the slave.
    //     Single master, single slave => HREADY loops back from HREADYOUT.
    .EXTM_HADDR(extm_haddr),
    .EXTM_HBURST(extm_hburst),
    .EXTM_HPROT(extm_hprot),
    .EXTM_HREADY(extm_hreadyout),        // loopback, per AHB-Lite
    .EXTM_HSEL(extm_hsel),
    .EXTM_HSIZE(extm_hsize),
    .EXTM_HTRANS(extm_htrans),
    .EXTM_HWDATA(extm_hwdata),
    .EXTM_HWRITE(extm_hwrite),
    .EXTM_HRDATA(extm_hrdata),
    .EXTM_HREADYOUT(extm_hreadyout),
    .EXTM_HRESP(extm_hresp),

    .TCK_IN(TCK_IN),
    .TMS_IN(TMS_IN),
    .TRST_IN(TRST_IN),
    .TDI_IN(TDI_IN),
    .TDO_OUT(TDO_OUT),
    .TDO_OE(),

    .UART2_TXD(UART2_TXD),
    .UART2_RTSN(),
    .UART2_RXD(UART2_RXD),
    .UART2_CTSN(1'b0),
    .UART2_DCDN(1'b0),
    .UART2_DSRN(1'b0),
    .UART2_RIN(1'b0),
    .UART2_DTRN(),
    .UART2_OUT1N(),
    .UART2_OUT2N(),

    // GPIO[5:0] = {SD_DAT3, SD_DAT0, KEY[0], SD_CMD, SD_CLK, LED[0]}
    //           =  CS_n     MISO     btn     MOSI    SCLK    LED
    // (REV10 contract; must match sd_probe.c / m9f / m9g G_* bit defines)
    .GPIO({SD_DAT3, SD_DAT0, KEY, SD_CMD, SD_CLK, LED}),

    .CORE_CLK(CORE_CLK),
    .DDR_CLK(DDR_CLK),
    .AHB_CLK(AHB_CLK),
    .APB_CLK(APB_CLK),
    .RTC_CLK(RTC_CLK),
    .POR_RSTN(ae350_rstn),
    .HW_RSTN(ae350_rstn)
);

// --- REV12: onboard audio egress (MAX98357A I2S DAC+amp) --------------
//     Self-contained bring-up. Local power-on reset on AHB_CLK (50 MHz,
//     from PLL1, independent of DDR3/AE350) so a correct tone on configure
//     proves pin -> amp -> speaker with NO firmware involved. test_tone=1
//     emits a ~1 kHz sine; for Step 1, set test_tone=0 and drive .pcm from
//     the A25/DMA sample FIFO. Add falcon_audio_i2s.v, i2s_tx.v and
//     sine_lut.hex to the project; add the four pins to the .cst
//     (i2s_bclk=Y17, i2s_lrck=AB17, i2s_din=AA16, pa_en=<confirm>).
reg [7:0] audio_por = 8'd0;
always @(posedge AHB_CLK) if (!audio_por[7]) audio_por <= audio_por + 8'd1;
wire audio_rstn = audio_por[7];

falcon_audio_i2s u_audio (
    .clk(AHB_CLK), .rstn(audio_rstn),
    .en(1'b1),
    .test_tone(~aud_magic_ok),  // REV13: tone until the m13 ring validates;
                                // firmware dead or EXTM reads broken => tone
    .pcm(aud_pcm),
    .samp_stb(samp_stb),        // v2 port: frame tick to the fetch engine
    .i2s_bclk(i2s_bclk), .i2s_lrck(i2s_lrck),
    .i2s_din(i2s_din),   .pa_en(pa_en)
);

endmodule
