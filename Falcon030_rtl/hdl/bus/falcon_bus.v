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
    output reg         cpu_ciin_n,    // BUS-1: cache inhibit, registered with the cycle start, held to the next
    // SDRAM word port (RAM and ROM copy), 16-bit, byte enables
    output reg         mem_req,
    output reg  [23:1] mem_a,
    output reg         mem_we,
    output reg  [1:0]  mem_be,        // {UDS, LDS}
    output reg  [15:0] mem_wdata,
    input  wire        mem_ack,
    input  wire [15:0] mem_rdata,
    output reg         mem_rd2,       // BUS-1: aligned long read, the arbiter also fetches A+2 (burst-2)
    input  wire [15:0] mem_rdata2,    // BUS-1: that second word
    // IO byte/word port to the peripherals (falcon_io.v)
    output wire        io_cyc,        // valid IO cycle in progress (whitelisted)
    output reg  [15:1] io_a,          // $FF8000 + .., latched with the cycle
    output reg         io_uds, io_lds,
    output reg         io_rw,         // latched R/W (1 = read)
    output reg         io_wr,         // one-clock write strobe
    output reg  [15:0] io_wdata,
    input  wire [15:0] io_rdata,
    input  wire        io_ext,        // this IO cycle goes to a clk_32 peripheral (falcon_pbus.v)
    input  wire        io_done,       // ... which has finished it (data valid on io_rdata)
    output wire        iack_mfp,      // level 6 IACK in progress
    input  wire [7:0]  mfp_vector,
    input  wire        mfp_dtack,     // MFP supplies its vector
    // blitter bus arbitration (falcon_blitter.v): BR/BG equivalent without the 030 pins
    input  wire        br_want,       // clk_32 level: blitter requests / owns the bus
    output reg         bus_grant,     // CPU parked in S_IDLE; no new cycle until br_want drops
    output reg         cyc_tog        // toggles at each CPU cycle start (blitter shared-mode count)
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
    // Vector mirror: $000000-$000007 reads map to $E00000+A2:A1. ram_a / mem_a
    // are [23:1] (23 bits). The previous concat {20'hE0000, A2:A1} was only 22
    // bits and zero-extended, so A23 was 0 and the read landed at $700000
    // (ST-RAM, zeros) instead of the TOS copy. That loaded PC=0, the 030
    // prefetched $000000/$00000002, and HALTed. Same prefix as tos_loader:
    // {5'b11100, ...} = $E00000.
    wire [23:1] mem_a_c     = is_vec ? {5'b11100, 16'd0, a24[2:1]} : a24[23:1];
    wire        mem_we_c    = !cpu_rw && is_ram;
    wire [1:0]  mem_be_c    = {uds, lds};
    wire [15:0] mem_wdata_c = cpu_dout[31:16];        // the core drives a 16-bit port on D31:16
    // io_a/uds/lds/rw are latched on the S_IDLE -> S_IO edge so the clk32
    // peripheral sub-bus (pbus, MFP, ACIAs, falcon_fdc -> arbiter dma_d) sees a
    // registered CDC, not the combo MMU PA / decode cone. 9bd249a still failed
    // clk_cpu030 -> clk32_core setup (-8.0 ns, FILL_ACC -> mem_a_c -> videl/io/
    // pbus -> sd_din) because those IO signals were left combinational.
    // io_wdata is sampled again in S_IO so a 030 write that presents data after
    // AS is still captured well before the clk32 write strobe.
    assign iack_mfp  = state == S_IACK && cpu_a[3:1] == 3'd6;
    // io_wr is registered and rises on the clock that leaves S_IO, so
    // cyc would already be 0 if it only followed the state. Hold cyc
    // for that one strobe cycle so VIDEL / falcon_io / NVRAM / YM see
    // sel && wr together (otherwise every IO write is silently dropped;
    // board HUD 6d7ae40: HHT stays 0 after TOS's MOVE.W #16,$FF8282,
    // last IO shows $8266 but SPSHIFT is the reset default).
    assign io_cyc    = (state == S_IO) || io_wr;

    localparam S_IDLE = 3'd0, S_MEM = 3'd1, S_IO = 3'd2, S_IACK = 3'd3,
               S_END = 3'd4, S_WEND = 3'd5, S_WAITACK = 3'd6;
    // BUS-1 (25 Nov 2026): mem_ack and mem_rdata are clk32 registers (the arbiter ack and sdram.v dout,
    // written on the same phase-4 edge) and clk_cpu rises on a clk32 edge, so they are sampled directly
    // (timed clk32 -> clk_cpu path, one clk32 = 31.25 ns) without the old extra mem_ack_s stage.
    // A leftover ack (still high from the previous word) is not accepted:
    // wait for it to fall, then raise mem_req.
    wire       mem_ack_s   = mem_ack;
    wire [15:0] mem_rdata_s = mem_rdata;
    // BUS-1: long-read split buffer. The 030 reads a long from this 16-bit port as SIZ=long at A (A1=0)
    // then SIZ=word at A+2 straight after (UM 7.2.1 dynamic bus sizing). The first portion fetches both
    // words in one SDRAM slot (sd_rd2); the second portion is answered from buf2 with no SDRAM slot.
    // buf2 is good only for the very next cycle (cleared by any other cycle start and by a blitter grant).
    reg [15:0] buf2;
    reg [3:1]  buf2_a;
    reg        buf2_v, rd2_pend;
    wire       long_rd = cpu_rw && cpu_siz == 2'b00 && !a24[1];
    wire       buf_hit = buf2_v && cpu_rw && cpu_siz == 2'b10 && a24[3:1] == buf2_a;
    // BLI-11 (25 Nov 2026): ROM instruction fetches cachable only (bisect2: boots to the desktop).
    // d3bfb3d (ROM I+D and ST-RAM program space cachable) hung TOS at the $E00D5A vsync wait; bisecting
    // ROM data / ST-RAM program caching separately. Full target: (is_rom && !is_vec) || (is_ram && cpu_fc[1:0] == 2'b10)
    wire       cachable = is_rom && !is_vec && cpu_fc[1:0] == 2'b10;
    reg [2:0] state;
    reg [3:0] wcnt;
    reg [1:0] br_s;
    always @(posedge clk) br_s <= reset ? 2'b00 : {br_s[0], br_want};
    always @(posedge clk) begin
        io_wr <= 1'b0;
        if (reset) begin
            bus_grant <= 1'b0; cyc_tog <= 1'b0;
            state <= S_IDLE; mem_req <= 1'b0;
            mem_a <= 23'd0; mem_we <= 1'b0; mem_be <= 2'b00; mem_wdata <= 16'd0;
            io_a <= 15'd0; io_uds <= 1'b0; io_lds <= 1'b0; io_rw <= 1'b1; io_wdata <= 16'd0;
            cpu_dsack_n <= 2'b11; cpu_berr_n <= 1'b1; cpu_avec_n <= 1'b1;
            cpu_ciin_n <= 1'b0; mem_rd2 <= 1'b0; buf2_v <= 1'b0; rd2_pend <= 1'b0;
        end else case (state)
            S_IDLE: if (bus_grant || br_s[1]) begin
                bus_grant <= br_s[1];             // grant only between cycles; release when BR drops
                buf2_v <= 1'b0;
            end else if (!cpu_as_n) begin
                wcnt <= 4'd0; cyc_tog <= ~cyc_tog;
                buf2_v <= 1'b0;
                // BUS-1 caching (MC68030 UM 5.7.1 CIIN; real Falcon: TOS flushes the D-cache after
                // blitter and DMA, tos4x hbbitblt.s / dmaread.s). ROM: I and D. ST-RAM: instruction
                // fetches only (program space FC=x10), data reads stay inhibited so blitter/DMA writes
                // can never leave a stale D-cache line. IO, IDE, cartridge, vector mirror: inhibited.
                cpu_ciin_n <= cachable;
                if (iack) state <= S_IACK;
                else if (buf_hit) begin
                    cpu_din <= {buf2, buf2}; cpu_dsack_n <= 2'b01; state <= S_END;
                end
                else if (is_ram || is_rom || is_vec) begin
                    if (!cpu_rw && !is_ram) begin cpu_dsack_n <= 2'b01; state <= S_WEND; end  // ROM write: dropped
                    else begin
                        mem_a <= mem_a_c; mem_we <= mem_we_c;
                        mem_be <= mem_be_c; mem_wdata <= mem_wdata_c;
                        mem_rd2 <= long_rd; rd2_pend <= long_rd; buf2_a <= a24[3:1] + 3'd1;
                        // 4-phase: do not raise req while a leftover ack is still high
                        if (mem_ack_s) state <= S_WAITACK;
                        else begin mem_req <= 1'b1; state <= S_MEM; end
                    end
                end else if (is_cart) begin cpu_din <= 32'hFFFFFFFF; cpu_dsack_n <= 2'b01; state <= S_END; end
                else if (io_ok) begin
                    io_a <= r[15:1]; io_uds <= uds; io_lds <= lds;
                    io_rw <= cpu_rw; io_wdata <= cpu_dout[31:16];
                    state <= S_IO;
                end
                else begin cpu_berr_n <= 1'b0; state <= S_END; end
            end
            S_WAITACK: if (!mem_ack_s) begin mem_req <= 1'b1; state <= S_MEM; end
            S_MEM: if (mem_ack_s) begin
                mem_req <= 1'b0; cpu_din <= {mem_rdata_s, mem_rdata_s}; cpu_dsack_n <= 2'b01; state <= S_END;
            end
            S_IO: begin
                io_wdata <= cpu_dout[31:16];
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
            S_END, S_WEND: begin
                // second burst word: written by sdram.v one clk32 after the ack edge, so one clk_cpu later
                if (rd2_pend) begin buf2 <= mem_rdata2; buf2_v <= 1'b1; rd2_pend <= 1'b0; end
                if (cpu_as_n) begin
                cpu_dsack_n <= 2'b11; cpu_berr_n <= 1'b1; cpu_avec_n <= 1'b1; state <= S_IDLE;
                end
            end
            default: state <= S_IDLE;
        endcase
    end
endmodule
