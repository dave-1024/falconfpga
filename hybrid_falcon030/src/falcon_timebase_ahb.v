// =====================================================================
// falcon_timebase_ahb.v  --  REV11b: timebase + grant-gated AHB engine
//
// Publishes the {MAGIC, tick200, tickvbl, cyc50} snapshot to the slot
// at SLOT_BASE roughly 1000x/s. Two silicon-diagnosed faults of the
// REV11 version are fixed here:
//
// FAULT 1 (arbitration): the REV11 engine had no concept of a grant.
//   When the mux parked it (t_hreadyout forced 1), the FSM free-ran its
//   burst into the void; combined with the mux's mid-burst release this
//   wedged the SoC Extended-AHB port inside the first ~5 ms of every
//   boot, freezing the slot at {MAGIC,0,0,.} (silicon: hz200=0).
//   FIX: req/gnt handshake. `busy` doubles as the REQUEST (asserted
//   from snapshot latch until the burst completes or aborts); the FSM
//   cannot leave WAIT_GNT, and cannot advance a beat, unless `gnt` is
//   high. Ungranted, it idles at htrans=IDLE -- it can never free-run.
//
// FAULT 2 (lane rule): REV11 wrote tick200@+4 and cyc50@+12 -- odd
//   word addresses -- with data in the LOW 32-bit lane. Per the HID
//   master's header (falcon_hid_ahb.v:28), the upper lane of this port
//   was MEASURED DEAD; the silicon-proven write pattern is low-lane
//   data at even word addresses (addr[2]==0) only, which is why HID
//   ring records occupy words +0/+8 of each 16-byte slot. tick200 and
//   cyc50 therefore never landed, mux or no mux.
//   FIX: slot re-laid on even words only -- 32 bytes:
//        +0  MAGIC   +8  tick200   +16 tickvbl   +24 cyc50
//   MAGIC still written LAST. The magic VALUE changes (7B10C0D2) so
//   firmware built for the old layout (m10/m10b/m11b) sees no magic on
//   a REV11b bitstream and falls back cleanly to mcycle; the new
//   layout ships with m10c/m11c. Skew-safe in both directions.
//
// WATCHDOG: WD_MAX cycles for the whole granted burst; on expiry the
//   engine drops the bus, counts err_count, skips this publish, and
//   retries at the next 1 ms tick. WD_MAX=512 also bounds how long the
//   mux may stall HID (grant hold <= ~WD_MAX+4), which must stay under
//   the HID master's own 1023-cycle watchdog: 514 < 1023, margin ~2x.
//   A genuinely wedged port thus degrades to "no hardware timebase +
//   err_count", never to the REV11 absorbing state.
// =====================================================================
module falcon_timebase_ahb #(
    parameter [31:0] SLOT_BASE   = 32'h04F0_0600,
    parameter [31:0] TB_MAGIC    = 32'h7B10_C0D2,  // v2 layout magic
    parameter [31:0] PERIOD_200  = 32'd250000,
    parameter [31:0] PERIOD_VBL  = 32'd833333,
    parameter [31:0] PUBLISH_DIV = 32'd50000,
    parameter [9:0]  WD_MAX      = 10'd512
)(
    input  wire        hclk,          // 50 MHz AHB_CLK
    input  wire        hresetn,

    input  wire        cfg_we,
    input  wire        cfg_sel,
    input  wire [31:0] cfg_val,

    // AHB-Lite master (timebase's own set; muxed with HID at top)
    output reg  [31:0] haddr,
    output reg  [2:0]  hburst,
    output reg  [3:0]  hprot,
    output reg         hsel,
    output reg  [2:0]  hsize,
    output reg  [1:0]  htrans,
    output reg  [63:0] hwdata,
    output reg         hwrite,
    input  wire        hreadyout,
    input  wire        hresp,

    input  wire        gnt,           // REV11b: mux grant
    output wire        busy,          // REV11b: doubles as bus REQUEST
    output reg  [7:0]  err_count      // watchdog aborts
);
    localparam [1:0] TRANS_IDLE = 2'b00, TRANS_NONSEQ = 2'b10;
    localparam [2:0] BURST_SINGLE = 3'b000, SIZE_WORD = 3'b010;
    localparam [3:0] PROT_DATA = 4'b0011;

    wire [31:0] tick200, tickvbl, cyc50;
    wire        snap_stb;

    falcon_timebase #(.PERIOD_200(PERIOD_200), .PERIOD_VBL(PERIOD_VBL),
                      .PUBLISH_DIV(PUBLISH_DIV)) u_tb (
        .clk(hclk), .rstn(hresetn),
        .cfg_we(cfg_we), .cfg_sel(cfg_sel), .cfg_val(cfg_val),
        .tick200(tick200), .tickvbl(tickvbl), .cyc50(cyc50),
        .snap_stb(snap_stb));

    // latched snapshot (frozen when the request is raised; refreshed on
    // every later snap_stb while still WAITING for grant, so a delayed
    // grant publishes fresh values, not millisecond-old ones)
    reg [31:0] s200, svbl, scyc;

    // 0 idle, 5 wait-grant, 1 addr drive, 2 wait addr accept,
    // 3 wait data complete
    reg [2:0] st;
    reg [1:0] widx;          // 0=tick200, 1=vbl, 2=cyc, 3=MAGIC (last)
    reg [9:0] wd;            // whole-burst watchdog
    assign busy = (st != 3'd0);

    function [31:0] wdat;
        input [1:0] i;
        begin
            case (i)
                2'd0: wdat = s200;
                2'd1: wdat = svbl;
                2'd2: wdat = scyc;
                default: wdat = TB_MAGIC;   // MAGIC last
            endcase
        end
    endfunction
    function [31:0] waddr;
        input [1:0] i;
        begin
            // v2 slot: EVEN WORD ADDRESSES ONLY (addr[2]==0), data in
            // the low 32-bit lane -- the silicon-proven write pattern.
            case (i)
                2'd0: waddr = SLOT_BASE + 32'd8;    // tick200
                2'd1: waddr = SLOT_BASE + 32'd16;   // tickvbl
                2'd2: waddr = SLOT_BASE + 32'd24;   // cyc50
                default: waddr = SLOT_BASE;         // MAGIC, written last
            endcase
        end
    endfunction

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            st <= 3'd0; widx <= 2'd0; wd <= 10'd0;
            haddr <= 32'd0; hburst <= BURST_SINGLE; hprot <= PROT_DATA;
            hsel <= 1'b0; hsize <= SIZE_WORD; htrans <= TRANS_IDLE;
            hwdata <= 64'd0; hwrite <= 1'b0;
            s200 <= 0; svbl <= 0; scyc <= 0; err_count <= 8'd0;
        end else begin
            case (st)
            3'd0: begin
                htrans <= TRANS_IDLE; hsel <= 1'b0; hwrite <= 1'b0;
                wd <= 10'd0;
                if (snap_stb) begin
                    s200 <= tick200; svbl <= tickvbl; scyc <= cyc50;
                    widx <= 2'd0;
                    st <= 3'd5;              // raise request, await grant
                end
            end
            3'd5: begin
                // REQUESTING (busy=1, bus idle). Never drives the port.
                htrans <= TRANS_IDLE; hsel <= 1'b0; hwrite <= 1'b0;
                if (snap_stb) begin          // refresh while waiting
                    s200 <= tick200; svbl <= tickvbl; scyc <= cyc50;
                end
                if (gnt) begin
                    wd <= 10'd0;
                    st <= 3'd1;
                end
            end
            3'd1: begin
                // address phase for word widx (granted)
                haddr  <= waddr(widx);
                hwrite <= 1'b1;
                hsize  <= SIZE_WORD;
                hburst <= BURST_SINGLE;
                hprot  <= PROT_DATA;
                hsel   <= 1'b1;
                htrans <= TRANS_NONSEQ;
                st <= 3'd2;
            end
            3'd2: begin
                wd <= wd + 10'd1;
                if (wd == WD_MAX) begin      // slave never ready: abort
                    htrans <= TRANS_IDLE; hsel <= 1'b0; hwrite <= 1'b0;
                    err_count <= err_count + 8'd1;
                    st <= 3'd0;              // drop request; retry in 1 ms
                end else if (hreadyout && gnt) begin
                    // address accepted; present the data phase
                    hwdata <= {32'd0, wdat(widx)};   // LOW lane only
                    htrans <= TRANS_IDLE;            // single transfer
                    hsel   <= 1'b0;
                    st <= 3'd3;
                end
            end
            3'd3: begin
                wd <= wd + 10'd1;
                if (wd == WD_MAX) begin
                    htrans <= TRANS_IDLE; hsel <= 1'b0; hwrite <= 1'b0;
                    err_count <= err_count + 8'd1;
                    st <= 3'd0;
                end else if (hreadyout && gnt) begin
                    if (widx == 2'd3) begin
                        st <= 3'd0;          // all four done; drop request
                    end else begin
                        widx <= widx + 2'd1;
                        st <= 3'd1;
                    end
                end
            end
            default: st <= 3'd0;
            endcase
        end
    end
endmodule
