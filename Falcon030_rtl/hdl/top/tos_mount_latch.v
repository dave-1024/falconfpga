// tos_mount_latch.v - FAL_01: sticky TOS image-mount, clk32 / sd_card domain
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// sd_card.v pulses image_mounted for one clk32 cycle (cleared the next).
// falcon_soc.por is por32|helper_hold, so a mount that arrives while the
// helper still holds the SOC resets tos_loader and the pulse is lost.
// This block is reset by por32 only. It latches a 524288-byte mount on
// slot 4 and issues a one-cycle go to the loader once helper_hold has
// fallen, the SDRAM is ready, and DELAY clk32 cycles have passed.
//
// DELAY covers the helper's follow-up SPI_SDC_DIRECT (CMD 6), which is
// sent after "DRV n: inserted" and programs direct_start. Starting the
// first sector read before that takes the MCU IRQ path ("spourious
// interrupt") and can drop the request. 32000 cycles is 1 ms at 32 MHz.
//
// Hybrid030 (falcon_m28.c flop_init / HOWTO.md ROM=): the 512K image is
// copied into the ROM window with the CPU held, then the CPU is released.
// The loader still does that; this block only makes the start of the copy
// reliable. The ST core has no TOS-from-SD loader: misterynano.sv uses
// image_mounted as a 1-cycle floppy/ACSI disk-change pulse after
// st_release, so it does not need a sticky latch.
//
// Clock: everything here, sd_card.v, helper_hold and tos_loader are on
// clk32. The 2-flop quals on hold/ram_ready are not a true CDC; they
// just ignore a release in the same cycle as the mount.
module tos_mount_latch #(
    parameter integer DELAY = 32_000
)(
    input  wire        clk,
    input  wire        por,             // por32 only, not helper_hold
    input  wire        hold,            // soc_reset = por32|helper_hold (qualifier)
    input  wire        ram_ready,
    input  wire        img_mounted,     // 1-cycle pulse, sd_card domain
    input  wire [31:0] img_size,
    output reg         go,              // 1-cycle pulse to tos_loader
    output reg  [31:0] size
);
    // 16-bit counter is enough for the 1 ms / 32 MHz default (32000).
    // Avoid $clog2 so Gowin V1.9.12.03 takes the file as plain Verilog.
    reg        sticky;
    reg [1:0]  hold_s, ready_s;
    reg [15:0] wait_n;

    wire hold_q  = hold_s[1];
    wire ready_q = ready_s[1];

    always @(posedge clk) begin
        if (por) begin
            sticky  <= 1'b0;
            size    <= 32'd0;
            go      <= 1'b0;
            hold_s  <= 2'b11;
            ready_s <= 2'b00;
            wait_n  <= 16'd0;
        end else begin
            hold_s  <= {hold_s[0], hold};
            ready_s <= {ready_s[0], ram_ready};
            go      <= 1'b0;
            if (img_mounted) begin
                size <= img_size;
                if (img_size == 32'd524288) begin
                    sticky <= 1'b1;
                    wait_n <= DELAY[15:0];
                end else begin
                    // eject (size 0) cancels a pending load, not a running one
                    sticky <= 1'b0;
                    wait_n <= 16'd0;
                end
            end else if (sticky) begin
                if (hold_q || !ready_q) begin
                    wait_n <= DELAY[15:0];
                end else if (wait_n != 16'd0) begin
                    wait_n <= wait_n - 16'd1;
                end else begin
                    go     <= 1'b1;
                    sticky <= 1'b0;
                end
            end
        end
    end
endmodule
