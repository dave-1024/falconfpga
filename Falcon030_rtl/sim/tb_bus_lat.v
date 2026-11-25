// tb_bus_lat.v - BUS-1: clk_cpu cycles per 68030 bus cycle through falcon_bus + falcon_sdram_arb
// CPU model = MC68030 UM 7.2 asynchronous cycle: S0 rising (address), AS asserted on the S1 falling edge,
// DSACK sampled on each falling edge from the end of S2 (no DSACK -> wait states), data latched one falling
// edge later (end of S4), AS negated at the next rising edge (S5), next S0 at the rising edge after.
// Zero-wait-state async cycle = 3 clocks. A long on a 16-bit port = 2 cycles (UM 7.2.1).
// SDRAM model = the sdram.v ST-port contract: cycle starts on a rising cs while idle, dout written at the
// state-4 edge, dout2 (st_rd2) at state 5, write taken at state 1, 8 clocks per cycle.
// -DOLD builds against the pre-BUS-1 files (no rd2 ports, ack at phase 6, extra ack sync).
`timescale 1ns/1ps
module tb_bus_lat;
    reg clk32 = 0; always #15.625 clk32 = ~clk32;
    reg clk_cpu = 0; always @(posedge clk32) clk_cpu <= ~clk_cpu;
    reg reset = 1, por = 1, ram_ready = 0;
    reg vid_on = 0;
    reg        as_n = 1, rw = 1; reg [31:0] a = 0, dout = 0; reg [1:0] siz = 0; reg [2:0] fc = 3'b101;
    wire [31:0] din; wire [1:0] dsack_n; wire berr_n, avec_n, ciin_n;
    wire mem_req, mem_we, mem_ack, mem_rd2; wire [23:1] mem_a; wire [1:0] mem_be; wire [15:0] mem_wdata, mem_rdata, mem_rdata2;
    wire io_cyc, io_uds, io_lds, io_rw, io_wr; wire [15:1] io_a; wire [15:0] io_wdata;
    wire sd_cs, sd_we, sd_ref, sd_ecs, sd_rd2; wire [21:0] sd_addr; wire [1:0] sd_ds, sd_ba; wire [15:0] sd_din;
    reg  [15:0] sd_dout = 0, sd_dout2 = 0;
    wire vid_ack; wire [15:0] vq, vq2; reg vid_req = 0; reg [23:1] vid_a = 23'h100000;
    falcon_bus #(.IO_WAIT(2)) bus (.clk(clk_cpu), .reset(reset), .cpu_a(a), .cpu_dout(dout), .cpu_din(din),
        .cpu_as_n(as_n), .cpu_ds_n(as_n), .cpu_rw(rw), .cpu_siz(siz), .cpu_fc(fc), .cpu_dsack_n(dsack_n),
        .cpu_berr_n(berr_n), .cpu_avec_n(avec_n),
`ifndef OLD
        .cpu_ciin_n(ciin_n), .mem_rd2(mem_rd2), .mem_rdata2(mem_rdata2),
`endif
        .mem_req(mem_req), .mem_a(mem_a), .mem_we(mem_we), .mem_be(mem_be), .mem_wdata(mem_wdata),
        .mem_ack(mem_ack), .mem_rdata(mem_rdata), .io_cyc(io_cyc), .io_a(io_a), .io_uds(io_uds), .io_lds(io_lds),
        .io_rw(io_rw), .io_wr(io_wr), .io_wdata(io_wdata), .io_rdata(16'h1234), .io_ext(1'b0), .io_done(1'b0),
        .iack_mfp(), .mfp_vector(8'h0), .mfp_dtack(1'b0), .br_want(1'b0), .bus_grant(), .cyc_tog());
    falcon_sdram_arb arb (.clk(clk32), .reset(por), .ram_ready(ram_ready), .sd_cs(sd_cs), .sd_we(sd_we),
        .sd_refresh(sd_ref), .sd_ecs(sd_ecs), .sd_addr(sd_addr), .sd_ds(sd_ds), .sd_din(sd_din), .sd_dout(sd_dout),
        .sd_dout2(sd_dout2), .sd_rd2(sd_rd2), .sd_ba(sd_ba), .vid_req(vid_req), .vid_a(vid_a), .vid_ack(vid_ack),
        .vid_q(vq), .vid_q2(vq2), .dma_req(1'b0), .dma_we(1'b0), .dma_a(23'd0), .dma_d(16'd0), .dma_ack(), .dma_q(),
        .ld_req(1'b0), .ld_a(23'd0), .ld_d(16'd0), .ld_ack(), .cpu_req(mem_req), .cpu_a(mem_a), .cpu_we(mem_we),
        .cpu_be(mem_be), .cpu_d(mem_wdata), .cpu_ack(mem_ack), .cpu_q(mem_rdata)
`ifndef OLD
        , .cpu_rd2(mem_rd2), .cpu_q2(mem_rdata2)
`endif
        );
`ifdef OLD
    assign ciin_n = 1'b0;
