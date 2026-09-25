// ============================================================================
// falcon_video.v -- FalconFPGA Stage 3 scanout: TOS modes + Falcon 256-colour
//                   Tang Console 138K (GW5AST-138C)
//
// v6.2 (2026-07-16, silicon fix 2): burstcount granularity. Also pads LINE
//   fetches to multiple-of-4 beats (320-wide 1bpp was 10 -- latent, caught
//   by the granularity-aware gate before it reached the bench).
//   Every burst
//   length ever proven on this IP (20/40/160) is a multiple of 4 words;
//   the v6/v6.1 second mailbox sub-burst was 117 -- the first non-multiple
//   ever issued -- and it wedges the read engine at any address, any gap
//   (strip YELLOW at 0x03FFF800 and 0x04F00000). Fetch is now padded to
//   320 words = 2 x 160-beat bursts (the line-fetch workhorse length);
//   parse ignores pad beats 277..319 (dead-DRAM overfetch, harmless).
// v6.1 (2026-07-16, silicon fix). The v6 mailbox issued sub-burst 2's rd_go
//   ONE cycle after sub-burst 1's last data beat -- the only request in this
//   project ever issued without long quiescence, and the only novel lane
//   behaviour v6 exercises before magic validates. On the board it bars out
//   (mailbox never completes) while the identical sources pass in sim with a
//   lane model that happily accepts immediate re-issue. Fix: an S_GAP state
//   idles rd_en/rd_go for 1024 clk_rw cycles (~20us; vblank budget 1.4ms)
//   between sub-bursts, restoring the proven "quiescent -> request" shape.
//   Reproduced + fixed against an adversarial lane model (recovery window +
//   stale-high rd_rdy). The bars screen also gains a 16-line status strip:
//     WHITE  = DDR3 up, no mailbox attempt seen
//     RED    = sub-burst 1 issued; died there (rdy/data/magic)
//     YELLOW = sub-burst 1 completed; died in gap / sub-burst 2
//     GREEN  = all 277 beats parsed but rejected (linebytes guard)
//   Strip renders only while bars do (pre-magic); gated frames unchanged.
// v6 (Stage 3, 2026-07-16). Extends the silicon-verified Stage 2 decode-on-
// fetch scanout with Falcon 8-plane (256-colour) modes. Deltas from v5:
//   * MAILBOX v3: 277 words at MBOX_ADDR (default 0x03FF_F800), new MAGIC
//     0xFA1C0DE6 so a stale bitstream/firmware pairing fails loudly to bars.
//       w0        MAGIC (written LAST by firmware; w0=0 first -> torn drop)
//       w1        fb_base (DDR3 byte address)
//       w2        GEOMETRY word -- EXTENDED:
//                   [3:0]  planes  0=chunky RGB565; 1/2/4/8 = planar depth
//                   [4]    hdbl    horizontal pixel-double (native 320 -> 640)
//                   [5]    vdbl    vertical line-double    (native 200 -> 400)
//                   [19:8] native visible lines (height BEFORE vdbl)   <- NEW
//       w3        linebytes ($FF8210 words-per-line x 2)
//       w4..w19   16 x ST palette ($0RGB, low 12 bits; linear intensity
//                 nibbles -- firmware converts from the STe rRRR encoding)
//       w20       pal_seq (reserved optimisation hook; parsed, unused)
//       w21..w276 256 x Falcon palette, packed {14'b0, R6, G6, B6}
//     The 277 beats are fetched as sub-bursts of <= 160 (160 is the largest
//     silicon-proven burst; the 8-bit burstcount caps at 255 anyway).
//   * FALCON PALETTE: 256 x 18 RAM, written during mailbox parse, read
//     SYNCHRONOUSLY during decode. Both ports are in the clk_rw domain --
//     the decode-on-fetch architecture does all format/palette work on the
//     rw side, so no CDC is involved (the roadmap's dual-clock note predates
//     this architecture). Sync read keeps it inferable as a real SDP BSRAM.
//   * DECODE PIPELINE: S_DEC gains one register stage (641 cycles/line):
//     stage A gathers the pixel and issues the palette read; stage B writes
//     the finished RGB. Output is bit-identical for all v5 modes (gated).
//   * 8->4 CLAMP REMOVED: planes carries 0/1/2/4/8; pshift gains the 8-plane
//     case (words per 16px group: 1->0, 2->1, 4->2, 8->3); the plane gather
//     widens to 8 words / 8-bit index. 1/2/4-plane paths are bit-identical.
//   * ACTIVE REGION from the height field: active = height << vdbl;
//     top = (480 - active)/2. Replaces the V_TOP=40/V_BOT=440 constants,
//     which could not distinguish HIGH (640x400x1, geom 0x01) from the
//     EmuTOS VGA 256-colour mode 320x480x8 (geom 0x18). TC publishes
//     height=480 -> top=0: identical to v5. Heights that would exceed 480
//     clamp to 480 (defensive; firmware only publishes realized geometry).
//   * GUARD: linebytes==0 or >640 invalidates the mailbox (bars) -- the
//     line buffer holds 640 bytes; fail loudly rather than fetch garbage.
//
// Architecture (unchanged from the verified Stage 2 rewrite):
//   * The clk_rw (DDR3 lane) side fetches ONE native source line, then DECODES
//     it -- planar->index->palette or chunky RGB565->888, WITH horizontal
//     doubling already applied -- into a 640-entry, 24-bit "finished RGB"
//     line buffer. All the format/palette/scale logic lives in this one clock
//     domain, in a plain sequential loop (easy to reason about, no CDC).
//   * The clk_pixel side is a TRIVIAL linear reader: for display column hc it
//     reads rgbbuf[row_parity][hc]. No decode, no palette, no per-pixel plane
//     gather in the pixel timing path -- that is where every prior bug lived.
//   * Only FINISHED RGB crosses the clock boundary (a dual-clock RAM, exactly
//     like the hardware-verified Tier-C buffer), plus the proven toggle
//     handshake for control. Palette/mode/stride never cross domains.
//   * Ping-pong parity keys off the DISPLAY ROW, not the native line, so a
//     line-doubled mode (two display rows -> one native line) can never make
//     the displayed buffer collide with the one being filled.
//
// PLANAR FORMAT (ST word-interleaved): per group of 16 px, `planes`
// consecutive BIG-ENDIAN 16-bit words; word p bit (15-k) = plane p of pixel k.
// Pixel index = OR of the plane bits. Index -> palette -> RGB888.
//   planes 1/2/4: ST palette ($0RGB, nibble-replicated to 8 bits/channel)
//   planes 8:     Falcon palette (6 bits/channel, expanded {c6, c6[5:4]})
//
// Lane5 read protocol / arbiter / coherency: unchanged from Tier-C.
// ============================================================================

