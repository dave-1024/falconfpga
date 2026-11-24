// falcon_core.v - FAL_01: Falcon030 core, clk_cpu domain: WF68K30L + falcon_bus + IO block,
//                 NVRAM, YM stub, VIDEL registers. clk_32 peripherals (MFP, ACIAs, floppy) and
//                 the SDRAM/scanout sit outside on the ports below (falcon_pbus.v, falcon_sdram_arb.v).
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
    input  wire [15:0] p_rdata,          // falcon_pbus.v latched read data
    input  wire        p_done,           // falcon_pbus.v cycle finished
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
    output wire        stpal_we,
    output wire [3:0]  stpal_wa,
    output wire [11:0] stpal_wd,
    output wire [7:0]  ym_porta,
    output wire [1:0]  fdc_hd,
    output wire        cpu_halted_n,
    // debug samples for the always-on HDMI hex overlay (clk_cpu)
    output reg  [31:0] dbg_pc,
    output reg  [15:0] dbg_berr_count,
    output reg  [31:0] dbg_berr_addr,
    output wire        dbg_reset_out,
    output reg  [15:0] dbg_io_addr,
    output reg  [15:0] dbg_io_data,
    output reg  [15:0] dbg_fetch_count,
    output wire [15:0] dbg_hht,
    output wire [15:0] dbg_vft,
    output wire [15:0] dbg_spshift,
    output wire [7:0]  dbg_shmode
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

    assign dbg_reset_out = cpu_reset_out;
    // Sample on the falling edge of AS (address is valid). Program space is FC x10.
    // BERR is counted on a falling BERRn while AS is still low.
    reg as_d, berr_d;
    always @(posedge clk_cpu) begin
        as_d   <= cpu_as_n;
        berr_d <= cpu_berr_n;
        if (reset) begin
            dbg_pc          <= 32'd0;
            dbg_berr_count  <= 16'd0;
            dbg_berr_addr   <= 32'd0;
            dbg_io_addr     <= 16'd0;
            dbg_io_data     <= 16'd0;
            dbg_fetch_count <= 16'd0;
            as_d   <= 1'b1;
            berr_d <= 1'b1;
        end else begin
            if (as_d && !cpu_as_n && cpu_fc[1] && !cpu_fc[0]) begin
                dbg_pc          <= cpu_a;
                dbg_fetch_count <= dbg_fetch_count + 16'd1;
            end
            if (berr_d && !cpu_berr_n) begin
                dbg_berr_count <= dbg_berr_count + 16'd1;
                dbg_berr_addr  <= cpu_a;
            end
            if (io_wr) begin
                dbg_io_addr <= {io_a, 1'b0};
                dbg_io_data <= io_wdata;
            end
        end
    end

    WF68K30L_TOP #(.CLK_N_EXT(1), .CACHES(0), .WA_ADR_HI(1), .FAST_HANDOFF(1)) cpu (
        .CLK(clk_cpu), .CLK_N(clk_cpu_n), .ADR_OUT(cpu_a), .DATA_IN(cpu_din), .DATA_OUT(cpu_dout), .DATA_EN(),
        .BERRn(cpu_berr_n), .RESET_INn(!reset), .RESET_OUT(cpu_reset_out), .HALT_INn(!reset), .HALT_OUTn(cpu_halted_n),
        .FC_OUT(cpu_fc), .AVECn(cpu_avec_n), .IPLn(ipl_r), .IPENDn(), .DSACKn(cpu_dsack_n), .SIZE(cpu_siz),
        .ASn(cpu_as_n), .RWn(cpu_rw), .RMCn(cpu_rmc_n), .DSn(cpu_ds_n), .ECSn(), .OCSn(), .DBENn(), .BUS_EN(),
        .STERMn(1'b1), .BRn(1'b1), .BGn(), .BGACKn(1'b1),
        .CIINn(cpu_ciin_n), .MMU_ON(), .CDISn(1'b1), .CBACKn(1'b1), .CBREQn(), .CIOUTn());

    wire sel_videl, sel_nv_a, sel_nv_d, sel_ym, sel_mfp, sel_acia, sel_dma;
    wire io_ext = sel_mfp || sel_acia || sel_dma;
    wire io_cyc, io_uds, io_lds, io_wr, io_rw; wire [15:1] io_a; wire [15:0] io_wdata, io_rdata;
    falcon_bus bus (
        .clk(clk_cpu), .reset(reset),
        .cpu_a(cpu_a), .cpu_dout(cpu_dout), .cpu_din(cpu_din), .cpu_as_n(cpu_as_n), .cpu_ds_n(cpu_ds_n),
        .cpu_rw(cpu_rw), .cpu_siz(cpu_siz), .cpu_fc(cpu_fc), .cpu_dsack_n(cpu_dsack_n), .cpu_berr_n(cpu_berr_n),
        .cpu_avec_n(cpu_avec_n),
        .mem_req(mem_req), .mem_a(mem_a), .mem_we(mem_we), .mem_be(mem_be), .mem_wdata(mem_wdata),
        .mem_ack(mem_ack), .mem_rdata(mem_rdata),
        .io_cyc(io_cyc), .io_a(io_a), .io_uds(io_uds), .io_lds(io_lds), .io_rw(io_rw), .io_wr(io_wr), .io_wdata(io_wdata),
        .io_rdata(io_ext ? p_rdata : io_rdata), .io_ext(io_ext), .io_done(p_done), .iack_mfp(p_iack_mfp), .mfp_vector(mfp_vector), .mfp_dtack(mfp_dtack));

    wire [15:0] videl_d; wire [7:0] nv_d, ym_d;
    falcon_io io (
        .clk(clk_cpu), .reset(reset), .cyc(io_cyc), .a(io_a), .uds(io_uds), .lds(io_lds), .wr(io_wr),
        .din(io_wdata), .dout(io_rdata),
        .sel_videl(sel_videl), .sel_nvram_a(sel_nv_a), .sel_nvram_d(sel_nv_d), .sel_ym(sel_ym),
        .sel_mfp(sel_mfp), .sel_acia(sel_acia), .sel_dma(sel_dma),
        .videl_d(videl_d), .nvram_d(nv_d), .ym_d(ym_d), .mfp_d(8'hFF), .acia_d(8'hFF), .dma_d(16'hFFFF),
        .fdc_hd(fdc_hd));
    assign p_sel_mfp = sel_mfp; assign p_sel_acia = sel_acia; assign p_sel_dma = sel_dma && !io_a[3];
    assign p_sel_dmaaddr = sel_dma && io_a[3];
    assign p_a = io_a; assign p_rw = io_rw; assign p_wdata = io_wdata;

    falcon_nvram nvram (.clk(clk_cpu), .reset(reset), .sel_addr(sel_nv_a), .sel_data(sel_nv_d), .wr(io_wr),
        .din(io_wdata[7:0]), .dout(nv_d));
    falcon_ym_stub ym (.clk(clk_cpu), .reset(reset), .sel(sel_ym), .a(io_a[1]), .wr(io_wr),
        .din(io_wdata[15:8]), .dout(ym_d), .porta(ym_porta));
    videl_regs videl (.clk(clk_cpu), .reset(reset), .sel(sel_videl), .a(io_a), .uds(io_uds), .lds(io_lds),
        .wr(io_wr), .din(io_wdata), .dout(videl_d), .vcount(vcount),
        .fb_base(fb_base), .planes(planes), .hdbl(hdbl), .vdbl(vdbl), .height(height), .linebytes(linebytes),
        .st_pal_rd(st_pal_rd), .st_pal_idx(st_pal_idx), .fpal_wa(fpal_wa), .fpal_wd(fpal_wd), .fpal_we(fpal_we),
        .stpal_we(stpal_we), .stpal_wa(stpal_wa), .stpal_wd(stpal_wd),
        .dbg_hht(dbg_hht), .dbg_vft(dbg_vft), .dbg_spshift(dbg_spshift), .dbg_shmode(dbg_shmode));
endmodule
