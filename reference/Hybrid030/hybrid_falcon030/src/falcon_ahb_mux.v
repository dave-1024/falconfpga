// =====================================================================
// falcon_ahb_mux.v  --  REV11b: burst-atomic two-master AHB mux
//
// HID (priority) and the timebase publisher share the SoC's Extended
// AHB Master port. REV11's version wedged the port on silicon inside
// the first ~5 ms of every boot; the post-mortem found two protocol
// faults, both fixed here:
//
//   1. MID-BURST RELEASE (the wedge): REV11 released the timebase
//      grant on `hid_active && hreadyout` -- the very edge on which
//      the slave accepts the timebase's address phase. The slave was
//      then owed a data phase that arrived from HID's bus instead,
//      and under real DDR3 wait-states this hand-off wedged the port
//      permanently (bug-ledger family: "never completes"). That
//      release was itself the ledger-#9 starvation FIX overcorrecting:
//      the edge-triggered entry alone was the fix; releasing mid-burst
//      re-opened the hazard. REV11b: the grant is BURST-ATOMIC --
//      once given, it is released ONLY when the publisher drops its
//      request (`!t_busy`, i.e. burst complete or watchdog abort).
//      HID priority is enforced purely at ENTRY: no grant while HID
//      is active. Entry is level-triggered (the request is held), so
//      the edge-detect is gone too.
//
//   2. FORCED READY=1 TO THE PARKED MASTER (the free-run): REV11 fed
//      the ungranted master a constant hreadyout=1 "so it never
//      stalls". A master mid-FSM interprets ready=1 as beat completion
//      and marches on -- the REV11 publisher completed whole bursts
//      into the void, and HID could lose a transfer begun during a
//      grant window. REV11b: the parked side sees hreadyout=0. An
//      idle master ignores it; a master that starts a transfer simply
//      HOLDS its address phase (per AHB) until the port is its again.
//      Nothing is ever silently completed or lost.
//
// STALL BOUND: HID can now be stalled for one timebase burst. The
// publisher's whole-burst watchdog (WD_MAX=512) bounds the grant hold
// to ~514 cycles, under HID's own 1023-cycle transfer watchdog with
// ~2x margin -- a stalled HID transfer waits, completes, and never
// spuriously aborts. Worst case is ~10.3 us once per millisecond.
//
// The timebase publisher is REV11b's grant-gated version: it cannot
// drive the bus, or advance a beat, without `t_gnt`. Defense in depth:
// even a buggy requester cannot free-run against ready=0.
// =====================================================================
module falcon_ahb_mux (
    input  wire        hclk,
    input  wire        hresetn,

    // HID master (priority)
    input  wire [31:0] h_haddr,
    input  wire [2:0]  h_hburst,
    input  wire [3:0]  h_hprot,
    input  wire        h_hsel,
    input  wire [2:0]  h_hsize,
    input  wire [1:0]  h_htrans,
    input  wire [63:0] h_hwdata,
    input  wire        h_hwrite,

    // Timebase master
    input  wire [31:0] t_haddr,
    input  wire [2:0]  t_hburst,
    input  wire [3:0]  t_hprot,
    input  wire        t_hsel,
    input  wire [2:0]  t_hsize,
    input  wire [1:0]  t_htrans,
    input  wire [63:0] t_hwdata,
    input  wire        t_hwrite,
    input  wire        t_busy,        // held REQUEST from the publisher
    output wire        t_gnt,         // REV11b: grant back to publisher

    // Muxed port (to SoC Extended AHB slave)
    output wire [31:0] haddr,
    output wire [2:0]  hburst,
    output wire [3:0]  hprot,
    output wire        hsel,
    output wire [2:0]  hsize,
    output wire [1:0]  htrans,
    output wire [63:0] hwdata,
    output wire        hwrite,
    input  wire        hreadyout,
    input  wire        hresp,

    // fan-back
    output wire        h_hreadyout,
    output wire        h_hresp,
    output wire        t_hreadyout,
    output wire        t_hresp
);
    localparam [1:0] TRANS_IDLE = 2'b00;

    wire hid_active = h_hsel || (h_htrans != TRANS_IDLE);

    // REV11b tear guard (found by tb_mux_atomic on first run): during
    // HID's DATA phase h_hsel=0/htrans=IDLE, so hid_active alone reads
    // "idle" while the slave still owes HID a beat -- granting there
    // switches the bus mid-transfer. Track the outstanding data phase
    // and refuse entry until it drains.
    reg h_pend;
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) h_pend <= 1'b0;
        else if (!tb_grant) begin
            if (h_hsel && (h_htrans == 2'b10) && hreadyout) h_pend <= 1'b1;
            else if (h_pend && hreadyout)                   h_pend <= 1'b0;
        end
    end
    wire hid_busy = hid_active || h_pend;

    reg tb_grant;
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) tb_grant <= 1'b0;
        else if (tb_grant) begin
            // BURST-ATOMIC: release only when the request drops.
            if (!t_busy) tb_grant <= 1'b0;
        end else begin
            // HID priority at entry; request is held, so level entry
            // is starvation-free in both directions.
            if (t_busy && !hid_busy) tb_grant <= 1'b1;
        end
    end
    assign t_gnt = tb_grant;

    assign haddr   = tb_grant ? t_haddr   : h_haddr;
    assign hburst  = tb_grant ? t_hburst  : h_hburst;
    assign hprot   = tb_grant ? t_hprot   : h_hprot;
    assign hsel    = tb_grant ? t_hsel    : h_hsel;
    assign hsize   = tb_grant ? t_hsize   : h_hsize;
    assign htrans  = tb_grant ? t_htrans  : h_htrans;
    assign hwdata  = tb_grant ? t_hwdata  : h_hwdata;
    assign hwrite  = tb_grant ? t_hwrite  : h_hwrite;

    // The ACTIVE master sees the real port; the PARKED master sees
    // ready=0 and simply waits. Never forced-1: a parked master must
    // not be told its (nonexistent or held) beat completed.
    assign h_hreadyout = tb_grant ? 1'b0 : hreadyout;
    assign h_hresp     = tb_grant ? 1'b0 : hresp;
    assign t_hreadyout = tb_grant ? hreadyout : 1'b0;
    assign t_hresp     = tb_grant ? hresp     : 1'b0;
endmodule
