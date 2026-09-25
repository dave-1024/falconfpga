// =====================================================================
// falcon_audio_i2s.v -- FalconFPGA audio egress for the onboard
//                       MAX98357A I2S DAC+amp (supersedes the
//                       sigma-delta egress; this board has no 1-bit pin).
//
// test_tone = 1 : internal ~1 kHz sine, advanced once per I2S frame
//                 (Step 0 bring-up: prove BCLK/LRCLK/DIN -> DAC -> speaker
//                  with no firmware).
// test_tone = 0 : external mono `pcm` (Step 1+: A25/DMA feeds samples).
//
// The MAX98357A is mono: fed the same value on L and R, it outputs the
// (L+R)/2 downmix -- so the stereo->mono collapse is free here. When a
// PMOD stereo DAC is added later, drive i2s_tx's L/R separately; the
// transmitter itself is unchanged.
//
// pa_en drives the amp's SD_MODE/shutdown line high (out of shutdown).
// The three I2S pins are BANK5: BCLK=Y17, LRCK=AB17, DIN=AA16.
// =====================================================================
module falcon_audio_i2s #(
    parameter integer BCLK_HALF = 8,           // 50MHz/16 -> fs 48.83 kHz
    parameter [31:0]  TONE_STEP = 32'd87960930 // ~1 kHz at fs (per frame)
)(
    input  wire               clk,       // 50 MHz AHB_CLK
    input  wire               rstn,
    input  wire               en,        // master enable / mute
    input  wire               test_tone, // 1 = internal tone, 0 = pcm
    input  wire signed [15:0] pcm,        // external mono sample
    output wire               i2s_bclk,   // -> Y17
    output wire               i2s_lrck,   // -> AB17
    output wire               i2s_din,    // -> AA16
    output wire               pa_en,       // -> MAX98357A SD_MODE (amp on)
    output wire               samp_stb     // v2 (REV13): frame tick at fs,
                                           // drains the fetch-engine FIFO
);

    // tone source: phase accumulator advanced once per I2S frame, HOLDS
    // its value between frames (unlike a free-running per-clk source).
    reg  [31:0] phase;
    reg  signed [15:0] tone;
    reg  signed [15:0] lut [0:255];
    initial $readmemh("sine_lut.hex", lut);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            phase <= 32'd0;
            tone  <= 16'sd0;
        end else if (samp_stb && en && test_tone) begin
            phase <= phase + TONE_STEP;
            tone  <= lut[phase[31:24]];
        end else if (!en) begin
            tone  <= 16'sd0;
        end
    end

    wire signed [15:0] src = test_tone ? tone : pcm;
    wire signed [15:0] smp = en ? src : 16'sd0;

    i2s_tx #(.BCLK_HALF(BCLK_HALF)) u_i2s (
        .clk(clk), .rstn(rstn),
        .l_sample(smp), .r_sample(smp),     // mono -> both slots
        .bclk(i2s_bclk), .lrck(i2s_lrck), .sdata(i2s_din),
        .samp_stb(samp_stb)
    );

    assign pa_en = en;      // hold the amp out of shutdown while enabled
endmodule
