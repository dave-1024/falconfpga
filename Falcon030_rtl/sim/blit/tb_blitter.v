// tb_blitter.v - FAL_01: falcon_blitter.v (stBlitter wrapper) against blit_model.py (Hatari-style STE blitter)
// Register writes go through the clk_32 sel/done port like falcon_core; the "CPU" grants the bus a few
// clocks after br_want and toggles cpu_cyc_tog while it owns the bus (shared mode). Memory: 64K words
// behind a 4-phase req/ack with variable latency (arbiter-like).
`timescale 1ns/1ps
module tb_blitter;
    reg clk = 0; always #15.625 clk = ~clk;
    reg reset = 1;
    reg sel = 0, rw = 1, uds = 0, lds = 0; reg [5:1] a = 0; reg [15:0] wd = 0;
    wire [15:0] rd; wire done;
    wire br_want, grant_32, m_req, m_we, irq_n; wire [23:1] m_a; wire [15:0] m_wdata;
    reg bus_grant = 0, tog = 0; reg m_ack = 0; reg [15:0] m_rdata = 0;
    falcon_blitter dut (.clk_32(clk), .reset(reset), .pwr_up(reset),
        .sel(sel), .a(a), .rw(rw), .uds(uds), .lds(lds), .wdata(wd), .rdata(rd), .done(done),
        .br_want(br_want), .bus_grant(bus_grant), .cpu_cyc_tog(tog),
        .grant_32(grant_32), .m_req(m_req), .m_a(m_a), .m_we(m_we), .m_wdata(m_wdata),
        .m_ack(m_ack), .m_rdata(m_rdata), .irq_n(irq_n));
    reg [15:0] mem [0:65535];
    integer lat = 0, errs = 0, cpu_cycles = 0, blt_cycles = 0, grant_viol = 0;
    // memory
    always @(posedge clk) begin
        if (m_req && !m_ack) begin
            if (!grant_32) grant_viol = grant_viol + 1;
            lat = lat + 1;
            if (lat >= 3 + (m_a[3:1] % 6)) begin
                lat = 0; m_ack <= 1; blt_cycles = blt_cycles + 1;
                if (m_we) mem[m_a[16:1]] <= m_wdata; else m_rdata <= mem[m_a[16:1]];
            end
        end else if (!m_req) m_ack <= 0;
    end
    // CPU side (falcon_bus): grant only between CPU cycles, 4 clocks after BR, release after BR drops; while not granted, a CPU cycle every 8 clocks
    integer gc = 0, cc = 0;
    always @(posedge clk) begin
        if (br_want && !bus_grant && !sel) begin gc = gc + 1; if (gc >= 4) begin bus_grant <= 1; gc = 0; end end
        else if (!br_want && bus_grant) bus_grant <= 0;
        if (!bus_grant && !br_want) begin cc = cc + 1; if (cc == 8) begin cc = 0; tog <= ~tog; cpu_cycles = cpu_cycles + 1; end end
    end
    task wr(input [5:0] off, input [15:0] d, input u, input l);
        begin
            @(posedge clk); while (bus_grant || br_want) @(posedge clk);   // falcon_bus: BR wins in S_IDLE
            a <= off[5:1]; wd <= d; rw <= 0; uds <= u; lds <= l; sel <= 1;
            wait (done); @(posedge clk); sel <= 0; rw <= 1; @(posedge clk); wait (!done);
        end
    endtask
    task rdw(input [5:0] off, output [15:0] d);
        begin
            @(posedge clk); while (bus_grant || br_want) @(posedge clk);
            a <= off[5:1]; rw <= 1; uds <= 1; lds <= 1; sel <= 1;
            wait (done); d = rd; @(posedge clk); sel <= 0; @(posedge clk); wait (!done);
        end
    endtask
    reg [15:0] st; integer polls;
    task wait_idle;
        begin
            polls = 0; st = 16'h8000;
            while (st[15]) begin rdw(6'h3C, st); polls = polls + 1; if (polls > 200000) begin $display("TIMEOUT"); $finish; end end
        end
    endtask
    integer i;
    initial begin
        $readmemh("mem_init.hex", mem);
        repeat (8) @(posedge clk); reset <= 0; repeat (8) @(posedge clk);
        `include "tests.vh"
        $writememh("mem_out.hex", mem);
        $display("DONE grant_viol=%0d blt_cycles=%0d cpu_cycles=%0d irq_n=%b", grant_viol, blt_cycles, cpu_cycles, irq_n);
        $finish;
    end
endmodule
