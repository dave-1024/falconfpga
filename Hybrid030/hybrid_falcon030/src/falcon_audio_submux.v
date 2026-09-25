// =====================================================================
// falcon_audio_submux.v -- REV13: 2:1 burst-atomic sub-mux
//
// Lets the timebase publisher (child A, priority) and the audio fetch
// engine (child B) share the single low-priority port of the REV11b
// falcon_ahb_mux, which stays BYTE-UNTOUCHED -- the module that fixed
// the REV11 silicon wedge is composed around, never edited.
//
// Both children are REV11b-style grant-gated masters (busy = held
// request, cannot drive or advance without gnt), which makes this mux
// strictly simpler than the HID one: there is no un-gated master, so
// no tear guard is needed -- an ungranted child is idle by
// construction and never has an outstanding data phase.
//
// Discipline cloned from falcon_ahb_mux:
//   - BURST-ATOMIC: a child grant is released only when that child
//     drops its request (job complete or watchdog abort)
//   - priority (timebase) enforced at ENTRY only; entry is
//     level-triggered on the held request, starvation-free both ways
//   - the parked child sees gnt=0 AND hreadyout=0 -- never forced-1
//   - upstream: busy_out = granted child's busy, so the top mux's
//     burst-atomic grant covers exactly one child job; between jobs
//     busy_out drops and HID re-arbitrates. The HID stall bound is
//     UNCHANGED: one child job <= WD_MAX+4 ~= 516 < HID's 1023.
//   - a child only receives gnt when BOTH this mux selected it AND the
//     upstream grant is in (sel & up_gnt), so neither child can ever
//     drive an ungranted upstream port.
// =====================================================================
module falcon_audio_submux (
    input  wire        hclk,
    input  wire        hresetn,

    // child A: timebase publisher (priority)
    input  wire [31:0] a_haddr,
    input  wire [2:0]  a_hburst,
    input  wire [3:0]  a_hprot,
    input  wire        a_hsel,
    input  wire [2:0]  a_hsize,
    input  wire [1:0]  a_htrans,
    input  wire [63:0] a_hwdata,
    input  wire        a_hwrite,
    input  wire        a_busy,
    output wire        a_gnt,
    output wire        a_hreadyout,
    output wire        a_hresp,

    // child B: audio fetch engine
    input  wire [31:0] b_haddr,
    input  wire [2:0]  b_hburst,
    input  wire [3:0]  b_hprot,
    input  wire        b_hsel,
    input  wire [2:0]  b_hsize,
    input  wire [1:0]  b_htrans,
    input  wire [63:0] b_hwdata,
    input  wire        b_hwrite,
    input  wire        b_busy,
    output wire        b_gnt,
    output wire        b_hreadyout,
    output wire        b_hresp,

    // upstream: presents ONE master to falcon_ahb_mux's t-port
    output wire [31:0] t_haddr,
    output wire [2:0]  t_hburst,
    output wire [3:0]  t_hprot,
    output wire        t_hsel,
    output wire [2:0]  t_hsize,
    output wire [1:0]  t_htrans,
    output wire [63:0] t_hwdata,
    output wire        t_hwrite,
    output wire        t_busy,
    input  wire        t_gnt,
    input  wire        t_hreadyout,
    input  wire        t_hresp
);
    // 00 = none, 01 = A, 10 = B
    reg [1:0] sel;
    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) sel <= 2'b00;
        else case (sel)
            2'b01:   if (!a_busy) sel <= 2'b00;   // burst-atomic release
            2'b10:   if (!b_busy) sel <= 2'b00;
            default: begin
                if      (a_busy) sel <= 2'b01;    // priority at entry
                else if (b_busy) sel <= 2'b10;
            end
        endcase
    end

    wire sa = (sel == 2'b01);
    wire sb = (sel == 2'b10);

    assign t_busy   = (sa & a_busy) | (sb & b_busy);

    assign t_haddr  = sb ? b_haddr  : a_haddr;
    assign t_hburst = sb ? b_hburst : a_hburst;
    assign t_hprot  = sb ? b_hprot  : a_hprot;
    assign t_hsel   = sa ? a_hsel   : sb ? b_hsel   : 1'b0;
    assign t_hsize  = sb ? b_hsize  : a_hsize;
    assign t_htrans = sa ? a_htrans : sb ? b_htrans : 2'b00;
    assign t_hwdata = sb ? b_hwdata : a_hwdata;
    assign t_hwrite = sa ? a_hwrite : sb ? b_hwrite : 1'b0;

    // grant + ready fan-back: only the selected child, only under the
    // upstream grant; the parked child sees 0/0 (never forced-1).
    assign a_gnt       = sa & t_gnt;
    assign b_gnt       = sb & t_gnt;
    assign a_hreadyout = (sa & t_gnt) ? t_hreadyout : 1'b0;
    assign b_hreadyout = (sb & t_gnt) ? t_hreadyout : 1'b0;
    assign a_hresp     = (sa & t_gnt) ? t_hresp     : 1'b0;
    assign b_hresp     = (sb & t_gnt) ? t_hresp     : 1'b0;
endmodule
