// tb_tosfill.v - FAL_01: TOS 4.04 hb_rect (tos4x pixvdi hbrect.s) register sequence, 4 planes, per-plane LOGOP, TAS poll
// Register writes go through the clk_32 sel/done port like falcon_core; the "CPU" grants the bus a few
// clocks after br_want and toggles cpu_cyc_tog while it owns the bus (shared mode). Memory: 64K words
// behind a 4-phase req/ack with variable latency (arbiter-like).
`timescale 1ns/1ps
module tb_tosfill;
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
    integer i, x, y, p, e;
    reg [15:0] exp, got, mk;
    // TAS (a5): read byte $8A3C, write it back with bit 7 set (UDS only), loop while it was set
    task tas_wait;
        begin
            polls = 0; st = 16'h8000;
            while (st[15]) begin
                rdw(6'h3C, st); wr(6'h3C, {st[15:8] | 8'h80, 8'h00}, 1, 0);
                polls = polls + 1; if (polls > 200000) begin $display("TIMEOUT"); $finish; end
            end
        end
    endtask
    // rectangle: 4 planes, X words 3 (span), Y lines 5, line = 160 bytes (ST low), base word $1000
    localparam BASE = 16'h1000, LW = 80, SPAN = 3, HGT = 5;
    reg [3:0] col; reg [15:0] lm, rm;
    initial begin
        for (i = 0; i < 65536; i = i + 1) mem[i] = (i % 4 == 1) ? 16'hFFFF : 16'h0000;   // green desktop: pen 2 = plane 1
        repeat (8) @(posedge clk); reset <= 0; repeat (8) @(posedge clk);
        lm = 16'h0FFF; rm = 16'hFFF0;
        for (e = 0; e < 3; e = e + 1) begin
            col = (e == 0) ? 4'd7 : (e == 1) ? 4'd0 : 4'd15;
            if (e > 0) begin lm = 16'hFFFF; rm = 16'hFFFF; end
            wr(6'h20, 16'h0000, 1, 1);                 // clr.w B_S_NXWD
            wr(6'h28, lm, 1, 1); wr(6'h2A, 16'hFFFF, 1, 1); wr(6'h2C, rm, 1, 1);
            wr(6'h2E, 16'd8, 1, 1);                    // D_NXWD = planes*2
            wr(6'h30, 16'd160 - 16'd8*(SPAN-1), 1, 1); // D_WRAP
            wr(6'h36, SPAN, 1, 1);                     // span
            for (i = 0; i < 16; i = i + 1) wr(i*2, 16'hFFFF, 1, 1);   // solid pattern
            for (p = 0; p < 4; p = p + 1) begin
                wr(6'h32, 16'h0000, 1, 1); wr(6'h34, (BASE + p) * 2, 1, 1);   // move.l a1,B_D_ADDR
                wr(6'h38, HGT, 1, 1);
                wr(6'h3A, col[p] ? 16'h0103 : 16'h0100, 1, 1);           // BM_PAT+3 / BM_PAT+0
                wr(6'h3C, 16'h8000, 1, 1);                               // move.w d4,(a5)  (line 0, GO)
                tas_wait;
            end
            for (y = 0; y < HGT; y = y + 1) for (x = 0; x < SPAN; x = x + 1) for (p = 0; p < 4; p = p + 1) begin
                mk = (x == 0) ? lm : (x == SPAN-1) ? rm : 16'hFFFF;
                i = BASE + y*LW + x*4 + p; got = mem[i];
                exp = (col[p] ? 16'hFFFF : 16'h0000) & mk | ((e == 0) ? ((p == 1) ? 16'hFFFF : 16'h0000) : 16'h0000) & ~mk;
                if (e > 0) exp = col[p] ? 16'hFFFF : 16'h0000;
                if (got !== exp) begin errs = errs + 1; if (errs < 20) $display("ERR fill%0d col %0d y%0d x%0d plane%0d got %h exp %h", e, col, y, x, p, got, exp); end
            end
            $display("fill%0d colour %0d done, errs so far %0d", e, col, errs);
        end
        $display("DONE errs=%0d grant_viol=%0d blt_cycles=%0d cpu_cycles=%0d", errs, grant_viol, blt_cycles, cpu_cycles);
        $finish;
    end
endmodule
