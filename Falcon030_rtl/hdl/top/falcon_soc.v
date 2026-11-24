// falcon_soc.v - FAL_01: Falcon030 fabric (CPU, bus, SDRAM arbiter, scanout, TOS loader)
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Glue for falcon_top.sv. clk_32 and clk_cpu are phase-locked (pll_160m, 32/16 MHz).
// clk_pixel is the 25.2 MHz HDMI clock (gowin_pll_hdmi). The TOS loader holds
// cpu_reset until the 512K image has been written to SDRAM $E00000. NVRAM PRESET
// defaults to 0 (Hybrid stock). st_rd2 is used only by the scanout.
module falcon_soc (
    input  wire        clk_32,
    input  wire        clk_cpu,
    input  wire        clk_cpu_n,
    input  wire        clk_pixel,
    input  wire        por,              // async/sync reset, clk_32 domain
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

    wire        sd_cs_i, sd_we_i, sd_refresh, sd_ecs, sd_rd2;
    wire [21:0] sd_waddr;
    wire [1:0]  sd_ds, sd_st_ba;
    wire [15:0] sd_din, sd_dout, sd_dout2;

    wire        core_reset = por | cpu_reset;

    // loader and CPU share the lowest arbiter port: loader only while cpu_reset
    wire        cpu_req  = cpu_reset ? 1'b0 : mem_req;
    wire        use_ld   = cpu_reset & ld_req;

    falcon_sdram_arb arb (
        .clk(clk_32), .reset(por), .ram_ready(ram_ready),
        .sd_cs(sd_cs_i), .sd_we(sd_we_i), .sd_refresh(sd_refresh), .sd_ecs(sd_ecs),
        .sd_addr(sd_waddr), .sd_ds(sd_ds), .sd_din(sd_din), .sd_dout(sd_dout),
        .sd_dout2(sd_dout2), .sd_rd2(sd_rd2), .sd_ba(sd_st_ba),
        .vid_req(vid_req), .vid_a(vid_a), .vid_ack(vid_ack), .vid_q(vid_q), .vid_q2(vid_q2),
        .dma_req(1'b0), .dma_we(1'b0), .dma_a(23'd0), .dma_d(16'd0), .dma_ack(), .dma_q(),
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

    wire [15:0] p_rdata = 16'hFFFF;
    wire        p_done  = 1'b1;          // no clk_32 peripherals in this cut (MFP/ACIA/FDC: NEXT)
    wire [7:0]  mfp_vector = 8'h00;
    wire        mfp_dtack = 1'b0, mfp_irq = 1'b0;

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
        .p_sel_mfp(), .p_sel_acia(), .p_sel_dma(), .p_sel_dmaaddr(),
        .p_a(), .p_rw(), .p_wdata(), .p_rdata(p_rdata), .p_done(p_done),
        .p_iack_mfp(), .mfp_vector(mfp_vector), .mfp_dtack(mfp_dtack),
        .mfp_irq(mfp_irq), .vbl(vbl), .hbl(hbl),
        .vcount(vcount), .fb_base(fb_base), .planes(planes), .hdbl(hdbl), .vdbl(vdbl),
        .height(height), .linebytes(linebytes),
        .st_pal_idx(st_pal_idx), .st_pal_rd(st_pal_rd),
        .fpal_wa(fpal_wa), .fpal_wd(fpal_wd), .fpal_we(fpal_we),
        .stpal_we(stpal_we), .stpal_wa(stpal_wa), .stpal_wd(stpal_wd),
        .ym_porta(), .fdc_hd(), .cpu_halted_n(cpu_halted_n)
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
        .vr(vr), .vg(vg), .vb(vb),
        .vbl(vbl), .hbl(hbl), .vcount(vcount), .underrun(scan_underrun)
    );
    // vid_rd2 is produced by the scanout and also generated by the arbiter from the
    // address; the arbiter's sd_rd2 is what sdram.v sees.

    tos_loader loader (
        .clk(clk_32), .reset(por),
        .img_mounted(tos_img_mounted), .img_size(tos_img_size),
        .sd_lba(tos_sd_lba), .sd_rd(tos_sd_rd), .sd_ack(tos_sd_ack),
        .sd_buff_addr(tos_sd_buff_addr), .sd_dout(tos_sd_dout), .sd_dout_strobe(tos_sd_dout_strobe),
        .ram_req(ld_req), .ram_a(ld_a), .ram_wdata(ld_d), .ram_ack(ld_ack),
        .cpu_reset(cpu_reset), .err(tos_err)
    );
endmodule
