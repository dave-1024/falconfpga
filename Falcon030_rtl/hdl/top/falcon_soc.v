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
    input  wire        mon_rgb,          // VID-SPLIT: helper option V (sysctrl system_video): 0 VGA 60, 1 RGB 50/60
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
    output wire        cpu_halted_n,
    // raw mount path (clk_32), for the colour-bar debug tray / helper port_status
    input  wire        dbg_mnt,          // sd_card image_mounted[4] pulse
    input  wire [31:0] dbg_mnt_size,
    input  wire        dbg_hold,         // soc_reset = por32|helper_hold
    input  wire        dbg_sticky,       // tos_mount_latch waiting
    output wire [31:0] loader_status     // flags[31:16], sect[9:0]
);
    wire        mem_req, mem_we, mem_ack;
    wire [23:1] mem_a;
    wire [1:0]  mem_be;
    wire [15:0] mem_wdata, mem_rdata, mem_rdata2;
    wire        mem_rd2;

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

    // CPU and falcon_bus reset must live in clk_cpu, like cpu030_st_bridge.v.
    // por / cpu_reset / user_reset are clk32 signals. clk_cpu rising coincides
    // with a clk32 edge, but the in-between clk32 tick is clk_cpu_n. Releasing
    // RESET_INn / HALT_INn on that tick lets the CLK and CLK_N halves of
    // WF68K30L leave reset a half-cycle apart; the 030 then double-faults on
    // the first vector reads (board HUD: HALT after two fetches at $00000002,
    // PC loaded as 0 because those reads returned 0). Sync, then hold both
    // pins low for RESET_HOLD clk_cpu cycles (>=16 required by the core;
    // 128 matches the ST bridge).
    localparam [7:0] RESET_HOLD = 8'd128;
    (* syn_preserve = 1 *) reg [1:0] rst_sync = 2'b11;
    reg [7:0] rst_cnt = 8'd0;
    reg       core_reset = 1'b1;
    wire      rst_src = por | cpu_reset | user_reset;
    always @(posedge clk_cpu) begin
        rst_sync <= {rst_sync[0], rst_src};
        if (rst_sync[1]) begin
            rst_cnt    <= 8'd0;
            core_reset <= 1'b1;
        end else if (rst_cnt != RESET_HOLD) begin
            rst_cnt    <= rst_cnt + 8'd1;
            core_reset <= 1'b1;
        end else
            core_reset <= 1'b0;
    end

    // loader and CPU share the lowest arbiter port: loader only while cpu_reset
    wire        cpu_req  = cpu_reset ? 1'b0 : mem_req;
    wire        use_ld   = cpu_reset & ld_req;

    // blitter master shares the CPU arbiter port while falcon_bus has parked the CPU (blt_g32)
    wire        blt_g32, blt_mreq, blt_mwe;
    wire [23:1] blt_ma;
    wire [15:0] blt_mwd;
    wire        a_cpu_req = blt_g32 ? blt_mreq : cpu_req;
    wire [23:1] a_cpu_a   = blt_g32 ? blt_ma : mem_a;
    wire        a_cpu_we  = blt_g32 ? blt_mwe : mem_we;
    wire [1:0]  a_cpu_be  = blt_g32 ? 2'b11 : mem_be;
    wire [15:0] a_cpu_d   = blt_g32 ? blt_mwd : mem_wdata;

    // Dialog debug 6 (BLI-9): write watch on the 8-byte plane group the scanout probe shows (native line 100,
    // col 320). Every write accepted on the arbiter CPU port (CPU or blitter) to that group is logged into an
    // 8-entry ring {blitter, A2:1 (plane), UDS, LDS, seq11, data16}, HUD slot 0 oldest; w_cnt = {all, blitter} counts.
    reg         w_ack_q = 1'b0;
    reg [255:0] w_ring = 256'd0;
    reg [10:0]  w_seq = 11'd0;
    reg [15:0]  w_nblt = 16'd0;
    always @(posedge clk_32) begin
        w_ack_q <= mem_ack;
        if (a_cpu_req && a_cpu_we && mem_ack && !w_ack_q && a_cpu_a[23:3] == scan_probe_a[23:3]) begin
            w_ring <= {blt_g32, a_cpu_a[2:1], a_cpu_be, w_seq, a_cpu_d, w_ring[255:32]};
            w_seq  <= w_seq + 11'd1;
            if (blt_g32) w_nblt <= w_nblt + 16'd1;
        end
    end

    falcon_sdram_arb arb (
        .clk(clk_32), .reset(por), .ram_ready(ram_ready),
        .sd_cs(sd_cs_i), .sd_we(sd_we_i), .sd_refresh(sd_refresh), .sd_ecs(sd_ecs),
        .sd_addr(sd_waddr), .sd_ds(sd_ds), .sd_din(sd_din), .sd_dout(sd_dout),
        .sd_dout2(sd_dout2), .sd_rd2(sd_rd2), .sd_ba(sd_st_ba),
        .vid_req(vid_req), .vid_a(vid_a), .vid_ack(vid_ack), .vid_q(vid_q), .vid_q2(vid_q2),
        .dma_req(dma_req), .dma_we(dma_we), .dma_a(dma_a), .dma_d(dma_d), .dma_ack(dma_ack), .dma_q(dma_q),
        .ld_req(use_ld), .ld_a(ld_a), .ld_d(ld_d), .ld_ack(ld_ack),
        .cpu_req(a_cpu_req), .cpu_a(a_cpu_a), .cpu_we(a_cpu_we), .cpu_be(a_cpu_be),
        .cpu_d(a_cpu_d), .cpu_ack(mem_ack), .cpu_q(mem_rdata),
        .cpu_rd2(!blt_g32 && !cpu_reset && mem_rd2), .cpu_q2(mem_rdata2)
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
    wire        tb_de;      // MFP TBI = native DE from falcon_videl_timing (VID-SPLIT; FB-1 had it from the scanout)
    wire [15:0] nat_vdb;
    wire        nat_vdbl;
    wire [9:0]  scan_vtop;
    wire        scan_fs_tgl;
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
    wire        st_shifter;
    wire [191:0] scan_pal;    // debug: scanout ST palette copy, 16 x 12

    falcon_core core (
        .clk_cpu(clk_cpu), .clk_cpu_n(clk_cpu_n), .reset(core_reset),
        .mem_req(mem_req), .mem_a(mem_a), .mem_we(mem_we), .mem_be(mem_be),
        .mem_wdata(mem_wdata), .mem_ack(mem_ack), .mem_rdata(mem_rdata),
        .mem_rd2(mem_rd2), .mem_rdata2(mem_rdata2),
        .p_sel_mfp(p_sel_mfp), .p_sel_acia(p_sel_acia), .p_sel_dma(p_sel_dma), .p_sel_dmaaddr(p_sel_dmaaddr),
        .p_a(p_a), .p_rw(p_rw), .p_wdata(p_wdata), .p_rdata(p_rdata), .p_done(p_done),
        .p_sel_blt(p_sel_blt), .p_uds(p_uds), .p_lds(p_lds), .blt_rdata(blt_rdata), .blt_done(blt_done),
        .blt_br(blt_br), .blt_bg(blt_bg), .cpu_cyc_tog(cpu_cyc_tog),
        .p_iack_mfp(p_iack_mfp), .mfp_vector(mfp_vector), .mfp_dtack(mfp_dtack),
        .mfp_irq(mfp_irq), .vbl(vbl), .hbl(hbl),
        .vcount(vcount), .mon_rgb(mon_rgb), .nat_vdb(nat_vdb), .nat_vdbl(nat_vdbl), .fb_base(fb_base), .planes(planes), .hdbl(hdbl), .vdbl(vdbl),
        .height(height), .linebytes(linebytes),
        .st_pal_idx(st_pal_idx), .st_pal_rd(st_pal_rd),
        .fpal_wa(fpal_wa), .fpal_wd(fpal_wd), .fpal_we(fpal_we),
        .stpal_we(stpal_we), .stpal_wa(stpal_wa), .stpal_wd(stpal_wd), .st_shifter(st_shifter),
        .ym_porta(ym_porta), .fdc_hd(), .cpu_halted_n(cpu_halted_n),
        .dbg_pc(dbg_pc), .dbg_berr_count(dbg_berr_count), .dbg_berr_addr(dbg_berr_addr),
        .dbg_reset_out(dbg_reset_out), .dbg_io_addr(dbg_io_addr), .dbg_io_data(dbg_io_data),
        .dbg_fetch_count(dbg_fetch_count),
        .dbg_hht(dbg_hht), .dbg_vft(dbg_vft), .dbg_spshift(dbg_spshift), .dbg_shmode(dbg_shmode),
        .dbg_vco(dbg_vco),
        .dbg_cycs(dbg_cycs), .dbg_ncyc(dbg_ncyc),
        .dbg_io_ring(dbg_io_ring), .dbg_pc_ring(dbg_pc_ring)
    );

    wire [31:0] dbg_pc, dbg_berr_addr;
    wire [15:0] dbg_berr_count, dbg_io_addr, dbg_io_data, dbg_fetch_count;
    wire [15:0] dbg_hht, dbg_vft, dbg_spshift;
    wire [7:0]  dbg_shmode;
    wire [15:0] dbg_vco;
    wire        dbg_reset_out;
    wire [383:0] dbg_cycs;
    wire [3:0]   dbg_ncyc;
    wire [255:0] dbg_io_ring, dbg_pc_ring;

    // ---- blitter $FF8A00 (falcon_blitter.v wraps the proven stBlitter.sv) ----
    wire        p_sel_blt, p_uds, p_lds, blt_done, blt_br, blt_bg, cpu_cyc_tog, blt_irq_n;
    wire [15:0] blt_rdata;
    wire [127:0] blt_dbg;
    wire [255:0] blt_snap;
    wire [31:0]  scan_probe;
    wire [23:1]  scan_probe_a;
    falcon_blitter blitter (
        .clk_32(clk_32), .reset(por | user_reset), .pwr_up(por),
        .sel(p_sel_blt), .a(p_a[5:1]), .rw(p_rw), .uds(p_uds), .lds(p_lds), .wdata(p_wdata),
        .rdata(blt_rdata), .done(blt_done),
        .br_want(blt_br), .bus_grant(blt_bg), .cpu_cyc_tog(cpu_cyc_tog),
        .grant_32(blt_g32), .m_req(blt_mreq), .m_a(blt_ma), .m_we(blt_mwe), .m_wdata(blt_mwd),
        .m_ack(mem_ack), .m_rdata(mem_rdata), .irq_n(blt_irq_n), .dbg(blt_dbg), .dbg_snap(blt_snap)
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

    // Keyboard ACIA + IKBD: the ST core's real path (atarist.v), unchanged modules.
    // ikbd.sv (HD63701 + MCU_BIROM ikbd.hex) on clk_32 with DIV=4 (2 MHz enables,
    // as the ST core); acia.v on the pbus E enable, 500 kHz rx/tx clock from clk_32.
    // Matrix/mouse/joystick come from the same helper hid.v as the ST core.
    // falcon_ikbd_acia.v (Hybrid030 M5 stub) is no longer instantiated.
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

    // HUD: keyboard ACIA traffic (clk_32). RX = CPU reads of RDR ($FFFC02),
    // TX = CPU writes of TDR. joy_chg counts changes of the helper mouse/joy0 bits.
    wire kacc = acia_cs && !p_a[2] && p_a[1];
    reg  kacc_d;
    reg [15:0] k_rxc;
    reg [11:0] k_txc;
    reg [7:0]  k_rxd, k_txd, k_jch;
    reg [5:0]  joy0_d;
    always @(posedge clk_32) begin
        kacc_d <= kacc;
        joy0_d <= joy0;
        if (por) begin
            k_rxc <= 16'd0; k_txc <= 12'd0; k_rxd <= 8'd0; k_txd <= 8'd0; k_jch <= 8'd0;
        end else begin
            if (kacc && !kacc_d && p_rw)  begin k_rxc <= k_rxc + 16'd1; k_rxd <= kbd_acia_d; end
            if (kacc && !kacc_d && !p_rw) begin k_txc <= k_txc + 12'd1; k_txd <= p_wdata[15:8]; end
            if (joy0 != joy0_d) k_jch <= k_jch + 8'd1;
        end
    end
    // s6 = {rx count, last rx, last tx}; s7 = {tx count, 0, 0, kbd irq, GPIP4 pin, joy changes, 00, joy0}
    wire [63:0] ikbd_dbg = { {k_txc, 2'b00, kbd_acia_irq, !acia_irq, k_jch, 2'b00, joy0},
                             {k_rxc, k_rxd, k_txd} };

    acia midi_acia (
        .clk(clk_32), .E(acia_E), .reset(por | user_reset),
        .din(p_wdata[15:8]), .sel(acia_cs && p_a[2]), .rs(p_a[1]), .rw(p_rw),
        .dout(midi_acia_d), .irq(midi_acia_irq),
        .rxtxclk_sel(1'b0), .dout_strobe(),
        .rx(1'b1), .tx()
    );

    // GPIP: Hybrid030 / DESIGN.md. GPIP7 reads 1 (no sound DMA). GPIP5 = !FDC IRQ
    // (IDE later shares it). GPIP4 = !ACIA IRQ. GPIP3 = blitter INTn (low = done), as atarist.v.
    wire [7:0] mfp_gpio_in = {1'b1, 1'b1, !fdc_irq, !acia_irq, blt_irq_n, 2'b11, 1'b1};
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
        .clk_ext(clk_mfp_en), .t_i({tb_de, 1'b0}), .i(mfp_gpio_in)
    );

    wire        nat_go;     // VID-SPLIT 3: native line start (RGB frame-buffer decode)
    wire [9:0]  nat_line;
    falcon_scanout scanout (
        .clk_32(clk_32), .clk_pixel(clk_pixel), .reset(por),
        .fb_base(fb_base), .planes(planes), .st_shifter(st_shifter), .hdbl(hdbl), .vdbl(vdbl),
        .height(height), .linebytes(linebytes), .dbg_pal(scan_pal),
        .use_fb(mon_rgb), .nat_go(nat_go), .nat_line(nat_line), .dbg_probe(scan_probe), .dbg_probe_a(scan_probe_a),
        .stpal_we(stpal_we), .stpal_wa(stpal_wa), .stpal_wd(stpal_wd),
        .fpal_we(fpal_we), .fpal_wa(fpal_wa), .fpal_wd(fpal_wd),
        .ram_req(vid_req), .ram_rd2(vid_rd2), .ram_a(vid_a),
        .ram_ack(vid_ack), .ram_q(vid_q), .ram_q2(vid_q2),
        .cx(cx), .cy(cy), .hsync(hsync), .vsync(vsync), .de(de),
        .vr(scan_r), .vg(scan_g), .vb(scan_b),
        .vbl(), .hbl(), .tb_de(), .vcount(), .underrun(scan_underrun),
        .vtop_o(scan_vtop), .fs_tgl(scan_fs_tgl)
    );

    // VID-SPLIT step 1+2: native Videl beam timing (clk_32) drives TBI, HBL, VBL and the
    // $FF8205/07/09 counter, as gstmcu does in the ST core; HDMI stays a reader.
    falcon_videl_timing vtim (
        .clk_32(clk_32), .reset(por), .mon_rgb(mon_rgb),
        .vft(dbg_vft), .vdb(nat_vdb), .vdbl(nat_vdbl), .height(height),
        .fb_base(fb_base), .linebytes(linebytes),
        .hdmi_vtop(scan_vtop), .hdmi_fs_tgl(scan_fs_tgl),
        .de(tb_de), .hbl(hbl), .vbl(vbl), .frame_start(), .vcount(vcount),
        .line_go(nat_go), .pline_o(nat_line), .vl_o(), .hc_o()
    );

    // Colour bars + a bottom debug tray while the TOS loader holds the CPU
    // in reset (or on a bad image). 3196a13c board grabs had a navy tray and
    // no yellow bar: that is also what busy=1 and sect=0 looks like, so it
    // does not prove the loader never started. The 3196a13c helper log had
    // "DRV 4: inserted. Size = 524288", "enable direct mapping @744008", then
    // "spourious interrupt" — sd_card only raises that IRQ on a rising
    // rstart/wstart while direct_enable is still 0, so tos_sd_rd likely went
    // high before CMD 6 finished. The tray now has sticky coloured blocks
    // so one grab shows where the path stopped.
    wire [7:0] scan_r, scan_g, scan_b;
    wire       ld_busy;
    wire [9:0] ld_sect;

    // Sticky flags on clk_32 (por32 only). Live bits 6/7/10 follow the inputs.
    reg [15:0] ld_flags;
    always @(posedge clk_32) begin
        if (loader_reset) begin
            ld_flags <= 16'd0;
        end else begin
            if (dbg_mnt)                         ld_flags[0]  <= 1'b1; // mount-seen
            if (dbg_mnt && dbg_mnt_size == 32'd524288)
                                                 ld_flags[1]  <= 1'b1; // size-ok
            if (dbg_mnt && dbg_mnt_size != 32'd524288)
                                                 ld_flags[11] <= 1'b1; // size-bad (eject or wrong)
            if (tos_img_mounted)                 ld_flags[2]  <= 1'b1; // go-seen
            if (ld_busy)                         ld_flags[3]  <= 1'b1; // busy-seen
            if (tos_sd_rd)                       ld_flags[4]  <= 1'b1; // sd_rd issued
            if (tos_sd_ack)                      ld_flags[5]  <= 1'b1; // sd_ack seen
            ld_flags[6]  <= ram_ready;                                 // live
            ld_flags[7]  <= dbg_hold;                                  // live
            if (tos_sd_dout_strobe)              ld_flags[8]  <= 1'b1; // byte strobe
            if (ld_ack)                          ld_flags[9]  <= 1'b1; // ram ack
            ld_flags[10] <= dbg_sticky;                                // live, waiting
        end
    end
    assign loader_status = { ld_flags, 6'd0, ld_sect };

    reg  [1:0] rst_s, busy_s, err_s;
    reg  [9:0] sect_s, sect_p;
    reg [15:0] flg_s, flg_p;
    always @(posedge clk_pixel) begin
        rst_s  <= { rst_s[0],  cpu_reset };
        busy_s <= { busy_s[0], ld_busy   };
        err_s  <= { err_s[0],  tos_err   };
        sect_s <= ld_sect;
        sect_p <= sect_s;
        flg_s  <= ld_flags;
        flg_p  <= flg_s;
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
    // 12 x 16 px flag blocks at the left of the tray, then 10 sector bits
    // (8 px each, x=192..271), then a yellow progress strip from x=272.
    // 0 mount-seen white, 1 size-ok green, 2 go yellow, 3 busy magenta,
    // 4 sd_rd blue, 5 sd_ack cyan, 6 ram_ready lime (live), 7 hold red (live),
    // 8 strobe teal, 9 ram_ack pink, 10 sticky orange (live), 11 size-bad maroon.
    reg [23:0] flag_rgb;
    always @(*) begin
        case (cx[7:4])
            4'd0:  flag_rgb = 24'hF0F0F0;
            4'd1:  flag_rgb = 24'h00C000;
            4'd2:  flag_rgb = 24'hF0C000;
            4'd3:  flag_rgb = 24'hC000C0;
            4'd4:  flag_rgb = 24'h3060FF;
            4'd5:  flag_rgb = 24'h00C0C0;
            4'd6:  flag_rgb = 24'h80FF00;
            4'd7:  flag_rgb = 24'hFF2020;
            4'd8:  flag_rgb = 24'h00E0C0;
            4'd9:  flag_rgb = 24'hFF80C0;
            4'd10: flag_rgb = 24'hFF8000;
            default: flag_rgb = 24'h800000;
        endcase
    end
    wire [3:0]  flag_i   = cx[7:4];
    wire        flag_on  = (flag_i < 4'd12) && flg_p[flag_i];
    wire        in_flags = (cy >= 10'd464) && (cx < 10'd192);
    // 10 sector bits at x=192..271, 8 px each, MSB at the left (no divider)
    wire [6:0]  bit_raw  = cx[9:3] - 7'd24;      // (cx-192)>>3, valid when in_bits
    wire [3:0]  bit_div  = bit_raw[3:0];
    wire        in_bits  = (cy >= 10'd464) && (cx >= 10'd192) && (cx < 10'd272);
    wire        bit_on   = in_bits && sect_p[4'd9 - bit_div];
    wire [12:0] prog_x   = 13'd272 + ({3'd0, sect_p} * 13'd23 / 13'd64); // 272..639
    wire        in_tray  = (rst_s[1] | err_s[1]) && (cy >= 10'd464);
    wire        in_prog  = in_tray && (cx >= 10'd272) && ({3'd0, cx} < prog_x);
    wire        show_bar = rst_s[1] | err_s[1];
    wire [7:0]  tray_r, tray_g, tray_b;
    assign tray_r = in_flags ? (flag_on ? flag_rgb[23:16] : 8'h18) :
                    in_bits  ? (bit_on  ? 8'hF0 : 8'h18) :
                    in_prog  ? 8'hFF :
                               8'h20;
    assign tray_g = in_flags ? (flag_on ? flag_rgb[15:8]  : 8'h18) :
                    in_bits  ? (bit_on  ? 8'hF0 : 8'h18) :
                    in_prog  ? 8'hC0 :
                               8'h20;
    assign tray_b = in_flags ? (flag_on ? flag_rgb[7:0]   : 8'h18) :
                    in_bits  ? (bit_on  ? 8'hF0 : 8'h18) :
                    in_prog  ? 8'h00 :
                               8'h40;
    // Always-on hex overlay (clk_pixel). Sampled at the start of each frame
    // so a grab is internally consistent. 2-flop the source bits first.
    reg [31:0] pc_s, pc_p, ba_s, ba_p, crc_s, crc_p;
    reg [15:0] ioa_s, ioa_p, iod_s, iod_p, bc_s, bc_p, fc_s, fc_p;
    reg [15:0] hht_s, hht_p, vft_s, vft_p, sp_s, sp_p;
    reg [11:0] lb_s, lb_p;
    reg [23:0] vb_s, vb_p;
    reg [9:0]  ht_s, ht_p;
    reg [7:0]  sh_s, sh_p;
    reg [3:0]  pl_s, pl_p;
    reg        ro_s, ro_p, hl_s, hl_p, rr_s, rr_p, vbll_s, vbll_p, hd_s, hd_p, vd_s, vd_p;
    reg [383:0] cycs_s, cycs_p;
    reg [3:0]   ncyc_s, ncyc_p;
    reg [255:0] ioring_s, ioring_p, pcring_s, pcring_p;
    always @(posedge clk_pixel) begin
        pc_s  <= dbg_pc;           pc_p  <= pc_s;
        ba_s  <= dbg_berr_addr;    ba_p  <= ba_s;
        crc_s <= tos_crc;          crc_p <= crc_s;
        ioa_s <= dbg_io_addr;      ioa_p <= ioa_s;
        iod_s <= dbg_io_data;      iod_p <= iod_s;
        bc_s  <= dbg_berr_count;   bc_p  <= bc_s;
        fc_s  <= dbg_fetch_count;  fc_p  <= fc_s;
        hht_s <= dbg_hht;          hht_p <= hht_s;
        vft_s <= dbg_vft;          vft_p <= vft_s;
        sp_s  <= dbg_spshift;      sp_p  <= sp_s;
        lb_s  <= linebytes;        lb_p  <= lb_s;
        vb_s  <= fb_base;          vb_p  <= vb_s;
        ht_s  <= height;           ht_p  <= ht_s;
        sh_s  <= dbg_shmode;       sh_p  <= sh_s;
        pl_s  <= planes;           pl_p  <= pl_s;
        ro_s  <= dbg_reset_out;    ro_p  <= ro_s;
        hl_s  <= ~cpu_halted_n;    hl_p  <= hl_s;
        rr_s  <= ram_ready;        rr_p  <= rr_s;
        vbll_s<= vbl;              vbll_p<= vbll_s;
        hd_s  <= hdbl;             hd_p  <= hd_s;
        vd_s  <= vdbl;             vd_p  <= vd_s;
        cycs_s<= dbg_cycs;         cycs_p<= cycs_s;
        ncyc_s<= dbg_ncyc;         ncyc_p<= ncyc_s;
        // (dialog debug build 2: rows 6-7 = frozen blitter start ring, slot k = entry k, oldest first)
        ioring_s<= w_ring;
        ioring_p<= ioring_s;
        // HUD row 9: slots 4-5 live blitter debug, slots 6-7 keyboard ACIA/IKBD, once the ring has frozen at
        // the first BERR (always the expected $FF8E09 probe); row 8 keeps the frozen context.
        // (dialog debug build: slots 4-7 = blitter flags, {halftone0, fills}, fill history; IKBD dropped)
        // (BLI-9: row 9 slot 7 = scanout pixel probe at native line 100, col 320 instead of blitter d_first)
        pcring_s<= (dbg_berr_count != 16'd0) ? {scan_probe, {5'd0, w_seq, w_nblt}, {8'd0, scan_probe_a, 1'b0}, blt_dbg[31:0], dbg_pc_ring[127:0]} : dbg_pc_ring;
        pcring_p<= pcring_s;
    end
    // Freeze a consistent snapshot at the first pixel of the frame.
    reg [31:0] pc_f, ba_f, crc_f;
    reg [15:0] ioa_f, iod_f, bc_f, fc_f, hht_f, vft_f, sp_f;
    reg [11:0] lb_f;
    reg [23:0] vb_f;
    reg [9:0]  ht_f;
    reg [7:0]  sh_f, frame_f, frame_c;
    reg [3:0]  pl_f;
    reg        ro_f, hl_f, rr_f, vbll_f, hd_f, vd_f, crst_f, terr_f;
    reg [383:0] cycs_f;
    reg [3:0]   ncyc_f;
    reg [255:0] ioring_f, pcring_f;
    always @(posedge clk_pixel) begin
        if (cx == 10'd0 && cy == 10'd0) begin
            pc_f   <= pc_p;
            ba_f   <= ba_p;
            crc_f  <= crc_p;
            ioa_f  <= ioa_p;
            iod_f  <= iod_p;
            bc_f   <= bc_p;
            fc_f   <= fc_p;
            hht_f  <= hht_p;
            vft_f  <= vft_p;
            sp_f   <= sp_p;
            lb_f   <= lb_p;
            vb_f   <= vb_p;
            ht_f   <= ht_p;
            sh_f   <= sh_p;
            pl_f   <= pl_p;
            ro_f   <= ro_p;
            hl_f   <= hl_p;
            rr_f   <= rr_p;
            vbll_f <= vbll_p;
            hd_f   <= hd_p;
            vd_f   <= vd_p;
            crst_f <= rst_s[1];
            terr_f <= err_s[1];
            cycs_f <= cycs_p;
            ncyc_f <= ncyc_p;
            ioring_f <= ioring_p;
            pcring_f <= pcring_p;
            frame_f<= frame_c;
            frame_c<= frame_c + 8'd1;
        end
    end
    wire        hud_hit;
    wire [7:0]  hud_r, hud_g, hud_b;
    wire        crc_ok = (crc_f == 32'h028B561D);
    // flags[7:0] = {hb, vbl, ram_ready, crc_ok, halted, reset_out, tos_err, cpu_reset}
    wire [7:0]  hud_flags = {frame_f[0], vbll_f, rr_f, crc_ok, hl_f, ro_f, terr_f, crst_f};
    falcon_dbg_hud u_hud (
        .cx(cx), .cy(cy),
        .pc(pc_f), .io_a(ioa_f), .io_d(iod_f),
        .berr_count(bc_f), .berr_addr(ba_f),
        .vbas(vb_f), .hht(hht_f), .vft(vft_f), .spshift(sp_f), .shmode(sh_f),
        .tos_crc(crc_f), .flags(hud_flags), .fetch_count(fc_f),
        .planes(pl_f), .linebytes(lb_f), .height(ht_f), .hdbl(hd_f), .vdbl(vd_f),
        .frame(frame_f), .cycs(cycs_f), .ncyc(ncyc_f),
        .io_ring(ioring_f), .pc_ring(pcring_f),
        .hit(hud_hit), .r(hud_r), .g(hud_g), .b(hud_b)
    );

    wire [7:0] pic_r = !show_bar ? scan_r : in_tray ? tray_r : err_s[1] ? 8'hC0 : bar_rgb[23:16];
    wire [7:0] pic_g = !show_bar ? scan_g : in_tray ? tray_g : err_s[1] ? 8'h00 : bar_rgb[15:8];
    wire [7:0] pic_b = !show_bar ? scan_b : in_tray ? tray_b : err_s[1] ? 8'h00 : bar_rgb[7:0];
    assign vr = hud_hit ? hud_r : pic_r;
    assign vg = hud_hit ? hud_g : pic_g;
    assign vb = hud_hit ? hud_b : pic_b;
    // vid_rd2 is produced by the scanout and also generated by the arbiter from the
    // address; the arbiter's sd_rd2 is what sdram.v sees.

    tos_loader loader (
        .clk(clk_32), .reset(loader_reset),
        .img_mounted(tos_img_mounted), .img_size(tos_img_size),
        .sd_lba(tos_sd_lba), .sd_rd(tos_sd_rd), .sd_ack(tos_sd_ack),
        .sd_buff_addr(tos_sd_buff_addr), .sd_dout(tos_sd_dout), .sd_dout_strobe(tos_sd_dout_strobe),
        .ram_req(ld_req), .ram_a(ld_a), .ram_wdata(ld_d), .ram_ack(ld_ack),
        .cpu_reset(cpu_reset), .err(tos_err), .busy(ld_busy), .sect(ld_sect),
        .crc(tos_crc)
    );
    wire [31:0] tos_crc;
endmodule
