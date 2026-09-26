// HDMI encoder pin check. Not part of the Gowin build.
// Free-running pixel clock, reset released, same shape as vreset idle.
// TMDS_BY_LOGIC only. This does not include the Gowin PLL or OSER10.
`timescale 1ns/1ps
module tb_hdmi_pins;
  reg clk_pixel;
  reg clk_pixel_x5;
  reg clk_audio;
  reg reset;
  reg [1:0] stmode;
  reg [1:0] screen;
  reg [23:0] rgb;
  reg [15:0] audio_sample_word [1:0];
  wire [5:0] tmds;
  wire [1:0] tmds_clock;

  integer clk_edges;
  integer data_edges;
  reg [1:0] clk_prev;
  reg [5:0] data_prev;

  hdmi #(.AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16)) u (
    .clk_pixel_x5(clk_pixel_x5),
    .clk_pixel(clk_pixel),
    .clk_audio(clk_audio),
    .reset(reset),
    .stmode(stmode),
    .screen(screen),
    .rgb(rgb),
    .audio_sample_word(audio_sample_word),
    .tmds(tmds),
    .tmds_clock(tmds_clock)
  );

  initial begin
    clk_pixel = 0;
    clk_pixel_x5 = 0;
    clk_audio = 0;
  end
  always #1 clk_pixel_x5 = ~clk_pixel_x5;
  always #5 clk_pixel = ~clk_pixel;
  always #80 clk_audio = ~clk_audio;

  always @(posedge clk_pixel_x5) begin
    if (!reset) begin
      if (tmds_clock != clk_prev) clk_edges = clk_edges + 1;
      if (tmds != data_prev) data_edges = data_edges + 1;
      clk_prev <= tmds_clock;
      data_prev <= tmds;
    end
  end

  initial begin
    clk_edges = 0;
    data_edges = 0;
    clk_prev = 2'b00;
    data_prev = 6'b000000;
    reset = 1;
    stmode = 2'd1;
    screen = 2'd0;
    rgb = 24'hFF0000;
    audio_sample_word[0] = 16'd0;
    audio_sample_word[1] = 16'd0;
    repeat (16) @(posedge clk_pixel);
    reset = 0;
    repeat (8000) @(posedge clk_pixel);
    $display("HDMI_EDGES clock=%0d data=%0d last_clock=%b last_data=%b", clk_edges, data_edges, tmds_clock, tmds);
    if (clk_edges > 10 && data_edges > 10)
      $display("HDMI_SIM PASS");
    else
      $display("HDMI_SIM FAIL");
    $finish;
  end
endmodule
