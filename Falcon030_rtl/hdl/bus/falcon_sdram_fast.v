// falcon_sdram_fast.v - SDR-1: SDRAM controller + arbiter at 80 MHz (clk_sd = pll_160m CLKOUT0, VCO 800 / 10)
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Replaces falcon_sdram_arb.v + sdram.v (32 MHz, fixed 8-clock = 250 ns slots). Same client ports.
// Why 80 and not 64 MHz: 64 MHz cannot come from the 50 MHz board clock on the PLL that makes clk32 /
// clk_cpu030 (needs a 1600 MHz VCO, out of range). The 2025 sdram64 attempt used a second PLL fed from
// clk32; STA could not follow that cascade and the clk32 <-> 64 MHz handover was mistimed (BAD ROM CRC).
// 80 MHz = VCO 800 / 10 on the SAME PLL: clk_cpu030 = clk_sd / 5, clk32 = clk_sd / 2.5, all phase-locked
// and timed by STA (worst clk32 <-> clk_sd edge pair 6.25 ns, clk_cpu <-> clk_sd 12.5 ns).
//
// W9825G6KH-6 at 80 MHz (12.5 ns): CL2, BL1, tRCD 2, tRAS 4, tRP 2, tRC 5, tWR 2, tRFC 6 clocks.
// One slot = 6 clocks (75 ns, was 250 ns), one bank opened and closed per access:
//   read : a0 ACT, a2 READ, a4 PRE       | burst-2: a2 READ, a3 READ (col+1), a4 PRE
//   write: a0 ACT, a2 WRITE (DQ, DQM), a4 PRE | refresh: a0 AUTO REFRESH; next slot a6
// Read data: the DQ input register samples on READ+3 (as sdram.v at 32 MHz; pad clock leads clk_sd),
// the client register is written on READ+4.
// CPU word read (falcon_bus raises mem_req on a clk_cpu edge, idle SDRAM): captured +1, ACT reg +2 (pin +3),
// READ pin +5, DQ +8, cpu_q/ack +9, falcon_bus sees ack on the next clk_cpu edge (+10) = 2 clk_cpu (was 4).
//
// Domains: every input is registered once in clk_sd. cpu_ack/cpu_q/cpu_q2 are clk_sd registers for
// falcon_bus (clk_cpu, 12.5 ns). The clk32 clients (scanout, floppy DMA, loader, blitter on the CPU port,
// debug) get clk32 copies (*_32), so their logic never sees the 6.25 ns clk_sd -> clk32 edge pair.
// 4-phase handshake as before: req held until ack, ack held (internally) until req is seen low.
// Priority per slot: refresh > scanout > floppy DMA > loader > CPU/blitter (as falcon_sdram_arb).
module falcon_sdram_fast #(
    parameter integer INIT_WAIT = 16000,  // clk_sd clocks of NOP after reset (200 us)
    parameter integer REF_INT   = 300     // clk_sd clocks between AUTO REFRESH (3.75 us; 8192 rows in 31 ms)
) (
    input  wire        clk_sd,          // 80 MHz
    input  wire        clk_32,          // 32 MHz, same PLL
    input  wire        reset,           // clk32 domain, active high
    // chip pins
    output wire        sd_clk, sd_cke, sd_cs, sd_we, sd_ras, sd_cas,
    inout  wire [31:0] sd_data,
    output wire [12:0] sd_addr,
    output wire [3:0]  sd_dqm,
    output wire [1:0]  sd_ba,
    output reg         ram_ready,       // clk32 copy
    // scanout (clk32)
    input  wire        vid_req,
    input  wire [23:1] vid_a,
    output reg         vid_ack,
    output reg  [15:0] vid_q,
    output reg  [15:0] vid_q2,
    // floppy DMA (clk32)
    input  wire        dma_req,
    input  wire        dma_we,
    input  wire [23:1] dma_a,
    input  wire [15:0] dma_d,
    output reg         dma_ack,
    output reg  [15:0] dma_q,
    // TOS loader (clk32, writes only)
    input  wire        ld_req,
    input  wire [23:1] ld_a,
    input  wire [15:0] ld_d,
    output reg         ld_ack,
    // CPU port (falcon_bus on clk_cpu, or the blitter on clk32)
    input  wire        cpu_req,
    input  wire [23:1] cpu_a,
    input  wire        cpu_we,
    input  wire [1:0]  cpu_be,          // {UDS,LDS} active high
    input  wire [15:0] cpu_d,
    input  wire        cpu_rd2,         // aligned long read: also fetch A+2 (second word -> cpu_q2)
    output reg         cpu_ack,         // clk_sd (falcon_bus)
    output reg  [15:0] cpu_q,           // clk_sd, valid with cpu_ack
    output reg  [15:0] cpu_q2,          // clk_sd, valid one clk_sd after cpu_ack
    output reg         cpu_ack_32,      // clk32 copies (blitter, debug write watch)
    output reg  [15:0] cpu_q_32,
    output reg         ext_wr_tog       // toggles when a floppy-DMA / loader write is taken (falcon_bus buf2)
);
    localparam [2:0] CMD_NOP = 3'b111, CMD_ACT = 3'b011, CMD_RD = 3'b101, CMD_WR = 3'b100,
                     CMD_PRE = 3'b010, CMD_REF = 3'b001, CMD_MRS = 3'b000;
    // {WB single, op 00, CL2, sequential, BL1}
    localparam [12:0] MODE = 13'h0220;
    localparam [2:0] W_NONE = 3'd0, W_VID = 3'd2, W_DMA = 3'd3, W_LD = 3'd4, W_CPU = 3'd5;

    // SDR-1 S3: fabric command registers (*_f, with enables) feed one IOB register stage that loads every clock (no CE, so
    // Gowin can pack it; S2's sa/sb with CE stayed in fabric: -10.3 ns pad path). Pins are one clk_sd behind the *_f regs.
    reg [2:0]  cmd_f = CMD_NOP;
    reg [15:0] dqo_f = 16'h0000;
    reg [1:0]  dqm_f = 2'b00;
    reg        oe_f  = 1'b0;
    reg        oe_hold = 1'b0;   // S5: keep DQ driven one more clk_sd after the WRITE (turn-off hold margin)
    reg [12:0] sa = 13'h0000;
    reg [1:0]  sb = 2'b00;
    (* syn_useioff = 1 *) reg [2:0]  sd_cmd = CMD_NOP;
    (* syn_useioff = 1 *) reg [15:0] dq_out = 16'h0000;
    (* syn_useioff = 1 *) reg [1:0]  dqm_r  = 2'b00;
    (* syn_useioff = 1 *) reg [15:0] dq_in  = 16'h0000;
    (* syn_useioff = 1 *) reg [12:0] sa_o = 13'h0000;
    (* syn_useioff = 1 *) reg [1:0]  sb_o = 2'b00;
    // S4: one OE register per DQ pin (S3: a single fabric dq_oe fanning out to 16 OEN pins, -9.2 ns).
    // S5: stored active-LOW (1 = tristate) so the register drives the buffer OEN pin with no inverter and can be IOB-packed
    // (S4: active-high per-pin regs stayed in fabric, -1.518 ns).
    (* syn_useioff = 1, syn_preserve = 1 *) reg [15:0] dq_oen = 16'hFFFF;
    always @(posedge clk_sd) begin
        sd_cmd <= cmd_f; sa_o <= sa; sb_o <= sb; dq_out <= dqo_f; dqm_r <= dqm_f; dq_oen <= {16{~oe_f}};
    end
    assign sd_addr = sa_o;
    assign sd_ba   = sb_o;
    assign sd_clk = 1'b0;            // the pad clock comes from pll_160m CLKOUT2
    assign sd_cke = 1'b1;
    assign sd_cs  = 1'b0;
    assign sd_ras = sd_cmd[2];
    assign sd_cas = sd_cmd[1];
    assign sd_we  = sd_cmd[0];
    genvar gi;
    generate for (gi = 0; gi < 16; gi = gi + 1) begin : g_dq
        assign sd_data[gi] = dq_oen[gi] ? 1'bz : dq_out[gi];
    end endgenerate
    assign sd_data[31:16] = 16'bz;
    assign sd_dqm  = {2'bzz, dqm_r};

    // ---- reset into clk_sd ----
    // S4: reset taken into a local clk32 register first (S3: the 868-fanout POR sync drove rst_s directly, -0.032 ns)
    reg       rst_p = 1'b1;
    always @(posedge clk_32) rst_p <= reset;
    reg [1:0] rst_s = 2'b11;
    always @(posedge clk_sd) rst_s <= {rst_s[0], rst_p};
    wire rst = rst_s[1];

    // ---- clk32 clients: registered once in clk32 first (S1: fdc dma_d logic + the 6.25 ns clk32->clk_sd pair failed) ----
    reg        vreq_p = 1'b0, dreq_p = 1'b0, dwe_p = 1'b0, lreq_p = 1'b0;
    reg [23:1] va_p, da_p, la_p;
    reg [15:0] dd_p, ld_p;
    always @(posedge clk_32) begin
        vreq_p <= vid_req; va_p <= vid_a;
        dreq_p <= dma_req; dwe_p <= dma_we; da_p <= dma_a; dd_p <= dma_d;
        lreq_p <= ld_req;  la_p <= ld_a; ld_p <= ld_d;
    end
    // ---- input registers (one clk_sd stage, no logic in front) ----
    reg        vreq_r = 1'b0, dreq_r = 1'b0, dwe_r = 1'b0, lreq_r = 1'b0, creq_r = 1'b0, cwe_r = 1'b0, crd2_r = 1'b0;
    reg [23:1] va_r, da_r, la_r, ca_r;
    reg [15:0] dd_r, ld_r, cd_r;
    reg [1:0]  cbe_r;
    always @(posedge clk_sd) begin
        vreq_r <= vreq_p; va_r <= va_p;
        dreq_r <= dreq_p; dwe_r <= dwe_p; da_r <= da_p; dd_r <= dd_p;
        lreq_r <= lreq_p; la_r <= la_p; ld_r <= ld_p;
        creq_r <= cpu_req; cwe_r <= cpu_we; ca_r <= cpu_a; cd_r <= cpu_d; cbe_r <= cpu_be; crd2_r <= cpu_rd2;
    end

    // ---- internal acks (clk_sd) ----
    reg vack = 1'b0, dack = 1'b0, lack = 1'b0;
    reg [15:0] vq = 16'h0, vq2 = 16'h0, dq = 16'h0;
    wire take_vid = vreq_r && !vack;
    wire take_dma = dreq_r && !dack;
    wire take_ld  = lreq_r && !lack;
    wire take_cpu = creq_r && !cpu_ack;

    // ---- init / refresh / slot state ----
    reg [14:0] icnt = 15'd0;
    reg [3:0]  istep = 4'd0;
    reg        ready = 1'b0;
    reg [8:0]  reftmr = 9'd0;
    reg        ref_pend = 1'b0;
    reg        busy = 1'b0;
    reg [2:0]  sc = 3'd0;            // slot clock of the NEXT edge (1..5)
    reg [2:0]  win = W_NONE;
    reg        s_we = 1'b0, s_rd2 = 1'b0;
    reg [8:0]  s_col = 9'd0;
    reg [1:0]  s_ba = 2'b00;
    reg [1:0]  s_be = 2'b00;
    reg [15:0] s_d = 16'h0;
    // read pipeline: bit k set k+1 clocks after the READ edge; [3] = dq_in holds the word now
    reg [4:0]  rp0 = 5'd0, rp1 = 5'd0;   // S3: +1 for the IOB stage (pin READ = issue+1, dq_in = issue+4, copy issue+5)
    reg [2:0]  dwin = W_NONE;        // owner of the words in flight (set at the first READ)
    reg        d_rd2 = 1'b0;

    function [12:0] rowof; input [23:1] a; begin rowof = a[22:10]; end endfunction
    function [8:0]  colof; input [23:1] a; begin colof = a[9:1];   end endfunction
    function [1:0]  bankof; input [23:1] a; begin bankof = {1'b0, a[23]}; end endfunction

    always @(posedge clk_sd) begin
        cmd_f <= CMD_NOP;
        oe_f  <= oe_hold;
        oe_hold <= 1'b0;
        dqm_f <= 2'b00;
        dq_in  <= sd_data[15:0];
        rp0 <= {rp0[3:0], 1'b0};
        rp1 <= {rp1[3:0], 1'b0};
        // 4-phase: an ack falls once its request is seen low
        if (vack && !vreq_r) vack <= 1'b0;
        if (dack && !dreq_r) dack <= 1'b0;
        if (lack && !lreq_r) lack <= 1'b0;
        if (cpu_ack && !creq_r) cpu_ack <= 1'b0;

        if (rst) begin
            icnt <= 15'd0; istep <= 4'd0; ready <= 1'b0; busy <= 1'b0; sc <= 3'd0;
            reftmr <= 9'd0; ref_pend <= 1'b0; win <= W_NONE; rp0 <= 5'd0; rp1 <= 5'd0;
            vack <= 1'b0; dack <= 1'b0; lack <= 1'b0; cpu_ack <= 1'b0; ext_wr_tog <= 1'b0;
        end else if (!ready) begin
            // power-up: NOP wait, PRECHARGE ALL, 2 x AUTO REFRESH, LOAD MODE
            icnt <= icnt + 15'd1;
            case (istep)
            4'd0: if (icnt == INIT_WAIT[14:0]) begin cmd_f <= CMD_PRE; sa <= 13'h0400; istep <= 4'd1; icnt <= 15'd0; end
            4'd1: if (icnt == 15'd4)  begin cmd_f <= CMD_REF; istep <= 4'd2; icnt <= 15'd0; end
            4'd2: if (icnt == 15'd8)  begin cmd_f <= CMD_REF; istep <= 4'd3; icnt <= 15'd0; end
            4'd3: if (icnt == 15'd8)  begin cmd_f <= CMD_MRS; sa <= MODE; sb <= 2'b00; istep <= 4'd4; icnt <= 15'd0; end
            4'd4: if (icnt == 15'd4)  begin ready <= 1'b1; end
            default: ;
            endcase
        end else begin
            reftmr <= reftmr + 9'd1;
            if (reftmr == REF_INT[8:0] - 9'd1) begin reftmr <= 9'd0; ref_pend <= 1'b1; end

            if (busy) begin
                sc <= sc + 3'd1;
                if (sc == 3'd5) busy <= 1'b0;
                if (sc == 3'd2 && win != W_NONE) begin
                    sb <= s_ba;
                    if (s_we) begin
                        cmd_f <= CMD_WR; sa <= {4'b0000, s_col};
                        dqo_f <= s_d; oe_f <= 1'b1; oe_hold <= 1'b1; dqm_f <= ~s_be;
                    end else begin
                        cmd_f <= CMD_RD; sa <= {4'b0000, s_col};
                        rp0[0] <= 1'b1; dwin <= win; d_rd2 <= s_rd2;
                    end
                end
                if (sc == 3'd3 && win != W_NONE && !s_we && s_rd2) begin
                    cmd_f <= CMD_RD; sa <= {4'b0000, s_col + 9'd1}; sb <= s_ba;
                    rp1[0] <= 1'b1;
                end
                // explicit bank PRECHARGE at a4 (tRAS 50 ns, tWR 2 after the a2 WRITE, after the last READ of
                // a burst-2 at a3 with CL2 the data is not cut); next ACT at a6 (tRP 25 ns, tRC 75 ns)
                if (sc == 3'd4 && win != W_NONE) begin
                    cmd_f <= CMD_PRE; sa <= 13'h0000; sb <= s_ba;
                end
            end else begin
                // slot start: ACT (or REFRESH) on this edge
                sc <= 3'd1;
                if (ref_pend) begin
                    busy <= 1'b1; win <= W_NONE; ref_pend <= 1'b0; cmd_f <= CMD_REF;
                end else if (take_vid) begin
                    busy <= 1'b1; win <= W_VID; s_we <= 1'b0; s_rd2 <= (va_r[9:1] != 9'h1FF);
                    cmd_f <= CMD_ACT; sa <= rowof(va_r); sb <= bankof(va_r);
                    s_col <= colof(va_r); s_ba <= bankof(va_r);
                end else if (take_dma) begin
                    busy <= 1'b1; win <= W_DMA; s_we <= dwe_r; s_rd2 <= 1'b0; s_be <= 2'b11; s_d <= dd_r;
                    cmd_f <= CMD_ACT; sa <= rowof(da_r); sb <= bankof(da_r);
                    s_col <= colof(da_r); s_ba <= bankof(da_r);
                    if (dwe_r) begin dack <= 1'b1; ext_wr_tog <= ~ext_wr_tog; end   // posted write
                end else if (take_ld) begin
                    busy <= 1'b1; win <= W_LD; s_we <= 1'b1; s_rd2 <= 1'b0; s_be <= 2'b11; s_d <= ld_r;
                    cmd_f <= CMD_ACT; sa <= rowof(la_r); sb <= bankof(la_r);
                    s_col <= colof(la_r); s_ba <= bankof(la_r);
                    lack <= 1'b1; ext_wr_tog <= ~ext_wr_tog;
                end else if (take_cpu) begin
                    busy <= 1'b1; win <= W_CPU; s_we <= cwe_r; s_rd2 <= crd2_r && !cwe_r && (ca_r[9:1] != 9'h1FF);
                    s_be <= cbe_r; s_d <= cd_r;
                    cmd_f <= CMD_ACT; sa <= rowof(ca_r); sb <= bankof(ca_r);
                    s_col <= colof(ca_r); s_ba <= bankof(ca_r);
                    if (cwe_r) cpu_ack <= 1'b1;   // posted write
                end
            end

            // read data hand-off (pin READ+4; dq_in was sampled on pin READ+3)
            if (rp0[4]) begin
                case (dwin)
                W_VID: begin vq <= dq_in; if (!d_rd2) vack <= 1'b1; end
                W_DMA: begin dq <= dq_in; dack <= 1'b1; end
                W_CPU: begin cpu_q <= dq_in; cpu_ack <= 1'b1; end
                default: ;
                endcase
            end
            if (rp1[4]) begin
                case (dwin)
                W_VID: begin vq2 <= dq_in; vack <= 1'b1; end
                W_CPU: cpu_q2 <= dq_in;
                default: ;
                endcase
            end
        end
    end

    // ---- clk32 copies for the clk32 clients ----
    // S4: one extra clk_sd stage (*_x, acks and data together) so the long route from the DQ IOB side to the clk32 logic
    // is on a 12.5 ns clk_sd pair, not the 6.25 ns clk_sd->clk32 pair (S3: vq -> vid_q -0.475 ns, pure route).
    reg        rdy_x = 1'b0, vack_x = 1'b0, dack_x = 1'b0, lack_x = 1'b0, cack_x = 1'b0;
    reg [15:0] vq_x = 16'h0, vq2_x = 16'h0, dq_x = 16'h0, cq_x = 16'h0;
    // S8e: S8d cq_x -> cpu_q_32 was -0.170 ns (6.25 ns clk_sd -> clk32 pair, pure route): a second stage near the clk32 regs
    reg        cack_y = 1'b0;
    reg [15:0] cq_y = 16'h0;
    always @(posedge clk_sd) begin
        rdy_x <= ready && !rst;
        vack_x <= vack; vq_x <= vq; vq2_x <= vq2;
        dack_x <= dack; dq_x <= dq;
        lack_x <= lack;
        cack_x <= cpu_ack; cq_x <= cpu_q;
        cack_y <= cack_x;  cq_y <= cq_x;    // S8e: one more clk_sd stage for the blitter/write-watch copy (ack and data together)
    end
    always @(posedge clk_32) begin
        ram_ready <= rdy_x;
        vid_ack <= vack_x; vid_q <= vq_x; vid_q2 <= vq2_x;
        dma_ack <= dack_x; dma_q <= dq_x;
        ld_ack  <= lack_x;
        cpu_ack_32 <= cack_y; cpu_q_32 <= cq_y;
    end
endmodule
