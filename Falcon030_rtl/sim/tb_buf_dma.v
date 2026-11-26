// tb_buf_dma.v - BLI-11h C5: falcon_bus byte/word rd2 buffer (buf2) vs DMA writes, idle and non-fill cycles.
// falcon_bus + falcon_sdram_arb + a behavioural SDRAM (dout = mem[addr], dout2 = mem[addr+1], write at cs rise).
// Cases (ST-RAM, cachable): 1 word read A, DMA write A+2, fill read A+2 must return the NEW data;
// 2 word read A then fill A+2 at once: hit (no SDRAM request); 3 word read A, then a read of another
// address with the same A3:1: correct data; 4 word read A, 8 idle clocks, read A+2: correct, from SDRAM;
// 5 byte read A+1 then fill A+2: hit. Run: iverilog -g2012 tb_buf_dma.v ../hdl/bus/falcon_bus.v ../hdl/bus/falcon_sdram_arb.v
`timescale 1ns/1ps
module tb_buf_dma;
    reg clk32 = 0; always #15.625 clk32 = ~clk32;
    reg clk_cpu = 0; always @(posedge clk32) clk_cpu <= ~clk_cpu;
    reg por = 1, reset = 1, ram_ready = 0;
    reg as_n = 1, rw = 1; reg [31:0] a = 0; reg [1:0] siz = 2'b10;
    wire [31:0] din; wire [1:0] dsack_n; wire berr_n, avec_n, ciin_n;
    wire mem_req, mem_we, mem_ack, mem_rd2; wire [23:1] mem_a; wire [1:0] mem_be; wire [15:0] mem_wdata, mem_rdata, mem_rdata2;
    wire sd_cs, sd_we, sd_ref, sd_ecs, sd_rd2; wire [21:0] sd_addr; wire [1:0] sd_ds, sd_ba; wire [15:0] sd_din;
    reg  [15:0] sd_dout = 0, sd_dout2 = 0;
    reg dma_req = 0, dma_we = 0; reg [23:1] dma_a = 0; reg [15:0] dma_d = 0; wire dma_ack; wire ext_wr_tog;
    falcon_bus #(.IO_WAIT(2)) bus (.clk(clk_cpu), .reset(reset), .cpu_a(a), .cpu_dout(32'd0), .cpu_din(din),
        .cpu_as_n(as_n), .cpu_ds_n(as_n), .cpu_rw(rw), .cpu_siz(siz), .cpu_fc(3'b101), .cpu_dsack_n(dsack_n),
        .cpu_berr_n(berr_n), .cpu_avec_n(avec_n), .cpu_ciin_n(ciin_n), .mem_rd2(mem_rd2), .mem_rdata2(mem_rdata2),
        .ext_wr_tog(ext_wr_tog),
        .mem_req(mem_req), .mem_a(mem_a), .mem_we(mem_we), .mem_be(mem_be), .mem_wdata(mem_wdata),
        .mem_ack(mem_ack), .mem_rdata(mem_rdata), .io_cyc(), .io_a(), .io_uds(), .io_lds(),
        .io_rw(), .io_wr(), .io_wdata(), .io_rdata(16'h1234), .io_ext(1'b0), .io_done(1'b0),
        .iack_mfp(), .mfp_vector(8'h0), .mfp_dtack(1'b0), .br_want(1'b0), .bus_grant(), .cyc_tog());
    falcon_sdram_arb arb (.clk(clk32), .reset(por), .ram_ready(ram_ready), .sd_cs(sd_cs), .sd_we(sd_we),
        .sd_refresh(sd_ref), .sd_ecs(sd_ecs), .sd_addr(sd_addr), .sd_ds(sd_ds), .sd_din(sd_din), .sd_dout(sd_dout),
        .sd_dout2(sd_dout2), .sd_rd2(sd_rd2), .sd_ba(sd_ba), .vid_req(1'b0), .vid_a(23'd0), .vid_ack(),
        .vid_q(), .vid_q2(), .dma_req(dma_req), .dma_we(dma_we), .dma_a(dma_a), .dma_d(dma_d), .dma_ack(dma_ack), .dma_q(),
        .ld_req(1'b0), .ld_a(23'd0), .ld_d(16'd0), .ld_ack(), .cpu_req(mem_req), .cpu_a(mem_a), .cpu_we(mem_we),
        .cpu_be(mem_be), .cpu_d(mem_wdata), .cpu_ack(mem_ack), .cpu_q(mem_rdata), .cpu_rd2(mem_rd2), .cpu_q2(mem_rdata2),
        .ext_wr_tog(ext_wr_tog));
    reg [15:0] mem [0:65535];
    integer i; initial for (i = 0; i < 65536; i = i + 1) mem[i] = i[15:0] ^ 16'hA500;
    // behavioural sdram.v contract: write taken when cs rises, dout/dout2 = array (combinational from the issued address)
    reg cs_d = 0; always @(posedge clk32) begin cs_d <= sd_cs; if (sd_cs && !cs_d && sd_we && !sd_ref) mem[sd_addr[15:0]] <= sd_din; end
    always @(*) begin sd_dout = mem[sd_addr[15:0]]; sd_dout2 = mem[sd_addr[15:0] + 16'd1]; end
    integer errors = 0, reqs, clks;
    reg mreq_d = 0; always @(posedge clk_cpu) begin mreq_d <= mem_req; if (mem_req && !mreq_d) reqs = reqs + 1; end
    function [15:0] init_w(input [23:0] ad); init_w = ad[16:1] ^ 16'hA500; endfunction
    task rd(input [23:0] ad, input [1:0] sz, output [15:0] d);
        begin
            @(posedge clk_cpu); a <= {8'h00, ad}; siz <= sz; rw <= 1; as_n <= 0; clks = 0;
            @(posedge clk_cpu); while (dsack_n === 2'b11 && clks < 200) begin @(posedge clk_cpu); clks = clks + 1; end
            d = din[31:16]; @(posedge clk_cpu); as_n <= 1;
        end
    endtask
    task chk(input [255:0] name, input [15:0] got, input [15:0] exp, input integer r, input integer rexp);
        begin
            if (got !== exp || (rexp >= 0 && r != rexp)) begin errors = errors + 1;
                $display("FAIL %0s: D=%h exp %h, SDRAM requests %0d exp %0d", name, got, exp, r, rexp); end
            else $display("ok   %0s: D=%h requests %0d (%0d clk to DSACK)", name, got, r, clks);
        end
    endtask
    reg [15:0] d;
    initial begin
        repeat (8) @(posedge clk32); por = 0; ram_ready = 1; repeat (16) @(posedge clk_cpu); reset = 0; repeat (4) @(posedge clk_cpu);
        // 1: word read $1000, DMA write $1002 := BEEF, fill $1002 -> BEEF
        rd(24'h001000, 2'b10, d); chk("1a word $1000", d, init_w(24'h1000), 0, -1);
        @(posedge clk32); dma_a <= 23'h000801; dma_d <= 16'hBEEF; dma_we <= 1; dma_req <= 1;
        @(posedge clk32); while (!dma_ack) @(posedge clk32); dma_req <= 0; dma_we <= 0;
        reqs = 0; rd(24'h001002, 2'b10, d); chk("1b fill $1002 after DMA write", d, 16'hBEEF, reqs, 1);
        // 2: back-to-back fill hits the buffer
        rd(24'h002000, 2'b10, d); reqs = 0; rd(24'h002002, 2'b10, d); chk("2 fill $2002 (buffer hit)", d, init_w(24'h2002), reqs, 0);
        // 3: other address with the same A3:1
        rd(24'h003000, 2'b10, d); reqs = 0; rd(24'h004002, 2'b10, d); chk("3 $4002 after $3000 (A3:1 alias)", d, init_w(24'h4002), reqs, 1);
        // 4: idle 8 clocks, then A+2 comes from SDRAM; also a DMA write without idle changes nothing else
        rd(24'h005000, 2'b10, d); mem[16'h2801] = 16'h1111; repeat (8) @(posedge clk_cpu);
        reqs = 0; rd(24'h005002, 2'b10, d); chk("4 $5002 after 8 idle clocks", d, 16'h1111, reqs, 1);
        // 5: byte read at $6001, fill $6002 hits
        rd(24'h006001, 2'b01, d); reqs = 0; rd(24'h006002, 2'b10, d); chk("5 fill $6002 after byte $6001", d, init_w(24'h6002), reqs, 0);
        // 6: long read still uses the A3:1 fast path
        rd(24'h007000, 2'b00, d); reqs = 0; rd(24'h007002, 2'b10, d); chk("6 long $7000 second word", d, init_w(24'h7002), reqs, 0);
        if (errors == 0) $display("ALL PASS"); else $display("FAILED %0d", errors);
        $finish;
    end
endmodule
