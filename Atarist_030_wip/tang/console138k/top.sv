/*
    top.sv - atarist on tang console 138k toplevel

    This top level implements the default variant for tc138k
*/ 
`include "build_sel.vh"

`define GOWIN

// FalconFPGA stage 1: HDMI_TESTPATTERN disconnects the Atari core video from
// the HDMI output and instead drives a standalone 640x480@60 (VIC 1, 25.2 MHz)
// colour-bar test pattern from its own PLL (hdmi_testpattern_640.sv). The core
// (clocks, SDRAM, OSD, scandoubler, lcd_* outputs) keeps running unchanged.
// Stage 2: by default hdmi_tp now shows the ST video through a BSRAM frame
// buffer (ST_VIDEO parameter at the hdmi_tp instance; 0 = colour bars).
// Comment this line out to restore the original video2hdmi path.
`define HDMI_TESTPATTERN

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
);

// route BL616 debug uart via the twi signals through the FPGA to
// unused pins on PMOD1 (the middle one)
assign bl616_rx = 1'b0;          // from PMOD to BL616, nowadays unused
`ifdef AE350_SERIAL
assign uart_ext_tx = banner_busy ? banner_tx : ae350_uart_tx; // U15. PIN, then AE350.
`elsif ST_HELPER
// U15 (BL616 USB serial, 115200 8N1): fabric letters while the AE350 is in
// reset, the AE350's UART2 while it runs (st_helper_ctrl.v).
assign uart_ext_tx = sth_ae_run ? ae350_uart_tx : sth_fab_tx;
`else
assign uart_ext_tx = bl616_tx;   // desktop image
`endif

wire clk32;
wire pll_lock;
wire flash_clk;

// S0 is AA13, port reset_n, pull-up. A press after lock reloads the ST reset
// counter (the same path as the cold-start second pulse). Ignored until the
// arm counter fills, so a sample at config cannot hold the CPU in reset.
// S1 (user_n) stays unused.
reg [1:0]  s0_sync = 2'b11;
reg [15:0] s0_arm  = 16'd0;
always @(posedge clk) begin
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
    if (por) begin
        s1_sync <= 2'b11;
        s1_release <= 1'b0;
    end else begin
        s1_sync <= {s1_sync[0], user_n};
        if (s1_sync == 2'b00)
            s1_release <= 1'b1;
    end
end
wire por = !pll_lock;  // FalconFPGA: no BL616 jtagsel gating (stock BL616 firmware never drives it low; matches Nano 20K)

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
always @(posedge clk) begin
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
  .rst          ( por       ),			   
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
    if(por)
        audio_bit_cnt <= 5'd0;
    else 
        audio_bit_cnt <= audio_bit_cnt + 5'd1;
end

// generate i2s signals
assign i2s_bclk = clk_audio;
assign i2s_lrck = por?1'b0:audio_bit_cnt[4];
assign i2s_din = por?1'b0:audio[i2s_lrck][15-audio_bit_cnt[3:0]];
   
// FalconFPGA stage 2: raw ST video (clk32 domain) for the 640x480 frame buffer
wire       st_video_hs_n, st_video_vs_n, st_video_de;
wire [3:0] st_video_r, st_video_g, st_video_b;
wire [7:0]  diag_flags;
wire [16:0] diag_rom_idx;
wire [15:0] diag_rom_data;
wire [3:0]  diag_030;
wire [167:0] diag_trace;
wire [17:0] diag_vbase;

// Helper bring-up. DDR3 trains, then the AE350 is released and owns MSPI
// until it drives GPIO 0xA5, or 20 seconds pass. The ready bit is latched,
// the AE350 is put back in reset, and the 030 gets the flash for TOS.
wire        DDR3_MEMORY_CLK, DDR3_CLK_IN, DDR3_RW_CLK, DDR3_LOCK, DDR3_STOP;
wire        CORE_CLK, DDR_CLK, AHB_CLK, APB_CLK, RTC_CLK;
wire        ddr3_init_completed;
wire        ae350_flash_csn, ae350_flash_miso, ae350_flash_mosi;
wire        ae350_uart_tx;
wire        ae350_flash_clk, ae350_flash_holdn, ae350_flash_wpn;
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
    .clkin(clk), .init_clk(clk),
    .clkout0(DDR_CLK), .clkout1(CORE_CLK), .clkout2(AHB_CLK),
    .clkout3(APB_CLK), .clkout4(RTC_CLK)
);
gowin_pll_ddr3 u_gowin_pll_ddr3 (
    .clkin(clk), .init_clk(clk),
    .enclk0(1'b1), .enclk1(1'b1), .enclk2(DDR3_STOP),
    .clkout0(DDR3_CLK_IN), .clkout1(DDR3_RW_CLK),
    .clkout2(DDR3_MEMORY_CLK), .lock(DDR3_LOCK)
);
`ifdef ST_HELPER
// ST_HELPER: S0 resets the ST only. The helper runs from DDR3 and its flash
// has been handed to the ST, so a DDR3 reset would kill it for good. DDR3
// reset is released 20 ms after configuration, independent of S0.
key_debounce u_key_debounce_ddr3 (
    .out(ddr3_rstn), .in(1'b1), .clk(clk), .rstn(1'b1)
);
`else
key_debounce u_key_debounce_ddr3 (
    .out(ddr3_rstn), .in(reset_n), .clk(clk), .rstn(1'b1)
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
    .out(ae350_rstn_deb), .in(ddr3_init_sync[1]), .clk(clk), .rstn(1'b1)
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
    if (por) begin
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
    .rst         ( por                 ),
    .ddr3_init_a ( ddr3_init_completed ),
    .ae_gpio_a   ( ae350_gpio[7:0]     ),
    .ae_csn_a    ( ae350_flash_csn     ),
    .s1_n_a      ( user_n              ),
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
always @(posedge flash_clk or posedge por)
    if (por) sth_frel <= 2'b00;
    else     sth_frel <= {sth_frel[0], sth_st_release};
wire flash_reinit = ~sth_frel[1];
`else
// Desktop image. AE350 stays in reset and off the flash pins.
wire ae350_run = 1'b0;
wire flash_reinit = 1'b0;
wire helper_hold = 1'b0;
`endif
always @(posedge clk32) begin
    if (por) begin
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
assign mspi_cs   = sth_flash_to_st ? st_mspi_cs   : ae350_flash_csn;
assign mspi_clk  = sth_flash_to_st ? mspi_clk_pll : ae350_flash_clk;
assign mspi_di   = sth_flash_to_st ? (st_mspi_io_oe[0] ? st_mspi_io_o[0] : 1'bz)
                                   : ae350_flash_mosi;
assign mspi_do   = (sth_flash_to_st && st_mspi_io_oe[1]) ? st_mspi_io_o[1] : 1'bz;
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
    .rst         ( por             ),
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

misterynano misterynano (
  .reset ( s0_reset | helper_hold ), // S0 only; helper_hold is tied off
  .flash_reinit ( flash_reinit ),
  .flash_ready ( flash_ready ),
  .user  ( 1'b0), // !user_n ),

  // clock and power on reset from system
  .clk32 ( clk32 ),         // 32 Mhz system clock input
  .clk_cpu ( clk_cpu030 ),  // 8 Mhz 68030 clock (only used with CPU_030 in atarist.v)
  .clk_cpu_n ( clk_cpu030_n ), // the same at 180 degrees (68030 falling-edge registers)
  .flash_clk ( flash_clk ), // 100 Mhz flash clock
  .por   ( por ),           // True while not all PLLs locked

  .leds_n ( leds_int_n ),
  .rom_fetch ( rom_fetch ),
  .ws2812 ( ),

  // spi flash interface
`ifdef ST_HELPER
  // Pads are built above (boot-then-release mux)
  .mspi_cs    ( st_mspi_cs              ),
  .mspi_io_o  ( st_mspi_io_o            ),
  .mspi_io_oe ( st_mspi_io_oe           ),
  .mspi_io_i  ( { mspi_do, mspi_di }    ),
  .ext_io_cs    ( ext_io_cs    ),
  .ext_io_a     ( ext_io_a     ),
  .ext_io_rw    ( ext_io_rw    ),
  .ext_io_uds_n ( ext_io_uds_n ),
  .ext_io_lds_n ( ext_io_lds_n ),
  .ext_io_wdata ( ext_io_wdata ),
  .ext_io_rdata ( ext_io_rdata ),
  .ext_io_dtack ( ext_io_dtack ),
