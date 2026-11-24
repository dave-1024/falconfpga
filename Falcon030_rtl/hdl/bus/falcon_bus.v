// falcon_bus.v - FAL_01: Falcon030 address decode and asynchronous DSACK bus for the WF68K30L
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The WF68K30L (Atarist_030_wip/hdl/cpu030, shared by path) talks to this block directly at
// 16 MHz, both clocked by clk_cpu. There is no ST bridge: the Falcon's 030 bus is async DSACK.
// Every port here is 16 bits wide (DSACK1 only), like the Falcon's ST-RAM/ROM/IO bus; the CPU
// does its own dynamic bus sizing. Map (24-bit bus: A31:24 are not decoded and everything aliases,
// like a stock Falcon and the Hybrid030 BUS=24 default, HOWTO.md), see docs/DESIGN.md:
//   $000000-$000007  ROM vector mirror (reads; writes go to RAM)
//   $000008-$DFFFFF  14 MB ST-RAM in SDRAM  -> mem_* port (ram)
//   $E00000-$E7FFFF  TOS 4.04, SDRAM copy loaded by the helper -> mem_* port (rom, writes dropped)
//   $F00000-$F0003F  IDE, one interface (falcon_m28.c M11q), v1 stub: no device -> io port
//   $FA0000-$FBFFFF  cartridge: reads $FFFF
//   $FF8000-$FFFFFF  IO: decoded selects below; whitelisted stubs latch; anything else BERR
//   everything else  BERR  (unmapped space must bus-error: that is how TOS tells the machine)
// Interrupt acknowledge (FC=7, A19:16=F): level 6 = MFP (vectored, iack_mfp), others autovector.
module falcon_bus #(
    parameter integer IO_WAIT = 2     // clocks from AS to DSACK for IO (Falcon IO is slow; tune later)
) (
    input  wire        clk,
    input  wire        reset,
    // CPU
    input  wire [31:0] cpu_a,
    input  wire [31:0] cpu_dout,
    output reg  [31:0] cpu_din,
    input  wire        cpu_as_n,
    input  wire        cpu_ds_n,
    input  wire        cpu_rw,
    input  wire [1:0]  cpu_siz,
    input  wire [2:0]  cpu_fc,
    output reg  [1:0]  cpu_dsack_n,
    output reg         cpu_berr_n,
    output reg         cpu_avec_n,
    // SDRAM word port (RAM and ROM copy), 16-bit, byte enables
    output reg         mem_req,
    output reg  [23:1] mem_a,
    output reg         mem_we,
    output reg  [1:0]  mem_be,        // {UDS, LDS}
    output reg  [15:0] mem_wdata,
    input  wire        mem_ack,
    input  wire [15:0] mem_rdata,
    // IO byte/word port to the peripherals (falcon_io.v)
    output wire        io_cyc,        // valid IO cycle in progress (whitelisted)
    output wire [15:1] io_a,          // $FF8000 + ..
    output wire        io_uds, io_lds,
    output reg         io_wr,         // one-clock write strobe
    output wire [15:0] io_wdata,
    input  wire [15:0] io_rdata,
    input  wire        io_ext,        // this IO cycle goes to a clk_32 peripheral (falcon_pbus.v)
    input  wire        io_done,       // ... which has finished it (data valid on io_rdata)
    output wire        iack_mfp,      // level 6 IACK in progress
    input  wire [7:0]  mfp_vector,
    input  wire        mfp_dtack      // MFP supplies its vector
);
    wire [23:0] a24 = cpu_a[23:0];
    wire top_ok = 1'b1;   // 24-bit bus (Hybrid030 BUS=24, the mode that matched Hatari and the bench for TOS)
    wire iack   = (cpu_fc == 3'b111);
    wire is_vec = top_ok && cpu_rw && (a24[23:3] == 21'd0);
    wire is_ram = top_ok && !is_vec && (a24 < 24'hE00000);
    wire is_ide = top_ok && (a24[23:6] == 18'h3C000);                 // $F00000-$F0003F
    wire is_rom = top_ok && (a24[23:19] == 5'b11100);                // $E00000-$E7FFFF
    wire is_cart= top_ok && (a24[23:17] == 7'b1111101);              // $FA0000-$FBFFFF
    wire [15:0] r = a24[15:0];
    wire in_io  = top_ok && (a24[23:15] == 9'h1FF);                  // $FF8000-$FFFFFF
    // Falcon IO whitelist (falcon_m28.c falcon_io_valid)
    wire io_ok = is_ide || in_io && (
        (r >= 16'h8000 && r <= 16'h800F) || (r >= 16'h8200 && r <= 16'h8211) ||
        (r >= 16'h8240 && r <= 16'h826F) || (r >= 16'h8280 && r <= 16'h82C7) ||
        (r >= 16'h8604 && r <= 16'h860F) || (r >= 16'h8780 && r <= 16'h878F) ||
        (r >= 16'h8800 && r <= 16'h88FF) || (r >= 16'h8900 && r <= 16'h897F) ||
        (r >= 16'h8A00 && r <= 16'h8A3D) || (r >= 16'h8C80 && r <= 16'h8C87) ||
        (r >= 16'h9200 && r <= 16'h921F) || (r >= 16'h9800 && r <= 16'h9BFF) ||
        (r >= 16'hA200 && r <= 16'hA207) || (r >= 16'hFA00 && r <= 16'hFA3F) ||
        (r >= 16'hFC00 && r <= 16'hFC07));
    // 16-bit port byte lanes (68030 UM table 7-4 for a 16-bit port): UDS = A0 = 0,
    // LDS = A0 = 1 or SIZ is not byte
    wire uds = !a24[0];
    wire lds = a24[0] || (cpu_siz != 2'b01);
    // mem_a/we/be/wdata are latched on the same clk_cpu edge as mem_req (S_IDLE
    // -> S_MEM). The combo MMU PA and CPU data path is a clk_cpu path (62.5 ns);
    // the arbiter then sees a registered CDC into clk32 (31.25 ns). Leaving them
    // combinational missed that relation by 6.2 ns on 56d6a85 (PF_ACC -> MMU PA
    // -> sd_din, 37.4 ns data delay).
    wire [23:1] mem_a_c     = is_vec ? {20'hE0000, a24[2:1]} : a24[23:1];
    wire        mem_we_c    = !cpu_rw && is_ram;
    wire [1:0]  mem_be_c    = {uds, lds};
    wire [15:0] mem_wdata_c = cpu_dout[31:16];        // the core drives a 16-bit port on D31:16
    assign io_a      = r[15:1];
    assign io_uds    = uds;
    assign io_lds    = lds;
    assign io_wdata  = cpu_dout[31:16];
    assign iack_mfp  = state == S_IACK && cpu_a[3:1] == 3'd6;
    assign io_cyc    = state == S_IO;

    localparam S_IDLE = 3'd0, S_MEM = 3'd1, S_IO = 3'd2, S_IACK = 3'd3, S_END = 3'd4, S_WEND = 3'd5;
    reg [2:0] state;
    reg [3:0] wcnt;
    always @(posedge clk) begin
        io_wr <= 1'b0;
        if (reset) begin
            state <= S_IDLE; mem_req <= 1'b0;
            mem_a <= 23'd0; mem_we <= 1'b0; mem_be <= 2'b00; mem_wdata <= 16'd0;
            cpu_dsack_n <= 2'b11; cpu_berr_n <= 1'b1; cpu_avec_n <= 1'b1;
        end else case (state)
            S_IDLE: if (!cpu_as_n) begin
                wcnt <= 4'd0;
                if (iack) state <= S_IACK;
                else if (is_ram || is_rom || is_vec) begin
                    if (!cpu_rw && !is_ram) begin cpu_dsack_n <= 2'b01; state <= S_WEND; end  // ROM write: dropped
                    else begin
                        mem_req <= 1'b1;
                        mem_a <= mem_a_c; mem_we <= mem_we_c;
                        mem_be <= mem_be_c; mem_wdata <= mem_wdata_c;
                        state <= S_MEM;
                    end
                end else if (is_cart) begin cpu_din <= 32'hFFFFFFFF; cpu_dsack_n <= 2'b01; state <= S_END; end
                else if (io_ok) state <= S_IO;
                else begin cpu_berr_n <= 1'b0; state <= S_END; end
            end
            S_MEM: if (mem_ack) begin
                mem_req <= 1'b0; cpu_din <= {mem_rdata, mem_rdata}; cpu_dsack_n <= 2'b01; state <= S_END;
            end
            S_IO: begin
                wcnt <= wcnt + 4'd1;
                if (io_ext ? io_done : (wcnt == IO_WAIT - 1)) begin
                    cpu_din <= {io_rdata, io_rdata}; io_wr <= !cpu_rw; cpu_dsack_n <= 2'b01; state <= S_END;
                end
            end
            S_IACK: begin
                if (cpu_a[3:1] == 3'd6) begin
                    if (mfp_dtack) begin cpu_din <= {4{mfp_vector}}; cpu_dsack_n <= 2'b01; state <= S_END; end
                end else begin cpu_avec_n <= 1'b0; state <= S_END; end
            end
            S_END, S_WEND: if (cpu_as_n) begin
                cpu_dsack_n <= 2'b11; cpu_berr_n <= 1'b1; cpu_avec_n <= 1'b1; state <= S_IDLE;
            end
            default: state <= S_IDLE;
        endcase
    end
endmodule
