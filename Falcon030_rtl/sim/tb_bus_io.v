// tb_bus_io.v - FAL_01: IO write strobe must overlap io_cyc, and $FF8006 = $A2xx
`timescale 1ns/1ps
module tb_bus_io;
    reg clk = 1'b0;
    always #31.25 clk = ~clk;          // 16 MHz

    reg reset = 1'b1;
    reg        cpu_as_n = 1'b1, cpu_ds_n = 1'b1, cpu_rw = 1'b1;
    reg [31:0] cpu_a = 32'd0, cpu_dout = 32'd0;
    reg [1:0]  cpu_siz = 2'b10;
    reg [2:0]  cpu_fc  = 3'b101;
    wire [31:0] cpu_din;
    wire [1:0]  cpu_dsack_n;
    wire        cpu_berr_n, cpu_avec_n;

    wire        mem_req, mem_we;
    wire [23:1] mem_a;
    wire [1:0]  mem_be;
    wire [15:0] mem_wdata;
    wire        io_cyc, io_uds, io_lds, io_rw, io_wr;
    wire [15:1] io_a;
    wire [15:0] io_wdata, io_rdata;

    falcon_bus #(.IO_WAIT(2)) u_bus (
        .clk(clk), .reset(reset),
        .cpu_a(cpu_a), .cpu_dout(cpu_dout), .cpu_din(cpu_din),
        .cpu_as_n(cpu_as_n), .cpu_ds_n(cpu_ds_n),
        .cpu_rw(cpu_rw), .cpu_siz(cpu_siz), .cpu_fc(cpu_fc),
        .cpu_dsack_n(cpu_dsack_n), .cpu_berr_n(cpu_berr_n), .cpu_avec_n(cpu_avec_n),
        .mem_req(mem_req), .mem_a(mem_a), .mem_we(mem_we), .mem_be(mem_be),
        .mem_wdata(mem_wdata), .mem_ack(1'b0), .mem_rdata(16'h0000),
        .io_cyc(io_cyc), .io_a(io_a), .io_uds(io_uds), .io_lds(io_lds),
        .io_rw(io_rw), .io_wr(io_wr), .io_wdata(io_wdata),
        .io_rdata(io_rdata), .io_ext(1'b0), .io_done(1'b0),
        .iack_mfp(), .mfp_vector(8'h00), .mfp_dtack(1'b0),
        .br_want(1'b0), .bus_grant(), .cyc_tog()
    );

    falcon_io #(.MONITOR(2'b10), .MEMCODE(3'd5)) u_io (
        .clk(clk), .reset(reset), .cyc(io_cyc), .a(io_a),
        .uds(io_uds), .lds(io_lds), .wr(io_wr), .din(io_wdata), .dout(io_rdata),
        .sel_videl(), .sel_nvram_a(), .sel_nvram_d(), .sel_ym(),
        .sel_mfp(), .sel_acia(), .sel_dma(),
        .videl_d(16'h0000), .nvram_d(8'h00), .ym_d(8'h00),
        .mfp_d(8'h00), .acia_d(8'h00), .dma_d(16'h0000), .fdc_hd()
    );

    integer fails = 0, overlap = 0;
    always @(posedge clk)
        if (io_cyc && io_wr) overlap <= overlap + 1;

    task cycle(input [31:0] adr, input rw, input [15:0] data);
        integer guard;
        begin
            @(negedge clk);
            cpu_a = adr; cpu_rw = rw; cpu_dout = {data, data};
            cpu_siz = 2'b10; cpu_fc = 3'b101;
            cpu_as_n = 1'b0; cpu_ds_n = 1'b0;
            guard = 0;
            while (((cpu_dsack_n & 2'b11) == 2'b11) && cpu_berr_n) begin
                @(negedge clk);
                guard = guard + 1;
                if (guard > 40) begin
                    $display("TIMEOUT a=%h dsack=%b", adr, cpu_dsack_n);
                    fails = fails + 1;
                    cpu_as_n = 1'b1; cpu_ds_n = 1'b1;
                    disable cycle;
                end
            end
            if (!cpu_berr_n) begin
                $display("BERR a=%h", adr);
                fails = fails + 1;
            end
            @(negedge clk);
            cpu_as_n = 1'b1; cpu_ds_n = 1'b1;
            @(negedge clk);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;
        repeat (4) @(posedge clk);

        cycle(32'h00FF8006, 1'b1, 16'h0000);
        if (cpu_din[15:8] !== 8'hA2 || cpu_din[7:0] !== 8'h00) begin
            $display("FAIL $FF8006=%h want A200", cpu_din[15:0]);
            fails = fails + 1;
        end else $display("PASS $FF8006=%h", cpu_din[15:0]);

        overlap = 0;
        cycle(32'h00FF8000, 1'b0, 16'hBEEF);
        if (overlap === 0) begin
            $display("FAIL write strobe never overlapped io_cyc");
            fails = fails + 1;
        end
        cycle(32'h00FF8000, 1'b1, 16'h0000);
        if (cpu_din[15:0] !== 16'hBEEF) begin
            $display("FAIL $FF8000 readback %h want BEEF (write dropped)", cpu_din[15:0]);
            fails = fails + 1;
        end else $display("PASS $FF8000 write landed (%0d strobe cycles)", overlap);

        if (fails == 0) $display("ALL PASS");
        else $display("FAILED %0d", fails);
        $finish;
    end
endmodule
