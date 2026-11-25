// falcon_top.sv - FAL_01: Falcon030 v1 toplevel for the Tang Console 138K
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Same board pins and helper (AE350, flash mux, USB, mailbox) as the
// ST console138k top. The ST core (misterynano)
// is replaced by falcon_soc (WF68K30L, SDRAM arbiter, scanout, TOS loader).
// HDMI is 640x480@60 from the scanout through hdmi_640 and its own 25.2 MHz
// PLL (gowin_pll_hdmi). Do not treat pll_160m clkout1 as a pixel clock: it
// is 32 MHz clk32. MFP, ACIAs, IKBD, falcon_fdc and falcon_pbus are in
// falcon_soc; helper HID (and USB host) is in this top. OSD "TOS ROM" is
// sysctrl slot / sd_card image 4 (falcon.xml). Floppy A: is image 0.
`include "build_sel.vh"

`define GOWIN

// FalconFPGA stage 1: HDMI_TESTPATTERN disconnects the Atari core video from
// the HDMI output and instead drives a standalone 640x480@60 (VIC 1, 25.2 MHz)
// colour-bar test pattern from its own PLL (hdmi_testpattern_640.sv). The core
// (clocks, SDRAM, OSD, scandoubler, lcd_* outputs) keeps running unchanged.
// Stage 2: by default hdmi_tp now shows the ST video through a BSRAM frame
// buffer (ST_VIDEO parameter at the hdmi_tp instance; 0 = colour bars).
// Comment this line out to restore the original video2hdmi path.
// ---------------------------------------------------------------------------
// BUILD OPTION: DIAG_OVERLAY (debug only, OFF by default)
// Uncomment the `define below and rebuild to draw the diagnostic overlay on the
// HDMI picture: three rows of status squares plus six 32-bit "bit-bar" rows
// (68030 bus state, first bus error, last bus cycle, bridge state, last program
// fetch). leds_n[1] then blinks while the 68030 runs bus cycles. The bar key is
// in docs/DIAG_OVERLAY.md. It costs fabric and some timing margin and covers
// part of the screen, so it is for debugging only; with the define commented
// out the debug wiring is unused and removed by synthesis (normal build).
// Needs HDMI_TESTPATTERN and ST_VIDEO=1 (both are the default).
// ---------------------------------------------------------------------------
//`define DIAG_OVERLAY

// Frame buffer self-test (separate mode, only with DIAG_OVERLAY): 1 = the
// frame buffer is filled from a locally generated fake ST picture (colour
// bars, grey ramp, checkerboard, white frame) INSTEAD of the real ST video.
// 0 = real ST video (default for this build).
`define DIAG_FB_SELFTEST 0

module top(
  input			clk, // 50 MHz in

  input			reset_n, // S2
  input			user_n, // S1

  output [1:0]	leds_n,

  // SOM DDR3, helper bring-up only. J9 SDRAM is unchanged.
  output [2:0]	DDR3_BANK,
  output		DDR3_CS_N,
  output		DDR3_RAS_N,
  output		DDR3_CAS_N,
  output		DDR3_WE_N,
  output		DDR3_CK,
  output		DDR3_CK_N,
  output		DDR3_CKE,
  output		DDR3_RESET_N,
  output		DDR3_ODT,
  output [13:0]	DDR3_ADDR,
  output [1:0]	DDR3_DM,
  inout  [15:0]	DDR3_DQ,
  inout  [1:0]	DDR3_DQS,
  inout  [1:0]	DDR3_DQS_N,

  // interface to Tang onboard BL616 UART
  //input		uart_rx,
  //output		uart_tx,
  // onboard Bl616 monitor console port interface
  //output		bl616_mon_tx,
  //input			bl616_mon_rx,

  // spi flash interface (inout: AE350 serial proof needs true IOBUFs on all
  // six MSPI balls, matching Hybrid030; desktop still drives cs/clk as outs)
  inout			mspi_cs,
  inout			mspi_clk,
  inout			mspi_di,
  inout			mspi_hold,
  inout			mspi_wp,
  inout			mspi_do,

  // MiSTer SDRAM module
  output		O_sdram_clk,
  output		O_sdram_cs_n, // chip select
  output		O_sdram_cas_n, // columns address select
  output		O_sdram_ras_n, // row address select
  output		O_sdram_wen_n, // write enable
  inout [15:0]	IO_sdram_dq, // 16 bit bidirectional data bus
  output [12:0]	O_sdram_addr, // 13 bit multiplexed address bus
  output [1:0]	O_sdram_ba, // two banks
  output [1:0]	O_sdram_dqm, // 16/2

  // give explicit directions for pmod1 as it's being used for the
  // FPGA Companion and this allows for clock buffering. Clock glitches
  // were observed when using inouts for the companion
  input			pmod_companion_din,
  output		pmod_companion_dout,
  input			pmod_companion_clk,
  input			pmod_companion_ss,
  output		pmod_companion_intn,

  // two dual shock controllers on left PMOD, only P1 is used
  // by MiSTeryNano for joystick
  output		ds1_csn,
  output		ds1_sclk,
  output		ds1_mosi,
  input			ds1_miso,
  output		ds2_csn,
  output		ds2_sclk,
  output		ds2_mosi,
  input			ds2_miso, 

  output		jtagseln,
  input			bl616_jtagsel,

  // interface to onboard BL616 µC
  input			spi_sclk, 
  input			spi_csn,
  output		spi_dir,
  input			spi_dat,
  output		spi_irqn,

  // debug uart from/to BL616
  //input			bl616_reconfig,
  input			bl616_tx,
  //output		bl616_rx,
  // external UART signals, the BL616 UART is bridged to
  output		uart_ext_tx,

  // SD card slot
  output		sd_clk,
  inout			sd_cmd, // MOSI
  inout [3:0]	sd_dat, // 0: MISO

  output		lcd_clk,
  output		lcd_en, //lcd data enable     
  output		lcd_hs, //lcd data enable     
  output		lcd_vs, //lcd data enable     
  output [7:0]	lcd_r, //lcd red
  output [7:0]	lcd_g, //lcd green
  output [7:0]	lcd_b, //lcd blue
  output		lcd_bl, //drive low to turn bl off

  // I2S DAC
  output		i2s_bclk,
  output		i2s_lrck,
  output		i2s_din,
  output		pa_en,
	   
  // hdmi/tdms
  output		tmds_clk_n,
  output		tmds_clk_p,
  output [2:0]	tmds_d_n,
  output [2:0]	tmds_d_p
`ifdef ST_HELPER_USB
  ,
  // USB-A host ports (pins from the NESTang Console port, as in Hybrid030)
  inout			usb1_dp, // H13
  inout			usb1_dn, // G13
  inout			usb2_dp, // M15
  inout			usb2_dn  // M16
`endif
);

// route BL616 debug uart via the twi signals through the FPGA to
// unused pins on PMOD1 (the middle one)
wire [1:0]   fcal_rpt;    // [F85] flash_cal report {own, tx} (misterynano)
assign bl616_rx = 1'b0;          // from PMOD to BL616, nowadays unused
`ifdef AE350_SERIAL
assign uart_ext_tx = banner_busy ? banner_tx : ae350_uart_tx; // U15. PIN, then AE350.
`elsif ST_HELPER
// U15 (BL616 USB serial, 115200 8N1): fabric letters while the AE350 is in
// reset, the AE350's UART2 while it runs (st_helper_ctrl.v).
// [F69] while the main PLL is not locked (por) pll_wdog.v owns U15 and sends its status line.
`ifdef DIAG_HEARTBEAT
// [F72] debug: once a second the 68030/ST heartbeat line borrows U15 while the AE350 UART is idle (cpu_heartbeat.v).
wire hb_own, hb_tx;
assign uart_ext_tx = por ? wd_tx : fcal_rpt[1] ? fcal_rpt[0] : diag_dump[1] ? diag_dump[0] : hb_own ? hb_tx : sth_ae_run ? ae350_uart_tx : sth_fab_tx;
`else
assign uart_ext_tx = por ? wd_tx : fcal_rpt[1] ? fcal_rpt[0] : sth_ae_run ? ae350_uart_tx : sth_fab_tx;
`endif
`else
assign uart_ext_tx = bl616_tx;   // desktop image
`endif

