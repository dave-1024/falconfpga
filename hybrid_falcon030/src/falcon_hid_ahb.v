// ============================================================================
// falcon_hid_ahb.v -- m6 rev2: USB HID -> DDR3 event ring via the AE350's
//                     Extended AHB Master port (fabric = master, SoC = slave)
//
// WHY: the shared-DDR3 write lane (lane4) is non-functional on this IP
// (2026-07-13/14: wr_done never arrives, even example-verbatim, isolated,
// and exclusively granted -- falcon_wprobe returned zero signatures in any
// address zone). The Extended AHB Master port is the documented, standard
// route for fabric masters into the SoC address map, and it replaces the
// lane4 path entirely. Lane5 (read) is untouched and keeps serving the
// scanout.
//
// AHB conventions used (ARM AMBA 2/3 AHB-Lite, single master):
//   - address phase: HSEL + HTRANS=NONSEQ(2'b10) + HADDR/HSIZE/HWRITE valid,
//     accepted on the rising edge where HREADY is high
//   - data phase: HWDATA valid, held until HREADYOUT high
//   - HREADY (in) is looped back from HREADYOUT by the top: single master,
//     single slave, so "the bus is ready" == "the slave is ready"
//   - HBURST = SINGLE (3'b000), HPROT = data/privileged/non-bufferable/
//     non-cacheable (4'b0011): the CPU's D-cache must not hold these lines,
//     and the firmware's 60Hz WBINVAL already guarantees it sees them.
//   - HRESP checked: an ERROR response aborts the record and increments an
//     error counter (readable in a later diag build) rather than hanging.
//
// DEFENSIVE, given this IP's history:
//   - every transfer is HSIZE=2 (32-bit) at an 8-byte-aligned address, so
//     data always lands on HWDATA[31:0] and the 64-bit bus's upper half --
//     whose lane equivalent was measured DEAD -- is never relied upon.
//     Ring records are therefore 16 bytes: two 32-bit words at +0 and +8.
//   - a watchdog aborts any transfer whose HREADYOUT never returns, so a
//     misbehaving slave degrades to "no input" rather than "wedged fabric"
//     (the failure mode that starved the scanout in v5).
//
// Ring contract with falcon_m6ahb.c (DDR3 byte addresses, CPU's view):
//   RING_BASE 0x03FE0000: 128 records x 16 bytes
//     record[i] + 0  : word0 (type/buttons/dx/dy | type/mods/k1/k2)
//     record[i] + 8  : word1 (k3/k4/port/seq)
//     (+4 and +12 are left untouched -- the upper halves we don't trust)
//   HEAD_ADDR 0x03FE0800: uint32, count of records ever written
//   head is written only after both record words have completed, so the
//   firmware can never observe a torn record.
// ============================================================================

module falcon_hid_ahb_core #(
    parameter [31:0] RING_BASE = 32'h03FE_0000,
    parameter [31:0] HEAD_ADDR = 32'h03FE_0800
)(
    // report snapshots, clk12 domain (unchanged from the lane4 version)
    input  wire        clk12,
    input  wire        rst12,
    input  wire        p0_report,
    input  wire [1:0]  p0_typ,
    input  wire [7:0]  p0_mod, p0_k1, p0_k2, p0_k3, p0_k4,
    input  wire [7:0]  p0_mbtn, p0_mdx, p0_mdy,
    input  wire        p1_report,
    input  wire [1:0]  p1_typ,
    input  wire [7:0]  p1_mod, p1_k1, p1_k2, p1_k3, p1_k4,
    input  wire [7:0]  p1_mbtn, p1_mdx, p1_mdy,

    // AHB master, AHB_CLK domain
    input  wire        hclk,
    input  wire        hresetn,
    output reg  [31:0] haddr,
    output reg  [2:0]  hburst,
    output reg  [3:0]  hprot,
    output reg         hsel,
    output reg  [2:0]  hsize,
    output reg  [1:0]  htrans,
    output reg  [63:0] hwdata,
    output reg         hwrite,
    input  wire [63:0] hrdata,      // unused: this master only writes
    input  wire        hreadyout,
    input  wire        hresp,

    output reg  [7:0]  err_count    // AHB ERROR responses + watchdog aborts
);

    localparam [1:0] TRANS_IDLE   = 2'b00;
    localparam [1:0] TRANS_NONSEQ = 2'b10;
    localparam [2:0] BURST_SINGLE = 3'b000;
    localparam [2:0] SIZE_WORD    = 3'b010;   // 32-bit
    localparam [3:0] PROT_DATA    = 4'b0011;  // data, privileged, non-buf/cache

    // ---------------- event encode (clk12) --------------------------------
    function [63:0] enc;
        input [1:0] typ; input [7:0] md,k1,k2,k3,k4,mb,dx,dy;
        input [7:0] port_id, seq;
        begin
            if (typ == 2'd2)                              /* mouse    */
                enc = { seq, port_id, 16'd0, dy, dx, mb, 8'h4D };
            else                                          /* keyboard */
                enc = { seq, port_id, k4, k3, k2, k1, md, 8'h4B };
        end
    endfunction

    // ---------------- per-port 8-deep dual-clock FIFO ----------------------
    // (identical structure to the lane4 version; read side now on hclk)
    reg [63:0] fmem0 [0:7];    reg [63:0] fmem1 [0:7];
    reg [3:0]  wptr0, rptr0, wptr1, rptr1;
    reg [3:0]  wgry0_s [0:1];  reg [3:0]  wgry1_s [0:1];
    reg [3:0]  rgry0_s [0:1];  reg [3:0]  rgry1_s [0:1];
    reg [3:0]  rgry0_h, rgry1_h;
    reg [7:0]  seq0, seq1;

    wire [3:0] wgry0 = wptr0 ^ (wptr0 >> 1);
    wire [3:0] wgry1 = wptr1 ^ (wptr1 >> 1);

    function [3:0] gray2bin;
        input [3:0] g;
        begin
            gray2bin[3] = g[3];
            gray2bin[2] = g[3] ^ g[2];
            gray2bin[1] = g[3] ^ g[2] ^ g[1];
            gray2bin[0] = g[3] ^ g[2] ^ g[1] ^ g[0];
        end
    endfunction

    wire [3:0] rptr0_in12 = gray2bin(rgry0_s[1]);
    wire [3:0] rptr1_in12 = gray2bin(rgry1_s[1]);

    always @(posedge clk12) begin
        if (rst12) begin
            wptr0 <= 4'd0; wptr1 <= 4'd0; seq0 <= 8'd0; seq1 <= 8'd0;
            rgry0_s[0] <= 4'd0; rgry0_s[1] <= 4'd0;
            rgry1_s[0] <= 4'd0; rgry1_s[1] <= 4'd0;
        end else begin
            rgry0_s[0] <= rgry0_h; rgry0_s[1] <= rgry0_s[0];
            rgry1_s[0] <= rgry1_h; rgry1_s[1] <= rgry1_s[0];
            if (p0_report && (p0_typ == 2'd1 || p0_typ == 2'd2)
                && (wptr0 - rptr0_in12) < 4'd8) begin
                fmem0[wptr0[2:0]] <= enc(p0_typ, p0_mod,p0_k1,p0_k2,p0_k3,p0_k4,
                                         p0_mbtn,p0_mdx,p0_mdy, 8'd0, seq0);
                wptr0 <= wptr0 + 4'd1;
                seq0  <= seq0 + 8'd1;
            end
            if (p1_report && (p1_typ == 2'd1 || p1_typ == 2'd2)
                && (wptr1 - rptr1_in12) < 4'd8) begin
                fmem1[wptr1[2:0]] <= enc(p1_typ, p1_mod,p1_k1,p1_k2,p1_k3,p1_k4,
                                         p1_mbtn,p1_mdx,p1_mdy, 8'd1, seq1);
                wptr1 <= wptr1 + 4'd1;
                seq1  <= seq1 + 8'd1;
            end
        end
    end

    // ---------------- hclk side: pop + AHB master --------------------------
    always @(posedge hclk) begin
        wgry0_s[0] <= wgry0; wgry0_s[1] <= wgry0_s[0];
        wgry1_s[0] <= wgry1; wgry1_s[1] <= wgry1_s[0];
        rgry0_h <= rptr0 ^ (rptr0 >> 1);
        rgry1_h <= rptr1 ^ (rptr1 >> 1);
    end
    wire [3:0] wptr0_inh = gray2bin(wgry0_s[1]);
    wire [3:0] wptr1_inh = gray2bin(wgry1_s[1]);
    wire ev0 = (rptr0 != wptr0_inh);
    wire ev1 = (rptr1 != wptr1_inh);

    reg [63:0] ev;
    reg [31:0] head_idx;
    reg [31:0] xfer_addr;
    reg [31:0] xfer_data;
    reg [1:0]  step;          // 0 = record word0, 1 = record word1, 2 = head
    reg [9:0]  wdog;

    localparam S_IDLE  = 3'd0,   // nothing in flight
               S_ADDR  = 3'd1,   // address phase presented
               S_DATA  = 3'd2,   // data phase, waiting HREADYOUT
               S_NEXT  = 3'd3;   // decide the next step of the record
    reg [2:0] st = S_IDLE;

    // 128 records x 16 bytes; word0 at +0, word1 at +8 (both 8-byte aligned,
    // so a 32-bit HSIZE transfer always lands on HWDATA[31:0])
    wire [31:0] rec_base = RING_BASE + ({24'd0, head_idx[6:0]} << 4);

    always @(posedge hclk) begin
        if (!hresetn) begin
            st        <= S_IDLE;
            hsel      <= 1'b0;
            htrans    <= TRANS_IDLE;
            hwrite    <= 1'b0;
            hsize     <= SIZE_WORD;
            hburst    <= BURST_SINGLE;
            hprot     <= PROT_DATA;
            haddr     <= 32'd0;
            hwdata    <= 64'd0;
            rptr0     <= 4'd0;
            rptr1     <= 4'd0;
            head_idx  <= 32'd0;
            step      <= 2'd0;
            err_count <= 8'd0;
            wdog      <= 10'd0;
        end else begin
            case (st)
            // ---------------------------------------------------------------
            S_IDLE: begin
                hsel   <= 1'b0;
                htrans <= TRANS_IDLE;
                hwrite <= 1'b0;
                wdog   <= 10'd0;
                if (ev0 || ev1) begin
                    if (ev0) begin ev <= fmem0[rptr0[2:0]]; rptr0 <= rptr0 + 4'd1; end
                    else     begin ev <= fmem1[rptr1[2:0]]; rptr1 <= rptr1 + 4'd1; end
                    step      <= 2'd0;
                    xfer_addr <= rec_base;                 // word0 at +0
                    st        <= S_ADDR;
                end
            end
            // ---------------------------------------------------------------
            // Address phase. Held until HREADY(=HREADYOUT) accepts it.
            // NOTE: `hsel` in the condition is NOT redundant. Outputs are
            // registered, so on the cycle we ENTER this state the bus still
            // carries the idle values -- sampling HREADY then would "accept"
            // an address phase we never drove (measured: 5 of 16 records
            // silently lost in simulation before this gate was added). The
            // first cycle in S_ADDR drives the address phase; acceptance is
            // only considered from the second cycle onward, when hsel is
            // genuinely high on the bus.
            S_ADDR: begin
                hsel   <= 1'b1;
                htrans <= TRANS_NONSEQ;
                hwrite <= 1'b1;
                hsize  <= SIZE_WORD;
                hburst <= BURST_SINGLE;
                hprot  <= PROT_DATA;
                haddr  <= xfer_addr;
                wdog   <= wdog + 10'd1;
                if (hsel && hreadyout) begin               // address accepted
                    // present the data phase on the next cycle
                    hwdata <= {32'd0, (step == 2'd0) ? ev[31:0]
                                    : (step == 2'd1) ? ev[63:32]
                                    :                  head_idx + 32'd1};
                    htrans <= TRANS_IDLE;                  // single transfer
                    hsel   <= 1'b0;
                    wdog   <= 10'd0;
                    st     <= S_DATA;
                end else if (&wdog) begin                  // slave never ready
                    err_count <= err_count + 8'd1;
                    hsel   <= 1'b0;
                    htrans <= TRANS_IDLE;
                    st     <= S_IDLE;
                end
            end
            // ---------------------------------------------------------------
            // Data phase. HWDATA held until HREADYOUT; HRESP checked.
            S_DATA: begin
                wdog <= wdog + 10'd1;
                if (hreadyout) begin
                    wdog <= 10'd0;
                    if (hresp) begin                       // ERROR response
                        err_count <= err_count + 8'd1;
                        st <= S_IDLE;                      // drop this record
                    end else
                        st <= S_NEXT;
                end else if (&wdog) begin
                    err_count <= err_count + 8'd1;
                    st <= S_IDLE;
                end
            end
            // ---------------------------------------------------------------
            S_NEXT: begin
                case (step)
                2'd0: begin                                // word1 at +8
                    step      <= 2'd1;
                    xfer_addr <= rec_base + 32'd8;
                    st        <= S_ADDR;
                end
                2'd1: begin                                // publish head
                    step      <= 2'd2;
                    xfer_addr <= HEAD_ADDR;
                    st        <= S_ADDR;
                end
                default: begin                             // record complete
                    head_idx <= head_idx + 32'd1;
                    st       <= S_IDLE;
                end
                endcase
            end
            default: st <= S_IDLE;
            endcase
        end
    end

endmodule


// --------------------------- board-level wrapper ---------------------------
module falcon_hid_ahb #(
    parameter [31:0] RING_BASE = 32'h03FE_0000,
    parameter [31:0] HEAD_ADDR = 32'h03FE_0800
)(
    input  wire clk12,
    inout  wire usb1_dp, usb1_dn,
    inout  wire usb2_dp, usb2_dn,

    input  wire        hclk,
    input  wire        hresetn,
    output wire [31:0] haddr,
    output wire [2:0]  hburst,
    output wire [3:0]  hprot,
    output wire        hsel,
    output wire [2:0]  hsize,
    output wire [1:0]  htrans,
    output wire [63:0] hwdata,
    output wire        hwrite,
    input  wire [63:0] hrdata,
    input  wire        hreadyout,
    input  wire        hresp,
    output wire [7:0]  err_count
);
    reg [7:0] por12 = 8'd0;
    always @(posedge clk12) if (!por12[7]) por12 <= por12 + 8'd1;
    wire rst12   = ~por12[7];
    wire rst12_n =  por12[7];

    wire        r0, r1;
    wire [1:0]  t0, t1;
    wire [7:0]  m0,a0,b0,c0,d0, mb0,dx0,dy0;
    wire [7:0]  m1,a1,b1,c1,d1, mb1,dx1,dy1;

    usb_hid_host u_usb0 (
        .usbclk(clk12), .usbrst_n(rst12_n),
        .usb_dm(usb1_dn), .usb_dp(usb1_dp),
        .typ(t0), .report(r0), .conerr(),
        .key_modifiers(m0), .key1(a0), .key2(b0), .key3(c0), .key4(d0),
        .mouse_btn(mb0), .mouse_dx(dx0), .mouse_dy(dy0),
        .game_snes(), .game_l(), .game_r(), .game_u(), .game_d(),
        .game_a(), .game_b(), .game_x(), .game_y(), .game_sel(), .game_sta(),
        .game_lb(), .game_rb(), .dbg_hid_report()
    );
    usb_hid_host u_usb1 (
        .usbclk(clk12), .usbrst_n(rst12_n),
        .usb_dm(usb2_dn), .usb_dp(usb2_dp),
        .typ(t1), .report(r1), .conerr(),
        .key_modifiers(m1), .key1(a1), .key2(b1), .key3(c1), .key4(d1),
        .mouse_btn(mb1), .mouse_dx(dx1), .mouse_dy(dy1),
        .game_snes(), .game_l(), .game_r(), .game_u(), .game_d(),
        .game_a(), .game_b(), .game_x(), .game_y(), .game_sel(), .game_sta(),
        .game_lb(), .game_rb(), .dbg_hid_report()
    );

    falcon_hid_ahb_core #(.RING_BASE(RING_BASE), .HEAD_ADDR(HEAD_ADDR)) u_core (
        .clk12(clk12), .rst12(rst12),
        .p0_report(r0), .p0_typ(t0),
        .p0_mod(m0), .p0_k1(a0), .p0_k2(b0), .p0_k3(c0), .p0_k4(d0),
        .p0_mbtn(mb0), .p0_mdx(dx0), .p0_mdy(dy0),
        .p1_report(r1), .p1_typ(t1),
        .p1_mod(m1), .p1_k1(a1), .p1_k2(b1), .p1_k3(c1), .p1_k4(d1),
        .p1_mbtn(mb1), .p1_mdx(dx1), .p1_mdy(dy1),
        .hclk(hclk), .hresetn(hresetn),
        .haddr(haddr), .hburst(hburst), .hprot(hprot), .hsel(hsel),
        .hsize(hsize), .htrans(htrans), .hwdata(hwdata), .hwrite(hwrite),
        .hrdata(hrdata), .hreadyout(hreadyout), .hresp(hresp),
        .err_count(err_count)
    );
endmodule
