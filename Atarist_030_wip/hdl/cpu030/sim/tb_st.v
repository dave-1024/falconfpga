`timescale 1ps/1ps
// Whole ST core (atarist.v) from reset with EmuTOS 192k in ROM
// (+rom=<hex> for another 192k image, +maxus=<n> for the time limit).
// Logs the CPU's ST bus cycles (as the GSTMCU sees them).
module tb_st;
    parameter integer MAX_CYC = 3000;
    parameter integer CPU_PHASE_PS = 15625;  // clk_cpu edges on clk32 rising edges, like the PLL
    reg clk32 = 0, clk_cpu = 0;
    always #15625 clk32 = ~clk32;
    parameter integer CPU_HALF_PS = 31250;   // 16 MHz clk_cpu (atarist.v: bridge CPU_DIV 2)
    initial begin #(CPU_PHASE_PS); forever #(CPU_HALF_PS) clk_cpu = ~clk_cpu; end
    wire clk_cpu_n = ~clk_cpu;               // the PLL's 180 degree copy (CLKOUT6)

    reg porb = 0, resb = 0;
    initial begin
        repeat (20) @(posedge clk32); porb = 1;
        repeat (200) @(posedge clk32); resb = 1;
    end

    wire ras_n, cash_n, casl_n, we_n, refresh, rom_n;
    wire [23:1] ram_a, rom_addr;
    wire [15:0] mdout;
    reg  [15:0] mdin = 16'h0000, rom_dout = 16'hffff;

    reg [15:0] rom [0:98303];
    reg [15:0] ram [0:(1<<21)-1];   // 4 MB
    integer k; reg [8*128-1:0] romfn;
    initial begin
        if ($value$plusargs("rom=%s", romfn)) $readmemh(romfn, rom); else $readmemh("etos192uk.hex", rom);
        for (k = 0; k < (1<<21); k = k + 1) ram[k] = 16'h0000;
    end
    always @(posedge clk32) begin
        rom_dout <= (rom_addr[17:1] < 98304) ? rom[rom_addr[17:1]] : 16'hffff;
        if (!ras_n && !ram_a[23]) begin
            if (!we_n) begin
                if (!cash_n) ram[ram_a[22:1]][15:8] <= mdout[15:8];
                if (!casl_n) ram[ram_a[22:1]][7:0]  <= mdout[7:0];
            end
            mdin <= ram[ram_a[22:1]];
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
        .ste(1'b0), .enable_extra_ram(1'b0), .blitter_en(1'b0), .floppy_protected(2'b00), .cubase_en(1'b0),
        .ram_ras_n(ras_n), .ram_cash_n(cash_n), .ram_casl_n(casl_n), .ram_we_n(we_n), .ram_ref(refresh),
        .ram_addr(ram_a), .ram_data_in(mdout), .ram_data_out(mdin),
        .rom_n(rom_n), .rom_addr(rom_addr), .rom_data_out(rom_dout),
        .leds()
    );

    GSR GSR (.GSRI(1'b1));
    // SIMINIT: registers without reset that the FPGA powers up as 0
    initial begin #1000; dut.dma.dma_in_progress = 1'b0; dut.dma.fifo_read_in_progress = 1'b0; dut.dma.fifo_write_in_progress = 1'b0; end
    // ---- CPU bus trace ----
    wire as_n = dut.cpu_as_n, rw = dut.cpu_rw;
    wire [23:0] a = {dut.cpu_a, 1'b0};
    wire [2:0] fc = {dut.cpu_fc2, dut.cpu_fc1, dut.cpu_fc0};
    reg u, l, as_q = 1; reg [15:0] dq; time t0; integer n = 0, tf;
    reg [8*64-1:0] tfn;
    initial begin if (!$value$plusargs("trace=%s", tfn)) tfn = "trace_st.txt"; tf = $fopen(tfn, "w"); end
    always @(posedge clk32) begin
        as_q <= as_n;
        if (as_q && !as_n) begin t0 = $time; u = 0; l = 0; end
        if (!as_n) begin
            if (!dut.cpu_uds_n) u = 1;
            if (!dut.cpu_lds_n) l = 1;
            dq <= rw ? dut.cpu_din : dut.cpu_dout;
        end
        if (!as_q && as_n) begin
            n = n + 1;
            $fwrite(tf, "%0d %0d fc%0d %s %06x %s%s %04x\n", n, t0/1000, fc, rw ? "R" : "W", a,
                    u ? "U" : "-", l ? "L" : "-", dq);
            if (n % 100 == 0) $fflush(tf);
            if (n == MAX_CYC) begin
                $display("%0d CPU bus cycles at %0t ns", n, $time/1000);
                $fclose(tf); $finish;
            end
        end
    end
    always #(200_000_000) $display("t=%0d us, %0d cycles, porb=%b resb=%b reset=%b rstn=%b asn=%b open=%b ph=%0d clkcpu=%b pend=%b BRi=%b BGACKi=%b arb=%0d br=%b bgack=%b en1=%b", $time/1000000, n, porb, resb, dut.reset, dut.cpu030.cpu_rst_n, dut.cpu030.cpu_asn, dut.cpu030.c_open, dut.cpu030.phase, dut.clk_cpu, dut.cpu030.pending, dut.cpu030.BRi, dut.cpu030.BgackI, dut.cpu030.arb, dut.cpu030.BRn, dut.cpu030.BGACKn, en1_seen); reg en1_seen = 0; always @(posedge clk32) if (dut.mhz8_en1) en1_seen <= 1;
    integer maxus = 40000;
    initial begin if ($value$plusargs("maxus=%d", maxus)) ; #(maxus * 1000000.0); $display("TIMEOUT after %0d cycles", n); $fclose(tf); $finish; end
endmodule
