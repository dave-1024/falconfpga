// falcon_sdram_arb.v - FAL_01: ST-slot arbiter for sdram.v (scanout > floppy DMA > loader/CPU)
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The ST core's sdram.v ST port is driven by the GSTMCU's fixed 8-clock (250 ns
// at 32 MHz) slot cadence: a rising cs at phase 0 starts RAS, CAS at phase 1,
// read data is in dout the cycle after phase 4 (STATE_READ). There is no GSTMCU
// here, so this block generates that cadence and picks one master per slot:
//   1. a periodic AUTO_REFRESH (every 16 slots = 4 us; 8192 rows in ~33 ms)
//   2. scanout line-fetch (highest client)
//   3. floppy DMA (falcon_fdc.v ram_req)
//   4. TOS loader (CPU is held in reset)
//   5. CPU word port of falcon_bus.v
// Bank mapping (DESIGN.md): 16 MB in banks 0/1, bank = {1'b0, byte A23}, word
// address = A22:A1. The ST build ties st_ba to 0 and is unchanged.
// ecs is held 0 in v1 (proven 8-clock cycle, no early start).
//
// Scanout uses sdram.v st_rd2 (page-mode burst-2, MODE stays BL=1): 160
// words of 640x480 4-plane in 80 slots = 20 us, inside a 31.8 us HDMI line.
module falcon_sdram_arb (
    input  wire        clk,             // clk_32, same edge as sdram.v
    input  wire        reset,           // sync, active high
    input  wire        ram_ready,
    // sdram.v ST port
    output reg         sd_cs,
    output reg         sd_we,
    output reg         sd_refresh,
    output wire        sd_ecs,
    output reg  [21:0] sd_addr,
    output reg  [1:0]  sd_ds,           // active-high byte masks (like GSTMCU CAS_n)
    output reg  [15:0] sd_din,
    input  wire [15:0] sd_dout,
    input  wire [15:0] sd_dout2,        // FAL_01 burst-2 second word
    output reg         sd_rd2,          // 1 = page-mode 2-word read this slot (scanout)
    output reg  [1:0]  sd_ba,
    // scanout
    input  wire        vid_req,
    input  wire [23:1] vid_a,
    output reg         vid_ack,
    output reg  [15:0] vid_q,
    output reg  [15:0] vid_q2,
    // floppy DMA
    input  wire        dma_req,
    input  wire        dma_we,
    input  wire [23:1] dma_a,
    input  wire [15:0] dma_d,
    output reg         dma_ack,
    output reg  [15:0] dma_q,
    // TOS loader (writes only)
    input  wire        ld_req,
    input  wire [23:1] ld_a,
    input  wire [15:0] ld_d,
    output reg         ld_ack,
    // CPU (clk_cpu 16 MHz, phase-locked; req held until ack, ack held until req falls)
    input  wire        cpu_req,
    input  wire [23:1] cpu_a,
    input  wire        cpu_we,
    input  wire [1:0]  cpu_be,          // {UDS,LDS} active high
    input  wire [15:0] cpu_d,
    input  wire        cpu_rd2,         // BUS-1: aligned long read, fetch A and A+2 in one slot (burst-2)
    output reg         cpu_ack,
    output wire [15:0] cpu_q,           // BUS-1: sdram.v dout itself (valid from the phase-4 edge to the next read)
    output wire [15:0] cpu_q2,          // BUS-1: sdram.v dout2 (second burst word, valid from the phase-5 edge)
    output reg         ext_wr_tog       // BLI-11h: toggles at the start of every floppy-DMA / loader write slot (falcon_bus buf2 invalidate)
);
    assign sd_ecs = 1'b0;

    localparam WIN_NONE = 3'd0, WIN_REF = 3'd1, WIN_VID = 3'd2,
               WIN_DMA  = 3'd3, WIN_LD  = 3'd4, WIN_CPU = 3'd5;

    reg [2:0] ph;                       // 0..7 slot phase
    reg [2:0] win;

    reg       vid_burst;                // this slot issued st_rd2
    // BUS-1 (25 Nov 2026): the slot cadence parks at phase 7 while no master wants the SDRAM, so a request
    // starts a slot on the next clk32 edge instead of waiting up to 7 clocks for the free-running phase 7.
    // sdram.v starts a cycle on any rising cs while it is idle (8 clocks per cycle, auto precharge), and a
    // parked phase 7 is always >= 8 clocks after the previous start. Refresh therefore comes from its own
    // 4 us timer (128 clk32) instead of counting slots: pending refresh wins the next slot.
    reg [6:0] reftmr;
    reg       ref_pend;
    assign cpu_q  = sd_dout;
    assign cpu_q2 = sd_dout2;

    wire [23:1] a_vid = vid_a, a_dma = dma_a, a_ld = ld_a, a_cpu = cpu_a;
    function [21:0] waddr; input [23:1] a; begin waddr = a[22:1]; end endfunction
    function [1:0]  bank;  input [23:1] a; begin bank  = {1'b0, a[23]}; end endfunction

    wire take_vid = vid_req && !vid_ack;
    wire take_dma = dma_req && !dma_ack;
    wire take_ld  = ld_req  && !ld_ack;
    wire take_cpu = cpu_req && !cpu_ack;

    always @(posedge clk) begin
        if (reset || !ram_ready) begin
            ph <= 3'd0; win <= WIN_NONE; reftmr <= 7'd0; ref_pend <= 1'b0;
            sd_cs <= 1'b0; sd_we <= 1'b0; sd_refresh <= 1'b0; sd_rd2 <= 1'b0;
            sd_ds <= 2'b00; sd_addr <= 22'd0; sd_ba <= 2'b00; sd_din <= 16'd0;
            vid_ack <= 1'b0; dma_ack <= 1'b0; ld_ack <= 1'b0; cpu_ack <= 1'b0;
            vid_burst <= 1'b0; ext_wr_tog <= 1'b0;
        end else begin
            if (vid_ack && !vid_req) vid_ack <= 1'b0;
            if (dma_ack && !dma_req) dma_ack <= 1'b0;
            if (ld_ack  && !ld_req)  ld_ack  <= 1'b0;
            if (cpu_ack && !cpu_req) cpu_ack <= 1'b0;

            reftmr <= reftmr + 7'd1;
            if (reftmr == 7'd127) ref_pend <= 1'b1;
            // park at phase 7 when nothing is wanted (see BUS-1 above)
            if (ph != 3'd7 || ref_pend || take_vid || take_dma || take_ld || take_cpu) ph <= ph + 3'd1;

            // sdram.v samples cs with a 1-cycle csD delay: to start a cycle on
            // our phase 0 (ACTIVE) we drop cs at phase 6 and raise it, with
            // addr/we/din already driven, at phase 7. Back-to-back slots stay
            // at 8 clocks. dout is captured at phase 5 (one edge after STATE_READ).
            if (ph == 3'd6) begin
                sd_cs <= 1'b0;
                sd_refresh <= 1'b0;
            end

            if (ph == 3'd7) begin
                if (ref_pend) begin
                    win <= WIN_REF; ref_pend <= 1'b0;
                    sd_cs <= 1'b1; sd_we <= 1'b0; sd_refresh <= 1'b1;
                    sd_ds <= 2'b00; sd_ba <= 2'b00;
                end else begin
                    sd_refresh <= 1'b0;
                    if (take_vid) begin
                        win <= WIN_VID;
                        sd_cs <= 1'b1; sd_we <= 1'b0; sd_ds <= 2'b00;
                        sd_addr <= waddr(a_vid); sd_ba <= bank(a_vid);
                        // burst-2 unless the column would wrap (sdram.v also guards this)
                        vid_burst <= (a_vid[9:1] != 9'h1FF);
                        sd_rd2    <= (a_vid[9:1] != 9'h1FF);
                    end else if (take_dma) begin
                        win <= WIN_DMA; vid_burst <= 1'b0; sd_rd2 <= 1'b0;
                        if (dma_we) ext_wr_tog <= ~ext_wr_tog;
                        sd_cs <= 1'b1; sd_we <= dma_we; sd_ds <= 2'b00;
                        sd_addr <= waddr(a_dma); sd_ba <= bank(a_dma); sd_din <= dma_d;
                    end else if (take_ld) begin
                        win <= WIN_LD; vid_burst <= 1'b0; sd_rd2 <= 1'b0; ext_wr_tog <= ~ext_wr_tog;
                        sd_cs <= 1'b1; sd_we <= 1'b1; sd_ds <= 2'b00;
                        sd_addr <= waddr(a_ld); sd_ba <= bank(a_ld); sd_din <= ld_d;
                    end else if (take_cpu) begin
                        win <= WIN_CPU; vid_burst <= 1'b0; sd_rd2 <= cpu_rd2 && !cpu_we;
                        sd_cs <= 1'b1; sd_we <= cpu_we; sd_ds <= cpu_we ? ~cpu_be : 2'b00;
                        sd_addr <= waddr(a_cpu); sd_ba <= bank(a_cpu); sd_din <= cpu_d;
                        // BUS-1: a write is posted. Address, masks and data are in the sd_* registers now
                        // and sdram.v takes them at phase 0/1, so the master may end its cycle at once.
                        if (cpu_we) cpu_ack <= 1'b1;
                    end else begin
                        win <= WIN_NONE; vid_burst <= 1'b0; sd_rd2 <= 1'b0;
                        sd_cs <= 1'b0; sd_we <= 1'b0;
                    end
                end
            end

            // Burst word 2 is one clock later (phase 6).
            // dout is written by sdram.v on the STATE_READ edge (phase 4);
            // it is visible here on the next edge (phase 5). For the CPU port,
            // present data at phase 5 and raise ack at phase 6 so a clk_cpu
            // flop that samples ack on the same edge still sees data that is
            // at least one clk32 (31.25 ns) old. clk_cpu rising coincides with
            // a clk32 edge; ph versus that edge is not fixed (ram_ready release).
            if (ph == 3'd5) begin
                case (win)
                    WIN_VID: begin vid_q <= sd_dout; if (!vid_burst) vid_ack <= 1'b1; end
                    WIN_DMA: begin dma_q <= sd_dout; dma_ack <= 1'b1; end
                    WIN_LD:  begin ld_ack <= 1'b1; end
                    WIN_CPU: ;
                    default: ;
                endcase
            end
            if (ph == 3'd6 && win == WIN_VID && vid_burst) begin
                vid_q2 <= sd_dout2; vid_ack <= 1'b1; sd_rd2 <= 1'b0;
            end
            // BUS-1: read ack on the phase-4 edge, the same edge sdram.v writes dout (cpu_q is that register,
            // so a master that samples ack on any later edge sees the word). A burst-2 CPU read's second word
            // (cpu_q2) is written on the phase-5 edge; falcon_bus samples it one clk_cpu after the ack.
            if (ph == 3'd4 && win == WIN_CPU && !sd_we) cpu_ack <= 1'b1;
            if (ph == 3'd6 && win == WIN_CPU) sd_rd2 <= 1'b0;
        end
    end
endmodule
