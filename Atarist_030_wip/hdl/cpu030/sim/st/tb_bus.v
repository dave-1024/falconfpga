`timescale 1ps/1ps
// Whole ST core (atarist.v, CPU_030 + cpu030_st_bridge + WF68K30L netlist)
// with board-like memory latencies:
//   RAM: tang/mega138kpro/sdram.v itself (F63: with the gstmcu early start) and an SDRAM chip model (CL2)
//   ROM: cycle model of tang/console60k/flash_dspi.v at 100 MHz (async to
//        clk32, 2-flop cs sync, 25 states, dout filled 2 bits per clock)
// Checks every bridge read: iEdb at en1 entering S6 (A+375) against iEdb at
// S6 en2 (A+437.5, the fx68k latch edge), per region; ST AS-to-AS spacing.
module tb_bus;
    parameter integer CPU_PHASE_PS = 15625;
    parameter integer FL_PHASE_PS  = 3000;
    reg clk32 = 0, clk_cpu = 0, flclk = 0;
    always #15625 clk32 = ~clk32;
    integer cph = CPU_PHASE_PS; initial begin if ($value$plusargs("cph=%d", cph)) ; #(cph); forever #31250 clk_cpu = ~clk_cpu; end
    initial begin #(FL_PHASE_PS); forever #5000 flclk = ~flclk; end
    wire clk_cpu_n = ~clk_cpu;
    reg porb = 0, resb = 0;
    initial begin repeat (20) @(posedge clk32); porb = 1; repeat (300) @(posedge clk32); resb = 1; end

    wire ras_n, cash_n, casl_n, we_n, refresh, rom_n;
    wire [23:1] ram_a, rom_addr;
    wire [15:0] mdout;
    reg  [15:0] mdin, rom_dout = 16'hffff;
    reg [15:0] rom [0:131071];
    reg [15:0] ram [0:(1<<21)-1];
    integer k; reg [8*128-1:0] romfn;
    initial begin
        if (!$value$plusargs("rom=%s", romfn)) romfn = "rom.hex";
        $readmemh(romfn, rom);
        for (k = 0; k < (1<<21); k = k + 1) ram[k] = 16'h0000;
    end
    // ---- RAM: tang/mega138kpro/sdram.v (as in misterynano.sv) + SDRAM chip model (CL2) ----
    wire ram_early; wire sd_ready;
    wire [31:0] sd_dq; wire [12:0] sd_a; wire [3:0] sd_dqm; wire [1:0] sd_ba;
    wire sd_clk, sd_cke, sd_cs, sd_we, sd_ras, sd_cas;
    wire [15:0] sd_dout;
    sdram sdram (.clk(clk32), .reset_n(porb), .ready(sd_ready), .zmask(1'b0),
        .sd_clk(sd_clk), .sd_cke(sd_cke), .sd_data(sd_dq), .sd_addr(sd_a), .sd_dqm(sd_dqm), .sd_ba(sd_ba),
        .sd_cs(sd_cs), .sd_we(sd_we), .sd_ras(sd_ras), .sd_cas(sd_cas),
        .refresh(refresh), .din(mdout), .dout(sd_dout), .addr(ram_a[22:1]), .ds({cash_n, casl_n}),
        .cs(!ras_n && !ram_a[23]), .ecs(ram_early_en & ram_early && !ram_a[23]), .we(!we_n)
`ifdef TTRAM
        , .tt_req(tt_req), .tt_we(tt_we), .tt_la(tt_la), .tt_be(tt_be), .tt_din(tt_wdata), .tt_ack(tt_ack), .tt_dout(tt_rdata)
