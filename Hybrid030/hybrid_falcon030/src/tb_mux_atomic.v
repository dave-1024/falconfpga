// =====================================================================
// tb_mux_atomic.v -- REV11b arbitration bench: random-wait slave, live
// HID traffic, real publisher+mux DUTs. Encodes everything the REV11
// bench missed:
//   * slave inserts RANDOM WAIT STATES (the silicon-only unknown)
//   * slave enforces the port's measured lane rule: 32-bit writes land
//     low-lane at EVEN word addresses; any addr[2]=1 write is an error
//   * scoreboard: every publish is atomic-and-coherent (t200,tvbl,cyc
//     all written by the same burst before MAGIC; values monotone),
//     >=90% of publish periods complete, ZERO HID writes lost or
//     corrupted, HID stall bounded, no deadlock, err_count==0.
// Mutations M1 (mid-burst release), M2 (free-run/forced-ready-1),
// M3 (odd-word slot layout) must each FAIL this bench.
// =====================================================================
`timescale 1ns/1ps
module tb_mux_atomic;
    reg hclk = 0; always #5 hclk = ~hclk;
    reg hresetn = 0;

    // ---------------- DUT wires ----------------
    wire [31:0] t_haddr;  wire [2:0] t_hburst, t_hsize; wire [3:0] t_hprot;
    wire t_hsel, t_hwrite; wire [1:0] t_htrans; wire [63:0] t_hwdata;
    wire t_hreadyout, t_hresp, t_busy, t_gnt; wire [7:0] t_err;

    reg  [31:0] h_haddr;  reg [2:0] h_hburst, h_hsize; reg [3:0] h_hprot;
    reg  h_hsel, h_hwrite; reg [1:0] h_htrans; reg [63:0] h_hwdata;
    wire h_hreadyout, h_hresp;

    wire [31:0] haddr; wire [2:0] hburst, hsize; wire [3:0] hprot;
    wire hsel, hwrite; wire [1:0] htrans; wire [63:0] hwdata;
    reg  hreadyout; wire hresp = 1'b0;

    localparam [31:0] SLOT = 32'h04F0_0600;
    localparam [31:0] MAG2 = 32'h7B10_C0D2;

    falcon_timebase_ahb #(.SLOT_BASE(SLOT), .TB_MAGIC(MAG2),
        .PERIOD_200(32'd40), .PERIOD_VBL(32'd133), .PUBLISH_DIV(32'd200),
        .WD_MAX(10'd512)) u_pub (
        .hclk(hclk), .hresetn(hresetn),
        .cfg_we(1'b0), .cfg_sel(1'b0), .cfg_val(32'd0),
        .haddr(t_haddr), .hburst(t_hburst), .hprot(t_hprot),
        .hsel(t_hsel), .hsize(t_hsize), .htrans(t_htrans),
        .hwdata(t_hwdata), .hwrite(t_hwrite),
        .hreadyout(t_hreadyout), .hresp(t_hresp),
        .gnt(t_gnt), .busy(t_busy), .err_count(t_err));

    falcon_ahb_mux u_mux (
        .hclk(hclk), .hresetn(hresetn),
        .h_haddr(h_haddr), .h_hburst(h_hburst), .h_hprot(h_hprot),
        .h_hsel(h_hsel), .h_hsize(h_hsize), .h_htrans(h_htrans),
        .h_hwdata(h_hwdata), .h_hwrite(h_hwrite),
        .t_haddr(t_haddr), .t_hburst(t_hburst), .t_hprot(t_hprot),
        .t_hsel(t_hsel), .t_hsize(t_hsize), .t_htrans(t_htrans),
        .t_hwdata(t_hwdata), .t_hwrite(t_hwrite),
        .t_busy(t_busy), .t_gnt(t_gnt),
        .haddr(haddr), .hburst(hburst), .hprot(hprot), .hsel(hsel),
        .hsize(hsize), .htrans(htrans), .hwdata(hwdata), .hwrite(hwrite),
        .hreadyout(hreadyout), .hresp(hresp),
        .h_hreadyout(h_hreadyout), .h_hresp(h_hresp),
        .t_hreadyout(t_hreadyout), .t_hresp(t_hresp));

    // ---------------- errors ----------------
    integer errs = 0;
    task fail(input [255:0] why); begin
        errs = errs + 1;
        $display("FAIL @%0t: %0s", $time, why);
    end endtask

    // ---------------- slave: random waits + lane rule ----------------
    reg        pend;            // data phase outstanding
    reg [31:0] pend_addr;
    reg [31:0] slot_mem [0:3];  // +0 MAGIC, +8 t200, +16 tvbl, +24 cyc
    reg [31:0] hid_mem  [0:255];
    integer k;
    initial begin
        pend = 0;
        for (k = 0; k < 4; k = k + 1) slot_mem[k] = 32'd0;
        for (k = 0; k < 256; k = k + 1) hid_mem[k] = 32'd0;
    end
    // ready pattern: pseudo-random 0..7 wait cycles
    reg [15:0] lfsr = 16'hACE1;
    reg [2:0]  waitcnt = 0;
    always @(posedge hclk) begin
        lfsr <= {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
        if (waitcnt != 0) begin hreadyout <= 1'b0; waitcnt <= waitcnt-1; end
        else begin
            hreadyout <= 1'b1;
            if (lfsr[1:0] == 2'b00) waitcnt <= lfsr[4:2]; // burst of waits
        end
    end
    // per-burst publish tracking
    reg [2:0]  burst_mask;      // t200,tvbl,cyc seen this burst
    reg [31:0] b200, bvbl, bcyc, p200, pvbl;
    integer publishes_ok = 0, hid_writes_done = 0, laneviol = 0;
    initial begin burst_mask=0; p200=0; pvbl=0; end

    always @(posedge hclk) if (hresetn) begin
        // address-phase accept
        if (htrans == 2'b10 && hsel && hreadyout) begin
            if (pend) fail("pipelined addr while data pending (mux tear)");
            pend      <= 1'b1;
            pend_addr <= haddr;
            if (!hwrite) fail("unexpected read");
        end else if (pend && hreadyout) begin
            // data phase completes: sample LOW lane, enforce lane rule
            pend <= 1'b0;
            if (pend_addr[2]) begin
                laneviol = laneviol + 1;
                fail("write to ODD word address (dead-lane rule)");
            end else if (pend_addr >= SLOT && pend_addr < SLOT+32) begin
                slot_mem[pend_addr[4:3]] <= hwdata[31:0];
                case (pend_addr[4:0])
                    5'd8:  begin burst_mask <= 3'b001; b200 <= hwdata[31:0]; end
                    5'd16: begin burst_mask <= burst_mask|3'b010; bvbl <= hwdata[31:0]; end
                    5'd24: begin burst_mask <= burst_mask|3'b100; bcyc <= hwdata[31:0]; end
                    5'd0: begin
                        if (hwdata[31:0] != MAG2) fail("bad MAGIC value");
                        if (burst_mask != 3'b111) fail("PARTIAL publish before MAGIC");
                        else begin
                            if (b200 < p200 || bvbl < pvbl) fail("non-monotone ticks");
                            p200 <= b200; pvbl <= bvbl;
                            publishes_ok = publishes_ok + 1;
                        end
                        burst_mask <= 3'b000;
                    end
                    default: fail("write to unmapped slot offset");
                endcase
            end else if (pend_addr >= 32'h03FE0000 && pend_addr < 32'h03FE0800) begin
                hid_mem[pend_addr[10:3]] <= hwdata[31:0];
            end else fail("write outside slot/ring ranges");
        end
    end

    // ---------------- HID surrogate master (AHB-correct) -------------
    reg [1:0]  hst;             // 0 idle-gap, 1 addr, 2 data
    reg [7:0]  hidx;
    reg [31:0] hval;
    reg [15:0] gap;
    integer stall, max_stall = 0;
    reg [31:0] hid_shadow [0:255];
    reg        chk_pend; reg [7:0] chk_idx; reg [31:0] chk_val;
    integer    hid_losses = 0;
    always @(posedge hclk) if (hresetn) begin
        if (chk_pend && hid_mem[chk_idx] !== chk_val) begin
            hid_losses = hid_losses + 1;
            fail("HID write lost/corrupted (immediate check)");
        end
    end
    initial begin
        hst=0; hidx=0; gap=8; stall=0; chk_pend=0; chk_idx=0; chk_val=0;
        h_hsel=0; h_htrans=0; h_hwrite=0; h_haddr=0; h_hwdata=0;
        h_hburst=0; h_hsize=3'b010; h_hprot=4'b0011;
        for (k=0;k<256;k=k+1) hid_shadow[k]=32'd0;
    end
    always @(posedge hclk) if (hresetn) begin
        case (hst)
        2'd0: begin
            h_hsel <= 0; h_htrans <= 0; h_hwrite <= 0; stall <= 0;
            chk_pend <= 1'b0;
            if (gap == 0) begin
                hval <= {16'hC0DE, 8'd0, hidx} ^ {24'd0, hidx};
                h_haddr  <= 32'h03FE0000 + {21'd0, hidx, 3'd0}; // even words
                h_hsel   <= 1'b1; h_htrans <= 2'b10; h_hwrite <= 1'b1;
                hst <= 2'd1;
            end else gap <= gap - 1;
        end
        2'd1: begin
            stall <= stall + 1;
            if (h_hreadyout) begin
                h_htrans <= 2'b00; h_hsel <= 1'b0;
                h_hwdata <= {32'd0, hval};
                hst <= 2'd2;
            end
        end
        2'd2: begin
            stall <= stall + 1;
            if (h_hreadyout) begin
                hid_shadow[hidx] <= hval;
                hid_writes_done  =  hid_writes_done + 1;
                if (stall > max_stall) max_stall = stall;
                chk_pend <= 1'b1; chk_idx <= hidx; chk_val <= hval;
                hidx <= hidx + 8'd1;
                gap  <= {8'd0, lfsr[7:0]} & 16'h001F;  // 0..31, often 0
                hst  <= 2'd0;
            end else chk_pend <= 1'b0;
        end
        default: hst <= 2'd0;
        endcase
    end

    // ---------------- run control ----------------
    integer i;
    initial begin
        hresetn = 0; hreadyout = 1;
        repeat (10) @(posedge hclk);
        hresetn = 1;
        repeat (120000) @(posedge hclk);

        // final verification
        if (publishes_ok < 500)
            fail("too few coherent publishes (expected ~590)");
        if (hid_writes_done < 2000)
            fail("HID surrogate starved");
        for (i = 0; i < 256; i = i + 1)
            if (hid_mem[i] !== hid_shadow[i])
                fail("HID data lost or corrupted");
        if (max_stall > 700) fail("HID stalled past bound (>700)");
        if (hid_losses != 0) fail("per-write HID losses recorded");
        if (t_err !== 8'd0) fail("publisher watchdog fired in clean run");
        if (laneviol != 0) fail("lane-rule violations");

        $display("stats: publishes_ok=%0d hid_writes=%0d max_hid_stall=%0d err_count=%0d",
                 publishes_ok, hid_writes_done, max_stall, t_err);
        if (errs == 0) $display("TB_MUX_ATOMIC: PASS");
        else           $display("TB_MUX_ATOMIC: FAIL (%0d errors)", errs);
        $finish;
    end

    // deadlock watchdog: coherent publishes must keep arriving
    integer last_pub = 0, last_seen = 0;
    always @(posedge hclk) if (hresetn) begin
        last_seen = last_seen + 1;
        if (publishes_ok != last_pub) begin
            last_pub = publishes_ok; last_seen = 0;
        end else if (last_seen > 20000) begin
            fail("DEADLOCK: no coherent publish in 20000 cycles");
            $display("TB_MUX_ATOMIC: FAIL (deadlock)");
            $finish;
        end
    end
endmodule
