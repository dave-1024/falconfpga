// falcon_soc.v - FAL_01: Falcon030 fabric (CPU, bus, SDRAM arbiter, scanout, TOS loader,
//                MFP, ACIAs, IKBD, floppy DMA)
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Glue for falcon_top.sv. clk_32 and clk_cpu are phase-locked (pll_160m, 32/16 MHz).
// clk_pixel is the 25.2 MHz HDMI clock (gowin_pll_hdmi). The TOS loader holds
// cpu_reset until the 512K image has been written to SDRAM $E00000. NVRAM PRESET
// defaults to 0 (Hybrid stock). st_rd2 is used only by the scanout.
// MFP/ACIA/FDC run on clk_32 with the ST core's enables; falcon_pbus holds a
// 68000-style select so each access is seen once (MFP UDR / ACIA RDR).
module falcon_soc (
    input  wire        clk_32,
    input  wire        clk_cpu,
    input  wire        clk_cpu_n,
    input  wire        clk_pixel,
    input  wire        por,              // async/sync reset, clk_32 domain (includes helper_hold)
    input  wire        loader_reset,     // por32 only: do not hold the loader with helper_hold
    input  wire        user_reset,       // helper OSD reset (CPU/chipset only; TOS stays in SDRAM)
    // sdram.v chip pins (16-bit)
    output wire        sd_clk, sd_cke, sd_cs, sd_we, sd_ras, sd_cas,
    inout  wire [31:0] sd_data,
    output wire [12:0] sd_addr,
    output wire [3:0]  sd_dqm,
    output wire [1:0]  sd_ba,
    output wire        ram_ready,
    // TOS loader <-> helper SD image slot 4
    input  wire        tos_img_mounted,
    input  wire [31:0] tos_img_size,
    output wire [31:0] tos_sd_lba,
    output wire        tos_sd_rd,
    input  wire        tos_sd_ack,
    input  wire [8:0]  tos_sd_buff_addr,
    input  wire [7:0]  tos_sd_dout,
    input  wire        tos_sd_dout_strobe,
    output wire        tos_err,
    output wire        cpu_reset,        // 1 while the loader runs
    // Floppy A: <-> helper SD image slot 0
    input  wire        fdc_img_mounted,
    input  wire [31:0] fdc_img_size,
    input  wire        fdc_img_wp,
    output wire [31:0] fdc_sd_lba,
    output wire        fdc_sd_rd,
    output wire        fdc_sd_wr,
    input  wire        fdc_sd_ack,
    input  wire        fdc_sd_err,
    input  wire [8:0]  fdc_sd_buff_addr,
    input  wire [7:0]  fdc_sd_dout,
    output wire [7:0]  fdc_sd_din,
    input  wire        fdc_sd_dout_strobe,
    // IKBD matrix + joystick/mouse (helper HID, clk_32)
    output wire [14:0] keyboard_matrix_out,
    input  wire [7:0]  keyboard_matrix_in,
    input  wire [5:0]  joy0,
    input  wire [4:0]  joy1,
    // HDMI 640x480 (clk_pixel)
    output wire [9:0]  cx, cy,
    output wire        hsync, vsync, de,
    output wire [7:0]  vr, vg, vb,
    output wire        vbl, hbl,
    output wire        scan_underrun,
    output wire        cpu_halted_n
);
    wire        mem_req, mem_we, mem_ack;
    wire [23:1] mem_a;
    wire [1:0]  mem_be;
    wire [15:0] mem_wdata, mem_rdata;

    wire        ld_req, ld_ack;
    wire [23:1] ld_a;
    wire [15:0] ld_d;

    wire        vid_req, vid_ack, vid_rd2;
    wire [23:1] vid_a;
    wire [15:0] vid_q, vid_q2;

    wire        dma_req, dma_we, dma_ack;
    wire [23:1] dma_a;
    wire [15:0] dma_d, dma_q;

    wire        sd_cs_i, sd_we_i, sd_refresh, sd_ecs, sd_rd2;
    wire [21:0] sd_waddr;
    wire [1:0]  sd_ds, sd_st_ba;
    wire [15:0] sd_din, sd_dout, sd_dout2;

    wire        core_reset = por | cpu_reset | user_reset;

    // loader and CPU share the lowest arbiter port: loader only while cpu_reset
    wire        cpu_req  = cpu_reset ? 1'b0 : mem_req;
    wire        use_ld   = cpu_reset & ld_req;

    falcon_sdram_arb arb (
        .clk(clk_32), .reset(por), .ram_ready(ram_ready),
        .sd_cs(sd_cs_i), .sd_we(sd_we_i), .sd_refresh(sd_refresh), .sd_ecs(sd_ecs),
        .sd_addr(sd_waddr), .sd_ds(sd_ds), .sd_din(sd_din), .sd_dout(sd_dout),
        .sd_dout2(sd_dout2), .sd_rd2(sd_rd2), .sd_ba(sd_st_ba),
        .vid_req(vid_req), .vid_a(vid_a), .vid_ack(vid_ack), .vid_q(vid_q), .vid_q2(vid_q2),
        .dma_req(dma_req), .dma_we(dma_we), .dma_a(dma_a), .dma_d(dma_d), .dma_ack(dma_ack), .dma_q(dma_q),
        .ld_req(use_ld), .ld_a(ld_a), .ld_d(ld_d), .ld_ack(ld_ack),
        .cpu_req(cpu_req), .cpu_a(mem_a), .cpu_we(mem_we), .cpu_be(mem_be),
        .cpu_d(mem_wdata), .cpu_ack(mem_ack), .cpu_q(mem_rdata)
    );

    sdram sdram (
        .clk(clk_32), .reset_n(~por), .ready(ram_ready),
        .sd_clk(sd_clk), .sd_cke(sd_cke), .sd_data(sd_data), .sd_addr(sd_addr),
        .sd_dqm(sd_dqm), .sd_ba(sd_ba), .sd_cs(sd_cs), .sd_we(sd_we), .sd_ras(sd_ras), .sd_cas(sd_cas),
        .refresh(sd_refresh), .din(sd_din), .dout(sd_dout), .dout2(sd_dout2),
        .addr(sd_waddr), .ds(sd_ds), .cs(sd_cs_i), .ecs(sd_ecs), .we(sd_we_i),
        .zmask(1'b0), .st_ba(sd_st_ba), .st_rd2(sd_rd2)
    );

    // ---- clk_32 enables, same idea as atarist.v (no GSTMCU) ----
    reg [1:0] div8;
    reg [2:0] div4;
    always @(posedge clk_32) begin
        if (por) begin div8 <= 2'd0; div4 <= 3'd0; end
        else begin
            div8 <= div8 + 2'd1;
            div4 <= div4 + 3'd1;
        end
    end
    wire clk8_en = (div8 == 2'd0);   // 8 MHz enable
    wire mhz4_en = (div4 == 3'd0);   // 4 MHz enable (MFP register clock)

    // 2.4576 MHz MFP timer clock. Board clk_32 is 32.000 MHz exact (PLL).
    localparam SYSTEM_CLOCK = 32'd32_000_000;
    localparam MFP_CLOCK    = 32'd2_457_600;
    reg [31:0] clk_cnt_mfp;
    reg        clk_mfp_en;
    always @(posedge clk_32) begin
        if (por) begin
            clk_cnt_mfp <= 32'd0;
            clk_mfp_en  <= 1'b0;
        end else if (clk_cnt_mfp < SYSTEM_CLOCK) begin
            clk_cnt_mfp <= clk_cnt_mfp + MFP_CLOCK;
            clk_mfp_en  <= 1'b0;
        end else begin
            clk_cnt_mfp <= clk_cnt_mfp - SYSTEM_CLOCK + MFP_CLOCK;
            clk_mfp_en  <= 1'b1;
        end
    end

    wire        p_sel_mfp, p_sel_acia, p_sel_dma, p_sel_dmaaddr, p_iack_mfp;
    wire [15:1] p_a;
    wire        p_rw;
    wire [15:0] p_wdata;
    wire [15:0] p_rdata;
    wire        p_done;
    wire [7:0]  mfp_vector;
    wire        mfp_dtack, mfp_irq;
    wire [7:0]  ym_porta;

    wire [23:0] fb_base, vcount;
    wire [3:0]  planes;
    wire        hdbl, vdbl;
    wire [9:0]  height;
    wire [11:0] linebytes;
    wire [11:0] st_pal_rd;
    wire [3:0]  st_pal_idx;
    wire [7:0]  fpal_wa;
    wire [17:0] fpal_wd;
    wire        fpal_we, stpal_we;
    wire [3:0]  stpal_wa;
    wire [11:0] stpal_wd;

    falcon_core core (
        .clk_cpu(clk_cpu), .clk_cpu_n(clk_cpu_n), .reset(core_reset),
        .mem_req(mem_req), .mem_a(mem_a), .mem_we(mem_we), .mem_be(mem_be),
        .mem_wdata(mem_wdata), .mem_ack(mem_ack), .mem_rdata(mem_rdata),
        .p_sel_mfp(p_sel_mfp), .p_sel_acia(p_sel_acia), .p_sel_dma(p_sel_dma), .p_sel_dmaaddr(p_sel_dmaaddr),
        .p_a(p_a), .p_rw(p_rw), .p_wdata(p_wdata), .p_rdata(p_rdata), .p_done(p_done),
        .p_iack_mfp(p_iack_mfp), .mfp_vector(mfp_vector), .mfp_dtack(mfp_dtack),
        .mfp_irq(mfp_irq), .vbl(vbl), .hbl(hbl),
        .vcount(vcount), .fb_base(fb_base), .planes(planes), .hdbl(hdbl), .vdbl(vdbl),
        .height(height), .linebytes(linebytes),
        .st_pal_idx(st_pal_idx), .st_pal_rd(st_pal_rd),
        .fpal_wa(fpal_wa), .fpal_wd(fpal_wd), .fpal_we(fpal_we),
        .stpal_we(stpal_we), .stpal_wa(stpal_wa), .stpal_wd(stpal_wd),
        .ym_porta(ym_porta), .fdc_hd(), .cpu_halted_n(cpu_halted_n)
    );

    // ---- peripheral sub-bus (clk_32) ----
    // MFP_CLK=24 / DMA_CLK=16: enough 4/8 MHz enables for dtack and the dma.v edge.
    wire        mfp_cs, mfp_ds_n, acia_cs, dma_cs, acia_E;
    wire [7:0]  mfp_d, acia_d;
    wire [15:0] fdc_cpu_d;
    falcon_pbus #(.MFP_CLK(24), .DMA_CLK(16)) pbus (
        .clk_32(clk_32), .reset(por | user_reset),
        .sel_mfp(p_sel_mfp), .sel_acia(p_sel_acia), .sel_dma(p_sel_dma), .sel_addr(p_sel_dmaaddr),
        .mfp_d(mfp_d), .acia_d(acia_d), .dma_d(fdc_cpu_d),
        .mfp_cs(mfp_cs), .mfp_ds_n(mfp_ds_n), .acia_cs(acia_cs), .dma_cs(dma_cs),
        .E(acia_E), .rdata(p_rdata), .done(p_done)
    );

    reg dma_cs_d;
    always @(posedge clk_32) dma_cs_d <= dma_cs;
    wire dma_wr_stb = dma_cs && !dma_cs_d && !p_rw;

    wire fdc_irq;
    falcon_fdc fdc (
        .clk_32(clk_32), .clk8_en(clk8_en), .reset(por | user_reset),
        .sel_dma(dma_cs && p_sel_dma), .sel_addr(dma_cs && p_sel_dmaaddr),
        .a(p_a[3:1]), .rw(p_rw), .wr_stb(dma_wr_stb), .din(p_wdata), .dout(fdc_cpu_d),
        .irq(fdc_irq), .ym_porta(ym_porta),
        .ram_req(dma_req), .ram_we(dma_we), .ram_a(dma_a), .ram_wdata(dma_d),
        .ram_ack(dma_ack), .ram_rdata(dma_q),
        .img_mounted(fdc_img_mounted), .img_size(fdc_img_size), .img_wp(fdc_img_wp),
        .sd_lba(fdc_sd_lba), .sd_rd(fdc_sd_rd), .sd_wr(fdc_sd_wr), .sd_ack(fdc_sd_ack),
        .sd_err(fdc_sd_err), .sd_buff_addr(fdc_sd_buff_addr), .sd_dout(fdc_sd_dout),
        .sd_din(fdc_sd_din), .sd_dout_strobe(fdc_sd_dout_strobe)
    );

    wire        kbd_acia_irq, midi_acia_irq;
    wire [7:0]  kbd_acia_d, midi_acia_d;
    wire        ikbd_tx, ikbd_rx;
    wire        acia_irq = kbd_acia_irq | midi_acia_irq;
    assign acia_d = p_a[2] ? midi_acia_d : kbd_acia_d;

    ikbd #(.DIV(4)) ikbd (
        .clk(clk_32), .res(por | user_reset),
        .tx(ikbd_tx), .rx(ikbd_rx),
        .matrix_out(keyboard_matrix_out), .matrix_in(keyboard_matrix_in),
        .caps_lock(),
        .joystick0({joy0[5:4], joy0[0], joy0[1], joy0[2], joy0[3]}),
        .joystick1({joy1[4], joy1[0], joy1[1], joy1[2], joy1[3]})
    );

    acia #(.INPUT_FILTER(0)) kbd_acia (
        .clk(clk_32), .E(acia_E), .reset(por | user_reset),
        .din(p_wdata[15:8]), .sel(acia_cs && !p_a[2]), .rs(p_a[1]), .rw(p_rw),
        .dout(kbd_acia_d), .irq(kbd_acia_irq),
        .rxtxclk_sel(1'b0), .dout_strobe(),
        .rx(ikbd_tx), .tx(ikbd_rx)
    );

    acia midi_acia (
        .clk(clk_32), .E(acia_E), .reset(por | user_reset),
        .din(p_wdata[15:8]), .sel(acia_cs && p_a[2]), .rs(p_a[1]), .rw(p_rw),
        .dout(midi_acia_d), .irq(midi_acia_irq),
        .rxtxclk_sel(1'b0), .dout_strobe(),
        .rx(1'b1), .tx()
    );

    // GPIP: Hybrid030 / DESIGN.md. GPIP7 reads 1 (no sound DMA). GPIP5 = !FDC IRQ
    // (IDE later shares it). GPIP4 = !ACIA IRQ. Blitter stub: no done IRQ (1).
    wire [7:0] mfp_gpio_in = {1'b1, 1'b1, !fdc_irq, !acia_irq, 1'b1, 2'b11, 1'b1};
    wire       mfp_int;
    assign mfp_irq = mfp_int;
    assign mfp_vector = mfp_d;   // during IACK, mfp.v puts the vector on dout

    mfp mfp (
        .clk(clk_32), .clk_en(mhz4_en), .reset(por | user_reset),
        .din(p_wdata[7:0]), .sel(mfp_cs), .addr(p_a[5:1]), .ds(mfp_ds_n), .rw(p_rw),
        .dout(mfp_d), .irq(mfp_int), .iack(p_iack_mfp), .dtack(mfp_dtack),
        .serial_status_out(),
        .serial_data_out_available(), .serial_strobe_out(1'b0), .serial_data_out(),
        .serial_data_in_free(), .serial_strobe_in(1'b0), .serial_data_in(8'd0),
        .clk_ext(clk_mfp_en), .t_i({hbl, 1'b0}), .i(mfp_gpio_in)
    );

    falcon_scanout scanout (
        .clk_32(clk_32), .clk_pixel(clk_pixel), .reset(por),
        .fb_base(fb_base), .planes(planes), .hdbl(hdbl), .vdbl(vdbl),
        .height(height), .linebytes(linebytes),
        .stpal_we(stpal_we), .stpal_wa(stpal_wa), .stpal_wd(stpal_wd),
        .fpal_we(fpal_we), .fpal_wa(fpal_wa), .fpal_wd(fpal_wd),
        .ram_req(vid_req), .ram_rd2(vid_rd2), .ram_a(vid_a),
        .ram_ack(vid_ack), .ram_q(vid_q), .ram_q2(vid_q2),
        .cx(cx), .cy(cy), .hsync(hsync), .vsync(vsync), .de(de),
        .vr(scan_r), .vg(scan_g), .vb(scan_b),
        .vbl(vbl), .hbl(hbl), .vcount(vcount), .underrun(scan_underrun)
    );

    // Colour bars + a bottom progress strip while the TOS loader holds the
    // CPU in reset (or on a bad image). Separates "HDMI is up but TOS has
    // not started" from "no TMDS". 85ca498 board grabs were a 6 kB black
    // 1920x1080 frame; the Hagibis dongle does not report the source size.
    wire [7:0] scan_r, scan_g, scan_b;
    wire       ld_busy;
    wire [9:0] ld_sect;
    reg  [1:0] rst_s, busy_s, err_s;
    reg  [9:0] sect_s, sect_p;
    always @(posedge clk_pixel) begin
        rst_s  <= { rst_s[0],  cpu_reset };
        busy_s <= { busy_s[0], ld_busy   };
        err_s  <= { err_s[0],  tos_err   };
        sect_s <= ld_sect;
        sect_p <= sect_s;
    end
    // 8 CEA-style 75% bars across 640 px (cx[9:7]).
    reg [23:0] bar_rgb;
    always @(*) begin
        case (cx[9:7])
            3'd0: bar_rgb = 24'hC0C0C0;
            3'd1: bar_rgb = 24'hC0C000;
            3'd2: bar_rgb = 24'h00C0C0;
            3'd3: bar_rgb = 24'h00C000;
            3'd4: bar_rgb = 24'hC000C0;
            3'd5: bar_rgb = 24'hC00000;
            3'd6: bar_rgb = 24'h0000C0;
            default: bar_rgb = 24'h000000;
        endcase
    end
    // progress width = sect * 640 / 1024 = sect * 5 / 8 (0..639)
    wire [12:0] prog_x = { 3'd0, sect_p } * 13'd5 >> 3;
    wire        in_tray  = rst_s[1] && (cy >= 10'd464);
    wire        in_prog  = in_tray && busy_s[1] && ({3'd0, cx} < prog_x);
    wire        show_bar = rst_s[1] | err_s[1];
    assign vr = !show_bar ? scan_r :
                err_s[1]  ? 8'hC0 :
                in_prog   ? 8'hFF :
                in_tray   ? 8'h20 : bar_rgb[23:16];
    assign vg = !show_bar ? scan_g :
                err_s[1]  ? 8'h00 :
                in_prog   ? 8'hC0 :
                in_tray   ? 8'h20 : bar_rgb[15:8];
    assign vb = !show_bar ? scan_b :
                err_s[1]  ? 8'h00 :
                in_prog   ? 8'h00 :
                in_tray   ? 8'h40 : bar_rgb[7:0];
    // vid_rd2 is produced by the scanout and also generated by the arbiter from the
    // address; the arbiter's sd_rd2 is what sdram.v sees.

    tos_loader loader (
        .clk(clk_32), .reset(loader_reset),
        .img_mounted(tos_img_mounted), .img_size(tos_img_size),
        .sd_lba(tos_sd_lba), .sd_rd(tos_sd_rd), .sd_ack(tos_sd_ack),
        .sd_buff_addr(tos_sd_buff_addr), .sd_dout(tos_sd_dout), .sd_dout_strobe(tos_sd_dout_strobe),
        .ram_req(ld_req), .ram_a(ld_a), .ram_wdata(ld_d), .ram_ack(ld_ack),
        .cpu_reset(cpu_reset), .err(tos_err), .busy(ld_busy), .sect(ld_sect)
    );
endmodule