module falcon_video #(
    parameter [31:0] MBOX_ADDR = 32'h03FF_F800,   // 277 words, 2KB below ST-RAM
    parameter [31:0] MAGIC     = 32'hFA1C_0DE6
)(
    input  wire        clk_pixel,
    input  wire        rst,
    input  wire        clk_rw,
    input  wire        ddr3_init,
    output reg  [31:0] addr_lane5,
    output reg         rd_go_lane5,
    output reg         rd_en_lane5,
    output reg  [7:0]  burstcount_lane5,
    input  wire        rd_rdy_lane5,
    input  wire        rd_valid_lane5,
    input  wire [31:0] rd_data_lane5,
    output wire        de,
    output wire        hsync,
    output wire        vsync,
    output wire [7:0]  vr,
    output wire [7:0]  vg,
    output wire [7:0]  vb,
    output wire        magic_ok_pix,
    input  wire        lane4_req,
    output reg         lane4_gnt
);

    // ----------------------------------------------- 640x480@60 timing ----
    localparam H_ACT = 640, H_FP = 16, H_SY = 96, H_BP = 48, H_TOT = 800;
    localparam V_ACT = 480, V_FP = 10, V_SY = 2,  V_BP = 33, V_TOT = 525;

    reg [9:0] hc = 0, vc = 0;
    always @(posedge clk_pixel) begin
        if (rst) begin hc <= 0; vc <= 0; end
        else if (hc == H_TOT-1) begin
            hc <= 0;
            vc <= (vc == V_TOT-1) ? 10'd0 : vc + 10'd1;
        end else hc <= hc + 10'd1;
    end
    assign de    = (hc < H_ACT) && (vc < V_ACT);
    assign hsync = ~((hc >= H_ACT+H_FP) && (hc < H_ACT+H_FP+H_SY)); // neg pol
    assign vsync = ~((vc >= V_ACT+V_FP) && (vc < V_ACT+V_FP+V_SY)); // neg pol

    // ============================================================ PIXEL ===
    // Geometry from mailbox w2 (latched by the rw side):
    //   [3:0] planes  (0 = chunky truecolor RGB565; 1/2/4/8 = planar depth)
    //   [4]   hdbl    (horizontal pixel-double: native 320 -> 640)
    //   [5]   vdbl    (vertical line-double: native 200 -> 400)
    // plus (v3) the native visible line count from w2[19:8].
    // The pixel side needs only vdbl and the derived active-region bounds,
    // brought across with the same 2-FF sync the mode enum used (all of these
    // change only at a mailbox event during vblank, long before use, so the
    // multi-bit value sync is safe by the same quasi-static argument).
    reg [7:0]  geom_rw   = 8'h10;       // default = TC (planes=0,hdbl=1,vdbl=0)
    reg [11:0] vlines_rw = 12'd480;     // v3: native visible lines (pre-vdbl)
    reg [7:0]  geom_s0 = 8'h10, geom_pix = 8'h10;
    always @(posedge clk_pixel) begin
        geom_s0  <= geom_rw;
        geom_pix <= geom_s0;
    end
    wire [1:0]  vshift_p = geom_pix[5] ? 2'd1 : 2'd0;    // vdbl

    // v3 active region (replaces the V_TOP/V_BOT constants):
    //   active = height << vdbl (clamped to 480); top = (480-active)/2.
    // TC (height 480, vdbl 0) -> rows 0..480, identical to v5.
    // LOW/MED (200,vdbl) and HIGH (400) -> rows 40..440, identical to v5.
    // 320x480x8 (height 480) -> rows 0..480: the case v5 could not express.
    wire [12:0] act_w   = {1'b0, vlines_rw} << (geom_rw[5] ? 1 : 0);
    wire [9:0]  act_cl  = (act_w >= 13'd480) ? 10'd480 : act_w[9:0];
    wire [9:0]  vtop_rw = (10'd480 - act_cl) >> 1;
    wire [9:0]  vbot_rw = vtop_rw + act_cl;
    reg  [9:0]  vtop_s0 = 10'd0,   vtop_pix = 10'd0;
    reg  [9:0]  vbot_s0 = 10'd480, vbot_pix = 10'd480;
    always @(posedge clk_pixel) begin
        vtop_s0 <= vtop_rw; vtop_pix <= vtop_s0;
        vbot_s0 <= vbot_rw; vbot_pix <= vbot_s0;
    end

    // native source line needed by a given display row (content region only)
    function [8:0] nl_of_row; input [9:0] row; begin
        nl_of_row = (row - vtop_pix) >> vshift_p;   // TC: top 0, shift 0 -> row
    end endfunction
    function is_content; input [9:0] row; begin
        is_content = (row >= vtop_pix) && (row < vbot_pix);
    end endfunction

    // ---- requests to the rw domain (Tier-C toggle-handshake pattern) ----
    // values latched at hc==0, toggle flips at hc==4: value is stable ~159ns
    // before any rw synchroniser can sample the edge.
    reg       line_req_tgl = 1'b0;
    reg [8:0] req_line     = 9'd0;      // native source line to fetch
    reg       req_buf      = 1'b0;      // ping-pong buffer = (next display row)&1
    reg       mbox_req_tgl = 1'b0;

    wire [9:0] nextrow   = (vc == V_TOT-1) ? 10'd0 : vc + 10'd1;
    wire       next_cont = is_content(nextrow);

    always @(posedge clk_pixel) begin
        if (rst) begin
            line_req_tgl <= 1'b0; mbox_req_tgl <= 1'b0;
            req_line <= 9'd0; req_buf <= 1'b0;
        end else begin
            if (hc == 10'd0) begin
                req_line <= nl_of_row(nextrow);
                req_buf  <= nextrow[0];
            end
            if (hc == 10'd4) begin
                if (next_cont)     line_req_tgl <= ~line_req_tgl;
                if (vc == V_ACT)   mbox_req_tgl <= ~mbox_req_tgl;
            end
        end
    end

    // ============================================================ RW ======
    // rw-domain synchronisers for the control toggles
    reg [2:0] line_tgl_s = 3'b000, mbox_tgl_s = 3'b000;
    always @(posedge clk_rw) begin
        line_tgl_s <= {line_tgl_s[1:0], line_req_tgl};
        mbox_tgl_s <= {mbox_tgl_s[1:0], mbox_req_tgl};
    end
    wire line_kick = line_tgl_s[2] ^ line_tgl_s[1];
    wire mbox_kick = mbox_tgl_s[2] ^ mbox_tgl_s[1];

    // latched mailbox config (all consumed in the rw domain)
    reg        magic_ok   = 1'b0;
    reg        lb_ok      = 1'b0;       // v3: linebytes sane (nonzero, <=640)
    reg [31:0] fb_base     = 32'd0;
    reg [15:0] linebytes   = 16'd640;
    reg [11:0] pal  [0:15];
    reg [17:0] fpal [0:255];            // v3: Falcon palette {R6,G6,B6}
    integer    pinit;
    initial begin
        for (pinit=0; pinit<16;  pinit=pinit+1) pal[pinit]  = 12'd0;
        for (pinit=0; pinit<256; pinit=pinit+1) fpal[pinit] = 18'd0;
    end

    // Decode parameters derived directly from the published geometry word,
    // not a fixed per-mode table -- so the scanout renders whatever plane
    // count / width the VIDEL registers actually describe. This keeps the
    // four Stage 2 modes bit-identical to the hardware-verified path:
    //   TC       geom 0x10 -> planes 0(chunky), hdbl 1, vdbl 0, height 480
    //   LOW      geom 0x34 -> planes 4,         hdbl 1, vdbl 1, height 200
    //   MED      geom 0x22 -> planes 2,         hdbl 0, vdbl 1, height 200
    //   HIGH     geom 0x01 -> planes 1,         hdbl 0, vdbl 0, height 400
    //   256      geom 0x38 -> planes 8,         hdbl 1, vdbl 1, height 200
    //   256/480  geom 0x18 -> planes 8,         hdbl 1, vdbl 0, height 480
    wire [3:0] planes_f = geom_rw[3:0];
    wire [3:0] planes   = planes_f;          // 0 chunky; 1/2/4/8 planar
    wire       hdbl     = geom_rw[4];
    wire [1:0] pshift   = planes_f[3]        ? 2'd3 :   // 8 planes: *8 words/16px
                          planes_f[2]        ? 2'd2 :   // 4 planes: *4
                          (planes_f == 4'd2) ? 2'd1 :   // 2 planes: *2
                                               2'd0;    // 1 plane:  *1
    // 32-bit lane beats, padded to a multiple of 4: burstcount must stay in
    // the silicon-proven granularity (v6.2 -- only 320-wide 1bpp changes,
    // 10 -> 12 beats; 20/40/80/160 are already multiples). Pad beats land
    // in rawbuf words the decode never reads.
    wire [7:0] line_beats_raw = (linebytes + 16'd3) >> 2;
    wire [7:0] line_beats     = (line_beats_raw + 8'd3) & 8'hFC;

    // raw fetched line (single-clock scratch, combinational multi-read OK)
    reg [31:0] rawbuf [0:159];
    reg [8:0]  beat;                     // widened: v3 mailbox is 277 beats
    reg        fetch_isline;             // 1 = source line, 0 = mailbox
    // ---- REV14: per-scanline ST-palette change list -----------------
    // A raster split IS a mid-frame palette change; one snapshot per
    // frame cannot represent it (measured: Frontier cockpit/viewport,
    // Dizzy flicker). Firmware records (visible line, 16 ST entries)
    // per change; this fetch, chained after the mailbox each frame,
    // loads them; S_PALAPP applies every entry with line <= the line
    // about to be DECODED (req_line, latched at fetch start), so the
    // decode-on-fetch pipeline needs no display-time patching.
    // Magic-gated: absent/garbage region => count 0 => exactly the
    // pre-REV14 single-palette behaviour. S_ABORT is already benign.
    localparam [31:0] CHG_ADDR  = 32'h04F0_5000;  // clear of audio @+4840
    localparam [31:0] CHG_MAGIC = 32'hC010_5717;
    reg        fetch_ischg;              // this fetch is the change list
    reg        chg_pend;                 // chained after mailbox commit
    reg        chg_ok;                   // beat-0 magic verdict
    reg [4:0]  chg_n;                    // parse-time count
    reg [4:0]  chg_count;                // committed count (0..30)
    reg [4:0]  chg_ptr;                  // next entry to apply this frame
    reg [3:0]  pl_i;                     // S_PALAPP load index
    reg [8:0]  req_line_rw;              // req_line latched at fetch start
    reg [8:0]  chg_line [0:29];
    reg [11:0] chg_pal  [0:479];         // entry e, colour c: [e*16+c]
    reg        line_pend, mbox_pend;
    reg [11:0] tmo;

    // v3 mailbox sub-burst bookkeeping (277 beats as bursts of <=160)
    localparam [8:0] MB_WORDS = 9'd277;  // words published/parsed
    localparam [8:0] MB_FETCH = 9'd320;  // words FETCHED: 2 x 160 exactly --
                                         // burstcount must stay in the
                                         // silicon-proven multiple-of-4 set
    localparam [7:0] MB_CHUNK = 8'd160;
    reg [8:0]  mb_rem;
    reg [31:0] mb_next;
    reg [7:0]  sb_len, sb_cnt;
    reg [9:0]  gap_cnt;                  // v6.1 inter-sub-burst quiescence
    reg [1:0]  mb_dbg = 2'd0;            // v6.1 status strip code

    // finished-RGB ping-pong line buffers (the ONLY data crossing to pixel)
    reg [23:0] rgbbuf0 [0:639];
    reg [23:0] rgbbuf1 [0:639];
    reg [9:0]  dcol;                     // decode compute column 0..639
    reg        dbuf;                     // which rgbbuf the decode writes

    // one-cycle decode pipeline (v6): stage A gathers pixel dcol and issues a
    // SYNCHRONOUS falcon-palette read; stage B writes the finished pixel for
    // dcol_w (= previous dcol). Keeps fpal a true sync-read RAM rather than a
    // 256:1 combinational mux, and keeps the gather off the RAM output path.
    reg        dvalid   = 1'b0;          // stage-B data valid
    reg        dlast    = 1'b0;          // stage-A finished column 639
    reg [9:0]  dcol_w   = 10'd0;
    reg [23:0] rgb_np_r = 24'd0;         // registered non-8-plane result
    reg [17:0] fpal_q   = 18'd0;         // falcon palette sync-read output

    // ---- decode helpers ----
    // one source 16-bit big-endian word at word-index w, from the raw line
    function [15:0] src16; input [8:0] w; reg [31:0] v; begin
        v = rawbuf[w[8:1]];
        src16 = w[0] ? {v[23:16], v[31:24]}    // odd word  = high half, swapped
                     : {v[7:0],   v[15:8]};    // even word = low  half, swapped
    end endfunction

    // RGB565 -> RGB888 (bit-replicated), matching the acceptance model
    function [23:0] c565; input [15:0] s; begin
        c565 = { s[15:11], s[15:13],       // R8
                 s[10:5],  s[10:9],         // G8
                 s[4:0],   s[4:2] };        // B8
    end endfunction
    // ST palette entry ($0RGB, 4b/ch) -> RGB888 (nibble-replicated)
    function [23:0] cpal; input [11:0] p; begin
        cpal = { p[11:8], p[11:8], p[7:4], p[7:4], p[3:0], p[3:0] };
    end endfunction

    // combinational decode of the CURRENT compute column (dcol) from rawbuf
    wire [9:0] dx    = hdbl ? {1'b0, dcol[9:1]} : dcol;      // native x
    // planar path: gather up to 8 plane words for dx's 16px group
    wire [8:0] grp   = {4'd0, dx[9:4]};                      // group index
    wire [3:0] pk    = dx[3:0];                              // pixel in group
    wire [8:0] wbase = grp << pshift;                        // first plane word
    wire [15:0] pw0  = src16(wbase + 9'd0);
    wire [15:0] pw1  = src16(wbase + 9'd1);
    wire [15:0] pw2  = src16(wbase + 9'd2);
    wire [15:0] pw3  = src16(wbase + 9'd3);
    wire [15:0] pw4  = src16(wbase + 9'd4);
    wire [15:0] pw5  = src16(wbase + 9'd5);
    wire [15:0] pw6  = src16(wbase + 9'd6);
    wire [15:0] pw7  = src16(wbase + 9'd7);
    wire [7:0] idx8  = { (planes>4'd7) ? pw7[15 - pk] : 1'b0,
                         (planes>4'd6) ? pw6[15 - pk] : 1'b0,
                         (planes>4'd5) ? pw5[15 - pk] : 1'b0,
                         (planes>4'd4) ? pw4[15 - pk] : 1'b0,
                         (planes>4'd3) ? pw3[15 - pk] : 1'b0,
                         (planes>4'd2) ? pw2[15 - pk] : 1'b0,
                         (planes>4'd1) ? pw1[15 - pk] : 1'b0,
                         (planes>4'd0) ? pw0[15 - pk] : 1'b0 };
    wire [23:0] dec_rgb = (planes==4'd0) ? c565(src16({1'b0,dx[8:1],dx[0]}))
                                         : cpal(pal[idx8[3:0]]);
    // NB for TC, src word index == native pixel index dx (each px is one word)

    // stage-B result: 8-plane pixels come from the falcon palette (6->8 bit
    // channel expansion {c6, c6[5:4]}); every other format is the registered
    // stage-A result (bit-identical to the v5 single-cycle decode).
    wire [23:0] f_rgb     = { fpal_q[17:12], fpal_q[17:16],
                              fpal_q[11:6],  fpal_q[11:10],
                              fpal_q[5:0],   fpal_q[5:4] };
    wire [23:0] rgb_final = (planes == 4'd8) ? f_rgb : rgb_np_r;

    // ---- lane5 burst + decode engine ----
    localparam S_IDLE=3'd0, S_WAIT=3'd2, S_DATA=3'd3, S_DEC=3'd4, S_ABORT=3'd5,
               S_GAP=3'd6;
    localparam S_PALAPP=3'd1;            // REV14: apply palette changes
    reg [2:0] st = S_IDLE;

    always @(posedge clk_rw) begin
        rd_go_lane5 <= 1'b0;

        if (line_kick) line_pend <= 1'b1;
        if (mbox_kick) mbox_pend <= 1'b1;

        if (!ddr3_init) begin
            st <= S_IDLE; rd_en_lane5 <= 1'b0; magic_ok <= 1'b0;
            line_pend <= 1'b0; mbox_pend <= 1'b0; lane4_gnt <= 1'b0;
            chg_pend <= 1'b0; fetch_ischg <= 1'b0;          // REV14
            chg_count <= 5'd0; chg_ptr <= 5'd0; pl_i <= 4'd0;
            dvalid <= 1'b0; mb_dbg <= 2'd0;
        end else begin
            case (st)
            S_IDLE: begin
                rd_en_lane5 <= 1'b0; beat <= 9'd0; tmo <= 12'd0;
                if (lane4_gnt) begin
                    if (!lane4_req) lane4_gnt <= 1'b0;
                end else if (lane4_req && !mbox_pend && !line_pend) begin
                    lane4_gnt <= 1'b1;
                end else if (mbox_pend) begin
                    mbox_pend    <= 1'b0;
                    fetch_isline <= 1'b0;
                    fetch_ischg  <= 1'b0;                    // REV14
                    addr_lane5       <= MBOX_ADDR;
                    burstcount_lane5 <= MB_CHUNK;          // 277 > 160 always
                    sb_len  <= MB_CHUNK;
                    sb_cnt  <= 8'd0;
                    mb_rem  <= MB_FETCH - {1'b0, MB_CHUNK};
                    mb_next <= MBOX_ADDR + {22'd0, MB_CHUNK, 2'b00};
                    lb_ok   <= 1'b0;
                    mb_dbg  <= 2'd1;
                    rd_go_lane5      <= 1'b1;
                    st <= S_WAIT;
                end else if (chg_pend) begin                 // REV14 fetch
                    chg_pend     <= 1'b0;
                    fetch_isline <= 1'b0;
                    fetch_ischg  <= 1'b1;
                    addr_lane5       <= CHG_ADDR;
                    burstcount_lane5 <= MB_CHUNK;            // 512 = 160*3+32
                    sb_len  <= MB_CHUNK;
                    sb_cnt  <= 8'd0;
                    mb_rem  <= 9'd352;           // = 512 total - 160 first chunk
                    mb_next <= CHG_ADDR + {22'd0, MB_CHUNK, 2'b00};
                    rd_go_lane5      <= 1'b1;
                    st <= S_WAIT;
                end else if (line_pend && magic_ok) begin
                    line_pend    <= 1'b0;
                    fetch_isline <= 1'b1;
                    fetch_ischg  <= 1'b0;                    // REV14
                    req_line_rw  <= req_line;  // REV14: latched in the same
                                               // stability window as addr
                    dbuf         <= req_buf;           // stable (toggle timing)
                    // addr = fb_base + req_line * linebytes
                    addr_lane5       <= fb_base
                                        + ({23'd0, req_line} * {16'd0, linebytes});
                    burstcount_lane5 <= line_beats;
                    rd_go_lane5      <= 1'b1;
                    st <= S_WAIT;
                end else if (line_pend) begin
                    line_pend <= 1'b0;                 // no base yet: drop
                end
            end
            S_WAIT: begin
                tmo <= tmo + 12'd1;
                if (rd_rdy_lane5) begin rd_en_lane5 <= 1'b1; st <= S_DATA; end
                else if (&tmo) st <= S_ABORT;
            end
            S_DATA: begin
                tmo <= tmo + 12'd1;
                if (rd_valid_lane5) begin
                    tmo <= 12'd0;
                    if (fetch_isline) begin
                        rawbuf[beat[7:0]] <= rd_data_lane5;
                        if (beat == {1'b0, line_beats} - 9'd1) begin
                            rd_en_lane5 <= 1'b0;
                            dcol   <= 10'd0;
                            dvalid <= 1'b0;
                            dlast  <= 1'b0;
                            pl_i   <= 4'd0;          // REV14
                            st     <= S_PALAPP;
                        end
                        beat <= beat + 9'd1;
                    end else if (fetch_ischg) begin    // REV14 change list
                        case (beat)
                        9'd0: chg_ok <= (rd_data_lane5 == CHG_MAGIC);
                        9'd1: chg_n  <= (!chg_ok) ? 5'd0
                                      : (rd_data_lane5[31:5] != 27'd0) ? 5'd30
                                      : (rd_data_lane5[4:0] > 5'd30)   ? 5'd30
                                      :  rd_data_lane5[4:0];
                        default:
                            if (beat < 9'd32) begin
                                if (beat <= 9'd31)
                                    chg_line[beat[4:0]-5'd2]
                                        <= rd_data_lane5[8:0];
                            end else
                                chg_pal[beat[8:0]-9'd32]
                                    <= rd_data_lane5[11:0];
                        endcase
                        if (sb_cnt == sb_len - 8'd1) begin // sub-burst done
                            rd_en_lane5 <= 1'b0;
                            if (mb_rem == 9'd0) begin
                                chg_count <= chg_n;    // commit atomically
                                chg_ptr   <= 5'd0;     // frame restart
                                st <= S_IDLE;
                            end else begin
                                addr_lane5       <= mb_next;
                                burstcount_lane5 <= (mb_rem > {1'b0,MB_CHUNK})
                                                    ? MB_CHUNK : mb_rem[7:0];
                                sb_len  <= (mb_rem > {1'b0,MB_CHUNK})
                                           ? MB_CHUNK : mb_rem[7:0];
                                sb_cnt  <= 8'd0;
                                mb_next <= mb_next
                                    + {22'd0, ((mb_rem > {1'b0,MB_CHUNK})
                                               ? MB_CHUNK : mb_rem[7:0]), 2'b00};
                                mb_rem  <= (mb_rem > {1'b0,MB_CHUNK})
                                           ? (mb_rem - {1'b0,MB_CHUNK}) : 9'd0;
                                gap_cnt <= 10'd0;
                                st <= S_GAP;
                            end
                        end else sb_cnt <= sb_cnt + 8'd1;
                        beat <= beat + 9'd1;
                    end else begin                     // v3 mailbox, 277 beats
                        if (beat == 9'd0 && rd_data_lane5 != MAGIC) begin
                            rd_en_lane5 <= 1'b0; st <= S_ABORT;
                        end else begin
                            case (beat)
                            9'd0: ;                    // magic checked above
                            9'd1: fb_base   <= rd_data_lane5;
                            9'd2: begin
                                      geom_rw   <= rd_data_lane5[7:0];
                                      vlines_rw <= rd_data_lane5[19:8];
                                  end
                            9'd3: begin
                                      linebytes <= rd_data_lane5[15:0];
                                      lb_ok <= (rd_data_lane5[15:0] != 16'd0)
                                            && (rd_data_lane5[15:0] <= 16'd640);
                                  end
                            9'd20: ;                   // pal_seq: reserved
                            default:
                                if (beat < 9'd20)
                                     pal [beat[4:0]-5'd4] <= rd_data_lane5[11:0];
                                else if (beat <= 9'd276)   // 277..319 = pad
                                     // 8-bit modular index == beat-21 for all
                                     // real beats; makes sim match hardware
                                     // address truncation so the pad guard
                                     // above is mutation-testable.
                                     fpal[beat[7:0]-8'd21] <= rd_data_lane5[17:0];
                            endcase
                            if (sb_cnt == sb_len - 8'd1) begin // sub-burst done
                                rd_en_lane5 <= 1'b0;
                                if (mb_rem == 9'd0) begin
                                    magic_ok <= lb_ok;   // whole mailbox parsed
                                    mb_dbg   <= 2'd3;
                                    chg_pend <= 1'b1;    // REV14: chain fetch
                                    st <= S_IDLE;
                                end else begin
                                    addr_lane5       <= mb_next;
                                    burstcount_lane5 <= (mb_rem > {1'b0,MB_CHUNK})
                                                        ? MB_CHUNK : mb_rem[7:0];
                                    sb_len  <= (mb_rem > {1'b0,MB_CHUNK})
                                               ? MB_CHUNK : mb_rem[7:0];
                                    sb_cnt  <= 8'd0;
                                    mb_next <= mb_next
                                        + {22'd0, ((mb_rem > {1'b0,MB_CHUNK})
                                                   ? MB_CHUNK : mb_rem[7:0]), 2'b00};
                                    mb_rem  <= (mb_rem > {1'b0,MB_CHUNK})
                                               ? (mb_rem - {1'b0,MB_CHUNK}) : 9'd0;
                                    mb_dbg  <= 2'd2;
                                    gap_cnt <= 10'd0;
                                    st <= S_GAP;         // v6.1: no immediate
                                                         // re-issue on silicon
                                end
                            end else sb_cnt <= sb_cnt + 8'd1;
                            beat <= beat + 9'd1;
                        end
                    end
                end else if (&tmo) st <= S_ABORT;
            end
            S_PALAPP: begin
                // REV14: fold in every change whose line has been reached
                // by the line about to be decoded. Entries line-sorted by
                // contract; typically 0 or 1 per line, 16 cycles each --
                // negligible against the ~20us S_GAP quiescence budget.
                if (chg_ptr < chg_count &&
                    chg_line[chg_ptr] <= req_line_rw) begin
                    pal[pl_i] <= chg_pal[{chg_ptr, 4'b0000} | {5'd0, pl_i}];
                    if (pl_i == 4'd15) begin
                        pl_i    <= 4'd0;
                        chg_ptr <= chg_ptr + 5'd1;
                    end else pl_i <= pl_i + 4'd1;
                end else st <= S_DEC;
            end
            S_DEC: begin
                // stage B: write the previous column's finished pixel
                if (dvalid) begin
                    if (dbuf) rgbbuf1[dcol_w] <= rgb_final;
                    else      rgbbuf0[dcol_w] <= rgb_final;
                    if (dcol_w == 10'd639) st <= S_IDLE;
                end
                // stage A: gather column dcol, issue the palette read
                if (!dlast) begin
                    fpal_q   <= fpal[idx8];
                    rgb_np_r <= dec_rgb;
                    dcol_w   <= dcol;
                    dvalid   <= 1'b1;
                    if (dcol == 10'd639) dlast <= 1'b1;
                    dcol <= dcol + 10'd1;
                end else begin
                    dvalid <= 1'b0;
                end
            end
            S_GAP: begin
                // v6.1: hold the lane fully quiescent between mailbox
                // sub-bursts. Every silicon-proven request in this design was
                // issued from long idle; 1024 cycles (~20us) restores that
                // precondition. Vblank budget is ~1.4ms.
                rd_en_lane5 <= 1'b0;
                gap_cnt <= gap_cnt + 10'd1;
                if (&gap_cnt) begin
                    tmo <= 12'd0;
                    rd_go_lane5 <= 1'b1;
                    st <= S_WAIT;
                end
            end
            S_ABORT: begin rd_en_lane5 <= 1'b0; st <= S_IDLE; end
            default: st <= S_IDLE;
            endcase
        end
    end

    // ================================================== PIXEL READOUT ======
    // trivial linear read of the finished-RGB buffer, with the same latency-2
    // read-ahead alignment the Tier-C design proved on hardware. rgbbuf is
    // read by DISPLAY-ROW parity; the last two pixels of a line look ahead
    // into the next row's buffer (already filled during this line).
    wire [9:0] hfetch = (hc >= H_TOT-2) ? (hc - (H_TOT-2)) : (hc + 10'd2);
    wire       rsel   = (hc >= H_TOT-2)
                        ? ((vc == V_TOT-1) ? 1'b0 : nextrow[0])
                        : vc[0];
    wire [9:0] ra     = (hfetch > 10'd639) ? 10'd639 : hfetch;  // clamp (blank)

    reg [23:0] q1 = 24'd0, q2 = 24'd0;
    always @(posedge clk_pixel) begin
        q1 <= rsel ? rgbbuf1[ra] : rgbbuf0[ra];
        q2 <= q1;
    end

    // status sync
    reg [1:0] magic_s = 2'b00;
    always @(posedge clk_pixel) magic_s <= {magic_s[0], magic_ok};
    assign magic_ok_pix = magic_s[1];

    // v6.1 mailbox status strip (bars screen only): 2-FF value sync of the
    // rw-domain code; changes at ~60Hz events, self-corrects next pixel clock.
    reg [1:0] dbg_s0 = 2'd0, dbg_pix = 2'd0;
    always @(posedge clk_pixel) begin dbg_s0 <= mb_dbg; dbg_pix <= dbg_s0; end
    wire [23:0] dbg_rgb = (dbg_pix==2'd0) ? 24'hFFFFFF :   // no attempt
                          (dbg_pix==2'd1) ? 24'hFF0000 :   // died in burst 1
                          (dbg_pix==2'd2) ? 24'hFFFF00 :   // died in gap/burst 2
                                            24'h00FF00;    // parsed, rejected
    wire dbg_row = (vc < 10'd16);

    // colour bars until firmware validates the mailbox (bring-up aid)
    wire [7:0] bar_r = hc[9:7]==3'd0 ? 8'hFF : hc[9:7]==3'd1 ? 8'hFF :
                       hc[9:7]==3'd2 ? 8'h00 : hc[9:7]==3'd3 ? 8'h00 :
                       hc[9:7]==3'd4 ? 8'hFF : 8'h20;
    wire [7:0] bar_g = hc[9:7]==3'd0 ? 8'hFF : hc[9:7]==3'd1 ? 8'h00 :
                       hc[9:7]==3'd2 ? 8'hFF : hc[9:7]==3'd3 ? 8'h00 :
                       hc[9:7]==3'd4 ? 8'h00 : 8'h20;
    wire [7:0] bar_b = hc[9:7]==3'd0 ? 8'hFF : hc[9:7]==3'd1 ? 8'h00 :
                       hc[9:7]==3'd2 ? 8'h00 : hc[9:7]==3'd3 ? 8'hFF :
                       hc[9:7]==3'd4 ? 8'hFF : 8'h20;

    wire content_now = is_content(vc);

    assign vr = !magic_ok_pix ? (dbg_row ? dbg_rgb[23:16] : bar_r)
                              : (content_now ? q2[23:16] : 8'd0);
    assign vg = !magic_ok_pix ? (dbg_row ? dbg_rgb[15:8]  : bar_g)
                              : (content_now ? q2[15:8]  : 8'd0);
    assign vb = !magic_ok_pix ? (dbg_row ? dbg_rgb[7:0]   : bar_b)
                              : (content_now ? q2[7:0]   : 8'd0);

endmodule