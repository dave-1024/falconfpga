`timescale 1ps/1ps
// Unit bench: cpu030_st_bridge + WF68K30L (Gowin post-synthesis netlist)
// against a behavioural ST bus (GSTMCU-like DTACK/VPA/BERR, ACIA E cycle,
// MFP vectored IACK, VBL autovector, a DMA master doing BR/BG/BGACK).
module tb;
    parameter integer CPU_PHASE_PS = 0;      // clk_cpu phase offset against clk32
    parameter integer MAX_US = 400;

    reg clk32 = 0, clk_cpu = 0;
    always #15625 clk32 = ~clk32;            // 32 MHz
    integer phase_ps = CPU_PHASE_PS;
    initial begin if ($value$plusargs("phase=%d", phase_ps)) ; #(phase_ps); forever #62500 clk_cpu = ~clk_cpu; end  // 8 MHz

    // en1/en2 like clockgen: one each per 4 clk32
    reg [1:0] cc = 0;
    always @(posedge clk32) cc <= cc + 1;
    wire en1 = (cc == 2'd0), en2 = (cc == 2'd2);

    reg pwrup = 1, reset = 1;
    initial begin
        repeat (8) @(posedge clk32); pwrup = 0;
        repeat (127) @(posedge clk32); reset = 0;
    end

    wire rw, as_n, lds_n, uds_n, E, vma_n, fc0, fc1, fc2, bg_n, rst_o_n, halted_n;
    wire [15:0] dout; wire [23:1] a;
    reg  dtack_n = 1, vpa_n = 1, berr_n = 1, br_n = 1, bgack_n = 1;
    reg  [2:0] ipl = 3'b111;
    reg  [15:0] din;

    cpu030_st_bridge dut (
        .clk(clk32), .clk_cpu(clk_cpu), .extReset(reset), .pwrUp(pwrup),
        .enPhi1(en1), .enPhi2(en2),
        .eRWn(rw), .ASn(as_n), .LDSn(lds_n), .UDSn(uds_n), .E(E), .VMAn(vma_n),
        .FC0(fc0), .FC1(fc1), .FC2(fc2), .BGn(bg_n), .oRESETn(rst_o_n), .oHALTEDn(halted_n),
        .DTACKn(dtack_n), .VPAn(vpa_n), .BERRn(berr_n), .HALTn(1'b1), .BRn(br_n), .BGACKn(bgack_n),
        .IPL0n(ipl[0]), .IPL1n(ipl[1]), .IPL2n(ipl[2]),
        .iEdb(din), .oEdb(dout), .eab(a));

    // ---------------- memory ----------------
    reg [15:0] rom [0:32767];     // $FC0000..$FCFFFF
    reg [15:0] ram [0:32767];     // $000000..$00FFFF
    integer i;
    initial begin
        for (i = 0; i < 32768; i = i + 1) begin rom[i] = 16'hffff; ram[i] = 16'h0000; end
        $readmemh("prog.hex", rom);
    end
    wire [23:0] addr = {a, 1'b0};
    wire [2:0] fc = {fc2, fc1, fc0};
    wire iack   = (fc == 3'b111);
    wire is_rom = !iack && (addr[23:16] == 8'hfc || addr[23:3] == 21'd0);
    wire is_ram = !iack && !is_rom && addr[23:16] == 8'h00;
    wire is_acia= !iack && addr[23:9] == (24'hfffc00 >> 9);
    wire is_mfp = !iack && addr[23:6] == (24'hfffa00 >> 6);
    wire iack_mfp = iack && a[3:1] == 3'd6;
    wire iack_av  = iack && (a[3:1] == 3'd4 || a[3:1] == 3'd2);

    reg [7:0] acia_wdata = 0; integer acia_writes = 0, acia_reads = 0;
    integer ascnt = 0, berrcnt = 0;
    always @(posedge clk32) begin
        if (as_n) begin
            ascnt <= 0; berrcnt <= 0; dtack_n <= 1; vpa_n <= 1; berr_n <= 1;
        end else begin
            ascnt <= ascnt + 1;
            if (is_ram && ascnt == 2) dtack_n <= 0;          // fast RAM
            if (is_rom && ascnt == 6) dtack_n <= 0;          // ROM with wait states
            if ((is_mfp || iack_mfp) && ascnt == 10) dtack_n <= 0;
            if (is_acia || iack_av) vpa_n <= 0;
            if (!(is_ram||is_rom||is_mfp||iack_mfp||is_acia||iack_av) && en1) berrcnt <= berrcnt + 1;
            if (berrcnt == 64) berr_n <= 0;                   // GSTMCU bus timeout
            // RAM writes on DS
            if (is_ram && !rw) begin
                if (!uds_n) ram[addr[15:1]][15:8] <= dout[15:8];
                if (!lds_n) ram[addr[15:1]][7:0]  <= dout[7:0];
            end
        end
    end
    always @* begin
        din = 16'hffff;
        if (!as_n && rw) begin
            if (is_rom) din = rom[addr[15:1]];
            else if (is_ram) din = ram[addr[15:1]];
            else if (is_acia) din = {8'h02, 8'hff};
            else if (iack_mfp) din = {8'hff, 8'h46};
        end
    end
    // ACIA access: VMA low while E is high (E falls at the same clk32 edge as AS rises)
    reg acia_counted = 0;
    always @(posedge clk32) begin
        if (as_n) acia_counted <= 0;
        else if (E && !vma_n && is_acia && !acia_counted) begin
            acia_counted <= 1;
            if (rw) acia_reads = acia_reads + 1;
            else begin acia_writes = acia_writes + 1; acia_wdata = dout[15:8]; end
        end
    end

    // ---------------- interrupts ----------------
    integer iack_av_seen = 0, iack_mfp_seen = 0;
    reg irq_armed = 0;
    always @(posedge clk32) begin
        if (!irq_armed && ram[16'h3400 >> 1][15:8] == 8'h01) begin
            irq_armed <= 1;
            ipl <= 3'b011;   // level 4 (VBL, autovector)
            $display("%t bench: IPL 4 raised", $time);
        end
    end
    reg as_q = 1;
    reg [15:0] din_q;
    always @(posedge clk32) if (!as_n) din_q <= din;
    always @(posedge clk32) begin
        as_q <= as_n;
        if (as_q && !as_n && iack) begin
            if (iack_av) begin iack_av_seen = iack_av_seen + 1; ipl <= 3'b001; // then level 6 (MFP)
                $display("%t bench: IACK level %0d (autovector/VPA), raising IPL 6", $time, a[3:1]); end
            if (iack_mfp) begin iack_mfp_seen = iack_mfp_seen + 1; ipl <= 3'b111;
                $display("%t bench: IACK level 6 (MFP vector $46)", $time); end
        end
    end

    // ---------------- DMA master (BR/BG/BGACK) ----------------
    integer bus_cycles = 0, dma_done = 0, as_during_bgack = 0;
    always @(posedge clk32) if (as_q && !as_n) bus_cycles = bus_cycles + 1;
    initial begin
        wait (bus_cycles == 30);
        @(posedge clk32); br_n = 0;
        $display("%t bench: DMA BR asserted (CPU active)", $time);
        wait (!bg_n);
        $display("%t bench: BG received", $time);
        wait (as_n && dtack_n);
        @(posedge clk32); bgack_n = 0; br_n = 1;
        $display("%t bench: BGACK asserted, bus taken", $time);
        repeat (200) @(posedge clk32);
        bgack_n = 1; dma_done = 1;
        $display("%t bench: BGACK released", $time);
    end
    always @(posedge clk32) if (!bgack_n && !as_n) as_during_bgack = as_during_bgack + 1;

    // ---------------- trace ----------------
    integer tf, ncyc = 0;
    time t_as;
    reg [8*64-1:0] tfn;
    initial begin if (!$value$plusargs("trace=%s", tfn)) tfn = "trace_unit.txt"; tf = $fopen(tfn, "w"); end
    reg uds_seen, lds_seen, vma_seen, berr_seen, dtack_seen;
    always @(negedge as_n) begin t_as = $time; uds_seen = 0; lds_seen = 0; vma_seen = 0; berr_seen = 0; end
    always @(posedge clk32) if (!as_n) begin
        if (!uds_n) uds_seen = 1; if (!lds_n) lds_seen = 1; if (!vma_n) vma_seen = 1; if (!berr_n) berr_seen = 1;
    end
    always @(posedge as_n) begin
        ncyc = ncyc + 1;
        $fwrite(tf, "%0d %t fc=%0d %s a=%06x %s%s d=%04x len=%0dns%s%s\n", ncyc, t_as, fc, rw ? "R" : "W",
                addr, uds_seen ? "U" : "-", lds_seen ? "L" : "-", rw ? din_q : dout, ($time - t_as)/1000,
                vma_seen ? " VMA" : "", berr_seen ? " BERR" : "");
    end
    // RW/strobe sanity: AS must never be low while BGACK low
    initial begin
        #(MAX_US * 1000000);
        $display("TIMEOUT");
        finish_check;
    end
    always @(posedge clk32) if (ram[16'h3300>>1] == 16'h600d && ram[16'h3302>>1] == 16'hc0de) begin
        repeat (10) @(posedge clk32);
        finish_check;
    end

    task chk(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got === exp) $display("PASS %0s = %08x", name, got);
            else begin $display("FAIL %0s = %08x expected %08x", name, got, exp); errors = errors + 1; end
        end
    endtask
    integer errors = 0;
    task finish_check;
        begin
            $display("---- results at %t, %0d ST bus cycles ----", $time, ncyc);
            chk("RAM $2000 long", {ram[16'h1000], ram[16'h1001]}, 32'h12345678);
            chk("RAM $2004 word", ram[16'h1002], 16'habcd);
            chk("RAM $2006 bytes", ram[16'h1003], 16'h1122);
            chk("RAM $2008 (misaligned long)", {ram[16'h1004], ram[16'h1005]}, 32'h00a5a55a);
            chk("RAM $200c", ram[16'h1006], 16'h5a00);
            chk("d1 long read", {ram[16'h1802], ram[16'h1803]}, 32'h12345678);
            chk("d2 word read", {ram[16'h1804], ram[16'h1805]}, 32'h0000abcd);
            chk("d3 even byte read", {ram[16'h1806], ram[16'h1807]}, 32'h00000011);
            chk("d4 odd byte read", {ram[16'h1808], ram[16'h1809]}, 32'h00000022);
            chk("d5 misaligned long read", {ram[16'h180a], ram[16'h180b]}, 32'ha5a55a5a);
            chk("d6 ROM word read", {ram[16'h180c], ram[16'h180d]}, 32'h00000000);
            chk("ACIA status via VPA", ram[16'h3100>>1][15:8], 8'h02);
            chk("ACIA E-cycle reads", acia_reads, 1);
            chk("ACIA E-cycle writes", acia_writes, 1);
            chk("ACIA write data", acia_wdata, 8'h96);
            chk("BERR handler ran", ram[16'h3104>>1][15:8], 8'h01);
            chk("BERR frame fmt/vector", ram[16'h3106>>1] & 16'h0fff, 16'h0008);
            chk("autovector IACK seen", iack_av_seen, 1);
            chk("MFP IACK seen", iack_mfp_seen, 1);
            chk("VBL handler (autovector)", ram[16'h3200>>1][7:0], 8'h01);
            chk("MFP handler (vector $46)", ram[16'h3202>>1][15:8], 8'h01);
            chk("DMA grant done", dma_done, 1);
            chk("CPU AS during BGACK", as_during_bgack, 0);
            chk("done marker", {ram[16'h3300>>1], ram[16'h3302>>1]}, 32'h600dc0de);
            $display("ERRORS=%0d", errors);
            $fclose(tf);
            $finish;
        end
    endtask
endmodule
