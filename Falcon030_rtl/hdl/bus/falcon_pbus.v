// falcon_pbus.v - FAL_01: clk_32 side of the Falcon peripheral sub-bus (MFP, ACIAs, floppy DMA)
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// clk_cpu (16 MHz) is phase-locked to clk_32 (one PLL, 2:1), so the clk_cpu signals of an IO cycle
// are sampled directly; falcon_bus.v holds them for the whole cycle. Per cycle this block:
//   - drives the peripheral strobes like a 68000 cycle as atarist.v did: MFP sel + ds low for
//     MFP_CLK clk_32 clocks (the MFP runs on the 4 MHz enable), dma.v sel for DMA_CLK clocks,
//     ACIA sel held across one full E period (6800-style VPA/VMA cycle, E = 32 MHz / 40 = 800 kHz
//     rounded from the ST's 8 MHz / 10);
//   - latches the read data, then raises done (one level until the cycle ends) for falcon_bus.
// Peripherals see each access exactly once (MFP UDR / ACIA RDR read side effects).
module falcon_pbus #(
    parameter integer MFP_CLK = 16,
    parameter integer DMA_CLK = 8
) (
    input  wire        clk_32,
    input  wire        reset,
    input  wire        sel_mfp, sel_acia, sel_dma, sel_addr,  // level, from falcon_core (clk_cpu)
    input  wire [7:0]  mfp_d, acia_d,
    input  wire [15:0] dma_d,
    output reg         mfp_cs, mfp_ds_n,
    output reg         acia_cs,
    output reg         dma_cs,
    output reg         E,                            // 6800 E clock for the ACIAs
    output reg  [15:0] rdata,
    output reg         done
);
    reg [5:0] ediv = 0;
    always @(posedge clk_32) begin
        ediv <= (ediv == 6'd39) ? 6'd0 : ediv + 6'd1;
        E <= (ediv >= 6'd24);                        // 40 % high, falls at ediv 0
    end
    wire e_fall = (ediv == 6'd0) && E;
    localparam I = 0, RUN = 1, AW = 2, AE = 3, FIN = 4;
    reg [2:0] st; reg [5:0] cnt;
    wire any = sel_mfp || sel_acia || sel_dma || sel_addr;
    always @(posedge clk_32) begin
        if (reset) begin st <= I; done <= 1'b0; mfp_cs <= 1'b0; mfp_ds_n <= 1'b1; acia_cs <= 1'b0; dma_cs <= 1'b0; end
        else case (st)
            I: if (any && !done) begin
                cnt <= 6'd0;
                if (sel_acia) begin st <= AW; end
                else begin mfp_cs <= sel_mfp; mfp_ds_n <= !sel_mfp; dma_cs <= sel_dma || sel_addr; st <= RUN; end
            end else if (!any) done <= 1'b0;
            RUN: begin
                cnt <= cnt + 6'd1;
                if (cnt == (mfp_cs ? MFP_CLK : DMA_CLK) - 1) begin
                    rdata <= mfp_cs ? {8'hFF, mfp_d} : dma_d;
                    mfp_cs <= 1'b0; mfp_ds_n <= 1'b1; dma_cs <= 1'b0; st <= FIN;
                end
            end
            AW: if (e_fall) begin acia_cs <= 1'b1; st <= AE; end   // start on an E period boundary
            AE: if (e_fall) begin rdata <= {acia_d, acia_d}; acia_cs <= 1'b0; st <= FIN; end
            FIN: begin done <= 1'b1; st <= I; end
            default: st <= I;
        endcase
    end
endmodule
