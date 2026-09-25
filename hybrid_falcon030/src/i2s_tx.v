// =====================================================================
// i2s_tx.v -- I2S transmitter for the onboard MAX98357A DAC+amp.
//
// Standard Philips I2S: 64 BCLK per LRCLK frame (32/channel), 16-bit
// sample MSB-first, left-justified in the 32-bit slot with the LSBs
// zero-padded and the mandatory 1-BCLK delay after each LRCLK edge.
// Data changes on the falling BCLK edge; the DAC latches on the rising
// edge. LRCLK low = left, high = right.
//
// BCLK = clk / (2*BCLK_HALF). Default 50 MHz / 16 = 3.125 MHz -> with
// 64 BCLK/frame, fs = 48.83 kHz (inside the MAX98357A 8-96 kHz range).
// No MCLK: the MAX98357A recovers everything from BCLK/LRCLK.
//
// samp_stb pulses one clk at each frame start so the sample source can
// advance at exactly fs. Pure synchronous logic -- Icarus-checkable.
//
// This same interface drives a PMOD stereo DAC (e.g. PCM5102) later --
// only the L/R sample sources change, not this block.
// =====================================================================
module i2s_tx #(
    parameter integer BCLK_HALF = 8    // sysclk per half BCLK (period = 16)
)(
    input  wire               clk,     // 50 MHz
    input  wire               rstn,
    input  wire signed [15:0] l_sample,
    input  wire signed [15:0] r_sample,
    output reg                bclk,
    output reg                lrck,     // word select (0=L, 1=R)
    output reg                sdata,    // serial data, MSB first
    output reg                samp_stb  // 1-clk pulse at frame start
);
    reg [$clog2(BCLK_HALF)-1:0] half;
    reg [6:0]  bitcnt;                  // 0..63 within a frame
    reg [63:0] shreg;

    // one 32-bit slot = {pad, sample[15:0], 15 pad}; two slots per frame
    function [63:0] build_frame;
        input signed [15:0] l, r;
        build_frame = { 1'b0, l, 15'b0, 1'b0, r, 15'b0 };
    endfunction

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            half <= 0; bclk <= 1'b0; bitcnt <= 7'd0;
            shreg <= 64'd0; lrck <= 1'b0; sdata <= 1'b0; samp_stb <= 1'b0;
        end else begin
            samp_stb <= 1'b0;
            if (half != BCLK_HALF-1) begin
                half <= half + 1'b1;
            end else begin
                half <= 0;
                bclk <= ~bclk;
                if (bclk) begin
                    // BCLK just went LOW -> falling edge: update data/LRCLK
                    sdata <= shreg[63];
                    lrck  <= (bitcnt >= 7'd32);
                    if (bitcnt == 7'd63) begin
                        bitcnt   <= 7'd0;
                        shreg    <= build_frame(l_sample, r_sample);
                        samp_stb <= 1'b1;
                    end else begin
                        bitcnt <= bitcnt + 1'b1;
                        shreg  <= {shreg[62:0], 1'b0};
                    end
                end
            end
        end
    end
endmodule