`elsif AE350_SERIAL
  // Flash pins belong to the AE350; keep the ST flash controller off them.
  .mspi_cs   ( nano_mspi_cs   ),
  .mspi_di   ( nano_mspi_di   ),
  .mspi_hold ( nano_mspi_hold ),
  .mspi_wp   ( nano_mspi_wp   ),
  .mspi_do   ( nano_mspi_do   ),
`else
  .mspi_cs   ( mspi_cs   ),
  .mspi_di   ( mspi_di   ),
  .mspi_hold ( mspi_hold ),
  .mspi_wp   ( mspi_wp   ),
  .mspi_do   ( mspi_do   ),
`endif

  // SDRAM
  .sdram_clk   ( ),
  .sdram_cke   ( ),
  .sdram_cs_n  ( O_sdram_cs_n   ), // chip select
  .sdram_cas_n ( O_sdram_cas_n  ), // columns address select
  .sdram_ras_n ( O_sdram_ras_n  ), // row address select
  .sdram_wen_n ( O_sdram_wen_n  ), // write enable
  .sdram_dq    ( sdram_dq       ), // 16 bit bidirectional data bus
  .sdram_addr  ( O_sdram_addr   ), // 13 bit multiplexed address bus
  .sdram_ba    ( O_sdram_ba     ), // two banks
  .sdram_dqm   ( sdram_dqm      ), // 16/4

  // generic IO, used for mouse/joystick/...
  .io          ( { 3'b111, ~ds1_p1 } ),

  // mcu interface
  .mcu_sclk ( spi_io_clk  ),
  .mcu_csn  ( spi_io_ss   ),
  .mcu_miso ( spi_io_dout ), // from FPGA to MCU
  .mcu_mosi ( spi_io_din  ), // from MCU to FPGA
  .mcu_intn ( spi_intn    ),

  // parallel port and MIDI are not implemented
		   
  // SD card slot
  .sd_clk ( sd_clk ),
  .sd_cmd ( sd_cmd ), // MOSI
  .sd_dat ( sd_dat ), // 0: MISO

  .vreset ( vreset ),
  .vmode  ( vmode  ),
  .screen ( screen ),
	   
  // scandoubled digital video to be
  // used with lcds
  .lcd_clk  ( lcd_clk),
  .lcd_hs_n ( lcd_hs),
  .lcd_vs_n ( lcd_vs),
  .lcd_de   ( lcd_en),
  .lcd_r    ( lcd_r ),
  .lcd_g    ( lcd_g ),
  .lcd_b    ( lcd_b ),

  // FalconFPGA stage 2: raw ST video (no OSD) for hdmi_tp's frame buffer
  .st_video_hs_n ( st_video_hs_n ),
  .st_video_vs_n ( st_video_vs_n ),
  .st_video_de   ( st_video_de   ),
  .st_video_r    ( st_video_r    ),
  .st_video_g    ( st_video_g    ),
  .st_video_b    ( st_video_b    ),

  // FalconFPGA DIAG: raw status for the overlay (unused in the normal build)
  .diag_flags    ( diag_flags    ),
  .diag_rom_idx  ( diag_rom_idx  ),
  .diag_rom_data ( diag_rom_data ),
  .diag_030      ( diag_030      ),
  .diag_trace    ( diag_trace    ),
  .diag_vbase    ( diag_vbase    ),

  // digital 16 bit audio output
  .audio ( audio )
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
 
wire	   clk_pixel_x5;
wire	   clk_pixel; 
wire	   clk_cpu030;   // Atarist_030_wip: 16 MHz 68030 clock, phase-locked to clk32
wire	   clk_cpu030_n; // clk_cpu030 at 180 degrees (global clock for the 68030's falling-edge registers)
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
               .init_clk(clk)
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
assign diag_rows = { diag_trace[159:128],
                     diag_trace[167:160], diag_vbase[15:0], diag_vbase[17:16], 6'd0,
                     diag_trace[127:0] };
`else
assign diag_rows = 192'd0;
assign diag_now = 20'd0;  assign diag_ever = 20'd0;  assign diag_word = 16'd0;
assign diag_vs_blink = 1'b0;  assign diag_hs_blink = 1'b0;
localparam DIAG_EN = 0;
localparam DIAG_ST = 0;
`endif

`ifdef HDMI_TESTPATTERN
// standalone 640x480@60 output; 50 MHz -> 126 MHz PLL -> CLKDIV/5
// DVI_OUTPUT: 1 = plain DVI (no data islands/guard bands, no audio), for the
//                 monitor on its DVI input via a DVI-to-HDMI cable (default)
//             0 = full HDMI (VIC 1 InfoFrames + 1 kHz test tone), for the TV
// ST_VIDEO:   1 = Atari ST video via the BSRAM frame buffer (stage 2, default,
//                 no OSD, no ST audio)
//             0 = colour bars (stage 1)
hdmi_testpattern_640 #(
    .DVI_OUTPUT ( 1 ),            // <-- set to 0 for HDMI mode
    .ST_VIDEO   ( 1 ),            // <-- set to 0 for the colour bars
    .DIAG_OVERLAY ( DIAG_EN ),    // set by `define DIAG_OVERLAY above
    .FB_SELFTEST  ( DIAG_ST )     // set by DIAG_FB_SELFTEST above
) hdmi_tp (
    .clk        ( clk        ),   // 50 MHz board clock
    .hdmi_lock  (            ),

    // DIAG overlay status (all 0 in the normal build)
    .diag_now      ( diag_now      ),
    .diag_ever     ( diag_ever     ),
    .diag_vs_blink ( diag_vs_blink ),
    .diag_hs_blink ( diag_hs_blink ),
    .diag_word     ( diag_word     ),
    .diag_rows     ( diag_rows     ),
    .diag_fb_we    ( diag_fb_we    ),

    // raw ST video from the core (stage 2)
    .clk32      ( clk32         ),
    .st_hs_n    ( st_video_hs_n ),
    .st_vs_n    ( st_video_vs_n ),
    .st_de      ( st_video_de   ),
    .st_r       ( st_video_r    ),
    .st_g       ( st_video_g    ),
    .st_b       ( st_video_b    ),

    .tmds_clk_n ( tmds_clk_n ),
    .tmds_clk_p ( tmds_clk_p ),
    .tmds_d_n   ( tmds_d_n   ),
    .tmds_d_p   ( tmds_d_p   )
);
`else
video2hdmi #(.PIXEL_CLOCK(32_000_000)) video2hdmi (
    .clk_pixel_x5 ( clk_pixel_x5  ),      // hdmi clock
    .clk_pixel    ( clk_pixel     ),      // pixel clock

    .vreset ( vreset ),
    .vmode ( vmode ),
    .screen ( screen ),

    .r( lcd_r ),
    .g( lcd_g ),
    .b( lcd_b ),
    .audio ( audio ),
    
    // tdms to be used with hdmi or dvi
    .tmds_clk_n ( tmds_clk_n ),
    .tmds_clk_p ( tmds_clk_p ),
    .tmds_d_n   ( tmds_d_n   ),
    .tmds_d_p   ( tmds_d_p   )
);
`endif

endmodule

// To match emacs with gw_ide default
// Local Variables:
// tab-width: 4
// End:

