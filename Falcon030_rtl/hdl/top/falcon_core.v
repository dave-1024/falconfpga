// falcon_core.v - FAL_01: Falcon030 core, clk_cpu domain: WF68K30L + falcon_bus + IO block,
//                 NVRAM, YM stub, VIDEL registers. clk_32 peripherals (MFP, ACIAs, floppy) and
//                 the SDRAM/scanout sit outside on the ports below (falcon_pbus.v, arbiter: NEXT).
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The CPU is the shared WF68K30L (Atarist_030_wip/hdl/cpu030/wf68k30L_*.vhd, by path) with the
// same generics as the ST build's board bitstreams (CLK_N_EXT 1, FAST_HANDOFF 1). No ST bridge.
module falcon_core (
    input  wire        clk_cpu,
    input  wire        clk_cpu_n,
    input  wire        reset,           // held by the TOS loader until the ROM copy is in SDRAM
    // SDRAM CPU word port (to the arbiter)
    output wire        mem_req,
    output wire [23:1] mem_a,
    output wire        mem_we,
    output wire [1:0]  mem_be,
    output wire [15:0] mem_wdata,
    input  wire        mem_ack,
    input  wire [15:0] mem_rdata,
    // clk_32 peripheral sub-bus (MFP, ACIAs, floppy DMA/FDC)
    output wire        p_sel_mfp, p_sel_acia, p_sel_dma, p_sel_dmaaddr,
    output wire [15:1] p_a,
    output wire        p_rw,
    output wire [15:0] p_wdata,
    input  wire [7:0]  p_mfp_d, p_acia_d,
    input  wire [15:0] p_dma_d,
    output wire        p_iack_mfp,
    input  wire [7:0]  mfp_vector,
    input  wire        mfp_dtack,
    input  wire        mfp_irq,          // level 6
    input  wire        vbl, hbl,         // level 4 / level 2 autovector
    // video
    input  wire [23:0] vcount,
    output wire [23:0] fb_base,
    output wire [3:0]  planes,
    output wire        hdbl, vdbl,
    output wire [9:0]  height,
    output wire [11:0] linebytes,
    input  wire [3:0]  st_pal_idx,
    output wire [11:0] st_pal_rd,
    output wire [7:0]  fpal_wa,
    output wire [17:0] fpal_wd,
    output wire        fpal_we,
    output wire [7:0]  ym_porta,
    output wire [1:0]  fdc_hd,
    output wire        cpu_halted_n
);
    wire [31:0] cpu_a, cpu_dout, cpu_din;
    wire        cpu_as_n, cpu_ds_n, cpu_rw, cpu_rmc_n, cpu_reset_out;
    wire [1:0]  cpu_siz, cpu_dsack_n;
    wire [2:0]  cpu_fc;
    wire        cpu_berr_n, cpu_avec_n;
    reg  [2:0]  ipl_r;
    // cache inhibit: IO, IDE, the vector mirror and ST-RAM (DMA'd by the floppy, no snooping: the ST build's rule);
    // only the TOS ROM copy at $E00000-$E7FFFF is cachable
    wire cpu_ciin_n = !(cpu_a[23:15] == 9'h1FF || cpu_a[23:20] == 4'hF || cpu_a[23:3] == 21'd0 || cpu_a[23:21] != 3'b111);
    always @(posedge clk_cpu) ipl_r <= mfp_irq ? 3'b001 : vbl ? 3'b011 : hbl ? 3'b101 : 3'b111;

    WF68K30L_TOP #(.CLK_N_EXT(1), .CACHES(0), .WA_ADR_HI(1), .FAST_HANDOFF(1)) cpu (
        .CLK(clk_cpu), .CLK_N(clk_cpu_n), .ADR_OUT(cpu_a), .DATA_IN(cpu_din), .DATA_OUT(cpu_dout), .DATA_EN(),
        .BERRn(cpu_berr_n), .RESET_INn(!reset), .RESET_OUT(cpu_reset_out), .HALT_INn(!reset), .HALT_OUTn(cpu_halted_n),
        .FC_OUT(cpu_fc), .AVECn(cpu_avec_n), .IPLn(ipl_r), .IPENDn(), .DSACKn(cpu_dsack_n), .SIZE(cpu_siz),
        .ASn(cpu_as_n), .RWn(cpu_rw), .RMCn(cpu_rmc_n), .DSn(cpu_ds_n), .ECSn(), .OCSn(), .DBENn(), .BUS_EN(),
        .STERMn(1'b1), .BRn(1'b1), .BGn(), .BGACKn(1'b1),
        .CIINn(cpu_ciin_n), .MMU_ON(), .CDISn(1'b1), .CBACKn(1'b1), .CBREQn(), .CIOUTn());

    wire io_cyc, io_uds, io_lds, io_wr; wire [15:1] io_a; wire [15:0] io_wdata, io_rdata;
    falcon_bus bus (
        .clk(clk_cpu), .reset(reset),
        .cpu_a(cpu_a), .cpu_dout(cpu_dout), .cpu_din(cpu_din), .cpu_as_n(cpu_as_n), .cpu_ds_n(cpu_ds_n),
        .cpu_rw(cpu_rw), .cpu_siz(cpu_siz), .cpu_fc(cpu_fc), .cpu_dsack_n(cpu_dsack_n), .cpu_berr_n(cpu_berr_n),
        .cpu_avec_n(cpu_avec_n),
        .mem_req(mem_req), .mem_a(mem_a), .mem_we(mem_we), .mem_be(mem_be), .mem_wdata(mem_wdata),
        .mem_ack(mem_ack), .mem_rdata(mem_rdata),
        .io_cyc(io_cyc), .io_a(io_a), .io_uds(io_uds), .io_lds(io_lds), .io_wr(io_wr), .io_wdata(io_wdata),
        .io_rdata(io_rdata), .iack_mfp(p_iack_mfp), .mfp_vector(mfp_vector), .mfp_dtack(mfp_dtack));

    wire sel_videl, sel_nv_a, sel_nv_d, sel_ym, sel_mfp, sel_acia, sel_dma;
    wire [15:0] videl_d; wire [7:0] nv_d, ym_d;
    falcon_io io (
        .clk(clk_cpu), .reset(reset), .cyc(io_cyc), .a(io_a), .uds(io_uds), .lds(io_lds), .wr(io_wr),
        .din(io_wdata), .dout(io_rdata),
        .sel_videl(sel_videl), .sel_nvram_a(sel_nv_a), .sel_nvram_d(sel_nv_d), .sel_ym(sel_ym),
        .sel_mfp(sel_mfp), .sel_acia(sel_acia), .sel_dma(sel_dma),
        .videl_d(videl_d), .nvram_d(nv_d), .ym_d(ym_d), .mfp_d(p_mfp_d), .acia_d(p_acia_d), .dma_d(p_dma_d),
        .fdc_hd(fdc_hd));
    assign p_sel_mfp = sel_mfp; assign p_sel_acia = sel_acia; assign p_sel_dma = sel_dma && !io_a[3];
    assign p_sel_dmaaddr = sel_dma && io_a[3];
    assign p_a = io_a; assign p_rw = cpu_rw; assign p_wdata = io_wdata;

    falcon_nvram nvram (.clk(clk_cpu), .reset(reset), .sel_addr(sel_nv_a), .sel_data(sel_nv_d), .wr(io_wr),
        .din(io_wdata[7:0]), .dout(nv_d));
    falcon_ym_stub ym (.clk(clk_cpu), .reset(reset), .sel(sel_ym), .a(io_a[1]), .wr(io_wr),
        .din(io_wdata[15:8]), .dout(ym_d), .porta(ym_porta));
    videl_regs videl (.clk(clk_cpu), .reset(reset), .sel(sel_videl), .a(io_a), .uds(io_uds), .lds(io_lds),
        .wr(io_wr), .din(io_wdata), .dout(videl_d), .vcount(vcount),
        .fb_base(fb_base), .planes(planes), .hdbl(hdbl), .vdbl(vdbl), .height(height), .linebytes(linebytes),
        .st_pal_rd(st_pal_rd), .st_pal_idx(st_pal_idx), .fpal_wa(fpal_wa), .fpal_wd(fpal_wd), .fpal_we(fpal_we));
endmodule
