// FalconFPGA TTRAM bench: cpu030_st_bridge (030 pins from wf030_stub.v) + sdram.v (TTRAM)
// + sdram_model.v, with random ST SDRAM traffic on the GSTMCU 8-clock slot grid.
// Shows: 32-bit TT-RAM read/write and byte-lane writes, ST-RAM data unaffected (shadow
// check of every ST read), no SDRAM command/data/DQM clash, BERR outside TT-RAM,
// $00/$FF still on the ST bus, and the 24-bit wrap with the switch off.
`timescale 1ns/1ps
module tb_ttram;
    reg clk = 0; always #15.625 clk = ~clk;          // 32 MHz
    reg clk_cpu = 0;                                  // 16 MHz, edges on clk rising edges
    always @(posedge clk) clk_cpu <= ~clk_cpu;
    wire clk_cpu_n = ~clk_cpu;
    integer gc = 0; always @(posedge clk) gc <= gc + 1;
    wire en1 = (gc % 4) == 0, en2 = (gc % 4) == 2;
    reg  pwrUp = 1, tt_en = 1;
    integer errors = 0;

    // ---------------- bridge ----------------
    wire eRWn, ASn, ASEn, LDSn, UDSn, VMAn, FC0, FC1, FC2, BGn, rstn, hlt; wire E;
    wire [15:0] oEdb; wire [23:1] eab; wire rom_fetch;
    reg  DTACKn = 1; reg [15:0] iEdb = 16'hffff;
    wire tt_req, tt_we, tt_ack; wire [21:0] tt_la; wire [3:0] tt_be; wire [31:0] tt_wdata, tt_rdata;
    cpu030_st_bridge #(.CPU_DIV(2), .RESET_HOLD(16)) br (
        .clk(clk), .clk_cpu(clk_cpu), .clk_cpu_n(clk_cpu_n), .extReset(1'b0), .pwrUp(pwrUp),
        .enPhi1(en1), .enPhi2(en2), .eRWn(eRWn), .ASn(ASn), .ASEn(ASEn), .LDSn(LDSn), .UDSn(UDSn),
        .E(E), .VMAn(VMAn), .FC0(FC0), .FC1(FC1), .FC2(FC2), .BGn(BGn), .oRESETn(rstn), .oHALTEDn(hlt),
        .DTACKn(DTACKn), .VPAn(1'b1), .BERRn(1'b1), .HALTn(1'b1), .BRn(1'b1), .BGACKn(1'b1),
        .IPL0n(1'b1), .IPL1n(1'b1), .IPL2n(1'b1), .iEdb(iEdb), .oEdb(oEdb), .eab(eab), .rom_fetch(rom_fetch),
        .dbg_run(), .dbg_req(), .dbg_dsack(), .dbg_berr(), .dbg_trace(),
        .tt_en(tt_en), .tt_req(tt_req), .tt_we(tt_we), .tt_la(tt_la), .tt_be(tt_be), .tt_wdata(tt_wdata),
        .tt_ack(tt_ack), .tt_rdata(tt_rdata));
    // ST bus responder (68000 side of the bridge): records the cycle, 16-bit memory
    reg [15:0] stbus [0:4095]; reg [23:1] st_last_a; integer st_cycles = 0;
    always @(posedge clk) begin
        if (!ASn && en1 && DTACKn) begin
            DTACKn <= 0; st_last_a <= eab; st_cycles = st_cycles + 1;
            iEdb <= stbus[eab[12:1]];
            if (!eRWn) begin
                if (!UDSn) stbus[eab[12:1]][15:8] <= oEdb[15:8];
                if (!LDSn) stbus[eab[12:1]][7:0]  <= oEdb[7:0];
            end
        end
        if (ASn) DTACKn <= 1;
    end

    // ---------------- SDRAM ----------------
    wire [31:0] sd_dq; wire [12:0] sd_a; wire [1:0] sd_ba; wire [3:0] sd_dqm;
    wire sd_cs, sd_we, sd_ras, sd_cas, sd_clk, sd_cke, ready;
    reg  st_cs = 0, st_we = 0, st_ecs = 0, st_ref = 0; reg [21:0] st_addr = 0; reg [1:0] st_ds = 0; reg [15:0] st_din = 0;
    wire [15:0] st_dout;
    reg  rst_n = 0;
    sdram u_sd (.sd_clk(sd_clk), .sd_cke(sd_cke), .sd_data(sd_dq), .sd_addr(sd_a), .sd_dqm(sd_dqm), .sd_ba(sd_ba),
        .sd_cs(sd_cs), .sd_we(sd_we), .sd_ras(sd_ras), .sd_cas(sd_cas), .clk(clk), .reset_n(rst_n), .ready(ready),
        .refresh(st_ref), .din(st_din), .dout(st_dout), .addr(st_addr), .ds(st_ds), .cs(st_cs), .ecs(st_ecs), .we(st_we), .zmask(1'b0),
        .tt_req(tt_req), .tt_we(tt_we), .tt_la(tt_la), .tt_be(tt_be), .tt_din(tt_wdata), .tt_ack(tt_ack), .tt_dout(tt_rdata));
    wire ctl_oe = u_sd.tt_oe | (!u_sd.tt_rdwin & st_cs & st_we);
    wire [31:0] m_err;
    sdram_model mdl (.clk(clk), .cmd({sd_ras, sd_cas, sd_we}), .a(sd_a), .ba(sd_ba), .dqm(sd_dqm[1:0]),
                     .dq(sd_dq[15:0]), .ctl_oe(ctl_oe), .errors(m_err));

    // ---------------- ST SDRAM traffic on the 8-clock grid ----------------
    // slot op: 0 idle, 1 read, 2 read with early start (ecs), 3 write, 4 refresh
    reg [15:0] shadow [0:1023]; integer i, st_reads = 0, st_writes = 0, st_ok = 0;
    reg st_on = 0; integer op = 0; reg [9:0] sa; reg chk = 0; reg [9:0] chk_a;
    initial for (i = 0; i < 1024; i = i + 1) shadow[i] = 16'h0000;
    function [21:0] stmap(input [9:0] x); stmap = {x[9:5], 8'h00, x[4:0], 4'h0}; endfunction  // spread over rows
    integer ph = 0;
    wire [2:0] gph = (gc + 64'd0 + ph) % 8;   // ph >= 0   // OFFGRID: phase lag, only ever grows -> ST slot gaps of 8..15 clocks (ST starts at any TT step)
`ifdef OFFGRID
    always @(posedge clk) if (st_on && gph == 3'd6 && ($urandom % 4) == 0) ph = ph + 8 - ($urandom % 8);  // delay the next slot by 0..7
`endif
    always @(posedge clk) if (st_on) begin
        #1;
        case (gph)
        7: begin op = $urandom % 6; if (op == 5) op = 1; sa = $urandom;
                 if (op == 2) begin st_ecs = 1; st_addr = stmap(sa); st_we = 0; end end   // ecs sampled at g7
        0: begin st_ecs = 0;
                 if (op != 0) begin st_cs = 1; st_addr = stmap(sa); st_ref = (op == 4); st_we = (op == 3);
                      st_ds = $urandom; st_din = $urandom; end end
        5: begin st_cs = 0; st_ref = 0; st_we = 0; end
        endcase
    end
    // shadow write at the WRITE command, read check after the capture edge (state 4)
    always @(posedge clk) begin
        if (st_on && st_cs && st_we && u_sd.state == 3'd1 && u_sd.sd_ba == 2'b00) begin
            if (!st_ds[1]) shadow[sa][15:8] <= st_din[15:8];
            if (!st_ds[0]) shadow[sa][7:0]  <= st_din[7:0];
            st_writes = st_writes + 1;
        end
        chk <= st_on && !st_we && !st_ref && st_cs && u_sd.state == 3'd4;
        chk_a <= sa;
    end
    always @(negedge clk) if (chk) begin
        st_reads = st_reads + 1;
        if (st_dout !== shadow[chk_a]) begin errors = errors + 1; $display("%t ST READ ERR a=%h got %h exp %h", $time, chk_a, st_dout, shadow[chk_a]); end
        else st_ok = st_ok + 1;
    end

    // ---------------- 030 bus cycles (stub pins) ----------------
    reg [31:0] rdat; reg rberr; integer cyc_t0, lat_sum = 0, lat_n = 0, lat_max = 0;
    task cpu(input [31:0] a, input [1:0] sz, input rw, input [31:0] wd);
        integer to; begin
        @(posedge clk_cpu); #1;
        br.i_wf68k30l.adr = a; br.i_wf68k30l.size = sz; br.i_wf68k30l.rwn = rw;
        br.i_wf68k30l.dout = wd; br.i_wf68k30l.fc = 3'd5; br.i_wf68k30l.asn = 0; cyc_t0 = gc;
        to = 0;
        @(posedge clk_cpu_n);
        while (br.cpu_dsackn == 2'b11 && br.cpu_berrn && to < 400) begin @(posedge clk_cpu_n); to = to + 1; end
        rberr = !br.cpu_berrn;
        @(posedge clk_cpu_n); rdat = br.cpu_din;
        if (br.cpu_dsackn == 2'b00) begin lat_sum = lat_sum + (gc - cyc_t0); lat_n = lat_n + 1; if (gc - cyc_t0 > lat_max) lat_max = gc - cyc_t0; end
        @(posedge clk_cpu); #1 br.i_wf68k30l.asn = 1;
        if (to >= 400) begin errors = errors + 1; $display("%t CPU TIMEOUT a=%h", $time, a); end
    end endtask
    // reference model of the TT-RAM (byte array) for the random test
    reg [7:0] ttm [0:65535];
    function [3:0] lanes(input [1:0] a, input [1:0] sz);
        integer n, k; begin n = (sz == 0) ? 4 : sz; lanes = 0;
        for (k = 0; k < 4; k = k + 1) if (k >= a && k < a + n) lanes[3-k] = 1; end endfunction
    task tt_w(input [31:0] a, input [1:0] sz, input [31:0] d); integer k; reg [3:0] l; begin
        cpu(a, sz, 0, d); l = lanes(a[1:0], sz);
        if (rberr) begin errors = errors + 1; $display("TT WRITE BERR %h", a); end
        for (k = 0; k < 4; k = k + 1) if (l[3-k]) ttm[{a[15:2], 2'b00} + k] = d[31-8*k -: 8];
    end endtask
    task tt_r(input [31:0] a, input [1:0] sz); integer k; reg [3:0] l; begin
        cpu(a, sz, 1, 0); l = lanes(a[1:0], sz);
        if (br.cpu_dsackn !== 2'b00 && !rberr) ; // DSACK already dropped: checked via rdat
        for (k = 0; k < 4; k = k + 1) if (l[3-k] && rdat[31-8*k -: 8] !== ttm[{a[15:2], 2'b00} + k]) begin
            errors = errors + 1; $display("%t TT READ ERR a=%h lane %0d got %h exp %h", $time, a, k, rdat[31-8*k -: 8], ttm[{a[15:2],2'b00}+k]); end
    end endtask

    integer n, tt_ops = 0; reg [31:0] ra; reg [1:0] rs;
    initial begin
        for (i = 0; i < 65536; i = i + 1) ttm[i] = 8'h00;
        for (i = 0; i < 4096; i = i + 1) stbus[i] = i;
        #200 pwrUp = 0; rst_n = 1;
        wait (ready); repeat (16) @(posedge clk);
        @(posedge clk); while (gc % 8 != 6) @(posedge clk);
        st_on = 1;
        repeat (2000) @(posedge clk);
        // --- directed: long, words, bytes, 3-byte, misaligned pieces
        tt_w(32'h01000100, 2'b00, 32'h12345678); tt_r(32'h01000100, 2'b00);
        if (rdat !== 32'h12345678) begin errors = errors + 1; $display("long rd %h", rdat); end
        tt_w(32'h01000101, 2'b01, 32'h00AA0000);   // byte at A1:0 = 01 -> D23:16
        tt_w(32'h01000103, 2'b01, 32'h000000BB);   // byte lane 3
        tt_r(32'h01000100, 2'b00);
        if (rdat !== 32'h12AA56BB) begin errors = errors + 1; $display("byte lanes rd %h", rdat); end
        tt_w(32'h01000102, 2'b10, 32'h0000CAFE);   // word at A1:0 = 10 -> D15:0
        tt_w(32'h01000204, 2'b00, 32'h01020304); tt_w(32'h01000201, 2'b00, 32'h005566FF);   // long at A=01: lanes 1-3
        tt_w(32'h01FFFFFC, 2'b00, 32'hDEADBEEF);   // last long of 16 MB (bank 2)
        tt_r(32'h01FFFFFC, 2'b00); if (rdat !== 32'hDEADBEEF) begin errors = errors + 1; $display("top rd %h", rdat); end
        tt_w(32'h01800000, 2'b00, 32'hA5A55A5A); tt_r(32'h01800000, 2'b00);
        if (rdat !== 32'hA5A55A5A) begin errors = errors + 1; $display("bank2 rd %h", rdat); end
        tt_r(32'h01000100, 2'b00); if (rdat !== 32'h12AACAFE) begin errors = errors + 1; $display("word rd %h", rdat); end
        tt_r(32'h01000200, 2'b00); if (rdat !== 32'h005566FF && rdat[23:0] !== 24'h5566FF) begin errors = errors + 1; $display("mis rd %h", rdat); end
        $display("directed TT-RAM r/w done, errors=%0d", errors);
        // --- random TT traffic (64 KB window, both banks via A23) against the byte model
        for (n = 0; n < 3000; n = n + 1) begin
            ra = {8'h01, 8'h00, 16'h0} | ($urandom & 32'h0000FFFF); rs = $urandom;
            if ($urandom % 2) tt_w(ra, rs, $urandom); else tt_r(ra, rs);
            tt_ops = tt_ops + 1;
        end
        $display("random TT-RAM: %0d ops, errors=%0d; TT access latency avg %0d.%0d max %0d clk32 (AS to DSACK seen)",
                 tt_ops, errors, lat_sum / lat_n, (lat_sum * 10 / lat_n) % 10, lat_max);
        // --- bus errors and ST-side decode with TT on
        cpu(32'h02000000, 2'b01, 1, 0); if (!rberr) begin errors = errors + 1; $display("no BERR at 02000000"); end
        cpu(32'h80001234, 2'b10, 1, 0); if (!rberr) begin errors = errors + 1; $display("no BERR at 80001234"); end
        n = st_cycles; cpu(32'h00000102, 2'b10, 1, 0);
        if (rberr || st_cycles != n + 1 || st_last_a != 23'h81) begin errors = errors + 1; $display("ST cycle $00000102 wrong"); end
        n = st_cycles; cpu(32'hFFFF0204, 2'b10, 1, 0);
        if (rberr || st_cycles != n + 1 || st_last_a != 23'h7F8102) begin errors = errors + 1; $display("ST cycle $FFFF0204 wrong %h", st_last_a); end
        if (br.cpu_cii_n !== 1'b0) ;
        $display("decode with TT on checked, errors=%0d", errors);
        // --- switch off: $01000100 is ST $000100 (24-bit wrap), no TT request, no BERR
        tt_en = 0; repeat (4) @(posedge clk);
        n = st_cycles; cpu(32'h01000100, 2'b10, 1, 0);
        if (rberr || st_cycles != n + 1 || st_last_a != 23'h80 || rdat[31:16] !== stbus[12'h80]) begin errors = errors + 1; $display("wrap off wrong a=%h d=%h", st_last_a, rdat); end
        n = st_cycles; cpu(32'h02000000, 2'b10, 1, 0);
        if (rberr || st_cycles != n + 1 || st_last_a != 23'h0) begin errors = errors + 1; $display("wrap off 02 wrong"); end
        $display("switch off: 24-bit wrap checked, errors=%0d", errors);
        repeat (200) @(posedge clk);
        $display("ST traffic: %0d reads checked (%0d ok), %0d writes; SDRAM model errors %0d", st_reads, st_ok, st_writes, m_err);
        if (errors == 0 && m_err == 0 && st_ok == st_reads && st_reads > 500) $display("TTRAM BENCH PASS");
        else $display("TTRAM BENCH FAIL");
        $finish;
    end
    // CIIN check on every TT cycle: negated (cachable) with TT on, asserted otherwise
    always @(posedge clk) if (!br.cpu_asn && br.i_wf68k30l.fc != 3'd7) begin
        if (br.i_wf68k30l.adr[31:24] == 8'h01 && tt_en && br.cpu_cii_n !== 1'b1) begin errors = errors + 1; $display("CIIN wrong (TT)"); end
        if ((br.i_wf68k30l.adr[31:24] != 8'h01 || !tt_en) && br.cpu_cii_n !== 1'b0) begin errors = errors + 1; $display("CIIN wrong (ST)"); end
    end
    initial begin #50_000_000; $display("TIMEOUT"); $finish; end
endmodule
