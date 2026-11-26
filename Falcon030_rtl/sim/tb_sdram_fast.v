// tb_sdram_fast.v - SDR-1: falcon_sdram_fast (80 MHz) + falcon_bus + a timed W9825G6KH model.
// Clocks from one 800 MHz "VCO" tick like pll_160m: clk_sd = /10, clk32 = /25, clk_cpu = /50, all rising together.
// Board model: pad clock leads clk_sd by PAD_LEAD, pad/board delay TPAD on clock and commands, tAC/tOH on reads.
// Traffic: loader fills region L, then scanout (burst-2) reads L, floppy DMA writes/reads region D, the CPU
// (030 bus BFM through falcon_bus) writes/reads region C and long-reads L, all at once. Every read is checked.
// Run: iverilog -g2012 -o t tb_sdram_fast.v ../hdl/bus/falcon_sdram_fast.v ../hdl/bus/falcon_bus.v && vvp t
`timescale 1ns/1ps
module tb_sdram_fast;
    parameter real PAD_LEAD = 1.875, TPAD = 3.0, TCO = 3.0, TAC = 6.0, TOH = 3.0, TBRD = 1.0;
    integer n = 0;
    reg vco = 0; always #0.625 begin vco = ~vco; n = n + 1; end
    wire clk_sd  = (n % 20) < 10;
    wire clk32   = (n % 50) < 25;
    wire clk_cpu = (n % 100) < 50;

    reg por = 1'b1;
    // ---------------- DUT ----------------
    wire        sd_cs, sd_we, sd_ras, sd_cas, ram_ready;
    wire [31:0] sd_data; wire [12:0] sd_addr; wire [3:0] sd_dqm; wire [1:0] sd_ba;
    reg vid_req = 0; reg [23:1] vid_a = 0; wire vid_ack; wire [15:0] vid_q, vid_q2;
    reg dma_req = 0, dma_we = 0; reg [23:1] dma_a = 0; reg [15:0] dma_d = 0; wire dma_ack; wire [15:0] dma_q;
    reg ld_req = 0; reg [23:1] ld_a = 0; reg [15:0] ld_d = 0; wire ld_ack;
    wire mem_req, mem_we, mem_ack, mem_rd2; wire [23:1] mem_a; wire [1:0] mem_be; wire [15:0] mem_wdata, mem_rdata, mem_rdata2;
    wire ext_wr_tog;
`ifdef OLD
    // baseline: falcon_sdram_arb + sdram.v at 32 MHz (pad clock from clk32)
    wire sd_cs_i, sd_we_i, sd_refresh, sd_ecs, sd_rd2; wire [21:0] sd_waddr; wire [1:0] sd_ds, sd_st_ba; wire [15:0] sd_din, sd_dout, sd_dout2;
    falcon_sdram_arb arb (.clk(clk32), .reset(por), .ram_ready(ram_ready),
        .sd_cs(sd_cs_i), .sd_we(sd_we_i), .sd_refresh(sd_refresh), .sd_ecs(sd_ecs), .sd_addr(sd_waddr), .sd_ds(sd_ds), .sd_din(sd_din),
        .sd_dout(sd_dout), .sd_dout2(sd_dout2), .sd_rd2(sd_rd2), .sd_ba(sd_st_ba),
        .vid_req(vid_req), .vid_a(vid_a), .vid_ack(vid_ack), .vid_q(vid_q), .vid_q2(vid_q2),
        .dma_req(dma_req), .dma_we(dma_we), .dma_a(dma_a), .dma_d(dma_d), .dma_ack(dma_ack), .dma_q(dma_q),
        .ld_req(ld_req), .ld_a(ld_a), .ld_d(ld_d), .ld_ack(ld_ack),
        .cpu_req(mem_req), .cpu_a(mem_a), .cpu_we(mem_we), .cpu_be(mem_be), .cpu_d(mem_wdata), .cpu_ack(mem_ack), .cpu_q(mem_rdata),
        .cpu_rd2(mem_rd2), .cpu_q2(mem_rdata2), .ext_wr_tog(ext_wr_tog));
    sdram sdram (.clk(clk32), .reset_n(~por), .ready(ram_ready), .sd_clk(), .sd_cke(), .sd_data(sd_data), .sd_addr(sd_addr),
        .sd_dqm(sd_dqm), .sd_ba(sd_ba), .sd_cs(sd_cs), .sd_we(sd_we), .sd_ras(sd_ras), .sd_cas(sd_cas),
        .refresh(sd_refresh), .din(sd_din), .dout(sd_dout), .dout2(sd_dout2), .addr(sd_waddr), .ds(sd_ds), .cs(sd_cs_i), .ecs(sd_ecs),
        .we(sd_we_i), .zmask(1'b0), .st_ba(sd_st_ba), .st_rd2(sd_rd2));
    wire ctl_clk = clk32; localparam real TCK = 31.25; wire ctl_oe = sd_cs_i && sd_we_i;
`else
    falcon_sdram_fast #(.INIT_WAIT(200), .REF_INT(300)) dut (
        .clk_sd(clk_sd), .clk_32(clk32), .reset(por),
        .sd_clk(), .sd_cke(), .sd_cs(sd_cs), .sd_we(sd_we), .sd_ras(sd_ras), .sd_cas(sd_cas),
        .sd_data(sd_data), .sd_addr(sd_addr), .sd_dqm(sd_dqm), .sd_ba(sd_ba), .ram_ready(ram_ready),
        .vid_req(vid_req), .vid_a(vid_a), .vid_ack(vid_ack), .vid_q(vid_q), .vid_q2(vid_q2),
        .dma_req(dma_req), .dma_we(dma_we), .dma_a(dma_a), .dma_d(dma_d), .dma_ack(dma_ack), .dma_q(dma_q),
        .ld_req(ld_req), .ld_a(ld_a), .ld_d(ld_d), .ld_ack(ld_ack),
        .cpu_req(mem_req), .cpu_a(mem_a), .cpu_we(mem_we), .cpu_be(mem_be), .cpu_d(mem_wdata), .cpu_rd2(mem_rd2),
        .cpu_ack(mem_ack), .cpu_q(mem_rdata), .cpu_q2(mem_rdata2), .cpu_ack_32(), .cpu_q_32(), .ext_wr_tog(ext_wr_tog));

    wire ctl_clk = clk_sd; localparam real TCK = 12.5; wire ctl_oe = dut.dq_oe[0];
`endif
    reg reset_cpu = 1'b1;
    reg cpu_as_n = 1, cpu_ds_n = 1, cpu_rw = 1; reg [31:0] cpu_a = 0, cpu_dout = 0; reg [1:0] cpu_siz = 0;
    wire [31:0] cpu_din; wire [1:0] cpu_dsack_n; wire cpu_berr_n, cpu_avec_n, cpu_ciin_n;
    falcon_bus #(.IO_WAIT(2)) u_bus (.clk(clk_cpu), .reset(reset_cpu),
        .cpu_a(cpu_a), .cpu_dout(cpu_dout), .cpu_din(cpu_din), .cpu_as_n(cpu_as_n), .cpu_ds_n(cpu_ds_n), .cpu_rw(cpu_rw),
        .cpu_siz(cpu_siz), .cpu_fc(3'b101), .cpu_dsack_n(cpu_dsack_n), .cpu_berr_n(cpu_berr_n), .cpu_avec_n(cpu_avec_n),
        .cpu_ciin_n(cpu_ciin_n), .mem_req(mem_req), .mem_a(mem_a), .mem_we(mem_we), .mem_be(mem_be), .mem_wdata(mem_wdata),
        .mem_ack(mem_ack), .mem_rdata(mem_rdata), .mem_rd2(mem_rd2), .mem_rdata2(mem_rdata2), .ext_wr_tog(ext_wr_tog),
        .io_cyc(), .io_a(), .io_uds(), .io_lds(), .io_rw(), .io_wr(), .io_wdata(), .io_rdata(16'h0), .io_ext(1'b0), .io_done(1'b0),
        .iack_mfp(), .mfp_vector(8'h0), .mfp_dtack(1'b0), .br_want(1'b0), .bus_grant(), .cyc_tog());

    // ---------------- board + W9825G6KH model ----------------
    reg pclk = 0; always @(ctl_clk) pclk <= #(TCK - PAD_LEAD + TPAD) ctl_clk;   // chip clock pin (transport delay)
    wire [2:0] c_cmd; wire [12:0] c_a; wire [1:0] c_ba, c_dqm; wire [15:0] c_dq_in; wire c_oe;
    assign #(TCO) c_cmd = {sd_ras, sd_cas, sd_we};
    assign #(TCO) c_a = sd_addr; assign #(TCO) c_ba = sd_ba; assign #(TCO) c_dqm = sd_dqm[1:0];
    assign #(TCO) c_dq_in = sd_data[15:0];
    assign #(TCO) c_oe = ctl_oe;
    reg [15:0] q_drv = 16'h0; reg q_en = 0;
    assign #(TBRD) sd_data[15:0] = q_en ? q_drv : 16'bz;
    localparam ACT=3'b011, RD=3'b101, WR=3'b100, PRE=3'b010, REF=3'b001, MRS=3'b000;
    reg [15:0] mem [0:(1<<24)-1];
    reg act [0:3]; reg [12:0] row [0:3]; realtime t_act [0:3], t_pre [0:3], t_wr [0:3], t_ref, t_lastref;
    reg mrs_done = 0; integer merr = 0, i, nref = 0;
    real tck = TCK;
    initial begin for (i=0;i<4;i=i+1) begin act[i]=0; t_act[i]=-1000; t_pre[i]=-1000; t_wr[i]=-1000; end t_ref=-1000; t_lastref=0; end
    task mE(input [8*48:1] s); begin merr = merr + 1; if (merr < 20) $display("%t MODEL ERR %0s", $time, s); end endtask
    reg rd_prev = 0; reg [23:0] rd_adr; realtime drop_t = 0;
    always @(posedge pclk) begin
        // CL2: data for the READ sampled at edge c0 is valid tAC after c1 until tOH after c2
        if (rd_prev) begin q_drv <= #(TAC) mem[rd_adr]; q_en <= #(TAC) 1'b1; drop_t = $realtime + tck + TOH; end
        rd_prev <= (c_cmd == RD); rd_adr <= {c_ba, row[c_ba], c_a[8:0]};
    end
    always @(posedge pclk) begin #(TOH); if (q_en && $realtime >= drop_t - 0.01) q_en = 0; end
    always @(posedge pclk) begin
        if (c_oe && q_en) mE("bus contention");
        case (c_cmd)
        ACT: begin
            if (!mrs_done) mE("ACT before MRS");
            if (act[c_ba]) mE("ACT on open bank");
            if ($realtime - t_act[c_ba] < 60 - 0.01) mE("tRC");
            if ($realtime - t_pre[c_ba] < 18 - 0.01) mE("tRP");
            if ($realtime - t_ref < 60 - 0.01) mE("tRFC");
            act[c_ba] = 1; row[c_ba] = c_a; t_act[c_ba] = $realtime; end
        RD, WR: begin
            if (!act[c_ba]) mE("RD/WR on idle bank");
            if ($realtime - t_act[c_ba] < 18 - 0.01) mE("tRCD");
`ifndef OLD
            if (c_a[10]) mE("unexpected auto precharge");
`endif
            if (c_cmd == RD) begin
                if (c_dqm != 2'b00) mE("read DQM");
            end else begin
                if (^c_dq_in === 1'bx) mE("write data X");
                if (!c_oe) mE("write without DQ drive");
                if (!c_dqm[1]) mem[{c_ba, row[c_ba], c_a[8:0]}][15:8] = c_dq_in[15:8];
                if (!c_dqm[0]) mem[{c_ba, row[c_ba], c_a[8:0]}][7:0]  = c_dq_in[7:0];
                t_wr[c_ba] = $realtime;
            end end
        PRE: for (i=0;i<4;i=i+1) if (c_a[10] || i == c_ba) begin
            if (act[i] && $realtime - t_act[i] < 42 - 0.01) mE("tRAS");
            if (act[i] && $realtime - t_wr[i] < 2*tck - 0.01) mE("tWR");
            act[i] = 0; t_pre[i] = $realtime; end
`ifdef OLD
        default: ;
        endcase
        if ((c_cmd == RD || c_cmd == WR) && c_a[10]) begin act[c_ba] = 0; t_pre[c_ba] = $realtime + tck; end
        case (c_cmd)
`endif
        REF: begin
            for (i=0;i<4;i=i+1) if (act[i] || $realtime - t_pre[i] < 18 - 0.01) mE("REF with bank busy");
            if ($realtime - t_ref < 60 - 0.01) mE("tRFC REF-REF");
            if (mrs_done && nref > 2 && $realtime - t_lastref > 7800) mE("refresh interval > 7.8us");
            t_ref = $realtime; t_lastref = $realtime; nref = nref + 1; end
        MRS: begin if (c_a != 13'h0220) mE("mode value"); mrs_done = 1; end
        default: ;
        endcase
    end

    // ---------------- traffic ----------------
    function [23:1] wa(input [1:0] reg_, input [11:0] i);   // region word address, spans both banks / many rows
        wa = {i[11], {reg_, i[10:9], 9'b101001101}, i[8:0]};
    endfunction
    function [15:0] pat(input [11:0] i); pat = {i[3:0], ~i[11:0]} ^ 16'h5A3C; endfunction
    integer errors = 0, k, vchk = 0, dchk = 0, cchk = 0;
    reg [15:0] cshadow [0:4095];
    reg traffic = 0, ldone = 0;

    // loader (clk32): fill region 0 with pat()
    initial begin
        @(negedge por);
        @(posedge clk32); while (!ram_ready) @(posedge clk32);
        for (k = 0; k < 4096; k = k + 1) begin
            @(posedge clk32); while (ld_req || ld_ack) begin if (ld_req && ld_ack) ld_req <= 0; @(posedge clk32); end
            ld_a <= wa(2'd0, k); ld_d <= pat(k); ld_req <= 1;
        end
        @(posedge clk32); while (!ld_ack) @(posedge clk32); ld_req <= 0;
        ldone = 1;
    end
    // scanout (clk32): burst-2 reads of region 0, raised again only when req and ack are both low
    integer vi = 0;
    always @(posedge clk32) if (traffic) begin
        if (vid_req && vid_ack) begin
            vid_req <= 0; vchk = vchk + 1;
            if (vid_q !== pat(vi) || vid_q2 !== pat(vi+1)) begin errors = errors + 1;
                if (errors < 10) $display("%t VID ERR i=%0d q=%h/%h exp %h/%h", $time, vi, vid_q, vid_q2, pat(vi), pat(vi+1)); end
            vi = (vi + 2) % 4094;
        end else if (!vid_req && !vid_ack && ($random & 3) != 0) begin vid_a <= wa(2'd0, vi); vid_req <= 1; end
    end
    // floppy DMA (clk32): write a word of region 1 then read it back
    integer di = 0; reg dph = 0; reg [15:0] dexp;
    always @(posedge clk32) if (traffic) begin
        if (dma_req && dma_ack) begin
            dma_req <= 0;
            if (!dma_we) begin dchk = dchk + 1; if (dma_q !== dexp) begin errors = errors + 1;
                if (errors < 10) $display("%t DMA ERR i=%0d q=%h exp %h", $time, di, dma_q, dexp); end di = (di + 1) % 4096; end
        end else if (!dma_req && !dma_ack && ($random & 7) == 0) begin
            dma_a <= wa(2'd1, di); dma_we <= !dph;
            if (!dph) begin dexp = $random; dma_d <= dexp; end
            dph <= !dph; dma_req <= 1;
        end
    end
    // 030 bus BFM
    integer lat, lat_min = 99, lat_max = 0, lat_sum = 0, lat_n = 0;
    task cyc(input rw, input [23:0] a, input [1:0] siz, input [15:0] wd, output [15:0] rd, output integer clocks);
        integer t; begin
            @(posedge clk_cpu); cpu_a <= {8'h00, a}; cpu_siz <= siz; cpu_rw <= rw; cpu_dout <= {wd, wd};
            cpu_as_n <= 0; cpu_ds_n <= 0; t = 0;
            @(posedge clk_cpu); while (cpu_dsack_n === 2'b11 && t < 400) begin @(posedge clk_cpu); t = t + 1; end
            if (t >= 400) begin errors = errors + 1; $display("%t DSACK timeout A=%h", $time, a); end
            rd = cpu_din[31:16]; clocks = t + 1;
            @(posedge clk_cpu); cpu_as_n <= 1; cpu_ds_n <= 1;
        end endtask
    reg [15:0] r0, r1; integer c0, c1, ci;
    initial begin
        for (k = 0; k < 4096; k = k + 1) cshadow[k] = 16'hxxxx;
        repeat (20) @(posedge clk32); por <= 0;
        wait (ldone); repeat (4) @(posedge clk_cpu); reset_cpu <= 0; repeat (4) @(posedge clk_cpu);
        // idle-SDRAM latency (no other traffic): word read, long read (2 cycles), word write
        for (k = 0; k < 8; k = k + 1) begin
            cyc(1, {wa(2'd0, 2*k), 1'b0}, 2'b10, 0, r0, c0);
            if (r0 !== pat(2*k)) begin errors = errors + 1; $display("CPU rd.w ERR %h exp %h", r0, pat(2*k)); end
            lat_sum = lat_sum + c0; lat_n = lat_n + 1; if (c0 < lat_min) lat_min = c0; if (c0 > lat_max) lat_max = c0;
            repeat (k % 3) @(posedge clk32);
        end
        $display("idle rd.w AS->DSACK clk_cpu: min %0d max %0d avg %0.2f", lat_min, lat_max, 1.0*lat_sum/lat_n);
        cyc(1, {wa(2'd0, 20), 1'b0}, 2'b00, 0, r0, c0); cyc(1, {wa(2'd0, 21), 1'b0}, 2'b10, 0, r1, c1);
        $display("idle rd.l: first %0d, second %0d clk_cpu (data %h %h)", c0, c1, r0, r1);
        if (r0 !== pat(20) || r1 !== pat(21)) begin errors = errors + 1; $display("CPU rd.l ERR"); end
        cyc(0, {wa(2'd2, 5), 1'b0}, 2'b10, 16'h1234, r0, c0); cshadow[5] = 16'h1234;
        $display("idle wr.w: %0d clk_cpu", c0);
        // C5 stale-buffer check: word read at A (rd2 fills buf2 with A+2), floppy DMA writes A+2, CPU reads A+2
        cyc(1, {wa(2'd0, 40), 1'b0}, 2'b10, 0, r0, c0);
        @(posedge clk32); dma_a <= wa(2'd0, 41); dma_we <= 1; dma_d <= 16'hBEEF; dma_req <= 1;
        @(posedge clk32); while (!dma_ack) @(posedge clk32); dma_req <= 0; @(posedge clk32); while (dma_ack) @(posedge clk32);
        cyc(1, {wa(2'd0, 41), 1'b0}, 2'b10, 0, r1, c1);
        $display("stale-buffer check: A+2 after DMA write = %h (%0d clk_cpu)", r1, c1);
        if (r1 !== 16'hBEEF) begin errors = errors + 1; $display("STALE BUFFER ERR"); end
        dma_we <= 0; cyc(0, {wa(2'd0, 41), 1'b0}, 2'b10, pat(41), r1, c1);   // restore region 0
        // everything at once
        traffic = 1;
        lat_min = 99; lat_max = 0; lat_sum = 0; lat_n = 0;
        for (k = 0; k < 3000; k = k + 1) begin
            ci = $random & 4095;
            case ($random & 3)
            0: begin cyc(0, {wa(2'd2, ci), 1'b0}, 2'b10, k[15:0] ^ 16'hC0DE, r0, c0); cshadow[ci] = k[15:0] ^ 16'hC0DE; end
            1: begin cyc(1, {wa(2'd2, ci), 1'b0}, 2'b10, 0, r0, c0); cchk = cchk + 1;
                     if (cshadow[ci] !== 16'hxxxx && r0 !== cshadow[ci]) begin errors = errors + 1;
                         if (errors < 10) $display("%t CPU ERR C i=%0d %h exp %h", $time, ci, r0, cshadow[ci]); end
                     lat_sum = lat_sum + c0; lat_n = lat_n + 1; if (c0 > lat_max) lat_max = c0; if (c0 < lat_min) lat_min = c0; end
            2: begin ci = ci & 12'hFFE; cyc(1, {wa(2'd0, ci), 1'b0}, 2'b00, 0, r0, c0); cyc(1, {wa(2'd0, ci+1), 1'b0}, 2'b10, 0, r1, c1);
                     cchk = cchk + 1; if (r0 !== pat(ci) || r1 !== pat(ci+1)) begin errors = errors + 1;
                         if (errors < 10) $display("%t CPU ERR L i=%0d %h %h exp %h %h", $time, ci, r0, r1, pat(ci), pat(ci+1)); end end
            3: begin // byte write to region C (upper byte), then the word
                     cyc(0, {wa(2'd2, ci), 1'b0}, 2'b01, {8'hA5, 8'hA5}, r0, c0);
                     if (cshadow[ci] !== 16'hxxxx) cshadow[ci] = {8'hA5, cshadow[ci][7:0]}; end
            endcase
        end
        $display("busy rd.w AS->DSACK clk_cpu: min %0d max %0d avg %0.2f (scanout+DMA+refresh traffic)", lat_min, lat_max, 1.0*lat_sum/lat_n);
        traffic = 0; repeat (50) @(posedge clk32);
        $display("checks: vid %0d dma %0d cpu %0d, refreshes %0d, model errors %0d, data errors %0d", vchk, dchk, cchk, nref, merr, errors);
        if (errors == 0 && merr == 0 && vchk > 100 && dchk > 100) $display("PASS"); else $display("FAIL");
        $finish;
    end
    initial begin #20_000_000; $display("TIMEOUT"); $finish; end
endmodule
