// falcon_sdp_ram.v - FAL_01: simple dual-port RAM, forced to Gowin BSRAM (SDPB)
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Same coding style as the ST core st_fb_ram, which Gowin V1.9.12.03
// infers as SDP BSRAM: separate write and registered-read clocks, no array
// reset, and an explicit syn_ramstyle = "block_ram" attribute. Hybrid030
// falcon_video.v relied on a sync read "to keep it inferable as a real SDP
// BSRAM" but did not stamp the attribute; without it, falcon_scanout's
// 640x24 ping-pong buffers and 256x18 Falcon palette were mapped to LUT/FF
// and blew the first Falcon build (scanout 62136 LUT, 5 BSRAM).
module falcon_sdp_ram #(
    parameter DEPTH = 1024,
    parameter AW    = 10,
    parameter DW    = 24
) (
    input  wire           wclk,
    input  wire           we,
    input  wire [AW-1:0]  waddr,
    input  wire [DW-1:0]  wdata,
    input  wire           rclk,
    input  wire [AW-1:0]  raddr,
    output reg  [DW-1:0]  rdata
);

    reg [DW-1:0] mem [0:DEPTH-1] /* synthesis syn_ramstyle = "block_ram" */;

    always @(posedge wclk)
        if (we) mem[waddr] <= wdata;

    always @(posedge rclk)
        rdata <= mem[raddr];

endmodule
