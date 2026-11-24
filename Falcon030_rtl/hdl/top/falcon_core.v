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
    // blitter ($FF8A00-$FF8A3F, falcon_blitter.v on clk_32) register port + bus arbitration
    output wire        p_sel_blt,
    output wire        p_uds, p_lds,
    input  wire [15:0] blt_rdata,
    input  wire        blt_done,
    input  wire        blt_br,           // blitter wants/owns the bus (clk_32 level)
    output wire        blt_bg,           // CPU parked between cycles (clk_cpu)
    output wire        cpu_cyc_tog,      // toggles on each CPU bus cycle start
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
    output wire [7:0]  dbg_shmode,
    output wire [15:0] dbg_vco,
    // Packed post-PMMU debug (see falcon_dbg_hud.v): descriptors, table XOR,
    // _phystop, _frclock, VCO, first fetch outside $E0, last table-walk.
    output wire [383:0] dbg_cycs,
    output wire [3:0]   dbg_ncyc,      // [0] = has left $E0 program space
    output reg  [255:0] dbg_io_ring,   // 8 x {addr[15:0], data[15:0]}, oldest in [31:0]
    output reg  [255:0] dbg_pc_ring    // 8 x pc[31:0], oldest in [31:0]; frozen after leave
);
    wire [31:0] cpu_a, cpu_dout, cpu_din;
    wire        cpu_as_n, cpu_ds_n, cpu_rw, cpu_rmc_n, cpu_reset_out;
    wire [1:0]  cpu_siz, cpu_dsack_n;
    wire [2:0]  cpu_fc;
    wire        cpu_berr_n, cpu_avec_n;
    reg  [2:0]  ipl_r;
    // cache inhibit: IO, IDE, the vector mirror and ST-RAM (DMA'd by the floppy, no snooping: the ST build's rule);
    // only the TOS ROM copy at $E00000-$E7FFFF was cachable.
    // 24 Nov 20:1x bring-up: CIIN asserted for EVERY cycle, like the ST bridge's ST side (the
    // cache was validated there on 32-bit TT-RAM only; I-cache fills over this 16-bit DSACK port
    // are untested). Hybrid030 (Musashi) has no cache model. Re-enable ROM caching once TOS boots.
    wire cpu_ciin_n = 1'b0;
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
        end
    end

    // Post-PMMU / IO / table snoops for the HUD (clk_cpu).
    // Shadow $700..$7FF (PMMU tables), _phystop ($42E), _frclock ($466),
    // last 8 IO writes, last 8 program fetches, first fetch outside $E0xxxx.
    reg [31:0] outpc, prevpc, last_e0_pc, walk_d;
    reg [23:0] walk_a;
    reg        left_e0, dsack_d, walk_pend, fpend;
    reg        berr1_seen, vpend;
    reg [1:0]  vcnt;
    reg [15:0] vaddr;
    reg [31:0] berr1_a, berr1_info, berr1_pc, vlog0, pwalk_d;
    reg [23:0] pwalk_a;
    wire [31:0] vlog1 = 32'd0;                     // dropped (always 000A/398C on 8a0cc24)
    wire [31:0] lastw_a = {8'h00, pwalk_a};       // slot reused: previous FC=5 long read addr
    wire [31:0] vlog2 = pwalk_d;                  // slot reused: previous FC=5 long read data
    wire [23:0] a24w = cpu_a[23:0];
    wire        wr_done = dsack_d && !(&cpu_dsack_n) && !cpu_rw;
    wire        rd_done = dsack_d && !(&cpu_dsack_n) &&  cpu_rw;
    always @(posedge clk_cpu) begin
        dsack_d <= &cpu_dsack_n;
        if (reset) begin
            outpc <= 32'd0; prevpc <= 32'd0; last_e0_pc <= 32'd0;
            walk_a <= 24'd0; walk_d <= 32'd0;
            left_e0 <= 1'b0; walk_pend <= 1'b0; fpend <= 1'b0;
            berr1_seen <= 1'b0; vpend <= 1'b0; vcnt <= 2'd0; vaddr <= 16'd0;
            berr1_a <= 32'd0; berr1_info <= 32'd0; berr1_pc <= 32'd0;
            vlog0 <= 32'd0; pwalk_a <= 24'd0; pwalk_d <= 32'd0;
            dbg_io_ring <= 256'd0; dbg_pc_ring <= 256'd0;
            dbg_io_addr <= 16'd0; dbg_io_data <= 16'd0;
            dsack_d <= 1'b1;
        end else begin
            // Program-space ring + first fetch outside $00E0xxxx (not the
            // $000000-$000007 vector mirror). Address valid on AS falling.
            // The ring now freezes at the FIRST BERR (so it shows the code
            // that bus-errored); outpc/prevpc still latch the first leave.
            if (as_d && !cpu_as_n && cpu_fc[1] && !cpu_fc[0]) begin
                // FAL_01 20:0x: ring entry = {A15:1, long(SIZ=00), fetched D31:16}
                // (data filled at DSACK) to compare with tos404.img at $E0032A.
                if (!berr1_seen) begin
                    dbg_pc_ring <= {cpu_a[15:1], (cpu_siz == 2'b00), 16'hEEEE, dbg_pc_ring[255:32]};
                    fpend <= 1'b1;
                end
                if (!left_e0) begin
                    if (a24w[23:16] == 8'hE0)
                        last_e0_pc <= cpu_a;
                    else if (a24w[23:3] != 21'd0) begin
                        left_e0 <= 1'b1;
                        outpc   <= cpu_a;
                        prevpc  <= last_e0_pc;
                    end
                end
            end
            if (fpend && rd_done) begin
                fpend <= 1'b0;
                if (!berr1_seen) dbg_pc_ring[239:224] <= cpu_din[31:16];
            end
            if (berr1_seen) fpend <= 1'b0;
            // Last data write address (stack / pointer hint for the BERR).
            // (lastw_a capture dropped 19:10: 8010a45 stalled in routing)
            // First BERR: address, {FC, R/W, SIZ}, last program fetch, last write.
            if (berr_d && !cpu_berr_n && !berr1_seen) begin
                berr1_seen <= 1'b1;
                berr1_a    <= cpu_a;
                berr1_info <= {5'd0, cpu_fc, 7'd0, cpu_rw, 6'd0, cpu_siz, 8'hB1};
                berr1_pc   <= dbg_pc;
            end
            // After the first BERR: log the next 3 FC=5 word reads of $8..$3FF
            // (exception vectors), {addr[15:0], data[15:0]}.
            if (berr1_seen && vcnt == 2'd0 && as_d && !cpu_as_n && cpu_fc == 3'b101 && cpu_rw &&
                a24w[23:10] == 14'd0 && a24w[9:3] != 7'd0)
                begin vpend <= 1'b1; vaddr <= a24w[15:0]; end
            if (vpend && rd_done) begin
                vpend <= 1'b0;
                vcnt  <= vcnt + 2'd1;
                case (vcnt)
                    2'd0: vlog0 <= {vaddr, cpu_din[31:16]};
                    default: ;  // vlog2 dropped (routing)
                endcase
            end
            // Last 8 IO writes (shift in at [255:224]; [31:0] is oldest).
            if (io_wr) begin
                dbg_io_addr <= {io_a, 1'b0};
                dbg_io_data <= io_wdata;
                dbg_io_ring <= {{io_a, 1'b0, io_wdata}, dbg_io_ring[255:32]};
            end
            // Table-walk reads (FC=5, $700..$7FF). Accumulate a long.
            // 8a0cc24 showed the 1st BERR is a FC=5 long READ of $00FFFFFC with
            // only writes in flight (= a PMMU table-walk read). Now: any FC=5
            // read, frozen at the 1st BERR; the previous long is kept too, so
            // the HUD shows the two descriptor reads that led to the bad address.
            if (as_d && !cpu_as_n && cpu_fc == 3'b101 && cpu_rw && !berr1_seen)
                walk_pend <= 1'b1;
            if (berr1_seen) walk_pend <= 1'b0;
            else if (walk_pend && rd_done) begin
                walk_pend <= 1'b0;
                if (!a24w[1]) begin
                    pwalk_a <= walk_a; pwalk_d <= walk_d;
                    walk_a  <= a24w;
                    walk_d  <= {cpu_din[31:16], 16'h0000};
                end else begin
                    if (a24w[23:2] != walk_a[23:2]) begin
                        pwalk_a <= walk_a; pwalk_d <= walk_d;
                        walk_d[31:16] <= 16'h0000;
                    end
                    walk_a <= {a24w[23:2], 2'b00};
                    walk_d[15:0] <= cpu_din[31:16];
                end
            end
        end
    end
    assign dbg_ncyc = {3'b000, left_e0};
    // Row 4 (was $700/$740/$7C0/$7F8): first BERR addr, {FC,RW,SIZ,B1},
    // last fetch PC before it, last data write addr before it.
    // Row 3 (was TBLXOR/_phystop/_frclock): first three vector reads after it.
    assign dbg_cycs = {berr1_a, berr1_info, berr1_pc, lastw_a,
                       vlog2, vlog0, vlog1,
                       dbg_vco, 16'h0000,
                       outpc, prevpc,
                       walk_a, walk_d, 8'h00};

    WF68K30L_TOP #(.CLK_N_EXT(1), .CACHES(0), .WA_ADR_HI(1), .FAST_HANDOFF(1)) cpu (
        .CLK(clk_cpu), .CLK_N(clk_cpu_n), .ADR_OUT(cpu_a), .DATA_IN(cpu_din), .DATA_OUT(cpu_dout), .DATA_EN(),
        .BERRn(cpu_berr_n), .RESET_INn(!reset), .RESET_OUT(cpu_reset_out), .HALT_INn(!reset), .HALT_OUTn(cpu_halted_n),
        .FC_OUT(cpu_fc), .AVECn(cpu_avec_n), .IPLn(ipl_r), .IPENDn(), .DSACKn(cpu_dsack_n), .SIZE(cpu_siz),
        .ASn(cpu_as_n), .RWn(cpu_rw), .RMCn(cpu_rmc_n), .DSn(cpu_ds_n), .ECSn(), .OCSn(), .DBENn(), .BUS_EN(),
        .STERMn(1'b1), .BRn(1'b1), .BGn(), .BGACKn(1'b1),
        .CIINn(cpu_ciin_n), .MMU_ON(), .CDISn(1'b1), .CBACKn(1'b1), .CBREQn(), .CIOUTn());

    wire sel_videl, sel_nv_a, sel_nv_d, sel_ym, sel_mfp, sel_acia, sel_dma;
    // io_a is [15:1] (A15..A1): $FF8A00-$FF8A3F is A15:A6 = $228. The old io_a[15:5] == $450
    // matched only $FF8A00-$FF8A1F (halftone RAM), so every register at $FF8A20-$FF8A3F
    // (addresses, counts, HOP/OP, control) went to falcon_io's $FFFF default: TAS $FF8A3C read
    // $FF forever (board f6e5591: last 8 IO = 8A3C=FFFF, PC around E12BCC..BD6).
    wire sel_blt = io_cyc && (io_a[15:6] == 10'h228);   // $FF8A00-$FF8A3F
    wire io_ext = sel_mfp || sel_acia || sel_dma || sel_blt;
    wire io_cyc, io_uds, io_lds, io_wr, io_rw; wire [15:1] io_a; wire [15:0] io_wdata, io_rdata;
    falcon_bus bus (
        .clk(clk_cpu), .reset(reset),
        .cpu_a(cpu_a), .cpu_dout(cpu_dout), .cpu_din(cpu_din), .cpu_as_n(cpu_as_n), .cpu_ds_n(cpu_ds_n),
        .cpu_rw(cpu_rw), .cpu_siz(cpu_siz), .cpu_fc(cpu_fc), .cpu_dsack_n(cpu_dsack_n), .cpu_berr_n(cpu_berr_n),
        .cpu_avec_n(cpu_avec_n),
        .mem_req(mem_req), .mem_a(mem_a), .mem_we(mem_we), .mem_be(mem_be), .mem_wdata(mem_wdata),
        .mem_ack(mem_ack), .mem_rdata(mem_rdata),
        .io_cyc(io_cyc), .io_a(io_a), .io_uds(io_uds), .io_lds(io_lds), .io_rw(io_rw), .io_wr(io_wr), .io_wdata(io_wdata),
        .io_rdata(sel_blt ? blt_rdata : io_ext ? p_rdata : io_rdata), .io_ext(io_ext),
        .io_done(sel_blt ? blt_done : p_done), .br_want(blt_br), .bus_grant(blt_bg), .cyc_tog(cpu_cyc_tog), .iack_mfp(p_iack_mfp), .mfp_vector(mfp_vector), .mfp_dtack(mfp_dtack));

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
    assign p_sel_blt = sel_blt; assign p_uds = io_uds; assign p_lds = io_lds;

    falcon_nvram nvram (.clk(clk_cpu), .reset(reset), .sel_addr(sel_nv_a), .sel_data(sel_nv_d), .wr(io_wr),
        .din(io_wdata[7:0]), .dout(nv_d));
    falcon_ym_stub ym (.clk(clk_cpu), .reset(reset), .sel(sel_ym), .a(io_a[1]), .wr(io_wr),
        .din(io_wdata[15:8]), .dout(ym_d), .porta(ym_porta));
    videl_regs videl (.clk(clk_cpu), .reset(reset), .sel(sel_videl), .a(io_a), .uds(io_uds), .lds(io_lds),
        .wr(io_wr), .din(io_wdata), .dout(videl_d), .vcount(vcount),
        .fb_base(fb_base), .planes(planes), .hdbl(hdbl), .vdbl(vdbl), .height(height), .linebytes(linebytes),
        .st_pal_rd(st_pal_rd), .st_pal_idx(st_pal_idx), .fpal_wa(fpal_wa), .fpal_wd(fpal_wd), .fpal_we(fpal_we),
        .stpal_we(stpal_we), .stpal_wa(stpal_wa), .stpal_wd(stpal_wd),
        .dbg_hht(dbg_hht), .dbg_vft(dbg_vft), .dbg_spshift(dbg_spshift), .dbg_shmode(dbg_shmode),
        .dbg_vco(dbg_vco));
endmodule
