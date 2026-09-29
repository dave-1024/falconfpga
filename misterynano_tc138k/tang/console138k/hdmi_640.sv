// hdmi_640.sv - FalconFPGA stage 1 HDMI bring-up
//
// Fixed 640x480@60 (CEA-861 VIC 1, 4:3, 25.2 MHz) variant of MiSTeryNano's
// hdmi/hdmi.sv (Sameer Puri's HDMI 1.4a core, https://github.com/sameer).
//
// Differences from hdmi/hdmi.sv:
//  - no Atari ST mode table (stmode/screen); timing is fixed 800x525,
//    640x480 active, CEA VIC 1, AVI picture aspect ratio 4:3.
//  - the pixel position (cx/cy) and the sync signals are supplied by an
//    external timing generator (video_testpattern_640) instead of the
//    internal counters, so the pattern and the encoder can never drift.
//    cx/cy/hsync/vsync/rgb must all refer to the same pixel in the same
//    clock. hsync/vsync are passed at transmit level (active low here).
//  - reuses the unchanged packet_picker / packet_assembler / tmds_channel /
//    serializer modules from hdmi/ (serializer uses the Gowin OSER10
//    branch, exactly as the Atari video path does).

module hdmi_640
#(
    parameter bit IT_CONTENT = 1'b1,
    parameter int AUDIO_RATE = 48000,
    parameter int AUDIO_BIT_WIDTH = 16,
    parameter bit [8*8-1:0] VENDOR_NAME = {"Unknown", 8'd0},
    parameter bit [8*16-1:0] PRODUCT_DESCRIPTION = {"FPGA", 96'd0},
    parameter bit [7:0] SOURCE_DEVICE_INFORMATION = 8'h00
)
(
    input logic                       clk_pixel_x5,
    input logic                       clk_pixel,
    input logic                       clk_audio,
    input logic                       reset,
    input logic [9:0]                 cx,      // from timing generator
    input logic [9:0]                 cy,
    input logic                       hsync,   // transmit level (negative polarity)
    input logic                       vsync,
    input logic [23:0]                rgb,     // {r,g,b}
    input logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word [1:0],

    output logic [2:0]                tmds,
    output logic                      tmds_clock
);

localparam int NUM_CHANNELS = 3;

// CEA-861 VIC 1: 640x480p @ 59.94/60 Hz, 4:3
localparam int FRAME_WIDTH   = 800;
localparam int FRAME_HEIGHT  = 525;
localparam int SCREEN_WIDTH  = 640;
localparam int SCREEN_HEIGHT = 480;
localparam bit [7:0] CEA     = 8'd1;
localparam real VIDEO_RATE   = 25.2E6;

// See Section 5.2
logic video_data_period = 0;
always_ff @(posedge clk_pixel)
begin
    if (reset)
        video_data_period <= 0;
    else
        video_data_period <= cx < SCREEN_WIDTH && cy < SCREEN_HEIGHT;
end

logic [2:0] mode = 3'd1;
logic [23:0] video_data = 24'd0;
logic [5:0] control_data = 6'd0;
logic [11:0] data_island_data = 12'd0;

generate
    begin: true_hdmi_output
        logic video_guard = 1;
        logic video_preamble = 0;
        always_ff @(posedge clk_pixel)
        begin
            if (reset)
            begin
                video_guard <= 1;
                video_preamble <= 0;
            end
            else
            begin
                video_guard <= cx >= FRAME_WIDTH - 2 && cx < FRAME_WIDTH && (cy == FRAME_HEIGHT - 1 || cy < SCREEN_HEIGHT - 1 /* no VG at end of last line */);
                video_preamble <= cx >= FRAME_WIDTH - 10 && cx < FRAME_WIDTH - 2 && (cy == FRAME_HEIGHT - 1 || cy < SCREEN_HEIGHT - 1 /* no VP at end of last line */);
            end
        end

        // See Section 5.2.3.1
        localparam int MAX_NUM_PACKETS_ALONGSIDE = (FRAME_WIDTH - SCREEN_WIDTH /* VD period */ - 2 /* V guard */ - 8 /* V preamble */ - 4 /* Min V control period */ - 2 /* DI trailing guard */ - 2 /* DI leading guard */ - 8 /* DI premable */ - 4 /* Min DI control period */) / 32;
        localparam int NUM_PACKETS_ALONGSIDE = MAX_NUM_PACKETS_ALONGSIDE > 18 ? 18 : MAX_NUM_PACKETS_ALONGSIDE;   // = 4 at 640x480

        logic data_island_period_instantaneous;
        assign data_island_period_instantaneous = NUM_PACKETS_ALONGSIDE > 0 && cx >= SCREEN_WIDTH + 14 && cx < SCREEN_WIDTH + 14 + NUM_PACKETS_ALONGSIDE * 32;
        logic packet_enable;
        assign packet_enable = data_island_period_instantaneous && 5'(cx + SCREEN_WIDTH + 18) == 5'd0;

        logic data_island_guard = 0;
        logic data_island_preamble = 0;
        logic data_island_period = 0;
        always_ff @(posedge clk_pixel)
        begin
            if (reset)
            begin
                data_island_guard <= 0;
                data_island_preamble <= 0;
                data_island_period <= 0;
            end
            else
            begin
                data_island_guard <= NUM_PACKETS_ALONGSIDE > 0 && (
                    (cx >= SCREEN_WIDTH + 12 && cx < SCREEN_WIDTH + 14) /* leading guard */ ||
                    (cx >= SCREEN_WIDTH + 14 + NUM_PACKETS_ALONGSIDE * 32 && cx < SCREEN_WIDTH + 14 + NUM_PACKETS_ALONGSIDE * 32 + 2) /* trailing guard */
                );
                data_island_preamble <= NUM_PACKETS_ALONGSIDE > 0 && cx >= SCREEN_WIDTH + 4 && cx < SCREEN_WIDTH + 12;
                data_island_period <= data_island_period_instantaneous;
            end
        end

        // See Section 5.2.3.4
        logic [23:0] header;
        logic [55:0] sub [3:0];
        logic video_field_end;
        assign video_field_end = cx == SCREEN_WIDTH - 1 && cy == SCREEN_HEIGHT - 1;
        logic [4:0] packet_pixel_counter;
        packet_picker #(
            .VIDEO_RATE(VIDEO_RATE),
            .IT_CONTENT(IT_CONTENT),
            .AUDIO_RATE(AUDIO_RATE),
            .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
            .VENDOR_NAME(VENDOR_NAME),
            .PRODUCT_DESCRIPTION(PRODUCT_DESCRIPTION),
            .SOURCE_DEVICE_INFORMATION(SOURCE_DEVICE_INFORMATION),
            .PICTURE_ASPECT_RATIO(2'b01)   // 4:3
        ) packet_picker (.clk_pixel(clk_pixel), .clk_audio(clk_audio), .reset(reset), .cea(CEA), .stmode(2'd0), .video_field_end(video_field_end), .packet_enable(packet_enable), .packet_pixel_counter(packet_pixel_counter), .audio_sample_word(audio_sample_word), .header(header), .sub(sub));
        logic [8:0] packet_data;
        packet_assembler packet_assembler (.clk_pixel(clk_pixel), .reset(reset), .data_island_period(data_island_period), .header(header), .sub(sub), .packet_data(packet_data), .counter(packet_pixel_counter));

        always_ff @(posedge clk_pixel)
        begin
            if (reset)
            begin
                mode <= 3'd2;
                video_data <= 24'd0;
                control_data <= 6'd0;
                data_island_data <= 12'd0;
            end
            else
            begin
                mode <= data_island_guard ? 3'd4 : data_island_period ? 3'd3 : video_guard ? 3'd2 : video_data_period ? 3'd1 : 3'd0;
                video_data <= (cx < SCREEN_WIDTH && cy < SCREEN_HEIGHT) ? rgb : 24'h000000;
                control_data <= {{1'b0, data_island_preamble}, {1'b0, video_preamble || data_island_preamble}, {vsync, hsync}}; // ctrl3, ctrl2, ctrl1, ctrl0, vsync, hsync
                data_island_data[11:4] <= packet_data[8:1];
                data_island_data[3] <= cx != 0;
                data_island_data[2] <= packet_data[0];
                data_island_data[1:0] <= {vsync, hsync};
            end
        end
    end
endgenerate

// All logic below relates to the production and output of the 10-bit TMDS code.
logic [9:0] tmds_internal [NUM_CHANNELS-1:0];
genvar i;
generate
    for (i = 0; i < NUM_CHANNELS; i++)
    begin: tmds_gen
        tmds_channel #(.CN(i)) tmds_channel (.clk_pixel(clk_pixel), .video_data(video_data[i*8+7:i*8]), .data_island_data(data_island_data[i*4+3:i*4]), .control_data(control_data[i*2+1:i*2]), .mode(mode), .tmds(tmds_internal[i]));
    end
endgenerate

serializer #(.NUM_CHANNELS(NUM_CHANNELS)) serializer(.clk_pixel(clk_pixel), .clk_pixel_x5(clk_pixel_x5), .reset(reset), .tmds_internal(tmds_internal), .tmds(tmds), .tmds_clock(tmds_clock));

endmodule