wire clk32;
wire pll_lock;
// FalconFPGA 9 Oct 2026: the 50 MHz board clock for FABRIC logic (pll_init
// FSMs, S0 debounce, DDR3/AE350 reset debounce, SPI-ext detect) goes through
// a DCE (global clock enable buffer) so it is distributed on the global clock network. Before, the
// router used generic routing for it (PR1014) and the pll_init hold paths had
// 0.5-0.8 ns clock skew (hold slack 0.005-0.03 ns, negative in some
// placements). The PLL CLKIN inputs still take the pad directly.
wire clk_g;
DCE u_clk_g ( .CLKIN(clk), .CE(1'b1), .CLKOUT(clk_g) );
// [F69] PLL lock watchdog on the raw 50 MHz clock: restarts a PLL_INIT whose PLL has not locked in 50 ms,
// and reports retries/lock bits on U15 while the fabric is still in por (docs/HELPER_SILENCE.md).
wire [2:0] wd_init_rst; wire wd_tx; wire [7:0] wd_status; wire ae350_pll_lock;
pll_wdog #(.N(3)) u_pll_wdog ( .clk(clk_g), .lock_a({DDR3_LOCK, ae350_pll_lock, pll_lock}),
    .init_rst(wd_init_rst), .tx(wd_tx), .status(wd_status) );
wire flash_clk;

// S0 is AA13, port reset_n, pull-up. A press after lock reloads the ST reset
// counter (the same path as the cold-start second pulse). Ignored until the
// arm counter fills, so a sample at config cannot hold the CPU in reset.
// S1 (user_n) stays unused.
reg [1:0]  s0_sync = 2'b11;
reg [15:0] s0_arm  = 16'd0;
always @(posedge clk_g) begin
    if (!pll_lock) begin
        s0_sync <= 2'b11;
        s0_arm  <= 16'd0;
    end else begin
        s0_sync <= {s0_sync[0], reset_n};
        if (s0_arm != 16'hffff) s0_arm <= s0_arm + 16'd1;
    end
end
wire s0_reset = (s0_arm == 16'hffff) && !s0_sync[1];
// S1 releases the 030. There is no 20 second timeout.
reg [1:0] s1_sync = 2'b11;
reg       s1_release = 1'b0;
always @(posedge clk32) begin
    if (por32) begin
        s1_sync <= 2'b11;
        s1_release <= 1'b0;
    end else begin
        s1_sync <= {s1_sync[0], user_n};
        if (s1_sync == 2'b00)
            s1_release <= 1'b1;
    end
end
wire por = !pll_lock;  // FalconFPGA: no BL616 jtagsel gating (stock BL616 firmware never drives it low; matches Nano 20K)
// FalconFPGA 9 Oct 2026: por (= !pll_lock, a clk_osc flop in pll_hdmi's
// pll_init) is asynchronous to every fabric clock. Each domain gets its own
// copy that asserts at once and deasserts synchronously (reset_sync.v), so
// the release meets recovery/removal in-domain. Sequencing is unchanged: the
// copies only leave reset 3 clocks of their own domain after lock.
wire por32;      // clk32 domain (ST core, helper control, MCU link, audio)
wire por_flash;  // flash_clk domain (ST flash controller, sth_frel)
reset_sync #(.STAGES(3)) u_por32_sync  ( .clk(clk32),     .arst(por), .rst(por32) );
reset_sync #(.STAGES(3)) u_porfl_sync  ( .clk(flash_clk), .arst(por), .rst(por_flash) );

reg     spi_ext = 1'b0;       // set when the external SPI interface on PMOD is active
reg boot_button_detected = 1'b1;
always @(posedge pll_lock)
  boot_button_detected <= !user_n || !reset_n;   
// boot_button_detected, disabled to fix tc138k booting, needs to be investigated !!!

// enable JTAG if any button has been pressed during boot and also once
// the external FPGA Companion has been seen
assign jtagseln = !(!pll_lock || spi_ext || bl616_jtagsel);
// -------------------------- FPGA Companion interface -----------------------

// map output data onto both spi outputs
wire spi_io_dout;
wire spi_intn;

// intn and dout are outputs driven by the FPGA to the MCU
// din, ss and clk are inputs coming from the MCU
`ifdef ST_HELPER
// ST_HELPER: the AE350 is the companion MCU (st_helper_mculink.v). The BL616
// (and a PMOD companion) are kept OFF the link so the two masters can never
// fight: their SS#/SCK/MOSI inputs are ignored, the BL616 MISO pin (spi_dir)
// is tristated and its IRQ pin (spi_irqn, C22 in this build) is held
// inactive high. The stock BL616 firmware only keeps the USB serial bridge
// (U15) and its JTAG/programming role; it is never reflashed.
assign spi_dir  = 1'bz;
assign spi_irqn = 1'b1;
assign pmod_companion_dout = 1'b0;
assign pmod_companion_intn = 1'b1;
`else
assign spi_dir = pll_lock?spi_io_dout:1'b1;
assign spi_irqn = pll_lock?spi_intn:1'b1;

assign pmod_companion_dout = spi_io_dout;
assign pmod_companion_intn = spi_intn;
`endif
   
// by default the internal SPI is being used. Once there is
// a select from the external spi, then the connection is
// being switched
always @(posedge clk_g) begin
    if(!pll_lock)
        spi_ext = 1'b0;
    else begin
        // spi_ext is activated once the m0s pins 2 (ss or csn) is
        // driven low by the m0s dock. This means that a m0s dock
        // is connected and the FPGA switches its inputs to the
        // m0s. Until then the inputs of the internal BL616 are
        // being used.
        if(pmod_companion_ss == 1'b0)
            spi_ext = 1'b1;
    end
end

// switch between internal SPI connected to the on-board bl616
// or to the external one possibly connected to a FPGA Companion
`ifdef ST_HELPER
// ST_HELPER: mcu_spi is driven only by the AE350 (st_helper_mculink below).
wire spi_io_din, spi_io_ss, spi_io_clk;
`else
wire spi_io_din = spi_ext?pmod_companion_din:spi_dat;
wire spi_io_ss = spi_ext?pmod_companion_ss:spi_csn;
wire spi_io_clk = spi_ext?pmod_companion_clk:spi_sclk;
`endif

wire [15:0] audio [2];
wire        vreset;
wire [1:0]  vmode;
wire [1:0]  screen;

wire [5:0] leds_int_n;
// leds_n[0] latches on from the first 030 ROM fetch. Active low.
wire rom_fetch;
`ifdef DIAG_OVERLAY
// DIAG: leds_n[1] blinks (~2 Hz) while the 030 starts bus cycles (030 AS
// seen by the bridge in the last ~0.13-0.26 s); steady = no 030 bus cycles.
// Same expression style as leds_n[0].
wire diag_led_030;
assign leds_n = {~diag_led_030, ~rom_fetch};
`else
assign leds_n = {~leds_int_n[1], ~rom_fetch};
`endif

assign lcd_bl = 1'bz;
   
// MiSTer SDRAM is only 16 bits wide
wire [31:0] sdram_dq;  
assign IO_sdram_dq = sdram_dq[15:0];
   
wire [3:0] sdram_dqm;  
assign O_sdram_dqm = sdram_dqm[1:0];

// ------ dual shock interface ------------

assign ds2_csn = 1'b1;   

// signals coming from dualshock2 p1
wire [4:0] ds1_p1;   

assign ds1_p1[0] = |ds1_buttons;
wire [3:0] ds1_buttons;   
   
dualshock2 ds2_p1 (
  .clk          ( clk32     ), // ds2 module actually expects 31.5 Mhz
  .rst          ( por32     ),			   
  .vsync        ( !lcd_vs   ), // refresh once a screen
				   
  .ds2_dat      ( ds1_miso  ), // connections to dualshock p1 port
  .ds2_cmd      ( ds1_mosi  ),
  .ds2_att      ( ds1_csn   ),
  .ds2_clk      ( ds1_sclk  ),
  .ds2_ack      (           ),

  .key_down     ( ds1_p1[1] ),
  .key_up       ( ds1_p1[2] ),
  .key_right    ( ds1_p1[3] ),
  .key_left     ( ds1_p1[4] ),

  .key_triangle ( ds1_buttons[0] ),
  .key_circle   ( ds1_buttons[1] ),
  .key_cross    ( ds1_buttons[2] ),
  .key_square   ( ds1_buttons[3] )
);  

// ------ feed audio into i2s dac ------------
assign pa_en = 1'b1;   // enable headphone amplifier

// generate 48k * 32 = 1536kHz audio clock. TODO: this is too
// imprecise
reg clk_audio;
reg [7:0] aclk_cnt;
always @(posedge clk32) begin
    if(aclk_cnt < 32000000 / 1536000 / 2 -1)
        aclk_cnt <= aclk_cnt + 8'd1;
    else begin
        aclk_cnt <= 8'd0;
        clk_audio <= ~clk_audio;
    end
end

// count 32 bits
reg [4:0] audio_bit_cnt;
always @(posedge clk_audio) begin
    if(por32)
        audio_bit_cnt <= 5'd0;
    else 
        audio_bit_cnt <= audio_bit_cnt + 5'd1;
end

// generate i2s signals
assign i2s_bclk = clk_audio;
assign i2s_lrck = por32?1'b0:audio_bit_cnt[4];
assign i2s_din = por32?1'b0:audio[i2s_lrck][15-audio_bit_cnt[3:0]];
   
// FalconFPGA stage 2: raw ST video (clk32 domain) for the 640x480 frame buffer
wire       st_video_hs_n, st_video_vs_n, st_video_de;
wire [3:0] st_video_r, st_video_g, st_video_b;
wire [7:0]  diag_flags;
wire [16:0] diag_rom_idx;
wire [15:0] diag_rom_data;
wire [3:0]  diag_030;
wire [167:0] diag_trace;
wire [1:0]   diag_dump;   // [F77] {own, tx} register dump while the 030 is halted (DIAG_DUMP)
wire         diag_go;
wire [23:0] diag_vbase;

// Helper bring-up. DDR3 trains, then the AE350 is released and owns MSPI
// until it drives GPIO 0xA5, or 20 seconds pass. The ready bit is latched,
// the AE350 is put back in reset, and the 030 gets the flash for TOS.
wire        DDR3_MEMORY_CLK, DDR3_CLK_IN, DDR3_RW_CLK, DDR3_LOCK, DDR3_STOP;
wire        CORE_CLK, DDR_CLK, AHB_CLK, APB_CLK, RTC_CLK;
wire        ddr3_init_completed;
wire        ae350_flash_csn, ae350_flash_miso, ae350_flash_mosi;
wire        ae350_uart_tx;
wire        ae350_flash_holdn, ae350_flash_wpn;
// syn_keep: the ae350_flash_clk SDC clock is attached to this net. Gowin
// V1.9.12.04 synthesis otherwise renames it (n250_3) and PnR stops (TA2003).
// (Restored after the 9fe250b pmmu merge dropped it.)
(* syn_keep = 1 *) wire ae350_flash_clk;
`ifdef AE350_SERIAL
`elsif ST_HELPER
// ST_HELPER: the SoC drives ae350_flash_csn/clk/mosi; they reach the MSPI
// balls only until the one-way switch (see the flash pad block below).
// ae350_flash_miso is fed from the R22 ball there.
`else
// Desktop image. Inouts cannot be tied to constants. Not on the ST flash pins.
assign ae350_flash_csn = 1'b1;
assign ae350_flash_miso = 1'b1;
assign ae350_flash_mosi = 1'b1;
assign ae350_flash_clk = 1'b0;
assign ae350_flash_holdn = 1'b1;
assign ae350_flash_wpn = 1'b1;
`endif
wire [31:0] ae350_gpio;
wire        ddr3_rstn;
wire [31:0] extm_hrdata;
wire        extm_hreadyout;
wire [1:0]  extm_hresp;

gowin_pll_ae350 u_gowin_pll_ae350 (
    .clkin(clk), .init_clk(clk_g),
    .clkout0(DDR_CLK), .clkout1(CORE_CLK), .clkout2(AHB_CLK),
    .clkout3(APB_CLK), .clkout4(RTC_CLK),
    .lock(ae350_pll_lock), .init_rst(wd_init_rst[1])
);
gowin_pll_ddr3 u_gowin_pll_ddr3 (
    .clkin(clk), .init_clk(clk_g), .init_rst(wd_init_rst[2]),
    .enclk0(1'b1), .enclk1(1'b1), .enclk2(DDR3_STOP),
    .clkout0(DDR3_CLK_IN), .clkout1(DDR3_RW_CLK),
    .clkout2(DDR3_MEMORY_CLK), .lock(DDR3_LOCK)
);
`ifdef ST_HELPER
// ST_HELPER: S0 resets the ST only. The helper runs from DDR3 and its flash
// has been handed to the ST, so a DDR3 reset would kill it for good. DDR3
// reset is released 20 ms after configuration, independent of S0.
key_debounce u_key_debounce_ddr3 (
    .out(ddr3_rstn), .in(1'b1), .clk(clk_g), .rstn(1'b1)
);
`else
key_debounce u_key_debounce_ddr3 (
    .out(ddr3_rstn), .in(reset_n), .clk(clk_g), .rstn(1'b1)
);
`endif

reg [1:0] ddr3_init_sync;
reg [29:0] helper_timer;
reg [7:0]  gpio_s0, gpio_s1;
reg [1:0]  ready_match;
reg        helper_ready;
reg [1:0]  phase;
reg [15:0] reinit_cnt;
reg        flash_ready_s0, flash_ready_s1;
localparam PH_HOLD = 2'd0, PH_LOAN = 2'd1, PH_REINIT = 2'd2, PH_RUN = 2'd3;
`ifdef AE350_SERIAL
// Proof image. 030 stays in reset. Flash is on the AE350 from t0 (hybrid).
// Stub is linked for DDR, so no D means it cannot reach main.
// Release AE350 only after ddr3_init has been stable ~20 ms (hybrid key_debounce).
wire flash_reinit = 1'b0;
wire helper_hold = 1'b1;
wire ae350_rstn_deb;
key_debounce u_key_debounce_ae350 (
    .out(ae350_rstn_deb), .in(ddr3_init_sync[1]), .clk(clk_g), .rstn(1'b1)
);
reg ae350_loan;
reg ae350_run;
reg [8:0] banner_div;
reg [3:0] banner_bit;
reg [3:0] banner_idx;
reg [7:0] banner_shift;
reg banner_busy;
reg banner_tx;
reg [1:0] banner_st;
reg [15:0] loan_wait;
localparam BST_PIN = 0, BST_WAIT = 1, BST_TAIL = 2, BST_LOAN = 3;
always @(posedge clk32) begin
    if (por32) begin
        ae350_loan <= 0;
        ae350_run <= 0;
        banner_div <= 0;
        banner_bit <= 0;
        banner_idx <= 0;
        banner_shift <= 8'h50; // P
        banner_busy <= 1;
        banner_tx <= 1;
        banner_st <= BST_PIN;
        loan_wait <= 0;
    end else if (banner_st == BST_WAIT) begin
        if (ddr3_init_sync[1] || helper_timer >= 30'd256_000_000) begin
            banner_shift <= ddr3_init_sync[1] ? 8'h44 : 8'h58; // D or X
            banner_bit <= 0;
            banner_idx <= 0;
            banner_st <= BST_TAIL;
        end
    end else if (banner_st == BST_LOAN) begin
        ae350_loan <= 1;
        // Hybrid waits ~20 ms after DDR3_INIT via key_debounce before AE350 reset.
        if (ae350_rstn_deb) begin
            banner_shift <= 8'h52; // R
            banner_bit <= 0;
            banner_idx <= 1;
            banner_st <= BST_TAIL;
        end
    end else if (banner_busy) begin
        if (banner_div != 9'd277) banner_div <= banner_div + 1;
        else begin
            banner_div <= 0;
            if (banner_bit == 0) begin
                banner_tx <= 0;
                banner_bit <= 1;
            end else if (banner_bit <= 8) begin
                banner_tx <= banner_shift[0];
                banner_shift <= {1'b1, banner_shift[7:1]};
                banner_bit <= banner_bit + 1;
            end else begin
                banner_tx <= 1;
                banner_bit <= 0;
                if (banner_st == BST_PIN) begin
                    if (banner_idx == 4) banner_st <= BST_WAIT;
                    else begin
                        banner_idx <= banner_idx + 1;
                        case (banner_idx)
                            0: banner_shift <= 8'h49; // I
                            1: banner_shift <= 8'h4E; // N
                            2: banner_shift <= 8'h0D;
                            default: banner_shift <= 8'h0A;
                        endcase
                    end
                end else if (banner_idx == 0) begin
                    banner_st <= BST_LOAN; // D or X sent, lend flash
                end else begin
                    ae350_run <= 1;        // R sent, release CPU, hand over the pin
                    banner_busy <= 0;
                end
            end
        end
    end
end
`elsif ST_HELPER
// ---------------------------------------------------------------------------
// ST_HELPER (build_st_helper.tcl): boot-then-release. The AE350 boots from
// the flash first while the ST is held, then the flash goes to the ST for
// good and TOS boots; the helper keeps running from DDR3. Details and the
// safety argument: st_helper_ctrl.v. Mailbox: st_helper_mailbox.v.
// ---------------------------------------------------------------------------
wire       sth_ae_run, sth_flash_to_st, sth_st_release;
wire       sth_helper_up, sth_helper_fail, sth_fab_tx, sth_ae_rxd;
wire [7:0] sth_boot_code, sth_gpio;
st_helper_ctrl u_sth_ctrl (
    .clk         ( clk32               ),
    .rst         ( por32               ),
    .ddr3_init_a ( ddr3_init_completed ),
    .ae_gpio_a   ( ae350_gpio[7:0]     ),
    .ae_csn_a    ( ae350_flash_csn     ),
    .s1_n_a      ( user_n              ),
    .fu_done     ( fu_done             ),   // [F70] flash out of continuous read
    .ae_run      ( sth_ae_run          ),
    .flash_to_st ( sth_flash_to_st     ),
    .st_release  ( sth_st_release      ),
    .helper_up   ( sth_helper_up       ),
    .helper_fail ( sth_helper_fail     ),
    .boot_code   ( sth_boot_code       ),
    .ae_gpio     ( sth_gpio            ),
    .fab_tx      ( sth_fab_tx          )
);
wire ae350_run   = sth_ae_run;
wire helper_hold = ~sth_st_release;        // ST (030 + chipset) in reset until the switch
// The ST flash controller is held in reset (flash_ready low) until the pads
// are the ST's; its reset is released synchronously to flash_clk.
reg [1:0] sth_frel = 2'b00;
always @(posedge flash_clk or posedge por_flash)
    if (por_flash) sth_frel <= 2'b00;
    else     sth_frel <= {sth_frel[0], sth_st_release};
wire flash_reinit = ~sth_frel[1];
`else
// Desktop image. AE350 stays in reset and off the flash pins.
wire ae350_run = 1'b0;
wire flash_reinit = 1'b0;
wire helper_hold = 1'b0;
`endif
// Falcon has no ST flash controller (TOS is loaded from the SD card). The
// leftover helper-phase FSM below still samples flash_ready; treat it as ready.
wire flash_ready = 1'b1;
always @(posedge clk32) begin
    if (por32) begin
        ddr3_init_sync <= 2'b00;
        helper_timer <= 30'd0;
        gpio_s0 <= 8'h00;
        gpio_s1 <= 8'h00;
        ready_match <= 2'b00;
        helper_ready <= 1'b0;
        phase <= PH_HOLD;
        reinit_cnt <= 16'd0;
        flash_ready_s0 <= 1'b0;
        flash_ready_s1 <= 1'b0;
    end else begin
        ddr3_init_sync <= {ddr3_init_sync[0], ddr3_init_completed};
        if (helper_timer != 30'd640_000_000)
            helper_timer <= helper_timer + 30'd1;
        gpio_s0 <= ae350_gpio[7:0];
        gpio_s1 <= gpio_s0;
        if (ae350_run && gpio_s1 == 8'hA5)
            ready_match <= ready_match + 2'b01;
        else
            ready_match <= 2'b00;
        if (ready_match == 2'b11)
            helper_ready <= 1'b1;
        flash_ready_s0 <= flash_ready;
        flash_ready_s1 <= flash_ready_s0;
        case (phase)
            PH_HOLD: if (s1_release)
                    phase <= PH_REINIT;
                else if (flash_ready_s1 && ddr3_init_sync[1])
                    phase <= PH_LOAN;
            PH_LOAN: if (helper_ready || s1_release)
                    phase <= PH_REINIT;
            PH_REINIT: begin
                reinit_cnt <= reinit_cnt + 16'd1;
                if (reinit_cnt == 16'd33792)
                    phase <= PH_RUN;
            end
            default: phase <= PH_RUN;
        endcase
        if (phase != PH_REINIT)
            reinit_cnt <= 16'd0;
    end
end
wire helper_timeout = (helper_timer == 30'd640_000_000);

RiscV_AE350_SOC_Top u_RiscV_AE350_SOC_Top (
`ifdef AE350_SERIAL
    // Direct to pads, hybrid map (no assign middleman on CSN/CLK).
    .FLASH_SPI_CSN(mspi_cs), .FLASH_SPI_CLK(mspi_clk),
    .FLASH_SPI_MOSI(mspi_di), .FLASH_SPI_MISO(mspi_do),
    .FLASH_SPI_HOLDN(mspi_hold), .FLASH_SPI_WPN(mspi_wp),
`else
    .FLASH_SPI_CSN(ae350_flash_csn), .FLASH_SPI_MISO(ae350_flash_miso), .FLASH_SPI_MOSI(ae350_flash_mosi),
    .FLASH_SPI_CLK(ae350_flash_clk), .FLASH_SPI_HOLDN(ae350_flash_holdn), .FLASH_SPI_WPN(ae350_flash_wpn),
`endif
    .DDR3_MEMORY_CLK(DDR3_MEMORY_CLK), .DDR3_CLK_IN(DDR3_CLK_IN),
    .DDR3_RSTN(ddr3_rstn), .DDR3_LOCK(DDR3_LOCK), .DDR3_STOP(DDR3_STOP),
    .DDR3_INIT(ddr3_init_completed),
    .DDR3_BANK(DDR3_BANK), .DDR3_CS_N(DDR3_CS_N), .DDR3_RAS_N(DDR3_RAS_N),
    .DDR3_CAS_N(DDR3_CAS_N), .DDR3_WE_N(DDR3_WE_N),
    .DDR3_CK(DDR3_CK), .DDR3_CK_N(DDR3_CK_N), .DDR3_CKE(DDR3_CKE),
    .DDR3_RESET_N(DDR3_RESET_N), .DDR3_ODT(DDR3_ODT), .DDR3_ADDR(DDR3_ADDR),
    .DDR3_DM(DDR3_DM), .DDR3_DQ(DDR3_DQ), .DDR3_DQS(DDR3_DQS),
    .DDR3_DQS_N(DDR3_DQS_N),
    .clk_lane4(DDR3_RW_CLK), .addr_lane4(32'd0), .wr_mask_lane4(4'd0),
    .wr_data_lane4(32'd0), .wr_en_lane4(1'b0), .wr_go_lane4(1'b0),
    .burstcount_lane4(8'd0), .wr_wait_lane4(), .wr_done_lane4(),
    .clk_lane5(DDR3_RW_CLK), .addr_lane5(32'd0), .rd_en_lane5(1'b0),
    .rd_go_lane5(1'b0), .burstcount_lane5(8'd0),
    .rd_valid_lane5(), .rd_data_lane5(), .rd_rdy_lane5(),
    .EXTM_HADDR(32'd0), .EXTM_HBURST(3'd0), .EXTM_HPROT(4'd0),
    .EXTM_HREADY(extm_hreadyout), .EXTM_HSEL(1'b0), .EXTM_HSIZE(3'd0),
    .EXTM_HTRANS(2'd0), .EXTM_HWDATA(64'd0), .EXTM_HWRITE(1'b0),
    .EXTM_HRDATA(extm_hrdata), .EXTM_HREADYOUT(extm_hreadyout),
    .EXTM_HRESP(extm_hresp),
    .TCK_IN(1'b0), .TMS_IN(1'b1), .TRST_IN(1'b1), .TDI_IN(1'b0),
    .TDO_OUT(), .TDO_OE(),
`ifdef ST_HELPER
    // UART2 RX = ST mailbox TX AND the BL616 USB-serial TX (V14, idle high,
    // "uart_rx" in the CST), so David can also type to the helper from the
    // PC terminal. Two senders at once garble each other (debug use only).
    .UART2_TXD(ae350_uart_tx), .UART2_RTSN(), .UART2_RXD(sth_ae_rxd & bl616_jtagsel),
    // companion MISO -> CTS (MSR b4 = MISO) once the link is up; MCR AFE is
    // off, so CTS never throttles TX
    .UART2_CTSN(sth_helper_up ? ~spi_io_dout : 1'b0),
`else
    .UART2_TXD(ae350_uart_tx), .UART2_RTSN(), .UART2_RXD(1'b1), .UART2_CTSN(1'b0),
`endif
`ifdef ST_HELPER
    // companion IRQ# -> DCD (MSR b7), link up -> DSR (MSR b5)
    // RI (MSR b6) = the SoC's own flash CS# asserted (diagnostic: the
    // firmware prints it around the flash release, see mailbox.c)
    .UART2_DCDN(sth_helper_up ? spi_intn : 1'b1), .UART2_DSRN(~sth_helper_up), .UART2_RIN(ae350_flash_csn),
`else
    .UART2_DCDN(1'b0), .UART2_DSRN(1'b0), .UART2_RIN(1'b0),
`endif
    .UART2_DTRN(), .UART2_OUT1N(), .UART2_OUT2N(),
    .GPIO(ae350_gpio),
    .CORE_CLK(CORE_CLK), .DDR_CLK(DDR_CLK), .AHB_CLK(AHB_CLK),
    .APB_CLK(APB_CLK), .RTC_CLK(RTC_CLK),
    .POR_RSTN(ae350_run), .HW_RSTN(ae350_run)
);

`ifdef AE350_SERIAL
// Proof: AE350 owns MSPI exclusively (030 held). SOC flash ports are wired
// straight to the six MSPI balls (hybrid map). ae350_loan only times reset.
wire        nano_mspi_cs, nano_mspi_hold, nano_mspi_wp, nano_mspi_do, nano_mspi_di, mspi_clk_pll;
`endif

`ifdef ST_HELPER
// ---------------------------------------------------------------------------
// ST_HELPER flash pads. One mux, switched ONCE by sth_flash_to_st (sticky,
// clk32 register), while the AE350's CS# has been high for 8 us and the ST
// flash controller is in reset (CS# high): no CS# glitch, and an SCK glitch
// with CS# high is ignored by the flash.
//   before: AE350 owns the balls, hybrid / serial-proof map:
//           CSN T19, CLK L12, MOSI -> P22 (mspi_di, IO0), MISO <- R22
//           (mspi_do, IO1), WP# P21 = 1, HOLD# R21 = 1.
//   after:  exactly the desktop ST flash controller: CS#, SCK = PLL clkout4
//           (100 MHz, 22.5 deg), IO0/IO1 bidirectional with the controller's
//           OWN output enables (dual-I/O read 0xBB), HOLD# = 1, WP# = 0.
// The pads are real IOBUFs on IO0/IO1 (tristate with the ST's OE), so the
// dual-I/O turnaround that the 988c846 runtime mux broke is preserved.
// Once switched, the AE350's CS# goes nowhere and its CLK/MOSI/MISO become
// the FPGA-Companion SPI link to mcu_spi (st_helper_mculink.v), never the flash.
// ---------------------------------------------------------------------------
wire        st_mspi_cs, mspi_clk_pll;
wire [1:0]  st_mspi_io_o, st_mspi_io_oe;
// [F70] Before the AE350 is released, flash_unstick.v takes the flash out of the ST reader's continuous-read mode
// (left over from before a JTAG reconfigure) and resets it (0x66/0x99). It owns the pads only while fu_busy (AE350 in reset).
wire fu_busy, fu_done, fu_csn, fu_sck, fu_io0, fu_io1_oe;
flash_unstick u_flash_unstick ( .clk(clk32), .rst(por32), .busy(fu_busy), .done(fu_done),
    .csn(fu_csn), .sck(fu_sck), .io0(fu_io0), .io1_oe(fu_io1_oe) );
wire fu_own = fu_busy & ~sth_flash_to_st;
// [F71] AE350-side signals are premuxed so mspi_clk keeps f69's single 2:1 mux after the PLL clock.
// [F73] syn_keep: the SCK pad LUT stays a 3-input mux of the PLL clock as in f69 (pmmu f70: TOS read as garbage).
wire ae_side_csn /* synthesis syn_keep=1 */ = fu_own ? fu_csn : ae350_flash_csn;
wire ae_side_clk /* synthesis syn_keep=1 */ = fu_own ? fu_sck : ae350_flash_clk;
assign mspi_cs   = sth_flash_to_st ? st_mspi_cs   : ae_side_csn;
assign mspi_clk  = sth_flash_to_st ? mspi_clk_pll : ae_side_clk;
assign mspi_di   = sth_flash_to_st ? (st_mspi_io_oe[0] ? st_mspi_io_o[0] : 1'bz)
                                   : fu_own ? fu_io0 : ae350_flash_mosi;
assign mspi_do   = (sth_flash_to_st && st_mspi_io_oe[1]) ? st_mspi_io_o[1] : (fu_own && fu_io1_oe) ? 1'b1 : 1'bz;
assign mspi_hold = 1'b1;                   // both masters keep HOLD# high
assign mspi_wp   = ~sth_flash_to_st;       // AE350: 1 (as its IP), ST: 0 (as flash_dspi.v)
// After the switch the AE350's (now idle) flash SPI controller becomes the
// FPGA-Companion SPI master: MISO returns mcu_spi's dout once the link is up.
assign ae350_flash_miso = sth_flash_to_st ? (sth_helper_up ? spi_io_dout : 1'b1)
                                          : mspi_do;

// AE350 -> core companion link (replaces the BL616), see st_helper_mculink.v
st_helper_mculink u_sth_mculink (
    .clk_ae    ( AHB_CLK          ),
    .link_en_a ( sth_helper_up    ),
    .ae_ss_n_a ( ae350_gpio[0]    ),
    .ae_sck_a  ( ae350_gpio[1]    ),   // bit-banged (see st_helper_mculink.v)
    .ae_mosi_a ( ae350_gpio[2]    ),
    .ss_n      ( spi_io_ss        ),
    .sck       ( spi_io_clk       ),
    .mosi      ( spi_io_din       )
);

// Helper mailbox at $FFFB00-$FFFB1F (ST side), UART2 link (helper side)
wire        ext_io_cs, ext_io_rw, ext_io_uds_n, ext_io_lds_n, ext_io_dtack;
wire [4:1]  ext_io_a;
wire [15:0] ext_io_wdata, ext_io_rdata;
st_helper_mailbox u_sth_mailbox (
    .clk         ( clk32           ),
    .rst         ( por32           ),
    .cs          ( ext_io_cs       ),
    .uds_n       ( ext_io_uds_n    ),
    .lds_n       ( ext_io_lds_n    ),
    .rw          ( ext_io_rw       ),
    .a           ( ext_io_a        ),
    .wdata       ( ext_io_wdata    ),
    .rdata       ( ext_io_rdata    ),
    .dtack       ( ext_io_dtack    ),
    .ae_txd_a    ( ae350_uart_tx   ),
    .ae_rxd      ( sth_ae_rxd      ),
    .ae_run      ( sth_ae_run      ),
    .helper_up   ( sth_helper_up   ),
    .helper_fail ( sth_helper_fail ),
    .boot_code   ( sth_boot_code   ),
    .ae_gpio     ( sth_gpio        )
);
`endif

// ==================================================================
// ======================== Falcon030 fabric ========================
// ==================================================================

// Flash stays with the AE350; the core has no ST flash TOS controller.
assign st_mspi_cs    = 1'b1;
assign st_mspi_io_o  = 2'b00;
assign st_mspi_io_oe = 2'b00;

// Mailbox I/O window: not yet decoded on the Falcon bus. Hold the ST-side
// cycle idle; the mailbox drives rdata/dtack. Helper still runs from DDR3.
assign ext_io_cs    = 1'b0;
assign ext_io_rw    = 1'b1;
assign ext_io_uds_n = 1'b1;
assign ext_io_lds_n = 1'b1;
assign ext_io_a     = 4'd0;
assign ext_io_wdata = 16'd0;

// Pads / leftover ST video path (no ST framebuffer, no LCD, no video2hdmi)
assign lcd_clk = 1'b0;
assign lcd_hs  = 1'b1;
assign lcd_vs  = 1'b1;
assign lcd_en  = 1'b0;
assign lcd_r   = 8'h00;
assign lcd_g   = 8'h00;
assign lcd_b   = 8'h00;
assign vreset  = 1'b0;
assign vmode   = 2'b00;
assign screen  = 2'b00;
assign audio[0] = 16'h0000;
assign audio[1] = 16'h0000;
assign st_video_hs_n = 1'b1;
assign st_video_vs_n = 1'b1;
assign st_video_de   = 1'b0;
assign st_video_r    = 4'h0;
assign st_video_g    = 4'h0;
assign st_video_b    = 4'h0;
assign diag_flags    = 8'h00;
assign diag_rom_idx  = 17'd0;
assign diag_rom_data = 16'd0;
assign diag_030      = 4'd0;
assign diag_trace    = 168'd0;
assign diag_dump     = 2'b00;
assign fcal_rpt      = 2'b00;
assign diag_vbase    = 24'd0;

wire        soc_reset = por32 | helper_hold;
wire        ram_ready, tos_err, cpu_reset, scan_underrun, cpu_halted_n;
wire [31:0] loader_status;
wire        sd_clk_unused, sd_cke_unused;
wire [9:0]  hdmi_cx, hdmi_cy;
wire        hdmi_hs, hdmi_vs, hdmi_de, hdmi_vbl, hdmi_hbl;
wire [7:0]  hdmi_r, hdmi_g, hdmi_b;
wire [63:0] sd_img_size;
wire [7:0]  sd_img_mounted;
wire        sd_busy, sd_done, sd_err, sd_rd_byte_strobe;
wire [8:0]  sd_byte_index;
wire [7:0]  sd_rd_data, sd_wr_data;
wire        fdc_img_mounted = sd_img_mounted[0];
wire [31:0] tos_sd_lba, fdc_sd_lba;
wire        tos_sd_rd, fdc_sd_rd, fdc_sd_wr;
wire        tos_sd_ack = sd_busy;
wire        fdc_sd_ack = sd_busy;
// Latch per-slot sizes: sd_card.v keeps only the last mounted image's size.
reg  [31:0] tos_img_size_r, fdc_img_size_r;
wire [1:0]  system_floppy_wprot;
wire [1:0]  system_reset;
wire        tos_mnt_go;
wire [31:0] tos_mnt_size;
always @(posedge clk32) begin
    if (por32) begin
        tos_img_size_r <= 32'd0;
        fdc_img_size_r <= 32'd0;
    end else begin
        if (sd_img_mounted[4]) tos_img_size_r <= sd_img_size[31:0];
        if (sd_img_mounted[0]) fdc_img_size_r <= sd_img_size[31:0];
    end
end
// Sticky TOS mount: see tos_mount_latch.v. Reset by por32 only; go waits for
// !soc_reset && ram_ready plus 1 ms for the helper's CMD 6 direct-map.
wire        tos_mnt_sticky;
tos_mount_latch #(.DELAY(32_000)) u_tos_mnt (
    .clk(clk32), .por(por32), .hold(soc_reset), .ram_ready(ram_ready),
    .img_mounted(sd_img_mounted[4]),
    .img_size(sd_img_mounted[4] ? sd_img_size[31:0] : tos_img_size_r),
    .go(tos_mnt_go), .size(tos_mnt_size), .sticky(tos_mnt_sticky)
);

// HID / IKBD
wire [7:0]  keyboard[14:0];
wire [14:0] keyboard_matrix_out;
wire [7:0]  keyboard_matrix_in =
              (!keyboard_matrix_out[0]?keyboard[0]:8'hff)&
              (!keyboard_matrix_out[1]?keyboard[1]:8'hff)&
              (!keyboard_matrix_out[2]?keyboard[2]:8'hff)&
              (!keyboard_matrix_out[3]?keyboard[3]:8'hff)&
              (!keyboard_matrix_out[4]?keyboard[4]:8'hff)&
              (!keyboard_matrix_out[5]?keyboard[5]:8'hff)&
              (!keyboard_matrix_out[6]?keyboard[6]:8'hff)&
              (!keyboard_matrix_out[7]?keyboard[7]:8'hff)&
              (!keyboard_matrix_out[8]?keyboard[8]:8'hff)&
              (!keyboard_matrix_out[9]?keyboard[9]:8'hff)&
              (!keyboard_matrix_out[10]?keyboard[10]:8'hff)&
              (!keyboard_matrix_out[11]?keyboard[11]:8'hff)&
              (!keyboard_matrix_out[12]?keyboard[12]:8'hff)&
              (!keyboard_matrix_out[13]?keyboard[13]:8'hff)&
              (!keyboard_matrix_out[14]?keyboard[14]:8'hff);
wire [5:0]  hid_mouse;
wire [7:0]  hid_joy [4];

// LEDs: [0] ROM/TOS loader done (was rom_fetch), [1] CPU running
assign rom_fetch   = ~cpu_reset & ram_ready & ~tos_err;
assign leds_int_n  = {4'b1111, cpu_halted_n, ~(cpu_reset | tos_err)};

// VID-SPLIT: helper option "V" (falcon.xml list Monitor): 0 = VGA 60 Hz, 1 = RGB 50/60 Hz -> $FF8006 b7:6
wire system_video;
falcon_soc u_soc (
    .clk_32          ( clk32        ),
    .clk_cpu         ( clk_cpu030   ),
    .clk_cpu_n       ( clk_cpu030_n ),
    .clk_pixel       ( clk_hdmi     ),
    .por             ( soc_reset    ),
    .loader_reset    ( por32        ),
    .user_reset      ( system_reset[0] ),
    .mon_rgb         ( system_video ),
    .sd_clk          ( sd_clk_unused ),
    .sd_cke          ( sd_cke_unused ),
    .sd_cs           ( O_sdram_cs_n ),
    .sd_we           ( O_sdram_wen_n),
    .sd_ras          ( O_sdram_ras_n),
    .sd_cas          ( O_sdram_cas_n),
    .sd_data         ( sdram_dq     ),
    .sd_addr         ( O_sdram_addr ),
    .sd_dqm          ( sdram_dqm    ),
    .sd_ba           ( O_sdram_ba   ),
    .ram_ready       ( ram_ready    ),
    .tos_img_mounted ( tos_mnt_go ),
    .tos_img_size    ( tos_mnt_size ),
    .tos_sd_lba      ( tos_sd_lba   ),
    .tos_sd_rd       ( tos_sd_rd    ),
    .tos_sd_ack      ( tos_sd_ack   ),
    .tos_sd_buff_addr( sd_byte_index ),
    .tos_sd_dout     ( sd_rd_data   ),
    .tos_sd_dout_strobe ( sd_rd_byte_strobe ),
    .tos_err         ( tos_err      ),
    .cpu_reset       ( cpu_reset    ),
    .fdc_img_mounted ( fdc_img_mounted ),
    .fdc_img_size    ( sd_img_mounted[0] ? sd_img_size[31:0] : fdc_img_size_r ),
    .fdc_img_wp      ( system_floppy_wprot[0] ),
    .fdc_sd_lba      ( fdc_sd_lba   ),
    .fdc_sd_rd       ( fdc_sd_rd    ),
    .fdc_sd_wr       ( fdc_sd_wr    ),
    .fdc_sd_ack      ( fdc_sd_ack   ),
    .fdc_sd_err      ( sd_err       ),
    .fdc_sd_buff_addr( sd_byte_index ),
    .fdc_sd_dout     ( sd_rd_data   ),
    .fdc_sd_din      ( sd_wr_data   ),
    .fdc_sd_dout_strobe ( sd_rd_byte_strobe ),
    .keyboard_matrix_out ( keyboard_matrix_out ),
    .keyboard_matrix_in  ( keyboard_matrix_in ),
    .joy0            ( hid_mouse    ),
    .joy1            ( hid_joy[0][4:0] ),
    .cx(hdmi_cx), .cy(hdmi_cy),
    .hsync(hdmi_hs), .vsync(hdmi_vs), .de(hdmi_de),
    .vr(hdmi_r), .vg(hdmi_g), .vb(hdmi_b),
    .vbl(hdmi_vbl), .hbl(hdmi_hbl),
    .scan_underrun   ( scan_underrun ),
    .cpu_halted_n    ( cpu_halted_n ),
    .dbg_mnt         ( sd_img_mounted[4] ),
    .dbg_mnt_size    ( sd_img_mounted[4] ? sd_img_size[31:0] : tos_img_size_r ),
    .dbg_hold        ( soc_reset ),
    .dbg_sticky      ( tos_mnt_sticky ),
    .loader_status   ( loader_status )
);

// ----- helper SPI (AE350) + OSD XML + SD images (TOS ROM = index 4) -----
wire       mcu_sys_strobe, mcu_hid_strobe, mcu_osd_strobe, mcu_sdc_strobe, mcu_start;
wire [7:0] mcu_data_out, sys_data_out, sdc_data_out;
wire [7:0] hid_data_out;
wire [7:0] osd_data_out = 8'h55;
wire [7:0] int_ack;
wire       hid_int;
wire       sdc_int;
wire       sdc_iack = int_ack[3];
wire [1:0] system_leds;
wire       jtagsel_unused;
wire [23:0] ws2812_color;

mcu_spi mcu (
    .clk(clk32), .reset(por32),
    .spi_io_ss(spi_io_ss), .spi_io_clk(spi_io_clk),
    .spi_io_din(spi_io_din), .spi_io_dout(spi_io_dout),
    .mcu_sys_strobe(mcu_sys_strobe), .mcu_hid_strobe(mcu_hid_strobe),
    .mcu_osd_strobe(mcu_osd_strobe), .mcu_sdc_strobe(mcu_sdc_strobe),
    .mcu_start(mcu_start), .mcu_dout(mcu_data_out),
    .mcu_sys_din(sys_data_out), .mcu_hid_din(hid_data_out),
    .mcu_osd_din(osd_data_out), .mcu_sdc_din(sdc_data_out)
);

sysctrl sysctrl (
    .clk(clk32), .reset(por32),
    .data_in_strobe(mcu_sys_strobe), .data_in_start(mcu_start),
    .data_in(mcu_data_out), .data_out(sys_data_out),
    .int_out_n(spi_intn),
    .int_in({ 4'b0000, sdc_int, 1'b0, hid_int, 1'b0 }),
    .int_ack(int_ack),
    .buttons({ 1'b0, s0_reset }),
    .leds(system_leds),
    .jtagsel(jtagsel_unused),
    .color(ws2812_color),
    .port_status(loader_status), .port_out_available(8'd0), .port_out_strobe(),
    .port_out_data(8'd0), .port_in_available(8'd0), .port_in_strobe(), .port_in_data(),
    .rtc(),
    .system_chipset(), .system_memory(), .system_video(system_video), .system_reset(system_reset),
    .system_scanlines(), .system_volume(), .system_screen(),
    .system_floppy_wprot(system_floppy_wprot), .system_cubase_en(),
    .system_port_mouse(), .system_port_joy(), .system_tos_slot()
);

wire hid_iack = int_ack[1];
`ifdef ST_HELPER_USB
wire [7:0] hid_data_out_hid;
wire [7:0] usb_data_out;
wire       usb_active;
assign hid_data_out = usb_active ? usb_data_out : hid_data_out_hid;
st_helper_usb st_helper_usb (
    .clk32(clk32), .reset(por32),
    .usb1_dp(usb1_dp), .usb1_dn(usb1_dn),
    .usb2_dp(usb2_dp), .usb2_dn(usb2_dn),
    .data_in_strobe(mcu_hid_strobe), .data_in_start(mcu_start),
    .data_in(mcu_data_out), .active(usb_active), .data_out(usb_data_out)
);
`else
// no USB host: hid.v still answers the helper
`endif

hid hid (
    .clk(clk32), .reset(por32),
    .data_in_strobe(mcu_hid_strobe), .data_in_start(mcu_start),
    .data_in(mcu_data_out),
`ifdef ST_HELPER_USB
    .data_out(hid_data_out_hid),
`else
    .data_out(hid_data_out),
`endif
    .db9_port(6'd0),
    .irq(hid_int), .iack(hid_iack),
    .mouse(hid_mouse), .keyboard(keyboard), .joystick(hid_joy)
);

// Image 4 = TOS ROM (read-only); image 0 = floppy A:. TOS wins if both request.
wire        sd_tos_busy = tos_sd_rd;
sd_card #(.CLK_DIV(3'd0)) sd_card (
    .rstn(!por32), .clk(clk32),
    .sdclk(sd_clk), .sdcmd(sd_cmd), .sddat(sd_dat),
    .data_strobe(mcu_sdc_strobe), .data_start(mcu_start),
    .data_in(mcu_data_out), .data_out(sdc_data_out),
    .image_size(sd_img_size), .image_mounted(sd_img_mounted),
    .irq(sdc_int), .iack(sdc_iack),
    .rstart({ 3'b000, tos_sd_rd, 3'b000, fdc_sd_rd & ~sd_tos_busy }),
    .wstart({ 7'b0000000, fdc_sd_wr & ~sd_tos_busy }),
    .rsector(sd_tos_busy ? tos_sd_lba : fdc_sd_lba),
    .idx_dbg(240'd0),
    .rsrc(),
    .rbusy(sd_busy), .sd_err(sd_err), .rdone(sd_done),
    .inbyte(sd_wr_data),
    .outen(sd_rd_byte_strobe), .outaddr(sd_byte_index), .outbyte(sd_rd_data)
);

// ==================================================================
// ========================= clock generation =======================
// ==================================================================

/*
Input clock: 50 Mhz
pf: 800.0 Mhz (IDIV 1, MDIV 16, ODIV 5/25/25/8/8)
Output0:
  Freq: 160.0 Mhz
  Phase: 0.0°
Output1:
  Freq: 32.0 Mhz
  Phase: 0.0°
Output2:
  Freq: 32.0 Mhz
  Phase: 338.4° (nearest step to 337.5° with ODIV 25)
Output3:
  Freq: 100.0 Mhz
  Phase: 0.0°
Output4:
  Freq: 100.0 Mhz
  Phase: 22.5°
*/
 
wire	   clk_pixel_x5; // pll_160m clkout0: 160 MHz (not used for HDMI)
wire	   clk_pixel;    // pll_160m clkout1: 32 MHz == clk32. NOT the 25.2 MHz HDMI clock.
wire	   clk_cpu030;   // 16 MHz 68030 clock, phase-locked to clk32
wire	   clk_cpu030_n; // clk_cpu030 at 180 degrees (WF68K30L falling-edge registers)
wire	   clk_hdmi;     // 25.2 MHz, CLKDIV/5 of gowin_pll_hdmi (scanout + hdmi_640)
wire	   clk_hdmi_x5;  // 126 MHz TMDS clock
wire	   hdmi_pll_lock;
pll_160m pll_hdmi (
               .clkout0(clk_pixel_x5),       // 160 MHz
               .clkout1(clk_pixel),          // 32 MHz
               .clkout2(O_sdram_clk),        // 32 MHz, shifted by 338,4°
               .clkout3(flash_clk),          // 100 MHz
`ifdef AE350_SERIAL
               .clkout4(mspi_clk_pll),       // 100 MHz, shifted by 22,5°
`elsif ST_HELPER
               .clkout4(mspi_clk_pll),       // 100 MHz, 22,5°: to the SCK pad mux
`else
               .clkout4(mspi_clk),           // 100 MHz, shifted by 22,5°
`endif
               .clkout5(clk_cpu030),         // 16 MHz, WF68K30L CPU clock
               .clkout6(clk_cpu030_n),       // 16 MHz, 180 deg: WF68K30L falling-edge registers
               .lock(pll_lock),
               .clkin(clk),
               .init_clk(clk_g),
               .init_rst(wd_init_rst[0])   // [F69]
	       );

assign clk32 = clk_pixel;   // the 32 Mhz system clock is the pixel clock

// ------------------------- DIAG status collection -------------------------
wire [19:0] diag_now, diag_ever;
wire        diag_vs_blink, diag_hs_blink, diag_fb_we;
wire [15:0] diag_word;
wire [191:0] diag_rows;
`ifdef DIAG_OVERLAY
diag_collect diag_collect (
    .clk            ( clk32               ),
    .st_hs_n        ( st_video_hs_n       ),
    .st_vs_n        ( st_video_vs_n       ),
    .st_de          ( st_video_de         ),
    .st_rgb         ( { st_video_r, st_video_g, st_video_b } ),
    .cpu_as_n       ( diag_flags[6]       ),
    .cpu_halted_n   ( diag_flags[7]       ),
    .rom_n          ( diag_flags[5]       ),
    .rom_idx        ( diag_rom_idx        ),
    .rom_data       ( diag_rom_data       ),
    .c030_run_async ( diag_030[0]         ),
    .c030_req       ( diag_030[1]         ),
    .c030_rom_fetch ( rom_fetch           ),
    .c030_dsack     ( diag_030[2]         ),
    .c030_berr      ( diag_030[3]         ),
    .st_resb        ( diag_flags[4]       ),
    .ram_ready      ( diag_flags[3]       ),
    .sd_ready       ( diag_flags[1]       ),
    .mcu_reset      ( diag_flags[0]       ),
    .mcu_ss_async   ( spi_io_ss           ),
    .pll_lock_async ( pll_lock            ),
    .fb_we          ( diag_fb_we          ),
    .now            ( diag_now            ),
    .ever           ( diag_ever           ),
    .vs_blink       ( diag_vs_blink       ),
    .hs_blink       ( diag_hs_blink       ),
    .rom_word0      ( diag_word           ),
    .led_030        ( diag_led_030        )
);
localparam DIAG_EN = 1;
localparam DIAG_ST = `DIAG_FB_SELFTEST;
// diag030c bit-bar rows (MSB = leftmost bar), see diag_overlay.v:
//   a: first BERR address A31:0
//   b: {got, FC2:0, RW, SIZE1:0, bad_space, $FF8201 byte, $FF8203 byte,
//       wr_hi, wr_mid, 6 unused}
//   c: A31:0 of the last bus cycle started by the 030
//   d: last-start FC/RW/SIZE, in-progress/hung, termination, IACK, CPU pins
//   e: bridge 68000-side state
//   f: {bus cycles started mod 256, live last program fetch A23:0}
`ifdef DIAG_PMMU
// [F76] PMMU overlay (cpu030_st_bridge.v DIAG_PMMU): rows a-e = PMMU page (TC/CRP/SRP or TT0/TT1/FAULT/PC/MMUSR+SSW),
// row f top byte = last exception vector.
assign diag_rows = { diag_trace, 24'd0 };
`else
assign diag_rows = { diag_trace[159:128],
                     diag_trace[167:160], diag_vbase[15:0], diag_vbase[23:16],
                     diag_trace[127:0] };
`endif
`else
assign diag_rows = 192'd0;
assign diag_now = 20'd0;  assign diag_ever = 20'd0;  assign diag_word = 16'd0;
assign diag_vs_blink = 1'b0;  assign diag_hs_blink = 1'b0;
localparam DIAG_EN = 0;
localparam DIAG_ST = 0;
`endif

// HDMI 640x480@60 (CEA VIC 1) from falcon_scanout, not the ST frame buffer.
// Own PLL: 50 MHz -> 126 MHz -> CLKDIV/5 = 25.2 MHz. pll_160m's clk_pixel is 32 MHz.
gowin_pll_hdmi pll_hdmi640 (
    .clkin    ( clk      ),
    .init_clk ( clk_g    ),
    .clkout0  ( clk_hdmi_x5 ),
    .lock     ( hdmi_pll_lock )
);

CLKDIV #(.DIV_MODE("5")) clkdiv_hdmi640 (
    .HCLKIN ( clk_hdmi_x5 ),
    .RESETN ( 1'b1        ),
    .CALIB  ( 1'b0        ),
    .CLKOUT ( clk_hdmi    )
);

reg [1:0] hdmi_lock_sync = 2'b00;
reg [7:0] hdmi_rst_cnt   = 8'd0;
always @(posedge clk_hdmi) begin
    hdmi_lock_sync <= { hdmi_lock_sync[0], hdmi_pll_lock };
    if (!hdmi_lock_sync[1])
        hdmi_rst_cnt <= 8'd0;
    else if (hdmi_rst_cnt != 8'hff)
        hdmi_rst_cnt <= hdmi_rst_cnt + 8'd1;
end
wire hdmi_pix_rst = (hdmi_rst_cnt != 8'hff);

// 48 kHz HDMI audio clock: 25.2 MHz / 525. Silent in v1 (YM stub later).
// Named hdmi_* so it does not collide with the I2S clk_audio / aclk_cnt above.
reg [9:0] hdmi_aclk_cnt  = 10'd0;
reg       hdmi_clk_audio = 1'b0;
always @(posedge clk_hdmi) begin
    if (hdmi_aclk_cnt == 10'd524) hdmi_aclk_cnt <= 10'd0;
    else                          hdmi_aclk_cnt <= hdmi_aclk_cnt + 10'd1;
    hdmi_clk_audio <= (hdmi_aclk_cnt < 10'd262);
end
wire [15:0] hdmi_audio [1:0];
assign hdmi_audio[0] = 16'h0000;
assign hdmi_audio[1] = 16'h0000;

wire [2:0] tmds;
wire       tmds_clock;
hdmi_640 #(
    .DVI_OUTPUT(1),
    .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16),
    .VENDOR_NAME( { "MiSTle", 16'd0} ),
    .PRODUCT_DESCRIPTION( {"Falcon030 v1  ", 16'd0} )
) u_hdmi (
    .clk_pixel_x5      ( clk_hdmi_x5  ),
    .clk_pixel         ( clk_hdmi     ),
    .clk_audio         ( hdmi_clk_audio ),
    .reset             ( hdmi_pix_rst ),
    .cx                ( hdmi_cx      ),
    .cy                ( hdmi_cy      ),
    .hsync             ( hdmi_hs      ),
    .vsync             ( hdmi_vs      ),
    .rgb               ( { hdmi_r, hdmi_g, hdmi_b } ),
    .audio_sample_word ( hdmi_audio   ),
    .tmds              ( tmds         ),
    .tmds_clock        ( tmds_clock   )
);

ELVDS_OBUF tmds_bufds [3:0] (
    .I  ( { tmds_clock, tmds }     ),
    .O  ( { tmds_clk_p, tmds_d_p } ),
    .OB ( { tmds_clk_n, tmds_d_n } )
);

`ifndef DIAG_HEARTBEAT
assign diag_go = 1'b0;   // [F77] no dump without the heartbeat's U15 arbitration
`endif
`ifdef DIAG_HEARTBEAT
// [F72] instance here, after diag_flags/por32/sth_ae_run are declared
cpu_heartbeat u_cpu_heartbeat ( .clk(clk32), .rst(por32 | ~sth_ae_run), .ae_tx(ae350_uart_tx),
    .flags(diag_flags), .c030(diag_030), .rom_idx(diag_rom_idx), .rom_data(diag_rom_data), .trace(diag_trace), .ext_busy(diag_dump[1]), .go_ext(diag_go), .own(hb_own), .tx(hb_tx) );
`endif

endmodule

// To match emacs with gw_ide default
// Local Variables:
// tab-width: 4
// End:

