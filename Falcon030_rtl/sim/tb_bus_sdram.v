// tb_bus_sdram.v - FAL_01: board-real clk32/clk_cpu phases for falcon_bus + falcon_sdram_arb
// A 68030-style long-word vector-mirror read (two 16-bit cycles) is run against
// the arbiter handshake at both alignments of ph versus clk_cpu, and with a
// leftover ack (stale 16'hDEAD) forced at the start of the second word.
`timescale 1ns/1ps
module tb_bus_sdram;
    reg clk32 = 1'b0;
    always #15.625 clk32 = ~clk32;          // 32 MHz

    reg align = 1'b0;                       // 0: clk_cpu rises on even clk32
    reg clk_cpu = 1'b0;
    integer div = 0;
    always @(posedge clk32) begin
        div = div + 1;
        if (div[0] == align) clk_cpu <= ~clk_cpu;
    end

    reg reset_32 = 1'b1, ram_ready = 1'b0, reset_cpu = 1'b1;

    reg        cpu_as_n = 1'b1, cpu_ds_n = 1'b1, cpu_rw = 1'b1;
    reg [31:0] cpu_a = 32'd0, cpu_dout = 32'd0;
    reg [1:0]  cpu_siz = 2'b00;
    reg [2:0]  cpu_fc  = 3'b101;
    wire [31:0] cpu_din;
    wire [1:0]  cpu_dsack_n;
    wire        cpu_berr_n, cpu_avec_n;
    wire        mem_req, mem_we, mem_ack;
    wire [23:1] mem_a;
    wire [1:0]  mem_be;
    wire [15:0] mem_wdata, mem_rdata;

    wire        sd_cs, sd_we, sd_refresh, sd_ecs, sd_rd2;
    wire [21:0] sd_addr;
    wire [1:0]  sd_ds, sd_ba;
    wire [15:0] sd_din;
    reg  [15:0] sd_dout = 16'hxxxx;

    falcon_bus #(.IO_WAIT(2)) u_bus (
        .clk(clk_cpu), .reset(reset_cpu),
        .cpu_a(cpu_a), .cpu_dout(cpu_dout), .cpu_din(cpu_din),
        .cpu_as_n(cpu_as_n), .cpu_ds_n(cpu_ds_n), .cpu_rw(cpu_rw),
        .cpu_siz(cpu_siz), .cpu_fc(cpu_fc),
        .cpu_dsack_n(cpu_dsack_n), .cpu_berr_n(cpu_berr_n), .cpu_avec_n(cpu_avec_n),
        .mem_req(mem_req), .mem_a(mem_a), .mem_we(mem_we), .mem_be(mem_be),
        .mem_wdata(mem_wdata), .mem_ack(mem_ack), .mem_rdata(mem_rdata),
        .io_cyc(), .io_a(), .io_uds(), .io_lds(), .io_rw(), .io_wr(), .io_wdata(),
        .io_rdata(16'h0), .io_ext(1'b0), .io_done(1'b0),
        .iack_mfp(), .mfp_vector(8'h0), .mfp_dtack(1'b0),
        .br_want(1'b0), .bus_grant(), .cyc_tog()
    );
    falcon_sdram_arb u_arb (
        .clk(clk32), .reset(reset_32), .ram_ready(ram_ready),
        .sd_cs(sd_cs), .sd_we(sd_we), .sd_refresh(sd_refresh), .sd_ecs(sd_ecs),
        .sd_addr(sd_addr), .sd_ds(sd_ds), .sd_din(sd_din), .sd_dout(sd_dout),
        .sd_dout2(16'h0), .sd_rd2(sd_rd2), .sd_ba(sd_ba),
        .vid_req(1'b0), .vid_a(23'd0), .vid_ack(), .vid_q(), .vid_q2(),
        .dma_req(1'b0), .dma_we(1'b0), .dma_a(23'd0), .dma_d(16'h0), .dma_ack(), .dma_q(),
        .ld_req(1'b0), .ld_a(23'd0), .ld_d(16'h0), .ld_ack(),
        .cpu_req(mem_req), .cpu_a(mem_a), .cpu_we(mem_we), .cpu_be(mem_be),
        .cpu_d(mem_wdata), .cpu_ack(mem_ack), .cpu_q(mem_rdata)
    );

    // sdram.v: dout is written on STATE_READ (ph 4) and is visible at ph 5.
    // Combinational lookup from the issued address is enough: the arbiter
    // captures it into cpu_q at ph 5.
    always @(*) begin
        // $E00000: A23=1 (sd_ba[0]), A22:A1 = 22'h300000
        if (sd_ba[0] == 1'b1)
            case (sd_addr)
                22'h300000: sd_dout = 16'h602E;
                22'h300001: sd_dout = 16'h0404;
                22'h300002: sd_dout = 16'h00E0;
                22'h300003: sd_dout = 16'h0030;
                default:    sd_dout = 16'hDEAD;
            endcase
        else
            sd_dout = 16'hDEAD;
    end

    integer errors, tmo;
    reg [15:0] d0, d1;

    task wait_dsack;
        begin
            tmo = 0;
            @(posedge clk_cpu);
            while (cpu_dsack_n === 2'b11 && tmo < 200) begin
                @(posedge clk_cpu);
                tmo = tmo + 1;
            end
            if (tmo >= 200) begin
                $display("FAIL: DSACK timeout A=%h", cpu_a);
                errors = errors + 1;
            end
        end
    endtask

    task word_read;
        input [23:0] addr;
        input [1:0]  siz;
        output [15:0] data;
        begin
            @(posedge clk_cpu);
            cpu_a    <= {8'h00, addr};
            cpu_siz  <= siz;
            cpu_fc   <= 3'b101;
            cpu_rw   <= 1'b1;
            cpu_as_n <= 1'b0;
            cpu_ds_n <= 1'b0;
            wait_dsack;
            data = cpu_din[31:16];
            // S5: AS high for one clk_cpu (a full cycle; the half-cycle
            // FAST_HANDOFF case is also tried by a back-to-back start).
            @(posedge clk_cpu);
            cpu_as_n <= 1'b1;
            cpu_ds_n <= 1'b1;
        end
    endtask

    task run_long;
        input integer do_leftover;
        begin
            reset_32 = 1'b1; ram_ready = 1'b0; reset_cpu = 1'b1;
            cpu_as_n = 1'b1; cpu_ds_n = 1'b1;
            repeat (8) @(posedge clk32);
            reset_32 = 1'b0; ram_ready = 1'b1;
            repeat (16) @(posedge clk_cpu);
            reset_cpu = 1'b0;
            repeat (4) @(posedge clk_cpu);

            word_read(24'h000000, 2'b00, d0);
            if (do_leftover) begin
                // leftover ack still high, with stale data, when the second
                // word's AS falls. The bus must not DSACK with DEAD.
                force u_arb.cpu_ack = 1'b1;
                force u_arb.cpu_q   = 16'hDEAD;
            end
            word_read(24'h000002, 2'b10, d1);
            if (do_leftover) begin
                // If the bus waited for leftover to drop, DSACK would never
                // come until we release. Release shortly after AS falls so a
                // correct 4-phase handshake can issue a real request.
                // word_read already returned, so if we got here with d1==DEAD
                // the leftover was wrongly accepted; if we hung, tmo fired.
                release u_arb.cpu_ack;
                release u_arb.cpu_q;
            end
        end
    endtask

    // leftover test needs to release BEFORE wait_dsack returns, so a
    // dedicated sequence is used for that case.
    task run_leftover;
        begin
            reset_32 = 1'b1; ram_ready = 1'b0; reset_cpu = 1'b1;
            cpu_as_n = 1'b1; cpu_ds_n = 1'b1;
            repeat (8) @(posedge clk32);
            reset_32 = 1'b0; ram_ready = 1'b1;
            repeat (16) @(posedge clk_cpu);
            reset_cpu = 1'b0;
            repeat (4) @(posedge clk_cpu);

            word_read(24'h000000, 2'b00, d0);
            force u_arb.cpu_ack = 1'b1;
            force u_arb.cpu_q   = 16'hDEAD;
            @(posedge clk_cpu);
            cpu_a    <= 32'h00000002;
            cpu_siz  <= 2'b10;
            cpu_as_n <= 1'b0;
            cpu_ds_n <= 1'b0;
            // hold leftover for a few clk_cpu so S_MEM would have seen it
            repeat (3) @(posedge clk_cpu);
            if (cpu_dsack_n !== 2'b11) begin
                $display("FAIL: leftover ack accepted, D=%h", cpu_din[31:16]);
                errors = errors + 1;
                d1 = cpu_din[31:16];
            end
            release u_arb.cpu_ack;
            release u_arb.cpu_q;
            wait_dsack;
            d1 = cpu_din[31:16];
            @(posedge clk_cpu);
            cpu_as_n <= 1'b1;
            cpu_ds_n <= 1'b1;
        end
    endtask

    integer a;
    initial begin
        errors = 0;
        for (a = 0; a < 2; a = a + 1) begin
            align = a[0];
            div = 0;
            clk_cpu = 1'b0;
            run_long(0);
            $display("ALIGN=%0d clean  D0=%h D1=%h DSACK0=%b BERR=%b",
                     a, d0, d1, cpu_dsack_n, cpu_berr_n);
            if (d0 !== 16'h602E) begin $display("FAIL: D0"); errors = errors + 1; end
            if (d1 !== 16'h0404) begin $display("FAIL: D1"); errors = errors + 1; end
            if (cpu_berr_n !== 1'b1) begin $display("FAIL: BERR"); errors = errors + 1; end

            run_leftover;
            $display("ALIGN=%0d leftover D0=%h D1=%h", a, d0, d1);
            if (d0 !== 16'h602E) begin $display("FAIL: leftover D0"); errors = errors + 1; end
            if (d1 !== 16'h0404) begin $display("FAIL: leftover D1 (got stale?)"); errors = errors + 1; end
        end
        if (errors == 0) $display("ALL PASS");
        else $display("FAILED %0d", errors);
        $finish;
    end
endmodule
