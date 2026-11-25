// falcon_io.v - FAL_01: Falcon030 IO block: register selects, stubs and the read mux
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Sits behind falcon_bus.v (which only passes whitelisted addresses, everything else has
// already bus-errored). Real blocks outside (MFP, ACIAs, FDC/DMA) get a select and return
// their data here; small blocks live inside (NVRAM, YM stub, VIDEL regs are instanced by the
// core). Stub behaviour follows falcon_m28.c (Hybrid030 booted TOS 4.04 with it):
//   $FF8006   monitor type b7:6 + RAM size code (MONITOR, MEMCODE), b7:0 of $FF8007 latch
//   $FF860E   floppy density latch (bits 1:0, 11 = HD) -> fdc_hd
//   $FF8780   NCR5380: reg 1 ICR (AIP follows mode bit 0), reg 2 mode reads back, rest 0
//   $FF8900-$FF897F, $FF8C80, $FF8000-$FF800F (except $8006): byte latches
//   $FF9200   joypads/DIP: $FF
//   $FFA200   DSP host: ISR ($A202) reads $06 (TXDE|TRDY), others $FF
module falcon_io #(
    parameter [1:0] MONITOR = 2'b10,   // VGA
    parameter [2:0] MEMCODE = 3'd5     // 14 MB
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        mon_rgb,        // VID-SPLIT: helper option V: 1 = RGB monitor (b7:6 = 01), 0 = MONITOR (VGA)
    input  wire        cyc,            // falcon_bus io_cyc
    input  wire [15:1] a,
    input  wire        uds, lds,
    input  wire        wr,             // one-clock strobe
    input  wire [15:0] din,
    output reg  [15:0] dout,
    // selects to the real blocks (level while cyc)
    output wire        sel_videl, sel_nvram_a, sel_nvram_d, sel_ym, sel_mfp, sel_acia, sel_dma,
    input  wire [15:0] videl_d,
    input  wire [7:0]  nvram_d, ym_d, mfp_d, acia_d,
    input  wire [15:0] dma_d,
    output reg  [1:0]  fdc_hd
);
    wire [15:0] r = {a, 1'b0};
    assign sel_videl   = cyc && ((r >= 16'h8200 && r <= 16'h82C6) || (r >= 16'h9800 && r <= 16'h9BFE));
    assign sel_nvram_a = cyc && r == 16'h8960 && lds;
    assign sel_nvram_d = cyc && r == 16'h8962 && lds;
    assign sel_ym      = cyc && r[15:8] == 8'h88;
    assign sel_mfp     = cyc && r >= 16'hFA00 && r <= 16'hFA3E;
    assign sel_acia    = cyc && r >= 16'hFC00 && r <= 16'hFC06;
    assign sel_dma     = cyc && r >= 16'h8604 && r <= 16'h860C;
    wire   is_dens     = cyc && r == 16'h860E;
    // byte latch stubs: 128 bytes sound/xbar ($8900-$897F), 16 config ($8000), 8 SCC
    reg [7:0] snd [0:127]; reg [7:0] cfg [0:15]; reg [7:0] scc [0:7]; reg [7:0] scsi [0:7];
    wire is_snd = cyc && r[15:7] == 9'h112 && !(r == 16'h8960 || r == 16'h8962);
    // $FF8A00-$FF8A3F: real blitter, falcon_blitter.v (clk_32 io_ext cycle in falcon_core)
    wire is_cfg = cyc && r[15:4] == 12'h800;
    wire is_scc = cyc && r[15:3] == 13'h1190;
    wire is_scsi= cyc && r[15:4] == 12'h878;
    wire is_joy = cyc && r[15:5] == 11'h490;
    wire is_dsp = cyc && r[15:3] == 13'h1440;
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            fdc_hd <= 2'b00;
            for (i = 0; i < 16; i = i + 1) cfg[i] <= 8'h00;
        end else if (wr) begin
            if (is_dens && lds) fdc_hd <= din[1:0];
            if (is_snd) begin if (uds) snd[{r[6:1], 1'b0}] <= din[15:8]; if (lds) snd[{r[6:1], 1'b1}] <= din[7:0]; end
            if (is_cfg) begin if (uds) cfg[{r[3:1], 1'b0}] <= din[15:8]; if (lds) cfg[{r[3:1], 1'b1}] <= din[7:0]; end
            if (is_scc) begin if (uds) scc[{r[2:1], 1'b0}] <= din[15:8]; if (lds) scc[{r[2:1], 1'b1}] <= din[7:0]; end
            if (is_scsi && lds) scsi[r[3:1]] <= din[7:0];
        end
    end
    always @(*) begin
        dout = 16'hFFFF;
        if (sel_videl) dout = videl_d;
        else if (sel_nvram_a || sel_nvram_d) dout = {8'hFF, nvram_d};
        else if (sel_ym)   dout = {ym_d, ym_d};
        else if (sel_mfp)  dout = {8'hFF, mfp_d};
        else if (sel_acia) dout = {acia_d, acia_d};
        else if (sel_dma)  dout = dma_d;
        else if (is_dens)  dout = {8'hFF, 6'h00, fdc_hd};
        // TOS 4.04 at $E0013A: memcfg = (($FF8006>>1)&1) | (($FF8006>>3)&6).
        // Hybrid030 falcon_m28.c: $A2 = VGA (b7:6=10) + MEMCODE 5 (b5:4=10, b1=1) = 14 MB.
        else if (is_cfg && r == 16'h8006) dout = {(mon_rgb ? 2'b01 : MONITOR), MEMCODE[2:1], 2'b00, MEMCODE[0], 1'b0, cfg[7]};
        else if (is_cfg)   dout = {cfg[{r[3:1], 1'b0}], cfg[{r[3:1], 1'b1}]};
        else if (is_snd)   dout = {snd[{r[6:1], 1'b0}], snd[{r[6:1], 1'b1}]};
        else if (is_scc)   dout = {scc[{r[2:1], 1'b0}], scc[{r[2:1], 1'b1}]};
        else if (is_scsi)  dout = {8'hFF, r[3:1] == 3'd1 ? ((scsi[1] & 8'h9F) | (scsi[2][0] ? 8'h40 : 8'h00)) :
                                          r[3:1] == 3'd2 ? scsi[2] : 8'h00};
        else if (is_joy)   dout = 16'hFFFF;
        else if (cyc && r < 16'h0040) dout = 16'h0000;   // IDE $F00000-$F0003F: no device (status 0)
        else if (is_dsp)   dout = (r == 16'hA202) ? 16'h0606 : 16'hFFFF;
    end
endmodule