`endif
        );
`ifdef TTRAM
    // TTRAM: +tten=0 switches TT-RAM off (24-bit wrap)
    wire tt_req, tt_we, tt_ack; wire [21:0] tt_la; wire [3:0] tt_be; wire [31:0] tt_wdata, tt_rdata;
    integer tten = 1; initial if ($value$plusargs("tten=%d", tten)) ;
    wire tt_en = (tten != 0);
    reg [15:0] ttm [0:(1<<22)-1];   // banks 1/2: {bank2, row[11:0], col[8:0]}
    integer n_clash = 0, n_ttact = 0, n_ttprog = 0, n_ttdata = 0;
    reg tq = 0;   // TT cycles seen by the bridge, program vs data space
    integer htt [0:31]; integer tt_c = 0, tt_sum = 0, tt_n = 0; initial for (k = 0; k < 32; k = k + 1) htt[k] = 0;
    // TT cycle length: first clk32 edge with AS low -> AS negated (clk32), reads and writes
    always @(posedge clk32) begin
        if (dut.cpu030.t_open) tt_c = tt_c + 1;
        if (tq && !dut.cpu030.t_open) begin if (tt_c > 31) tt_c = 31; htt[tt_c] = htt[tt_c] + 1; tt_sum = tt_sum + tt_c; tt_n = tt_n + 1; tt_c = 0; end
    end
    always @(posedge clk32) begin tq <= dut.cpu030.t_open;
        if (dut.cpu030.t_open && !tq) begin if (dut.cpu030.cpu_fc[1]) n_ttprog = n_ttprog + 1; else n_ttdata = n_ttdata + 1; end end
    initial for (k = 0; k < (1<<22); k = k + 1) ttm[k] = 16'h0000;
    always @(negedge sd_clk) if (dq_oe && (sdram.tt_oe || (!sdram.tt_rdwin && sdram.cs && sdram.we))) begin
        n_clash = n_clash + 1; if (n_clash < 10) $display("%0t SDRAM DATA BUS CLASH", $time); end
    always @(posedge sd_clk) if ({sd_ras, sd_cas, sd_we} == 3'b011 && sd_ba != 0) n_ttact = n_ttact + 1;
`endif
    integer early_en = 1; initial if ($value$plusargs("early=%d", early_en)) ;
    wire ram_early_en = (early_en != 0);
    always @* mdin = sd_dout;
    // chip: commands sampled on the sd_clk rising edge (= clk32 falling edge), CL2,
    // tAC 5.4 ns, tOH 2.7 ns; READ/WRITE with A10 = auto precharge; memory = ram[]
    // TTRAM: rows per bank; bank 0 = ram[] (ST), banks 1/2 = ttm[] (TT-RAM)
    reg [12:0] sd_row, brow [0:3]; reg [1:0] rdq = 0; reg [22:0] ra0, ra1, ra_now; reg [15:0] dq_o; reg dq_oe = 0;
    assign sd_dq[15:0] = dq_oe ? dq_o : 16'hzzzz;
    always @(posedge sd_clk) begin
        ra_now = ra1;   // TTRAM: sample before the #delays (back-to-back READs: ra1 changes meanwhile)
        rdq <= {rdq[0], ({sd_ras, sd_cas, sd_we} == 3'b101)};
        ra1 <= ra0;
        if ({sd_ras, sd_cas, sd_we} == 3'b011) begin sd_row <= sd_a; brow[sd_ba] <= sd_a; end
        if ({sd_ras, sd_cas, sd_we} == 3'b101) ra0 <= {sd_ba, brow[sd_ba][11:0], sd_a[8:0]};
        if ({sd_ras, sd_cas, sd_we} == 3'b100) begin
            if (sd_ba == 0) begin
            if (!sd_dqm[1]) ram[{brow[0][11:0], sd_a[8:0]}][15:8] <= sd_dq[15:8];
            if (!sd_dqm[0]) ram[{brow[0][11:0], sd_a[8:0]}][7:0]  <= sd_dq[7:0];
            end else begin
`ifdef TTRAM
            if (!sd_dqm[1]) ttm[{sd_ba[1], brow[sd_ba][11:0], sd_a[8:0]}][15:8] <= sd_dq[15:8];
            if (!sd_dqm[0]) ttm[{sd_ba[1], brow[sd_ba][11:0], sd_a[8:0]}][7:0]  <= sd_dq[7:0];
`endif
            end
        end
`ifdef TTRAM
        if (rdq[1]) begin #2700 dq_oe <= 0; #2700 dq_o <= (ra_now[22:21] == 0) ? ram[ra_now[20:0]] : ttm[{ra_now[22], ra_now[20:0]}]; dq_oe <= 1; end
`else
        if (rdq[1]) begin #2700 dq_oe <= 0; #2700 dq_o <= ram[ra_now[20:0]]; dq_oe <= 1; end
`endif
        else if (dq_oe) begin #2700 dq_oe <= 0; end
    end
    // early start statistics: ACTIVE commands by origin, CPU half (time0 low) vs video half
    integer n_early = 0, n_rasrd = 0, n_raswr = 0, n_vid = 0;
    always @(posedge clk32) if (sd_ready && dut.gstmcu.time0_s == 1'b1 && sdram.ecs && (sdram.state == 0 || sdram.state == 6)) n_early = n_early + 1;
    reg t_csD = 0; always @(posedge clk32) t_csD <= sdram.cs;
    always @(posedge clk32) if (sd_ready && sdram.state == 0 && sdram.cs && !t_csD && !refresh && !(sdram.ecs)) begin
        if (dut.gstmcu.time0_s == 1'b0) begin if (we_n) n_rasrd = n_rasrd + 1; else n_raswr = n_raswr + 1; end else n_vid = n_vid + 1; end
    // ---- flash_dspi.v cycle model ----
    reg fD = 0, fD2 = 0, busy = 0; reg [5:0] fs = 0; reg [15:0] fw;
    // TODO 9: +fl0=<n> flash start state (8 = flash_dspi continuous read; lower = slower read), missed-edge monitor
    integer fl0 = 8, n_flmiss = 0; initial if ($value$plusargs("fl0=%d", fl0)) ;
    // short rom_n pulses (ROM select that ends before the flash read can finish)
    reg rnq = 1; integer rn_t0 = 0, n_rnshort = 0;
    always @(posedge clk32) begin rnq <= rom_n;
        if (rnq && !rom_n) rn_t0 = $time;
        if (!rnq && rom_n && ($time - rn_t0) < 200000) begin n_rnshort = n_rnshort + 1; if (n_rnshort < 20) $display("%0t SHORT rom_n pulse %0d ns A=%h blt=%b", $time, ($time-rn_t0)/1000, {rom_addr,1'b0}, dut.blitter_has_bus); end
    end
    always @(posedge flclk) begin
        fD <= !rom_n; fD2 <= fD;
        if (fD && !fD2 && !busy) begin busy <= 1; fs <= fl0; end
        if (fD && !fD2 && busy) begin n_flmiss = n_flmiss + 1; if (n_flmiss < 20) $display("%0t FLASH MISSED rom_n edge while busy (fs=%0d) A=%h", $time, fs, {rom_addr,1'b0}); end
        if (busy) begin
            fs <= fs + 1;
            if (fs == 8) fw = rom[rom_addr[17:1]];
            if (fs >= 25 && fs <= 32) rom_dout[15 - 2*(fs-25) -: 2] <= fw[15 - 2*(fs-25) -: 2];
            if (fs == 32) begin fs <= 0; busy <= 0; end
        end
    end

    atarist dut (
        .clk_32(clk32), .clk_cpu(clk_cpu), .clk_cpu_n(clk_cpu_n), .porb(porb), .resb(resb),
        .mono_detect(1'b1), .r(), .g(), .b(), .hsync_n(), .vsync_n(), .de(), .blank_n(),
        .keyboard_matrix_out(), .keyboard_matrix_in(8'hff), .joy0(6'd0), .joy1(5'd0),
        .audio_mix_l(), .audio_mix_r(),
        .sd_lba(), .sd_rd(), .sd_wr(), .sd_ack(1'b0), .sd_buff_addr(9'd0), .sd_dout(8'd0), .sd_din(), .sd_dout_strobe(1'b0),
        .sd_img_mounted(4'd0), .sd_img_size(64'd0),
        .acsi_rd_req(), .acsi_wr_req(), .acsi_sd_lba(), .acsi_sd_done(1'b0), .acsi_sd_busy(1'b0),
        .acsi_sd_rd_byte_strobe(1'b0), .acsi_sd_rd_byte(8'd0), .acsi_sd_wr_byte(), .acsi_sd_byte_addr(9'd0),
        .rtc(12'd0),
        .serial_status(), .serial_tx_available(), .serial_tx_strobe(1'b0), .serial_tx_data(),
        .serial_rx_available(), .serial_rx_strobe(1'b0), .serial_rx_data(8'd0),
        .midi_rx(1'b1), .midi_tx(),
        .parallel_strobe_oe(), .parallel_strobe_in(1'b1), .parallel_strobe_out(), .parallel_data_oe(),
        .parallel_data_in(8'hff), .parallel_data_out(), .parallel_busy(1'b0),
        .ste(1'b1), .enable_extra_ram(1'b0), .blitter_en(1'b1), .floppy_protected(2'b00), .cubase_en(1'b0),
        .ram_early(ram_early), .ram_ras_n(ras_n), .ram_cash_n(cash_n), .ram_casl_n(casl_n), .ram_we_n(we_n), .ram_ref(refresh),
        .ram_addr(ram_a), .ram_data_in(mdout), .ram_data_out(mdin),
        .rom_n(rom_n), .rom_addr(rom_addr), .rom_data_out(rom_dout),
        .leds(), .rom_fetch(), .dbg_cpu_as_n(), .dbg_cpu_halted_n(), .dbg_030(), .dbg_trace(), .dbg_vbase(),
        .ext_io_cs(), .ext_io_a(), .ext_io_rw(), .ext_io_uds_n(), .ext_io_lds_n(), .ext_io_wdata(),
        .ext_io_rdata(16'h0000), .ext_io_dtack(1'b0)
`ifdef TTRAM
        , .tt_en(tt_en), .tt_req(tt_req), .tt_we(tt_we), .tt_la(tt_la), .tt_be(tt_be), .tt_wdata(tt_wdata),
        .tt_ack(tt_ack), .tt_rdata(tt_rdata)
`endif
    );
    GSR GSR (.GSRI(1'b1));
    initial begin #1000; dut.dma.dma_in_progress = 1'b0; dut.dma.fifo_read_in_progress = 1'b0; dut.dma.fifo_write_in_progress = 1'b0; end

    // ---- read data validity check in the bridge ----
    // v[0] = iEdb at S4 en2 (A+312.5, DTACK seen), v[1] A+343.75, v[2] A+375
    // (en1 entering S6), v[3] A+406.25; compared with iEdb at S6 en2 (A+437.5).
    wire b_en1 = dut.cpu030.enPhi1, b_en2 = dut.cpu030.enPhi2;
    wire [2:0] ph = dut.cpu030.phase;
    reg [15:0] v [0:3]; integer vk = 9, j, e;
    integer cnt [0:2][0:4]; integer bad375 [0:2]; integer bshow = 0;
    initial for (j = 0; j < 3; j = j + 1) begin bad375[j] = 0; for (e = 0; e < 5; e = e + 1) cnt[j][e] = 0; end
    wire [23:0] ba = {dut.cpu030.r_adr, 1'b0};
    wire b_rom = (ba[23:20] == 4'he) || (ba[23:16] >= 8'hfc && ba[23:16] <= 8'hfe) || ba[23:3] == 0;
    wire b_ram = !b_rom && ba < 24'h400000;
    wire [1:0] rg = b_ram ? 0 : b_rom ? 1 : 2;
    always @(posedge clk32) begin
        if (vk < 4) begin v[vk] = dut.cpu030.iEdb; vk = vk + 1; end
        if (b_en2 && ph == 3'd3 && !dut.cpu030.DTACKn && !dut.cpu030.r_write) begin v[0] = dut.cpu030.iEdb; vk = 1; end
        if (b_en2 && ph == 3'd4) begin
            if (vk == 4) begin
                e = 4; while (e > 0 && v[e-1] === dut.cpu030.iEdb) e = e - 1;
                cnt[rg][e] = cnt[rg][e] + 1;
                if (e > 2) begin bad375[rg] = bad375[rg] + 1;
                    if (bshow < 12) begin bshow = bshow + 1; $display("%0t late data rg%0d %06x v=%04x %04x %04x %04x final %04x", $time, rg, ba, v[0], v[1], v[2], v[3], dut.cpu030.iEdb); end end
            end
            vk = 9;
        end
    end
`ifdef TTRAM
    // ---- TT cycle trace (+tttrace=file, +ttus=start us): addr fc rw size data at DSACK ----
    integer ttf = 0, ttus = 0, ttn = 0; reg [8*64-1:0] ttfn; reg tto_q = 0; reg [31:0] tta, ttd; reg [2:0] ttfc; reg ttrw; reg [1:0] ttsz;
    initial begin if ($value$plusargs("tttrace=%s", ttfn)) ttf = $fopen(ttfn, "w"); if ($value$plusargs("ttus=%d", ttus)) ; end
    always @(posedge clk32) if (ttf != 0 && $time >= ttus * 64'd1000000) begin
        tto_q <= dut.cpu030.t_open;
        if (dut.cpu030.t_open && !tto_q) begin tta = dut.cpu030.cpu_adr; ttfc = dut.cpu030.cpu_fc; ttrw = dut.cpu030.cpu_rwn; ttsz = dut.cpu030.cpu_size; end
        if (dut.cpu030.t_open && dut.cpu030.cpu_dsackn != 2'b11) ttd = ttrw ? dut.cpu030.cpu_din : dut.cpu030.cpu_dout;
        if (!dut.cpu030.t_open && tto_q && !ttrw && (dut.cpu030.tt_wdata !== ttd)) $display("%0t WDATA RACE a=%08x taken=%08x dout=%08x", $time, tta, dut.cpu030.tt_wdata, ttd);
        if (!dut.cpu030.t_open && tto_q) begin ttn = ttn + 1;
            $fwrite(ttf, "%0d %0d fc%0d %s %08x s%0d %08x\n", ttn, $time/1000, ttfc, ttrw ? "R" : "W", tta, ttsz, ttd);
            if (ttn % 1000 == 0) $fflush(ttf); end
    end
`endif
`ifdef TOSDBG
    initial #1 dut.dma.dma_scnt = 8'd0;   // FPGA power-up value (sim: uninitialised reg)
    reg as30_q = 1'b1;
    always @(posedge clk32) begin
        as30_q <= dut.cpu030.cpu_asn;
        if (as30_q && !dut.cpu030.cpu_asn && dut.cpu030.cpu_adr[31:24] != 8'h00 && dut.cpu030.cpu_adr[31:24] != 8'hFF)
            $display("HI %0t A=%08x fc=%0d rw=%b", $time, dut.cpu030.cpu_adr, dut.cpu030.cpu_fc, dut.cpu030.cpu_rwn);
    end
    reg be_q = 1'b1;
    always @(posedge clk32) begin
        be_q <= dut.cpu030.cpu_berrn;
        if (be_q && !dut.cpu030.cpu_berrn) $display("BERR %0t A=%08x fc=%0d rw=%b", $time, dut.cpu030.cpu_adr, dut.cpu030.cpu_fc, dut.cpu030.cpu_rwn);
    end
    always @(dut.cpu030.cpu_rst_n or dut.cpu030.extReset or dut.cpu030.cpu_reset_out)
        $display("RST %0t rst_n=%b ext=%b reset_out=%b", $time, dut.cpu030.cpu_rst_n, dut.cpu030.extReset, dut.cpu030.cpu_reset_out);
`endif
    // ---- ST bus trace + spacing histogram ----
    wire as_n = dut.cpu_as_n, rw = dut.cpu_rw;
    wire [23:0] a = {dut.cpu_a, 1'b0};
    wire [2:0] fc = {dut.cpu_fc2, dut.cpu_fc1, dut.cpu_fc0};
    reg u, l, as_q = 1; reg [15:0] dq; time t0, tprev = 0; integer n = 0, tf, sp;
    integer hist [0:31]; integer hr [0:31]; initial for (k = 0; k < 32; k = k + 1) begin hist[k] = 0; hr[k] = 0; end
    reg [8*64-1:0] tfn; integer MAXC = 20000;
    initial begin if (!$value$plusargs("trace=%s", tfn)) tfn = "trace.txt"; tf = $fopen(tfn, "w");
                  if ($value$plusargs("maxc=%d", MAXC)) ; end
    reg prev_ram = 0;
    always @(posedge clk32) begin
        as_q <= as_n;
        if (as_q && !as_n) begin
            t0 = $time; u = 0; l = 0;
            sp = (t0 - tprev) / 125000; if (sp > 31) sp = 31;
            if (n > 0) begin hist[sp] = hist[sp] + 1; if (a < 24'h400000 && a[23:3] != 0 && prev_ram) hr[sp] = hr[sp] + 1; end
            prev_ram = (a < 24'h400000 && a[23:3] != 0);
            tprev = t0;
        end
        if (!as_n) begin
            if (!dut.cpu_uds_n) u = 1;
            if (!dut.cpu_lds_n) l = 1;
            dq <= rw ? dut.cpu_din : dut.cpu_dout;
        end
        if (!as_q && as_n) begin
            n = n + 1;
            $fwrite(tf, "%0d %0d fc%0d %s %06x %s%s %04x\n", n, t0/1000, fc, rw ? "R" : "W", a, u ? "U" : "-", l ? "L" : "-", dq);
            if (n % 1000 == 0) $fflush(tf);
            if (n == MAXC) report;
        end
    end
    // ---- 030 request -> ST S0 latency and 030 AS-negate -> next 030 AS gap (31.25 ns units) ----
    integer hlat [0:31]; integer hgap [0:31]; time t_as30 = 0, t_neg30 = 0; reg asn30_q = 1; reg req_open = 0; integer q;
    initial for (k = 0; k < 32; k = k + 1) begin hlat[k] = 0; hgap[k] = 0; end
    always @(posedge clk32) begin
        asn30_q <= dut.cpu030.cpu_asn;
        if (asn30_q && !dut.cpu030.cpu_asn) begin t_as30 = $time; req_open = 1;
            if (t_neg30 != 0) begin q = ($time - t_neg30) / 31250; if (q > 31) q = 31; hgap[q] = hgap[q] + 1; end end
        if (!asn30_q && dut.cpu030.cpu_asn) t_neg30 = $time;
    end
    // S0 entry: bridge phase becomes P_S0 (value of the localparam)
    reg [2:0] ph_q = 0;
    always @(posedge clk32) begin
        ph_q <= ph;
        if (req_open && ph == 3'd1 && ph_q != 3'd1) begin
            q = ($time - t_as30) / 31250; if (q > 31) q = 31; hlat[q] = hlat[q] + 1; req_open = 0; end
    end
    // back-to-back 030 requests (030 AS reasserted <= 2 clk32 after it negated): ST idle time between
    // the previous ST AS negation and the new S0, and the ST AS->AS spacing of the pair
    integer hbi [0:31]; integer hbs [0:31]; integer last_gap = 99, bb = 0; time t_stneg = 0, t_stfall = 0; reg stas_q = 1;
    initial for (k = 0; k < 32; k = k + 1) begin hbi[k] = 0; hbs[k] = 0; end
    always @(posedge clk32) begin
        stas_q <= dut.cpu_as_n;
        if (asn30_q && !dut.cpu030.cpu_asn) last_gap = (t_neg30 != 0) ? ($time - t_neg30) / 31250 : 99;
        if (!stas_q && dut.cpu_as_n) t_stneg = $time;
        if (ph == 3'd1 && ph_q != 3'd1) begin bb = (last_gap <= 2);
            if (bb) begin q = ($time - t_stneg) / 31250; if (q > 31) q = 31; hbi[q] = hbi[q] + 1; end end
        if (stas_q && !dut.cpu_as_n) begin if (bb && t_stfall != 0) begin q = ($time - t_stfall) / 125000; if (q > 31) q = 31; hbs[q] = hbs[q] + 1; end t_stfall = $time; end
    end
    task report; begin
        $display("%0d ST cycles at %0t ns", n, $time/1000);
        for (j = 0; j < 3; j = j + 1) $display("%s reads: data valid from A+312:%0d A+344:%0d A+375:%0d A+406:%0d A+437:%0d  (late for A+375: %0d)",
            j == 0 ? "RAM" : j == 1 ? "ROM" : "IO ", cnt[j][0], cnt[j][1], cnt[j][2], cnt[j][3], cnt[j][4], bad375[j]);
        $display("SDRAM ACTIVE: early (CPU/DMA read) %0d, at RAS in the CPU half: reads %0d writes %0d, video half %0d", n_early, n_rasrd, n_raswr, n_vid);
        $write("030 AS -> ST S0 (31.25ns units):"); for (k = 0; k < 32; k = k + 1) if (hlat[k]) $write(" %0d:%0d", k, hlat[k]); $display("");
        $write("030 AS negate -> next 030 AS (31.25ns units):"); for (k = 0; k < 32; k = k + 1) if (hgap[k]) $write(" %0d:%0d", k, hgap[k]); $display("");
        $write("back-to-back: ST AS negate -> next S0 (31.25ns units):"); for (k = 0; k < 32; k = k + 1) if (hbi[k]) $write(" %0d:%0d", k, hbi[k]); $display("");
        $write("back-to-back: ST AS->AS spacing (125ns units):"); for (k = 0; k < 32; k = k + 1) if (hbs[k]) $write(" %0d:%0d", k, hbs[k]); $display("");
        $write("AS->AS spacing (125ns units) all:");  for (k = 2; k < 32; k = k + 1) if (hist[k]) $write(" %0d:%0d", k, hist[k]); $display("");
        $write("AS->AS spacing RAM->RAM:");          for (k = 2; k < 32; k = k + 1) if (hr[k]) $write(" %0d:%0d", k, hr[k]); $display("");
`ifdef TTRAM
        $display("TTRAM: tt_en=%0d, TT ACTIVE commands %0d, SDRAM data bus clashes %0d, TT bus cycles: program %0d data %0d", tten, n_ttact, n_clash, n_ttprog, n_ttdata);
        $write("TT0:"); for (k = 0; k < 24; k = k + 1) $write(" %04x", ttm[k]); $display("");
        $write("ST0:"); for (k = 16'h8000; k < 16'h8000+24; k = k + 1) $write(" %04x", ram[k]); $display("");
        $write("TT cycle AS->AS negate (clk32):"); for (k = 0; k < 32; k = k + 1) if (htt[k]) $write(" %0d:%0d", k, htt[k]);
        if (tt_n) $display("  avg %0d.%02d", tt_sum / tt_n, (tt_sum * 100 / tt_n) % 100); else $display("");
        $write("TTDIFF:"); for (k = 0; k < 160; k = k + 1) if (ttm[k] !== ram[16'h8000+k]) $write(" %0d:%04x/%04x", k, ttm[k], ram[16'h8000+k]); $display("");
        $write("R1300:"); for (k = 16'h1300>>1; k < 16'h1370>>1; k = k + 1) $write(" %04x", ram[k]); $display(" V=%04x%04x", ram[16'h1ff8>>1], ram[16'h1ffa>>1]);
`endif
        $display("FLASH: missed edges %0d, short rom_n pulses %0d", n_flmiss, n_rnshort);
        if ($test$plusargs("ramdump")) $writememh("ram_dump.hex", ram, 0, 24'h1ffff);
        $fclose(tf); $finish;
    end endtask
    // bus test ROM: done marker at $1FFC, results at $1000/$1100/$1200
    integer w;
    always @(posedge clk32) if ((ram[16'h1ffc>>1] == 16'h600d && ram[16'h1ffe>>1] == 16'hc0de) || (ram[16'h1ffc>>1] == 16'hbadb && ram[16'h1ffe>>1] == 16'had00)) begin
        $write("R1000:"); for (w = 16'h1000>>1; w < 16'h1020>>1; w = w + 1) $write(" %04x", ram[w]); $display("");
        $write("R1100:"); for (w = 16'h1100>>1; w < 16'h1118>>1; w = w + 1) $write(" %04x", ram[w]); $display("");
        $write("R1200:"); for (w = 16'h1200>>1; w < 16'h1214>>1; w = w + 1) $write(" %04x", ram[w]); $display("");
        report;
    end
    // event probe: +pf=<ns> +pt=<ns>
    integer pf = 0, pt = 0; initial begin if ($value$plusargs("pf=%d", pf)) ; if ($value$plusargs("pt=%d", pt)) ; end
    always @(dut.cpu030.cpu_asn or dut.cpu030.cpu_dsackn or ph or dut.cpu_as_n or dut.cpu030.s_dsack or dut.cpu030.c_open or dut.cpu030.cpu_rwn)
        if ($time/1000 >= pf && $time/1000 < pt)
            $display("%0d.%03d asn030=%b rw030=%b dsack=%b s_dsack=%b open=%b ph=%0d stAS=%b en1=%b en2=%b clkcpu=%b a030=%h", $time/1000, $time%1000,
                     dut.cpu030.cpu_asn, dut.cpu030.cpu_rwn, dut.cpu030.cpu_dsackn, dut.cpu030.s_dsack, dut.cpu030.c_open, ph, dut.cpu_as_n,
                     dut.cpu030.enPhi1, dut.cpu030.enPhi2, clk_cpu, dut.cpu030.cpu_adr[23:0]);
    // TODO 9 arbitration monitor: +mf=<ns> +mt=<ns>
    integer mf = 0, mt = 0; initial begin if ($value$plusargs("mf=%d", mf)) ; if ($value$plusargs("mt=%d", mt)) ; end
    always @(dut.cpu030.arb or dut.cpu030.BRi or dut.cpu030.BgackI or dut.cpu030.BGn or dut.cpu030.phase or dut.cpu030.rmc_lock
             or dut.stBlitter.bltBusCtrl.dmaState or dut.stBlitter.bltBusCtrl.busOwned or dut.stBlitter.busy or dut.cpu030.cpu_asn
             or dut.cpu030.cpu_rmcn or dut.cpu030.pending or dut.as_n or dut.stBlitter.bltControl.bltActive)
        if ($time/1000 >= mf && $time/1000 < mt)
            $display("%0d ARB arb=%0d BRi=%b BgI=%b BGn=%b ph=%0d rmc=%b/%b pend=%b asn030=%b a030=%h | blt dma=%0d own=%b act=%b busy=%b stAS=%b",
                $time/1000, dut.cpu030.arb, dut.cpu030.BRi, dut.cpu030.BgackI, dut.cpu030.BGn, dut.cpu030.phase, dut.cpu030.rmc_lock, dut.cpu030.cpu_rmcn,
                dut.cpu030.pending, dut.cpu030.cpu_asn, dut.cpu030.cpu_adr[23:0], dut.stBlitter.bltBusCtrl.dmaState, dut.stBlitter.bltBusCtrl.busOwned,
                dut.stBlitter.bltControl.bltActive, dut.stBlitter.busy, dut.as_n);
    // blitter/IRQ monitor (blitter shared-mode diagnosis): MFP INT, IACKs, blitter bus ownership
    integer nmfp = 0, nown = 0; reg mfpq = 1, ownq = 0;
    always @(posedge clk32) begin
        mfpq <= dut.mfpint_n; ownq <= dut.blitter_has_bus;
        if (mfpq && !dut.mfpint_n) begin nmfp = nmfp + 1; if (nmfp < 4) $display("%0t MFP INT", $time); end
        if (!ownq && dut.blitter_has_bus) begin nown = nown + 1; if (nown < 40) $display("%0t BLT own #%0d", $time, nown); end
        if (ownq && !dut.blitter_has_bus && nown < 40) $display("%0t BLT release", $time);
    end
    reg tdq = 0; integer ntd = 0;
    always @(posedge clk32) begin tdq <= dut.mfp.timera_done; if (dut.mfp.timera_done && !tdq) begin ntd = ntd + 1; if (ntd < 4) $display("%0t TA done ier=%h imr=%h ipr=%h ctrl=%h", $time, dut.mfp.ier, dut.mfp.imr, dut.mfp.ipr, dut.mfp.timera_ctrl_o); end end
    initial begin #600000000; $display("MFP@600us ctrl=%h dat=%h ier=%h imr=%h ipr=%h rst=%b xclk=%0d", dut.mfp.timera_ctrl_o, dut.mfp.timera_dat_o, dut.mfp.ier, dut.mfp.imr, dut.mfp.ipr, dut.mfp.reset, 0); end
    integer maxus = 30000;
    initial begin if ($value$plusargs("maxus=%d", maxus)) ; #(maxus * 1000000.0); $display("TIMEOUT"); report; end
endmodule
