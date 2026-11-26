// tb_ikbd_real.v - FAL_01: keyboard ACIA ($FFFC00/$FFFC02) through falcon_bus + falcon_io +
// falcon_pbus to the ST core's acia.v + ikbd.sv (HD63701, ikbd.hex ROM), as falcon_soc wires it.
// Checks: TDRE after reset, master reset $03 / $96, $80 $01 -> $F1, IRQ + GPIP4 (active low),
// RDR read clears RDRF/IRQ, a matrix key press gives a make code, mouse quadrature gives a packet.
// Run: iverilog -g2012 -I <hd63701> ... (see run_ikbd_real.sh); needs ikbd.hex in the cwd.
`timescale 1ns/1ps
module tb_ikbd_real;
    reg clk32 = 1'b0;
    always #15.625 clk32 = ~clk32;          // 32 MHz
    reg clk = 1'b0;                         // 16 MHz, phase-locked (rises with clk32)
    always @(posedge clk32) clk <= ~clk;

    reg reset = 1'b1;
    reg        cpu_as_n = 1'b1, cpu_ds_n = 1'b1, cpu_rw = 1'b1;
    reg [31:0] cpu_a = 32'd0, cpu_dout = 32'd0;
    reg [1:0]  cpu_siz = 2'b01;
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
    wire [15:0] io_wdata, io_rdata, p_rdata;
    wire        sel_mfp, sel_acia, sel_dma, p_done;
    wire        io_ext = sel_mfp || sel_acia || sel_dma;

    falcon_bus u_bus (
        .clk(clk), .reset(reset),
        .cpu_a(cpu_a), .cpu_dout(cpu_dout), .cpu_din(cpu_din),
        .cpu_as_n(cpu_as_n), .cpu_ds_n(cpu_ds_n),
        .cpu_rw(cpu_rw), .cpu_siz(cpu_siz), .cpu_fc(cpu_fc),
        .cpu_dsack_n(cpu_dsack_n), .cpu_berr_n(cpu_berr_n), .cpu_avec_n(cpu_avec_n),
        .mem_req(mem_req), .mem_a(mem_a), .mem_we(mem_we), .mem_be(mem_be),
        .mem_wdata(mem_wdata), .mem_ack(1'b0), .mem_rdata(16'h0000),
        .io_cyc(io_cyc), .io_a(io_a), .io_uds(io_uds), .io_lds(io_lds),
        .io_rw(io_rw), .io_wr(io_wr), .io_wdata(io_wdata),
        .io_rdata(io_ext ? p_rdata : io_rdata), .io_ext(io_ext), .io_done(p_done),
        .iack_mfp(), .mfp_vector(8'h00), .mfp_dtack(1'b0),
        .br_want(1'b0), .bus_grant(), .cyc_tog()
    );
    falcon_io #(.MONITOR(2'b10), .MEMCODE(3'd5)) u_io (
        .clk(clk), .reset(reset), .cyc(io_cyc), .a(io_a),
        .uds(io_uds), .lds(io_lds), .wr(io_wr), .din(io_wdata), .dout(io_rdata),
        .sel_videl(), .sel_nvram_a(), .sel_nvram_d(), .sel_ym(),
        .sel_mfp(sel_mfp), .sel_acia(sel_acia), .sel_dma(sel_dma),
        .videl_d(16'h0000), .nvram_d(8'h00), .ym_d(8'h00),
        .mfp_d(8'hFF), .acia_d(8'hFF), .dma_d(16'hFFFF), .fdc_hd()
    );

    wire mfp_cs, mfp_ds_n, acia_cs, dma_cs, acia_E;
    wire [7:0] acia_d, kbd_acia_d, midi_acia_d;
    falcon_pbus #(.MFP_CLK(24), .DMA_CLK(16)) pbus (
        .clk_32(clk32), .reset(reset),
        .sel_mfp(sel_mfp), .sel_acia(sel_acia), .sel_dma(sel_dma && !io_a[3]), .sel_addr(sel_dma && io_a[3]),
        .mfp_d(8'hFF), .acia_d(acia_d), .dma_d(16'hFFFF),
        .mfp_cs(mfp_cs), .mfp_ds_n(mfp_ds_n), .acia_cs(acia_cs), .dma_cs(dma_cs),
        .E(acia_E), .rdata(p_rdata), .done(p_done)
    );
    wire [15:1] p_a = io_a;
    wire kbd_acia_irq, midi_acia_irq, ikbd_tx, ikbd_rx;
    wire acia_irq = kbd_acia_irq | midi_acia_irq;
    wire gpip4 = !acia_irq;                   // MFP GPIP4 pin, active low
    assign acia_d = p_a[2] ? midi_acia_d : kbd_acia_d;

    wire [14:0] mout;
    reg  [3:0]  key_row = 4'hF;              // pressed key: matrix_out row, matrix_in column
    reg  [2:0]  key_col = 3'd0;
    reg         key_dn  = 1'b0;
    wire [7:0]  min = (key_dn && !mout[key_row]) ? ~(8'd1 << key_col) : 8'hFF;
    reg  [5:0]  joy0 = 6'd0;                 // {rb, lb, ...quadrature} as hid.v mouse
    ikbd #(.DIV(4)) ikbd (
        .clk(clk32), .res(reset), .tx(ikbd_tx), .rx(ikbd_rx),
        .matrix_out(mout), .matrix_in(min), .caps_lock(),
        .joystick0({joy0[5:4], joy0[0], joy0[1], joy0[2], joy0[3]}),
        .joystick1(5'd0)
    );
    acia #(.INPUT_FILTER(0)) kbd_acia (
        .clk(clk32), .E(acia_E), .reset(reset),
        .din(io_wdata[15:8]), .sel(acia_cs && !p_a[2]), .rs(p_a[1]), .rw(io_rw),
        .dout(kbd_acia_d), .irq(kbd_acia_irq), .rxtxclk_sel(1'b0), .dout_strobe(),
        .rx(ikbd_tx), .tx(ikbd_rx)
    );
    acia midi_acia (
        .clk(clk32), .E(acia_E), .reset(reset),
        .din(io_wdata[15:8]), .sel(acia_cs && p_a[2]), .rs(p_a[1]), .rw(io_rw),
        .dout(midi_acia_d), .irq(midi_acia_irq), .rxtxclk_sel(1'b0), .dout_strobe(),
        .rx(1'b1), .tx()
    );

    integer fails = 0;
    // acia.v serial_clk and ikbd.sv clk_cnt have no reset (FPGA power-up 0); X in iverilog.
    initial begin kbd_acia.serial_clk = 8'd0; midi_acia.serial_clk = 8'd0; ikbd.clk_cnt = 0; end
    always begin #5000000; $display("  .. t=%0t SR-poll cyc a=%h tx=%b rx=%b irq=%b", $time, cpu_a, ikbd_rx, ikbd_tx, kbd_acia_irq); end
    reg [7:0] rd;
    task bcycle(input [31:0] adr, input rw, input [7:0] data);   // byte cycle, even address -> D31:24
        integer guard;
        begin
            @(negedge clk);
            cpu_a = adr; cpu_rw = rw; cpu_dout = {4{data}};
            cpu_siz = 2'b01; cpu_fc = 3'b101;
            cpu_as_n = 1'b0; cpu_ds_n = 1'b0;
            guard = 0;
            while (((cpu_dsack_n & 2'b11) == 2'b11) && cpu_berr_n) begin
                @(negedge clk);
                guard = guard + 1;
                if (guard > 400) begin
                    $display("TIMEOUT a=%h", adr); fails = fails + 1;
                    cpu_as_n = 1'b1; cpu_ds_n = 1'b1; disable bcycle;
                end
            end
            if (!cpu_berr_n) begin $display("BERR a=%h", adr); fails = fails + 1; end
            if (cpu_dsack_n !== 2'b01) begin $display("DSACK %b (want 01, 16-bit port) a=%h", cpu_dsack_n, adr); fails = fails + 1; end
            @(negedge clk);
            rd = adr[0] ? cpu_din[23:16] : cpu_din[31:24];
            cpu_as_n = 1'b1; cpu_ds_n = 1'b1;
            @(negedge clk);
        end
    endtask
    localparam SR = 32'hFFFFFC00, DR = 32'hFFFFFC02, MSR = 32'hFFFFFC04;

    // wait (polling SR like TOS) for RDRF, up to n ms
    task wait_rx(input integer ms, output reg got);
        integer t;
        begin
            got = 0;
            for (t = 0; t < ms*100 && !got; t = t + 1) begin
                repeat (160) @(posedge clk32);   // 5 us
                if (kbd_acia_irq) got = 1;
            end
        end
    endtask
    task read_byte(output reg [7:0] b);
        begin
            bcycle(SR, 1, 0);
            if (!rd[0]) begin $display("FAIL: RDRF not set in SR %02x", rd); fails = fails + 1; end
            if (!rd[7]) begin $display("FAIL: IRQ bit not set in SR %02x", rd); fails = fails + 1; end
            if (gpip4 !== 1'b0) begin $display("FAIL: GPIP4 not low with RX pending"); fails = fails + 1; end
            bcycle(DR, 1, 0); b = rd;
        end
    endtask

    reg got; reg [7:0] b, b1, b2;
    integer n;
    initial begin
        repeat (40) @(posedge clk32);
        reset = 1'b0;
        repeat (200) @(posedge clk32);
        bcycle(SR, 1, 0);
        $display("SR after reset = %02x", rd);
        if (!rd[1]) begin $display("FAIL: TDRE clear after reset"); fails = fails + 1; end
        bcycle(MSR, 1, 0);
        $display("MIDI SR = %02x", rd);
        // TOS: master reset, then 8N1 /64 RX IRQ on
        bcycle(SR, 0, 8'h03);
        bcycle(SR, 0, 8'h96);
        if (gpip4 !== 1'b1) begin $display("FAIL: GPIP4 low with nothing pending"); fails = fails + 1; end
        // the IKBD sends $F1 by itself after its own reset; drain anything first
        wait_rx(30, got);
        n = 0;
        while (got && n < 8) begin read_byte(b); $display("t=%0t power-on byte %02x", $time, b); n = n + 1; wait_rx(2, got); end
        // IKBD reset command
        bcycle(DR, 0, 8'h80);
        repeat (2000) @(posedge clk32);
        bcycle(SR, 1, 0);
        if (!rd[1]) $display("note: TDRE busy after 1st byte (SR %02x)", rd);
        while (!rd[1]) bcycle(SR, 1, 0);
        bcycle(DR, 0, 8'h01);
        wait_rx(200, got);
        if (!got) begin $display("FAIL: no reply to $80 $01"); fails = fails + 1; end
        else begin
            read_byte(b);
            $display("t=%0t reply to $80 $01 = %02x", $time, b);
            if (b !== 8'hF1) begin $display("FAIL: want F1"); fails = fails + 1; end
            repeat (50) @(posedge clk32);
            bcycle(SR, 1, 0);
            if (rd[0] || kbd_acia_irq || gpip4 !== 1'b1) begin
                $display("FAIL: RDRF/IRQ not cleared after RDR read (SR %02x irq %b)", rd, kbd_acia_irq); fails = fails + 1; end
        end
        // key press: matrix row 5, column 3 (any key), make then break
        key_row = 4'd5; key_col = 3'd3; key_dn = 1'b1;
        wait_rx(100, got);
        if (!got) begin $display("FAIL: no make code"); fails = fails + 1; end
        else begin read_byte(b1); $display("t=%0t make code %02x", $time, b1); end
        key_dn = 1'b0;
        wait_rx(100, got);
        if (!got) begin $display("FAIL: no break code"); fails = fails + 1; end
        else begin read_byte(b2); $display("t=%0t break code %02x", $time, b2);
            if (b2 !== (b1 | 8'h80)) begin $display("FAIL: break != make|$80"); fails = fails + 1; end end
        // mouse: a few quadrature steps on X (joy0[1:0] style), then right button
        repeat (4) begin
            joy0[0] = 1; repeat (3200) @(posedge clk32);
            joy0[1] = 1; repeat (3200) @(posedge clk32);
            joy0[0] = 0; repeat (3200) @(posedge clk32);
            joy0[1] = 0; repeat (3200) @(posedge clk32);
        end
        wait_rx(100, got);
        if (!got) begin $display("FAIL: no mouse packet"); fails = fails + 1; end
        else begin
            n = 0;
            while (got && n < 6) begin read_byte(b); $display("t=%0t mouse byte %02x", $time, b); n = n + 1; wait_rx(6, got); end
            if (n < 3) begin $display("FAIL: short mouse packet (%0d)", n); fails = fails + 1; end
        end
        if (fails == 0) $display("ALL PASS"); else $display("FAILED %0d", fails);
        $finish;
    end
endmodule
