// tb_tos_loader.v - FAL_01: iverilog check of tos_mount_latch + tos_loader
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Two cases, both must copy 1024 sectors into $E00000 and release the CPU:
//   1. 1-cycle mount pulse while helper_hold / soc_reset is high
//   2. 1-cycle mount pulse after hold has already fallen (board 3196a13 case)
`timescale 1ns/1ps
module tb_tos_loader;
    localparam integer DELAY = 4;
    localparam integer NSEC  = 1024;
    localparam [31:0]  TOSZ  = 32'd524288;

    reg         clk, por, hold, ram_ready, img_mounted;
    reg  [31:0] img_size;
    wire        go;
    wire [31:0] size;

    wire [31:0] sd_lba;
    wire        sd_rd;
    reg         sd_ack;
    reg  [8:0]  sd_buff_addr;
    reg  [7:0]  sd_dout;
    reg         sd_dout_strobe;
    wire        ram_req;
    wire [23:1] ram_a;
    wire [15:0] ram_wdata;
    reg         ram_ack;
    wire        cpu_reset, err, busy;
    wire [9:0]  sect;

    tos_mount_latch #(.DELAY(DELAY)) u_mnt (
        .clk(clk), .por(por), .hold(hold), .ram_ready(ram_ready),
        .img_mounted(img_mounted), .img_size(img_size),
        .go(go), .size(size)
    );
    tos_loader u_ld (
        .clk(clk), .reset(por),
        .img_mounted(go), .img_size(size),
        .sd_lba(sd_lba), .sd_rd(sd_rd), .sd_ack(sd_ack),
        .sd_buff_addr(sd_buff_addr), .sd_dout(sd_dout), .sd_dout_strobe(sd_dout_strobe),
        .ram_req(ram_req), .ram_a(ram_a), .ram_wdata(ram_wdata), .ram_ack(ram_ack),
        .cpu_reset(cpu_reset), .err(err), .busy(busy), .sect(sect)
    );

    // 512K word-addressed RAM at $E00000 (ram_a is [23:1])
    reg [15:0] ram [0:262143];
    integer i;
    initial for (i = 0; i < 262144; i = i + 1) ram[i] = 16'hxxxx;

    always #5 clk = ~clk; // 100 MHz sim clock (period only; counts matter, not Hz)

    // SD stub: ack a request, then stream 512 bytes. Byte 0 of sector s
    // is s[7:0], then increment, except sector 0 bytes 8..11 = 00 E0 00 00.
    function [7:0] sec_byte(input [31:0] lba, input [8:0] a);
        begin
            if (lba == 32'd0 && a == 9'd8)  sec_byte = 8'h00;
            else if (lba == 32'd0 && a == 9'd9)  sec_byte = 8'hE0;
            else if (lba == 32'd0 && a == 9'd10) sec_byte = 8'h00;
            else if (lba == 32'd0 && a == 9'd11) sec_byte = 8'h00;
            else sec_byte = lba[7:0] ^ a[7:0];
        end
    endfunction

    // Real sd_card.v is much slower than one byte/clk; the loader has only a
    // one-word buffer, so the stub waits 4 clocks between bytes (still faster
    // than a 32 MHz board, but enough for ram_req to be acked).
    reg        sd_active;
    reg [9:0]  sd_idx;
    reg [2:0]  sd_wait;
    reg [2:0]  sd_gap;
    reg [31:0] sd_cur;
    always @(posedge clk) begin
        if (por) begin
            sd_ack <= 1'b0; sd_dout_strobe <= 1'b0; sd_buff_addr <= 9'd0;
            sd_dout <= 8'd0; sd_active <= 1'b0; sd_idx <= 10'd0; sd_wait <= 3'd0;
            sd_gap <= 3'd0; sd_cur <= 32'd0;
        end else begin
            sd_dout_strobe <= 1'b0;
            if (sd_rd && !sd_ack && !sd_active) begin
                sd_wait <= 3'd3;
                sd_active <= 1'b1;
                sd_cur <= sd_lba;
                sd_idx <= 10'd0;
                sd_gap <= 3'd0;
            end
            if (sd_active && sd_wait != 3'd0) begin
                sd_wait <= sd_wait - 3'd1;
                if (sd_wait == 3'd1) sd_ack <= 1'b1;
            end else if (sd_active && sd_ack) begin
                if (sd_idx < 10'd512) begin
                    if (sd_gap != 3'd0) sd_gap <= sd_gap - 3'd1;
                    else begin
                        sd_buff_addr <= sd_idx[8:0];
                        sd_dout <= sec_byte(sd_cur, sd_idx[8:0]);
                        sd_dout_strobe <= 1'b1;
                        sd_idx <= sd_idx + 10'd1;
                        sd_gap <= 3'd3;
                    end
                end else begin
                    sd_ack <= 1'b0;
                    sd_active <= 1'b0;
                end
            end
        end
    end

    // RAM stub: 1-cycle ack
    always @(posedge clk) begin
        if (por) ram_ack <= 1'b0;
        else begin
            ram_ack <= 1'b0;
            if (ram_req && !ram_ack) begin
                ram[ram_a[18:1]] <= ram_wdata;
                ram_ack <= 1'b1;
            end
        end
    end

    integer errors, nread, s, a, exp;
    reg [15:0] gotw, expw;
    task automatic check_ram;
        begin
            errors = 0;
            // header long at +8
            if (ram[4] !== 16'h00E0) begin
                $display("FAIL header word @+8 = %04x want 00E0", ram[4]);
                errors = errors + 1;
            end
            if (ram[5] !== 16'h0000) begin
                $display("FAIL header word @+10 = %04x want 0000", ram[5]);
                errors = errors + 1;
            end
            for (s = 0; s < NSEC; s = s + 1) begin
                for (a = 0; a < 512; a = a + 2) begin
                    // skip the four header bytes already checked
                    if (s == 0 && a >= 8 && a <= 10) begin
                    end else begin
                        expw = {sec_byte(s, a[8:0]), sec_byte(s, a[8:0] + 9'd1)};
                        gotw = ram[(s * 256) + (a/2)];
                        if (gotw !== expw) begin
                            if (errors < 8)
                                $display("FAIL s=%0d a=%0d got %04x want %04x", s, a, gotw, expw);
                            errors = errors + 1;
                        end
                    end
                end
            end
            if (errors == 0) $display("RAM ok: 1024 sectors at $E00000, header $00E00000");
            else $display("RAM errors: %0d", errors);
        end
    endtask

    task automatic pulse_mount(input [31:0] sz);
        begin
            @(posedge clk);
            img_mounted <= 1'b1;
            img_size <= sz;
            @(posedge clk);
            img_mounted <= 1'b0;
        end
    endtask

    task automatic wait_done(input integer tmo);
        begin
            begin : waitloop
                integer t;
                for (t = 0; t < tmo; t = t + 1) begin
                    @(posedge clk);
                    if (!cpu_reset && !busy) disable waitloop;
                end
            end
        end
    endtask

    task automatic run_case(input [8*32-1:0] name, input during_hold);
        integer t;
        begin
            $display("==== %0s ====", name);
            por <= 1'b1; hold <= during_hold; ram_ready <= 1'b0;
            img_mounted <= 1'b0; img_size <= 32'd0;
            for (t = 0; t < 8; t = t + 1) @(posedge clk);
            por <= 1'b0;
            for (t = 0; t < 8; t = t + 1) @(posedge clk);
            // dirty RAM so a missed write is visible
            for (i = 0; i < 262144; i = i + 1) ram[i] = 16'hDEAD;

            pulse_mount(TOSZ);

            if (during_hold) begin
                // go must not fire, loader must stay idle while hold is up
                for (t = 0; t < 40; t = t + 1) begin
                    @(posedge clk);
                    if (go) begin
                        $display("FAIL %0s: go while hold still 1", name);
                        errors = errors + 1;
                    end
                    if (busy) begin
                        $display("FAIL %0s: loader busy while hold still 1", name);
                        errors = errors + 1;
                    end
                end
                if (busy || go) $fatal(1, "%0s started during hold", name);
                $display("%0s: pulse during hold ignored, sticky kept", name);
                hold <= 1'b0;
                for (t = 0; t < 4; t = t + 1) @(posedge clk);
                ram_ready <= 1'b1;
            end else begin
                // already out of hold, as on the 3196a13 board
                hold <= 1'b0;
                ram_ready <= 1'b1;
            end

            wait_done(NSEC * 8000 + 20000);
            if (cpu_reset || busy || err) begin
                $display("FAIL %0s: after wait cpu_reset=%0d busy=%0d err=%0d sect=%0d",
                         name, cpu_reset, busy, err, sect);
                $fatal(1, "%0s did not finish", name);
            end
            if (sect !== 10'd1023) begin
                $display("FAIL %0s: sect=%0d want 1023", name, sect);
                $fatal(1, "%0s sector count", name);
            end
            check_ram;
            if (errors != 0) $fatal(1, "%0s RAM compare", name);
            $display("%0s PASS", name);
        end
    endtask

    initial begin
        clk = 1'b0; por = 1'b1; hold = 1'b1; ram_ready = 1'b0;
        img_mounted = 1'b0; img_size = 32'd0;
        errors = 0;
        run_case("during_hold", 1);
        run_case("after_hold", 0);
        $display("ALL PASS");
        $finish;
    end

    // watchdog
    initial begin
        #(20 * (NSEC * 8000 + 40000));
        $display("FAIL timeout, busy=%0d sect=%0d cpu_reset=%0d", busy, sect, cpu_reset);
        $fatal(1, "timeout");
    end
endmodule
