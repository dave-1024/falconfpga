// tb_busfill.v - FAL_01 BLI-9: TOS 4.04 hb_rect per-plane fills through falcon_bus + falcon_blitter.
// A 68030-style async bus model (AS on the falling clk_cpu edge, DSACK sampled on the rising edge, data out
// as WF68K30L DATA_PORT_OUT: bytes on all four lanes, words on both halves) drives falcon_bus; the blitter
// is selected like falcon_core (sel = io_cyc && io_a[15:6] == $228, io_done = blt_done) and shares a
// req/ack memory with the CPU like falcon_soc (blt_g32 mux). Sequence per AES box: a black border fill
// (OP 3,3,3,3), then a mixed interior fill (hw 7 = OP 3,3,3,0 or hw 8 = OP 0,0,0,3), each plane:
// move.l a1,B_D_ADDR; move.w d7,B_HEIGHT; move.w (op_table),B_LOGOP (or move.b to $8A3B); move.w d4,(a5);
// tas (a5) / nop / bmi loop, with opcode fetches between data cycles.
`timescale 1ns/1ps
module tb_busfill;
    reg clk32 = 0, clk = 0;
    always #15.625 clk32 = ~clk32;
    always @(posedge clk32) clk <= ~clk;           // clk_cpu = clk32/2, phase locked
    reg reset = 1;
    reg        cpu_as_n = 1, cpu_ds_n = 1, cpu_rw = 1;
    reg [31:0] cpu_a = 0, cpu_dout = 0;
    reg [1:0]  cpu_siz = 2'b10;
    reg [2:0]  cpu_fc = 3'b101;
    wire [31:0] cpu_din; wire [1:0] cpu_dsack_n; wire cpu_berr_n, cpu_avec_n;
    wire mem_req, mem_we; wire [23:1] mem_a; wire [1:0] mem_be; wire [15:0] mem_wdata;
    wire io_cyc, io_uds, io_lds, io_rw, io_wr; wire [15:1] io_a; wire [15:0] io_wdata;
    wire br_want, bus_grant, cyc_tog;
    wire sel_blt = io_cyc && (io_a[15:6] == 10'h228);
    wire [15:0] blt_rdata; wire blt_done;
    reg  m_ack = 0; reg [15:0] m_rdata = 0;
    falcon_bus #(.IO_WAIT(2)) u_bus (
        .clk(clk), .reset(reset),
        .cpu_a(cpu_a), .cpu_dout(cpu_dout), .cpu_din(cpu_din), .cpu_as_n(cpu_as_n), .cpu_ds_n(cpu_ds_n),
        .cpu_rw(cpu_rw), .cpu_siz(cpu_siz), .cpu_fc(cpu_fc),
        .cpu_dsack_n(cpu_dsack_n), .cpu_berr_n(cpu_berr_n), .cpu_avec_n(cpu_avec_n),
        .mem_req(mem_req), .mem_a(mem_a), .mem_we(mem_we), .mem_be(mem_be), .mem_wdata(mem_wdata),
        .mem_ack(m_ack), .mem_rdata(m_rdata),
        .io_cyc(io_cyc), .io_a(io_a), .io_uds(io_uds), .io_lds(io_lds), .io_rw(io_rw), .io_wr(io_wr),
        .io_wdata(io_wdata), .io_rdata(sel_blt ? blt_rdata : 16'hFFFF), .io_ext(sel_blt), .io_done(blt_done),
        .iack_mfp(), .mfp_vector(8'h00), .mfp_dtack(1'b0),
        .br_want(br_want), .bus_grant(bus_grant), .cyc_tog(cyc_tog));
    wire g32, b_req, b_we, irq_n; wire [23:1] b_a; wire [15:0] b_wd; wire [127:0] dbg; wire [255:0] snap;
    falcon_blitter dut (.clk_32(clk32), .reset(reset), .pwr_up(reset),
        .sel(sel_blt), .a(io_a[5:1]), .rw(io_rw), .uds(io_uds), .lds(io_lds), .wdata(io_wdata),
        .rdata(blt_rdata), .done(blt_done),
        .br_want(br_want), .bus_grant(bus_grant), .cpu_cyc_tog(cyc_tog),
        .grant_32(g32), .m_req(b_req), .m_a(b_a), .m_we(b_we), .m_wdata(b_wd),
        .m_ack(m_ack), .m_rdata(m_rdata), .irq_n(irq_n), .dbg(dbg), .dbg_snap(snap));
    // memory: falcon_soc mux, 4-phase req/ack on clk32, variable latency
    wire        a_req = g32 ? b_req : mem_req;
    wire [23:1] a_a   = g32 ? b_a : mem_a;
    wire        a_we  = g32 ? b_we : mem_we;
    wire [1:0]  a_be  = g32 ? 2'b11 : mem_be;
    wire [15:0] a_d   = g32 ? b_wd : mem_wdata;
    reg [15:0] mem [0:65535];
    integer lat = 0, errs = 0, seed = 1;
    always @(posedge clk32) begin
        if (a_req && !m_ack) begin
            lat = lat + 1;
            if (lat >= 3 + (a_a[3:1] % 5)) begin
                lat = 0; m_ack <= 1;
                if (a_a[23:21] == 3'b111) m_rdata <= 16'h4E71;                 // ROM: nop
                else if (a_we) begin
                    if (a_be[1]) mem[a_a[16:1]][15:8] <= a_d[15:8];
                    if (a_be[0]) mem[a_a[16:1]][7:0]  <= a_d[7:0];
                end else m_rdata <= mem[a_a[16:1]];
            end
        end else if (!a_req) m_ack <= 0;
    end
    // 68030 async bus cycle. siz: 01 byte, 10 word. Returns the 16-bit port data.
    reg [15:0] rdv;
    task cyc(input [31:0] adr, input rw, input [1:0] siz, input [15:0] d);
        integer g;
        begin
            @(negedge clk);
            cpu_a = adr; cpu_rw = rw; cpu_siz = siz; cpu_fc = adr[23:20] == 4'hE ? 3'b110 : 3'b101;
            cpu_dout = (siz == 2'b01) ? {4{d[7:0]}} : {d, d};
            cpu_as_n = 0; cpu_ds_n = !rw;
            @(negedge clk); cpu_ds_n = 0;
            g = 0;
            while (cpu_dsack_n == 2'b11 && cpu_berr_n) begin
                @(posedge clk); g = g + 1;
                if (g > 20000) begin $display("BUS TIMEOUT at %h", adr); $finish; end
            end
            rdv = adr[0] && siz == 2'b01 ? {8'h00, cpu_din[23:16]} : cpu_din[31:16];
            @(negedge clk); cpu_as_n = 1; cpu_ds_n = 1;
        end
    endtask
    reg [31:0] pc = 32'hE12B00;
    task fetch(input integer n); integer k; begin for (k = 0; k < n; k = k + 1) begin cyc(pc, 1, 2'b10, 0); pc = pc + 2; end end endtask
    task ww(input [31:0] adr, input [15:0] d); begin fetch(1); cyc(adr, 0, 2'b10, d); end endtask
    task wb(input [31:0] adr, input [7:0] d);  begin fetch(1); cyc(adr, 0, 2'b01, {8'h00, d}); end endtask
    task wl(input [31:0] adr, input [31:0] d); begin fetch(1); cyc(adr, 0, 2'b10, d[31:16]); cyc(adr + 2, 0, 2'b10, d[15:0]); end endtask
    integer polls;
    task tas_loop;   // tas (a5); nop; bmi
        reg [7:0] v;
        begin
            polls = 0; v = 8'h80;
            while (v[7]) begin
                fetch(1);
                cyc(32'hFF8A3C, 1, 2'b01, 0); v = rdv[15:8];
                cyc(32'hFF8A3C, 0, 2'b01, {8'h00, v | 8'h80});
                fetch(2);
                polls = polls + 1; if (polls > 100000) begin $display("TAS TIMEOUT"); $finish; end
            end
        end
    endtask
    localparam BASE = 32'h00002000, LINEB = 160, SPAN = 4, HGT = 6;
    task fill(input [3:0] col, input bytelop, input [15:0] lm, input [15:0] rm);
        integer p, i;
        begin
            ww(32'hFF8A20, 0);
            ww(32'hFF8A28, lm); ww(32'hFF8A2A, 16'hFFFF); ww(32'hFF8A2C, rm);
            ww(32'hFF8A2E, 8); ww(32'hFF8A30, LINEB - 8*(SPAN-1)); ww(32'hFF8A36, SPAN);
            for (i = 0; i < 16; i = i + 1) ww(32'hFF8A00 + 2*i, 16'hFFFF);
            for (p = 0; p < 4; p = p + 1) begin
                wl(32'hFF8A32, BASE + 2*p);
                ww(32'hFF8A38, HGT);
                fetch(3);                                   // ror.l / scs / and.w
                cyc(32'hE3F000 + (col[p] ? 2 : 0), 1, 2'b10, 0);   // op_table read
                if (bytelop) begin wb(32'hFF8A3A, 8'h01); wb(32'hFF8A3B, col[p] ? 8'h03 : 8'h00); end
                else ww(32'hFF8A3A, col[p] ? 16'h0103 : 16'h0100);
                ww(32'hFF8A3C, 16'h8000);
                tas_loop;
            end
        end
    endtask
    task check(input [3:0] col, input integer n, input [15:0] lm, input [15:0] rm);
        integer x, y, p, i; reg [15:0] mk, exp, got;
        begin
            for (y = 0; y < HGT; y = y + 1) for (x = 0; x < SPAN; x = x + 1) for (p = 0; p < 4; p = p + 1) begin
                mk = (x == 0) ? lm : (x == SPAN-1) ? rm : 16'hFFFF;
                i = (BASE/2) + y*(LINEB/2) + x*4 + p; got = mem[i];
                exp = ((col[p] ? 16'hFFFF : 16'h0000) & mk) | (16'hFFFF & ~mk);   // over the black border fill
                if (got !== exp) begin errs = errs + 1; if (errs < 30) $display("ERR fill%0d col %0d y%0d x%0d p%0d got %h exp %h", n, col, y, x, p, got, exp); end
            end
            $display("fill%0d colour %0d checked, errs %0d", n, col, errs);
        end
    endtask
    integer i, n;
    initial begin
        for (i = 0; i < 65536; i = i + 1) mem[i] = (i % 4 == 1) ? 16'hFFFF : 16'h0000;   // green desktop
        repeat (10) @(posedge clk); reset <= 0; repeat (10) @(posedge clk);
        n = 0;
        // box 1: black border then LWHITE (hw 7) interior, word LOGOP
        fill(4'hF, 0, 16'hFFFF, 16'hFFFF); fill(4'h7, 0, 16'h0FFF, 16'hFFF0); check(4'h7, n, 16'h0FFF, 16'hFFF0); n = n + 1;
        // box 2: black then LBLACK (hw 8)
        fill(4'hF, 0, 16'hFFFF, 16'hFFFF); fill(4'h8, 0, 16'h0FFF, 16'hFFF0); check(4'h8, n, 16'h0FFF, 16'hFFF0); n = n + 1;
        // box 3/4: same with byte HOP/LOP writes ($8A3A / $8A3B move.b)
        fill(4'hF, 1, 16'hFFFF, 16'hFFFF); fill(4'h7, 1, 16'hFFFF, 16'hFFFF); check(4'h7, n, 16'hFFFF, 16'hFFFF); n = n + 1;
        fill(4'hF, 1, 16'hFFFF, 16'hFFFF); fill(4'h8, 1, 16'h00FF, 16'hFF00); check(4'h8, n, 16'h00FF, 16'hFF00); n = n + 1;
        $display("dbg %h", dbg);
        for (i = 0; i < 8; i = i + 1) $display("snap[%0d] %h", i, snap[32*i +: 32]);
        $display("DONE errs=%0d", errs);
        $finish;
    end
endmodule