`endif
    // SDRAM contract model (word memory = address pattern; writes stored)
    reg [15:0] m [0:4095]; integer k; initial for (k = 0; k < 4096; k = k + 1) m[k] = k ^ 16'hA500;
    reg [3:0] st = 0; reg csD = 0; reg [21:0] la; reg lwe, lrd2; reg [1:0] lds; reg [15:0] ld;
    always @(posedge clk32) begin
        csD <= sd_cs;
        if (st == 0) begin
            if (sd_cs && !csD) begin st <= 1; la <= sd_addr; lwe <= sd_we; lds <= sd_ds; ld <= sd_din; end
        end else begin
            st <= (st == 7) ? 0 : st + 1;
            if (st == 1) lrd2 <= sd_rd2;
            if (st == 1 && lwe && !sd_ref) m[la[11:0]] <= ld;
            if (st == 4 && !lwe) sd_dout <= m[la[11:0]];
            if (st == 5 && !lwe && lrd2) sd_dout2 <= m[la[11:0] + 1];
        end
    end
    // scanout load: one burst request every 32 clk32 (= 640x480 4-plane rate, 160 words per 31.8 us)
    integer vt = 0;
    always @(posedge clk32) begin
        vt = vt + 1;
        if (vid_ack) vid_req <= 1'b0;
        else if (vid_on && vt % 32 == 0) vid_req <= 1'b1;
    end
    // 68030 async bus cycle; returns clocks S0..S5
    integer t0, nclk, errors = 0; reg [15:0] got;
    task cyc(input [31:0] ad, input r, input [1:0] sz, input [15:0] wd, output integer n);
        integer w;
        begin
            @(posedge clk_cpu); t0 = $time; a <= ad; rw <= r; siz <= sz; dout <= {wd, wd};   // S0
            @(negedge clk_cpu); as_n <= 0;                                                       // S1
            @(negedge clk_cpu); w = 0;                                                           // end S2
            while (dsack_n == 2'b11 && berr_n && w < 200) begin @(negedge clk_cpu); w = w + 1; end
            @(negedge clk_cpu); got = din[31:16];                                                // end S4
            @(posedge clk_cpu); as_n <= 1;                                                       // S5
            n = ($time - t0 + 62) / 62.5;
            if (w >= 200) begin $display("FAIL timeout %h", ad); errors = errors + 1; end
        end
    endtask
    task run(input [8*12-1:0] name, input [31:0] ad, input r, input lng, input integer reps);
        integer i, n1, n2, tot; reg [15:0] e;
        begin
            tot = 0;
            for (i = 0; i < reps; i = i + 1) begin
                cyc(ad + 4*i, r, lng ? 2'b00 : 2'b10, 16'h5A00 + i, n1); tot = tot + n1;
                e = r ? (((ad + 4*i) >> 1) & 12'hFFF) ^ 16'hA500 : 0;
                if (r && ad < 32'hE00000 && got !== e) begin $display("FAIL %h got %h exp %h", ad + 4*i, got, e); errors = errors + 1; end
                if (lng) begin
                    cyc(ad + 4*i + 2, r, 2'b10, 16'h6B00 + i, n2); tot = tot + n2;
                    e = r ? (((ad + 4*i + 2) >> 1) & 12'hFFF) ^ 16'hA500 : 0;
                    if (r && ad < 32'hE00000 && got !== e) begin $display("FAIL %h+2 got %h exp %h", ad + 4*i, got, e); errors = errors + 1; end
                end
            end
            $display("%s vid=%0d: %0d.%02d clk_cpu per %s (manual zero-wait %0d)", name, vid_on, tot / reps, (tot * 100 / reps) % 100,
                     lng ? "long (2 cycles)" : "word cycle", lng ? 6 : 3);
        end
    endtask
    initial begin
        repeat (4) @(posedge clk32); por = 0; ram_ready = 1;
        repeat (20) @(posedge clk_cpu); reset = 0; repeat (4) @(posedge clk_cpu);
        for (k = 0; k < 2; k = k + 1) begin
            vid_on = k;
            run("RAM rd.w   ", 32'h000100, 1, 0, 40);
            run("RAM rd.l   ", 32'h000400, 1, 1, 40);
            run("RAM wr.w   ", 32'h000800, 0, 0, 40);
            run("RAM wr.l   ", 32'h000C00, 0, 1, 40);
            run("ROM rd.l   ", 32'hE00100, 1, 1, 40);
            run("IO  rd.w   ", 32'hFF8240, 1, 0, 40);
        end
        // write then read back (posted write ordering)
        cyc(32'h001000, 0, 2'b10, 16'hBEEF, nclk); cyc(32'h001000, 1, 2'b10, 0, nclk);
        if (got !== 16'hBEEF) begin $display("FAIL write->read got %h", got); errors = errors + 1; end
        $display("%s errors=%0d", errors ? "FAIL" : "PASS", errors);
        $finish;
    end
endmodule
