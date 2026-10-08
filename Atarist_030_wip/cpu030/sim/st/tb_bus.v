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
    sdram sdram (.clk(clk32), .reset_n(porb), .ready(sd_ready),
        .sd_clk(sd_clk), .sd_cke(sd_cke), .sd_data(sd_dq), .sd_addr(sd_a), .sd_dqm(sd_dqm), .sd_ba(sd_ba),
        .sd_cs(sd_cs), .sd_we(sd_we), .sd_ras(sd_ras), .sd_cas(sd_cas),
        .refresh(refresh), .din(mdout), .dout(sd_dout), .addr(ram_a[22:1]), .ds({cash_n, casl_n}),
        .cs(!ras_n && !ram_a[23]), .ecs(ram_early_en & ram_early && !ram_a[23]), .we(!we_n));
    integer early_en = 1; initial if ($value$plusargs("early=%d", early_en)) ;
    wire ram_early_en = (early_en != 0);
    always @* mdin = sd_dout;
    // chip: commands sampled on the sd_clk rising edge (= clk32 falling edge), CL2,
    // tAC 5.4 ns, tOH 2.7 ns; READ/WRITE with A10 = auto precharge; memory = ram[]
    reg [12:0] sd_row; reg [1:0] rdq = 0; reg [20:0] ra0, ra1; reg [15:0] dq_o; reg dq_oe = 0;
    assign sd_dq[15:0] = dq_oe ? dq_o : 16'hzzzz;
    always @(posedge sd_clk) begin
        rdq <= {rdq[0], ({sd_ras, sd_cas, sd_we} == 3'b101)};
        ra1 <= ra0;
        if ({sd_ras, sd_cas, sd_we} == 3'b011) sd_row <= sd_a;
        if ({sd_ras, sd_cas, sd_we} == 3'b101) ra0 <= {sd_row[11:0], sd_a[8:0]};
        if ({sd_ras, sd_cas, sd_we} == 3'b100) begin
            if (!sd_dqm[1]) ram[{sd_row[11:0], sd_a[8:0]}][15:8] <= sd_dq[15:8];
            if (!sd_dqm[0]) ram[{sd_row[11:0], sd_a[8:0]}][7:0]  <= sd_dq[7:0];
        end
        if (rdq[1]) begin #2700 dq_oe <= 0; #2700 dq_o <= ram[ra1]; dq_oe <= 1; end
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
    always @(posedge flclk) begin
        fD <= !rom_n; fD2 <= fD;
        if (fD && !fD2 && !busy) begin busy <= 1; fs <= 8; end
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
    task report; begin
        $display("%0d ST cycles at %0t ns", n, $time/1000);
        for (j = 0; j < 3; j = j + 1) $display("%s reads: data valid from A+312:%0d A+344:%0d A+375:%0d A+406:%0d A+437:%0d  (late for A+375: %0d)",
            j == 0 ? "RAM" : j == 1 ? "ROM" : "IO ", cnt[j][0], cnt[j][1], cnt[j][2], cnt[j][3], cnt[j][4], bad375[j]);
        $display("SDRAM ACTIVE: early (CPU/DMA read) %0d, at RAS in the CPU half: reads %0d writes %0d, video half %0d", n_early, n_rasrd, n_raswr, n_vid);
        $write("030 AS -> ST S0 (31.25ns units):"); for (k = 0; k < 32; k = k + 1) if (hlat[k]) $write(" %0d:%0d", k, hlat[k]); $display("");
        $write("030 AS negate -> next 030 AS (31.25ns units):"); for (k = 0; k < 32; k = k + 1) if (hgap[k]) $write(" %0d:%0d", k, hgap[k]); $display("");
        $write("AS->AS spacing (125ns units) all:");  for (k = 2; k < 32; k = k + 1) if (hist[k]) $write(" %0d:%0d", k, hist[k]); $display("");
        $write("AS->AS spacing RAM->RAM:");          for (k = 2; k < 32; k = k + 1) if (hr[k]) $write(" %0d:%0d", k, hr[k]); $display("");
        $fclose(tf); $finish;
    end endtask
    // bus test ROM: done marker at $1FFC, results at $1000/$1100/$1200
    integer w;
    always @(posedge clk32) if (ram[16'h1ffc>>1] == 16'h600d && ram[16'h1ffe>>1] == 16'hc0de) begin
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
    integer maxus = 30000;
    initial begin if ($value$plusargs("maxus=%d", maxus)) ; #(maxus * 1000000.0); $display("TIMEOUT"); report; end
endmodule
