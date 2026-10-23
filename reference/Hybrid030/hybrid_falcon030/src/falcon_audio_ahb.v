// =====================================================================
// falcon_audio_ahb.v -- REV13: audio sample fetcher (AHB READ master)
//
// Fetches 16-bit mono samples from a DDR3 ring the A25 firmware fills,
// through the SoC Extended AHB Master port, into a fabric FIFO drained
// at the I2S frame rate. This is the FIRST fabric READ on this port
// (HID + timebase are write-only), so the whole engine is MAGIC-GATED
// with a graceful fallback: until the firmware-planted MAGIC validates,
// magic_ok stays low and the top keeps the test tone. Firmware dead or
// absent => tone. Reads broken on silicon => tone. Reads work + m13
// publishes => CPU audio replaces the tone. Rollback = bitstream.
//
// Faithful sibling of falcon_timebase_ahb (REV11b, silicon-proven):
//   - identical single-transfer AHB pattern: BURST_SINGLE, SIZE_WORD,
//     NONSEQ address phase then IDLE data phase, one outstanding
//   - identical req/gnt discipline: `busy` doubles as the REQUEST; the
//     FSM cannot drive the bus or advance a beat without `gnt`
//   - identical whole-job watchdog (WD_MAX) bounding the grant hold,
//     so the HID stall bound of the REV11b mux analysis is unchanged
//   - LANE RULE applied to reads: only hrdata[31:0] is trusted, and
//     every address is an even word (addr[2]==0) -- mirror of the
//     measured dead upper write lane; never assume reads differ
//
// Ring protocol (v1, "m13 contract"):
//   AUD_BASE + 0   MAGIC     (written by firmware LAST, after WR_WIDX=0)
//   AUD_BASE + 8   WR_WIDX   uint32, total ring WORDS written
//   AUD_BASE + 64  data ring, RING_WORDS words, one 32-bit word per
//                  8 bytes (low lane), 2 samples/word: sample[15:0]
//                  first, sample[31:16] second (little-endian pairs as
//                  the A25 naturally stores them)
//   Firmware zeroes WR_WIDX, plants MAGIC, then streams: write sample
//   words, CCTL-flush, then update WR_WIDX (flush) -- publish order,
//   like the mailbox. Rate-match is by construction: both ends derive
//   from the same 50 MHz (fs = 50e6/1024), so no read-pointer feedback
//   is needed, only ring slack against CPU jitter.
//
// Job scheduler: a TICK_DIV timer launches at most one short job:
//   no magic (or recheck due) -> read MAGIC (+WR_WIDX on fresh validate)
//   FIFO has room & samples known available -> fetch <= FETCH_MAX words
//   otherwise -> refresh WR_WIDX
// Each job is one grant hold, bounded by WD_MAX. MAGIC is re-checked
// every MAGIC_RECHECK ticks so a dead firmware returns the tone (live
// diagnostic) instead of freezing on stale audio.
// =====================================================================
module falcon_audio_ahb #(
    parameter [31:0] AUD_BASE      = 32'h04F0_0800,
    parameter [31:0] AUD_MAGIC     = 32'hFA1C_A0D1,
    parameter [31:0] RING_WORDS    = 32'd2048,   // power of 2; 2 samples/word
    parameter [31:0] TICK_DIV      = 32'd2048,   // job cadence in hclk cycles
    parameter [15:0] MAGIC_RECHECK = 16'd256,    // ticks between magic audits
    parameter [9:0]  WD_MAX        = 10'd512,
    parameter [3:0]  FETCH_MAX     = 4'd8        // ring words per granted job
)(
    input  wire        hclk,          // 50 MHz AHB_CLK
    input  wire        hresetn,

    // AHB-Lite master (own set; sub-muxed with the timebase at top)
    output reg  [31:0] haddr,
    output reg  [2:0]  hburst,
    output reg  [3:0]  hprot,
    output reg         hsel,
    output reg  [2:0]  hsize,
    output reg  [1:0]  htrans,
    output reg  [63:0] hwdata,        // never driven with data: read-only master
    output reg         hwrite,        // always 0 during transfers
    input  wire [63:0] hrdata,
    input  wire        hreadyout,
    input  wire        hresp,

    input  wire        gnt,           // sub-mux grant
    output wire        busy,          // doubles as bus REQUEST
    output reg  [7:0]  err_count,     // watchdog/hresp aborts

    // sample side (all same 50 MHz domain -- no CDC)
    input  wire        samp_stb,      // 1-clk pulse per I2S frame (fs)
    output reg  signed [15:0] pcm,    // held between frames
    output reg         magic_ok      // live: gates tone-vs-pcm at top
);
    localparam [1:0] TRANS_IDLE = 2'b00, TRANS_NONSEQ = 2'b10;
    localparam [2:0] BURST_SINGLE = 3'b000, SIZE_WORD = 3'b010;
    localparam [3:0] PROT_DATA = 4'b0011;
    localparam [31:0] DATA_BASE = AUD_BASE + 32'd64;

    // ---- job types ---------------------------------------------------
    localparam [1:0] J_MAGIC = 2'd0, J_WIDX = 2'd1, J_FETCH = 2'd2;

    // ---- sample FIFO: 256 x 32-bit ring words ------------------------
    reg [31:0] fmem [0:255];
    reg [7:0]  fwp, frp;
    reg [8:0]  fcnt;                  // 0..256
    wire       f_full_soon = (fcnt > 9'd240);   // room for a whole job
    wire       f_empty     = (fcnt == 9'd0);

    // unpacker: current word + half index; hold-last on underrun
    reg [31:0] cur;
    reg        cur_v, half;

    // ---- ring bookkeeping -------------------------------------------
    reg [31:0] rd_widx;               // ring words consumed (fabric-private)
    reg [31:0] wr_widx_seen;          // last WR_WIDX read
    wire [31:0] avail_words = wr_widx_seen - rd_widx;   // unsigned wrap

    // ---- job scheduler ----------------------------------------------
    reg [31:0] tick;
    reg [15:0] audit;                 // ticks since last magic audit
    reg [1:0]  job;                   // current job type
    reg        fresh_validate;        // this magic job may chain a WIDX read
    reg [3:0]  words_left;            // fetch countdown

    // ---- AHB engine (mirrors falcon_timebase_ahb states) ------------
    // 0 idle, 5 wait-grant, 1 addr drive, 2 wait addr accept,
    // 3 wait data complete
    reg [2:0] st;
    reg [9:0] wd;
    reg [31:0] rd_addr;
    assign busy = (st != 3'd0);

    // exact push condition: mirrors the FSM's J_FETCH capture precisely
    // (watchdog expiry and hresp excluded) so fcnt can never drift on
    // an aborted job
    wire fifo_push = (st == 3'd3) && (wd != WD_MAX) && hreadyout && gnt
                     && !hresp && (job == J_FETCH);

    wire [31:0] ring_off  = rd_widx & (RING_WORDS - 32'd1);
    wire [31:0] fetch_adr = DATA_BASE + {ring_off[28:0], 3'b000}; // *8

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            st <= 3'd0; wd <= 10'd0;
            haddr <= 32'd0; hburst <= BURST_SINGLE; hprot <= PROT_DATA;
            hsel <= 1'b0; hsize <= SIZE_WORD; htrans <= TRANS_IDLE;
            hwdata <= 64'd0; hwrite <= 1'b0;
            err_count <= 8'd0;
            tick <= 32'd0; audit <= 16'd0;
            job <= J_MAGIC; fresh_validate <= 1'b0; words_left <= 4'd0;
            fwp <= 8'd0; frp <= 8'd0; fcnt <= 9'd0;
            cur <= 32'd0; cur_v <= 1'b0; half <= 1'b0;
            rd_widx <= 32'd0; wr_widx_seen <= 32'd0;
            magic_ok <= 1'b0; pcm <= 16'sd0;
        end else begin
            // ---------- sample drain (independent of bus state) -------
            if (!cur_v && !f_empty) begin
                cur   <= fmem[frp];
                frp   <= frp + 8'd1;
                fcnt  <= fcnt - 9'd1 + (fifo_push ? 9'd1 : 9'd0);
                cur_v <= 1'b1;
                half  <= 1'b0;
            end else if (fifo_push) begin
                fcnt <= fcnt + 9'd1;               // push only (no pop)
            end
            if (samp_stb && magic_ok && cur_v) begin
                pcm <= half ? $signed(cur[31:16]) : $signed(cur[15:0]);
                if (half) cur_v <= 1'b0;           // word consumed
                half <= ~half;
            end
            // (no cur_v && samp_stb => underrun: pcm holds last value)

            // ---------- job scheduler ---------------------------------
            if (tick == TICK_DIV - 32'd1) tick <= 32'd0;
            else                          tick <= tick + 32'd1;

            // ---------- AHB engine ------------------------------------
            case (st)
            3'd0: begin
                htrans <= TRANS_IDLE; hsel <= 1'b0; hwrite <= 1'b0;
                wd <= 10'd0;
                if (tick == 32'd0) begin
                    if (audit != 16'hFFFF) audit <= audit + 16'd1;
                    if (!magic_ok || audit >= MAGIC_RECHECK) begin
                        job <= J_MAGIC; fresh_validate <= !magic_ok;
                        audit <= 16'd0;
                        st <= 3'd5;
                    end else if (!f_full_soon && avail_words != 32'd0) begin
                        job <= J_FETCH;
                        words_left <= (avail_words > {28'd0, FETCH_MAX})
                                      ? FETCH_MAX : avail_words[3:0];
                        st <= 3'd5;
                    end else begin
                        job <= J_WIDX;
                        st <= 3'd5;
                    end
                end
            end
            3'd5: begin
                // REQUESTING (busy=1, bus idle). Never drives the port.
                htrans <= TRANS_IDLE; hsel <= 1'b0; hwrite <= 1'b0;
                if (gnt) begin
                    wd <= 10'd0;
                    st <= 3'd1;
                end
            end
            3'd1: begin
                // address phase (granted). READ: hwrite=0, low-lane word.
                haddr  <= (job == J_MAGIC) ? AUD_BASE
                        : (job == J_WIDX)  ? (AUD_BASE + 32'd8)
                        :                    fetch_adr;
                hwrite <= 1'b0;
                hsize  <= SIZE_WORD;
                hburst <= BURST_SINGLE;
                hprot  <= PROT_DATA;
                hsel   <= 1'b1;
                htrans <= TRANS_NONSEQ;
                st <= 3'd2;
            end
            3'd2: begin
                wd <= wd + 10'd1;
                if (wd == WD_MAX) begin
                    htrans <= TRANS_IDLE; hsel <= 1'b0;
                    err_count <= err_count + 8'd1;
                    st <= 3'd0;
                end else if (hreadyout && gnt) begin
                    htrans <= TRANS_IDLE;          // single transfer
                    hsel   <= 1'b0;
                    st <= 3'd3;
                end
            end
            3'd3: begin
                wd <= wd + 10'd1;
                if (wd == WD_MAX) begin
                    htrans <= TRANS_IDLE; hsel <= 1'b0;
                    err_count <= err_count + 8'd1;
                    st <= 3'd0;
                end else if (hreadyout && gnt) begin
                    if (hresp) begin
                        err_count <= err_count + 8'd1;
                        magic_ok  <= (job == J_MAGIC) ? 1'b0 : magic_ok;
                        st <= 3'd0;
                    end else begin
                        // LANE RULE: trust hrdata[31:0] ONLY.
                        case (job)
                        J_MAGIC: begin
                            if (hrdata[31:0] == AUD_MAGIC) begin
                                if (fresh_validate) begin
                                    // chain a WR_WIDX read; on completion
                                    // start at the live head
                                    job <= J_WIDX;
                                    fresh_validate <= 1'b0;
                                    st <= 3'd1;
                                end else begin
                                    magic_ok <= 1'b1;
                                    st <= 3'd0;
                                end
                            end else begin
                                magic_ok <= 1'b0;
                                st <= 3'd0;
                            end
                        end
                        J_WIDX: begin
                            wr_widx_seen <= hrdata[31:0];
                            if (!magic_ok) begin
                                // fresh validate path: begin at live head
                                rd_widx  <= hrdata[31:0];
                                magic_ok <= 1'b1;
                            end
                            st <= 3'd0;
                        end
                        default: begin  // J_FETCH
                            fmem[fwp] <= hrdata[31:0];
                            fwp <= fwp + 8'd1;
                            // fcnt increment handled in drain block above
                            rd_widx <= rd_widx + 32'd1;
                            if (words_left == 4'd1) begin
                                st <= 3'd0;
                            end else begin
                                words_left <= words_left - 4'd1;
                                st <= 3'd1;    // next word, same grant
                            end
                        end
                        endcase
                    end
                end
            end
            default: st <= 3'd0;
            endcase
        end
    end
endmodule
