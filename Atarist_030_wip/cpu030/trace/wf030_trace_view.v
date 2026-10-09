// wf030_trace_view.v - FalconFPGA diag-trace (debug only, `define WF030_TRACE).
// Holds the wf030_trace_cap ring (4096 x 144) and watch ring (16 x 144) in
// BSRAM (written on clk_cpu, read on the HDMI pixel clock) and, once the
// trace has triggered, replaces the 640x480 picture by a bit dump that the
// HDMI capture can decode (wf030_trace_decode.py). Before the trigger the
// picture is untouched except for an 8x8 square at x 624, y 4:
// yellow = not armed yet, green = armed.
//
// Dump layout: cells 2 px wide, 4 px tall; two 146-cell halves per row at
// x 8 and x 328: [white marker][entry bit 143 .. bit 0][white marker].
//   row 0      calibration (alternating 0/1)
//   row 1      left: {78'b0, frame[7:0], 16'hC0DE, page[5:0], status[47:0]}
//              right: {page[5:0] repeated, 16'h5A5A, status[47:0]} (see code)
//   rows 2-9   watch slots 2k (left) / 2k+1 (right)
//   rows 10-117 ring slots page*216 + 2*(row-10) + half
// The page advances every 120 frames (2 s), 19 pages = all 4096 slots.
module wf030_trace_view #(
    parameter PAGE_FRAMES = 120       // frames per page (sim: 1)
) (
    input  wire         wclk,        // clk_cpu030
    input  wire [353:0] trc,         // from wf030_trace_cap (via the bridge)
    input  wire         clk,         // pixel clock
    input  wire [9:0]   cx,
    input  wire [9:0]   cy,
    input  wire [7:0]   r_in, g_in, b_in,
    output reg  [7:0]   r, g, b
);
    wire         t_we    = trc[353];
    wire [11:0]  t_waddr = trc[352:341];
    wire [143:0] t_wdata = trc[340:197];
    wire         t_wwe   = trc[196];
    wire [3:0]   t_wwaddr= trc[195:192];
    wire [143:0] t_wwdata= trc[191:48];
    wire [47:0]  t_status= trc[47:0];

    // ---- RAMs ----
    reg [143:0] ring  [0:4095];
    reg [143:0] watch [0:15];
    always @(posedge wclk) begin
        if (t_we)  ring[t_waddr]   <= t_wdata;
        if (t_wwe) watch[t_wwaddr] <= t_wwdata;
    end
    reg  [11:0] ra = 12'd0;
    reg  [3:0]  wa = 4'd0;
    reg [143:0] rq = 144'd0, wq = 144'd0;
    always @(posedge clk) begin
        rq <= ring[ra];
        wq <= watch[wa];
    end

    // ---- status into the pixel domain (slow / frozen after the trigger) ----
    reg [47:0] st1 = 48'd0, st = 48'd0;
    always @(posedge clk) begin st1 <= t_status; st <= st1; end
    wire trig  = st[47];
    wire armed = st[46];

    // ---- page / frame counters ----
    reg [7:0] frame = 8'd0;
    reg [6:0] fpage = 7'd0;
    reg [5:0] page  = 6'd0;
    always @(posedge clk) begin
        if (cx == 10'd0 && cy == 10'd0) begin
            frame <= frame + 8'd1;
            if (fpage == PAGE_FRAMES - 1) begin
                fpage <= 7'd0;
                page  <= (page == 6'd18) ? 6'd0 : page + 6'd1;
            end else
                fpage <= fpage + 7'd1;
        end
    end

    // ---- next-line row fetch during the horizontal blank ----
    wire [9:0]  ny   = (cy >= 10'd524) ? 10'd0 : cy + 10'd1;
    wire [7:0]  nrow = ny[9:2];
    wire [12:0] base = page * 13'd216;
    wire [12:0] ridx_l = base + {nrow - 8'd10, 1'b0};
    // left-entry RAM outputs held from 662 (the right read replaces rq from 664)
    reg [143:0] rq_l = 144'd0, wq_l = 144'd0;
    always @(posedge clk) if (cx == 10'd662) begin rq_l <= rq; wq_l <= wq; end
    reg  [143:0] nl = 144'd0, nr = 144'd0, cl = 144'd0, cr = 144'd0;
    reg  [7:0]   crow = 8'd0, nrow_r = 8'd0;
    reg          nbl = 1'b0, nbr = 1'b0, cbl = 1'b0, cbr = 1'b0;
    wire [143:0] w_stat_l = {78'd0, frame, 16'hC0DE, page, st};
    wire [143:0] w_stat_r = {72'd0, page, page, 16'h5A5A, st};
    wire [143:0] w_cal    = {72{2'b01}};
    always @(posedge clk) begin
        case (cx)
        10'd660: begin                      // left entry address
            ra <= ridx_l[11:0];
            wa <= {nrow[2:0] - 3'd2, 1'b0};
            nbl <= (nrow >= 8'd10) && (ridx_l > 13'd4095);
        end
        10'd662: begin                      // right entry address
            ra <= ridx_l[11:0] + 12'd1;
            wa <= {nrow[2:0] - 3'd2, 1'b1};
            nbr <= (nrow >= 8'd10) && (ridx_l + 13'd1 > 13'd4095);
        end
        10'd663: begin                      // left data (ra set at 660, rq valid by 662)
            nl <= (nrow == 8'd0) ? w_cal : (nrow == 8'd1) ? w_stat_l :
                  (nrow < 8'd10) ? wq_l : rq_l;
        end
        10'd666: begin
            nr <= (nrow == 8'd0) ? w_cal : (nrow == 8'd1) ? w_stat_r :
                  (nrow < 8'd10) ? wq : rq;
        end
        10'd790: begin
            cl <= nl; cr <= nr; cbl <= nbl; cbr <= nbr; crow <= nrow;
        end
        default: ;
        endcase
    end

    // ---- pixel ----
    wire       in_l  = (cx >= 10'd8)   && (cx < 10'd300);
    wire       in_r  = (cx >= 10'd328) && (cx < 10'd620);
    wire [9:0] dx    = in_l ? cx - 10'd8 : cx - 10'd328;
    wire [7:0] cel   = dx[8:1];                 // 0..145
    wire       mark  = (cel == 8'd0) || (cel == 8'd145);
    wire [7:0] bi    = 8'd144 - cel;            // cell 1 -> bit 143
    wire       bitv  = in_l ? (cbl ? 1'b0 : cl[bi]) : (cbr ? 1'b0 : cr[bi]);
    wire       table_y = (cy < 10'd472);
    wire       on    = mark | bitv;
    wire       sq    = (cx >= 10'd624) && (cx < 10'd632) && (cy >= 10'd4) && (cy < 10'd12);
    always @* begin
        if (trig) begin
            if (table_y && (in_l || in_r)) begin
                r = on ? 8'hFF : 8'h00; g = r; b = r;
            end else begin
                r = 8'h00; g = 8'h00; b = 8'h60;
            end
        end else if (sq) begin
            r = armed ? 8'h00 : 8'hFF; g = 8'hFF; b = 8'h00;
        end else begin
            r = r_in; g = g_in; b = b_in;
        end
    end
endmodule
