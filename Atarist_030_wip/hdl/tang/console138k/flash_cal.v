// ===========================================================================
// flash_cal.v - [F85] ST_HELPER TOS flash reader (dual-I/O 0xBB continuous read, same protocol and states as
// console60k/flash_dspi.v) with a measured, self-calibrated sample point.
// The flash pads are not timed by STA (clock through a LUT, SCK at 100 MHz / 22.5 deg, flash tCLQV, board traces),
// so the right sample instant depends on placement. Here each pad goes through a Gowin IDDR (in the IOB): Q0 = rising
// edge sample, Q1 = the falling edge 5 ns later. Sample point p = 0..7: latch offset o = p[2:1] clocks, edge p[0];
// p+1 is 5 ns later than p. After init (the ST is held in reset until `ready`), every p reads the TOS slot
// (SCAN_WORDS words from scan_base) and gets a CRC32 plus the first word. A one-clock shift still reads stable data
// (the neighbouring bit pair), so a CRC match alone cannot pick the alignment: a point is valid only if words 0..2
// look like a TOS/EmuTOS header (BRA $60xx, version word <= $04xx, reset PC high word $00E0 or $00FC), and among valid points the one whose neighbours give the same CRC (centre of the eye) wins (none: DEF_P). With REPORT, one line on `rtx` (U15):
//   "FCAL c0 c1 c2 c3 c4 c5 c6 c7 S=p" + CRLF   (c = CRC32 per sample point, hex)
// ===========================================================================
module flash_cal #(
    parameter integer SCAN_WORDS = 131072,       // 256 KB
    parameter [2:0]   DEF_P      = 3'd0,          // = F79's fixed point (pad sample at state 25)
    parameter integer REPORT     = 0,
    parameter integer CLK_HZ     = 100_000_000,
    parameter integer BAUD       = 115_200
)(
    input             clk,
    input             resetn,
    output            ready,
    input  [21:0]     scan_base,                 // word address of the TOS slot the ST will read (rom_addr 0)
    input  [21:0]     address,
    input             cs,
    output reg [15:0] dout,
    output reg        mspi_cs,
    output [1:0]      mspi_io_o,
    output [1:0]      mspi_io_oe,
    input  [1:0]      mspi_io_i,
    output reg        busy,
    output reg        rown = 1'b0,               // report owns U15
    output reg        rtx  = 1'b1
);
    reg dspi_mode;
    reg [5:0] state;
    reg [4:0] init;
    wire [7:0] CMD_RD_DIO = 8'hbb;
    wire [7:0] M = 8'b0010_0000;
    // ---- sample point ----
    wire [1:0] q0, q1;
    IDDR u_iddr0 ( .D(mspi_io_i[0]), .CLK(clk), .Q0(q0[0]), .Q1(q1[0]) );
    IDDR u_iddr1 ( .D(mspi_io_i[1]), .CLK(clk), .Q0(q0[1]), .Q1(q1[1]) );
    reg [2:0] p = DEF_P;
    wire [1:0] o = p[2:1];
    wire [1:0] din = p[0] ? q1 : q0;
    // ---- request mux: calibration scan first, then the chipset ----
    reg        cal_done = 1'b0;
    reg        s_req = 1'b0;
    reg [21:0] s_adr = 22'd0;
    wire [21:0] adr = cal_done ? address : s_adr;
    assign ready = (init == 5'd0) & cal_done;
    wire init_done = (init == 5'd0);
    wire spi_di = (init>1)?1'b1:CMD_RD_DIO[3'd7-state[2:0]];
    wire [1:0] dspi_out =
          (state== 6'd8)?{2'b01}:
          (state== 6'd9)?adr[20:19]: (state==6'd10)?adr[18:17]: (state==6'd11)?adr[16:15]:
          (state==6'd12)?adr[14:13]: (state==6'd13)?adr[12:11]: (state==6'd14)?adr[10:9]:
          (state==6'd15)?adr[8:7]:   (state==6'd16)?adr[6:5]:   (state==6'd17)?adr[4:3]:
          (state==6'd18)?adr[2:1]:   (state==6'd19)?{adr[0],1'b0}:
          (state==6'd20)?M[7:6]: (state==6'd21)?M[5:4]: (state==6'd22)?M[3:2]: (state==6'd23)?M[1:0]: 2'b00;
    assign mspi_io_oe = { dspi_mode?(state<=6'd22):1'b0, dspi_mode?(state<=6'd22):1'b1 };
    assign mspi_io_o  = { dspi_mode?dspi_out[1]:1'b0, dspi_mode?dspi_out[0]:spi_di };
    // latch states: base 27 (= F79's 26 + 1 for the IDDR's extra stage), + o
    reg  [5:0] l0r = 6'd27; reg [2:0] dc = 3'd0;
    always @(posedge clk) l0r <= 6'd27 + {4'd0, o};   // p only changes between reads
    reg csD, csD2;
    reg done_stb;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            dspi_mode <= 1'b0; mspi_cs <= 1'b1; dc <= 3'd0; busy <= 1'b0; init <= 5'd20; csD <= 1'b0; csD2 <= 1'b0;
            state <= 6'd0; done_stb <= 1'b0;
        end else begin
            done_stb <= 1'b0;
            csD <= cal_done ? cs : s_req; csD2 <= csD;
            if (init != 5'd0) begin
                if (init == 5'd20) mspi_cs <= 1'b0;
                if (init == 5'd4)  mspi_cs <= 1'b1;
                if (init != 5'd1 || !busy) init <= init - 5'd1;
            end
            if ((csD && !csD2 && !busy) || (init == 5'd2)) begin
                mspi_cs <= 1'b0; busy <= 1'b1;
                state <= dspi_mode ? 6'd8 : 6'd0;
            end
            if (busy) begin
                state <= state + 6'd1;
                if (state == 6'd7) dspi_mode <= 1'b1;
                // 8 bit pairs from state l0r on, shifted in MSB first (no per-pair compares against a variable state)
                if (state == l0r) begin dc <= 3'd7; dout <= {dout[13:0], din}; end
                else if (dc != 3'd0) begin
                    dc <= dc - 3'd1; dout <= {dout[13:0], din};
                    if (dc == 3'd1) begin state <= 6'd0; busy <= 1'b0; done_stb <= 1'b1; end
                end
                if (state == 6'd33) mspi_cs <= 1'b1;   // one SCK after the last data bit (flash_dspi: 32)
            end
        end
    end
    // ---- calibration scan ----
    // [F91] eight explicit registers (the array version read back the same value for every point on the board)
    reg [31:0] c0r=0, c1r=0, c2r=0, c3r=0, c4r=0, c5r=0, c6r=0, c7r=0;
    reg [15:0] f0=0, f1=0, f2=0, f3=0, f4=0, f5=0, f6=0, f7=0;   // first word read at each point
    function [31:0] crcsel(input [2:0] i); case (i) 0: crcsel=c0r; 1: crcsel=c1r; 2: crcsel=c2r; 3: crcsel=c3r;
        4: crcsel=c4r; 5: crcsel=c5r; 6: crcsel=c6r; default: crcsel=c7r; endcase endfunction
    function [15:0] fsel(input [2:0] i); case (i) 0: fsel=f0; 1: fsel=f1; 2: fsel=f2; 3: fsel=f3;
        4: fsel=f4; 5: fsel=f5; 6: fsel=f6; default: fsel=f7; endcase endfunction
    reg [31:0] c = 32'hFFFFFFFF;
    reg [16:0] w = 0;
    reg [15:0] sh = 0; reg [4:0] nb = 0;
    reg [3:0]  cs_st = 0;   // 0 wait init, 1 issue, 2 wait, 3 crc bits, 4 next, 5 pick, 6 report, 7 done
    reg [2:0]  pp = 0;
    reg [7:0]  ok = 0;
    reg [3:0]  k = 0; reg [1:0] best_sc = 0; reg [2:0] best_p = 0;
    wire [2:0] kp = k[2:0];
    reg [31:0] cm, cl, ch_; reg okm, okl, okh; reg eql, eqh; reg [1:0] ph = 0;
    wire [1:0] sc = okm ? 2'd1 + eql + eqh : 2'd0;
    reg        rep_go = 1'b0;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin cal_done <= 1'b0; cs_st <= 0; s_req <= 1'b0; pp <= 0; p <= 3'd0; rep_go <= 1'b0; end
        else case (cs_st)
            0: if (init_done) begin pp <= 0; p <= 3'd0; w <= 0; c <= 32'hFFFFFFFF; cs_st <= 1; end
            1: begin s_adr <= scan_base + {5'd0, w}; s_req <= 1'b1; cs_st <= 2; end
            2: if (done_stb) begin s_req <= 1'b0; sh <= dout; nb <= 5'd16; cs_st <= 3; 
                   if (w == 0) begin ok[pp] <= (dout[15:8] == 8'h60);
                       case (pp) 0: f0 <= dout; 1: f1 <= dout; 2: f2 <= dout; 3: f3 <= dout; 4: f4 <= dout; 5: f5 <= dout; 6: f6 <= dout; default: f7 <= dout; endcase end
                   if (w == 1 && dout[15:8] > 8'h04) ok[pp] <= 1'b0;
                   if (w == 2 && dout != 16'h00E0 && dout != 16'h00FC) ok[pp] <= 1'b0; end
            3: if (nb != 0) begin
                   c <= (c[31] ^ sh[15]) ? {c[30:0], 1'b0} ^ 32'h04C11DB7 : {c[30:0], 1'b0};
                   sh <= {sh[14:0], 1'b0}; nb <= nb - 1'b1;
               end else if (w == SCAN_WORDS - 1) begin
                   case (pp) 0: c0r <= c; 1: c1r <= c; 2: c2r <= c; 3: c3r <= c; 4: c4r <= c; 5: c5r <= c; 6: c6r <= c; default: c7r <= c; endcase c <= 32'hFFFFFFFF; w <= 0;
                   if (pp == 3'd7) begin k <= 0; ph <= 0; best_sc <= 0; best_p <= DEF_P; cs_st <= 5; end
                   else begin pp <= pp + 1'b1; p <= pp + 1'b1; cs_st <= 1; end
               end else begin w <= w + 1'b1; cs_st <= 1; end
            5: begin   // k = 0..7, 3 clocks each: fetch, compare, score (pipelined for 100 MHz)
                   ph <= ph + 1'b1;
                   if (ph == 2'd0) begin
                       cm <= crcsel(kp); cl <= crcsel(kp - 1'b1); ch_ <= crcsel(kp + 1'b1);
                       okm <= ok[kp]; okl <= (kp != 3'd0) && ok[kp - 1'b1]; okh <= (kp != 3'd7) && ok[kp + 1'b1];
                   end else if (ph == 2'd1) begin
                       eql <= okl && (cm == cl); eqh <= okh && (cm == ch_);
                   end else begin
                       ph <= 2'd0;
                       if (sc > best_sc) begin best_sc <= sc; best_p <= kp; end
                       if (k == 4'd7) cs_st <= 6; else k <= k + 1'b1;
                   end
               end
            6: begin p <= best_p; rep_go <= (REPORT != 0); cal_done <= 1'b1; cs_st <= 7; end
            default: rep_go <= 1'b0;
        endcase
    end
    // ---- report ----
    localparam integer DIV = CLK_HZ / BAUD;
    function [7:0] hx(input [3:0] v); hx = (v < 10) ? 8'h30 + v : 8'h37 + v; endfunction
    // character sequence: "FCAL " , 8 x (8 hex + ' '/'+'), "S=" p, CRLF; seg/j/n counters, char registered
    reg [2:0] seg = 0;    // 0 "FCAL ", 1 crc digits, 2 "S=p", 3 CRLF
    reg [2:0] j = 0; reg [3:0] n = 0; reg [15:0] bd = 0; reg [3:0] bi = 0; reg [7:0] ch = 8'h46; reg [31:0] cj; reg [15:0] fj;
    reg last = 1'b0;
    // [F86] status line while not calibrated, about once a second: "FCS  <cs_st pp init busy state w[15:8]>"
    reg stat = 1'b0; reg [31:0] sw = 0; reg [26:0] tk = 0; reg [1:0] rc = 0;
    wire [31:0] stw = {cs_st, 1'b0, pp, 3'b0, init, busy, 1'b0, state, w[15:8]};
    always @(posedge clk) begin
        cj <= stat ? sw : crcsel(j); fj <= fsel(j);
        tk <= (tk == CLK_HZ - 1) ? 27'd0 : tk + 1'b1;
        case (seg)
            0: ch <= (n==0)?"F":(n==1)?"C":(n==2)?(stat?"S":"A"):(n==3)?(stat?" ":"L"):" ";
            1: ch <= (n == 4'd13) ? (ok[j] ? "+" : " ") : (n == 4'd8) ? "/" : (n > 4'd8) ? hx(fj[15 - 4*(n - 4'd9) -: 4]) : hx(cj[31 - 4*n[2:0] -: 4]);
            2: ch <= (n==0)?"S":(n==1)?"=":(8'h30 + p);
            default: ch <= (n==0) ? 8'h0D : 8'h0A;
        endcase
        last <= (seg == 3'd3) && (n == 4'd1);
        if (!rown) begin
            rtx <= 1'b1;
            if (tk == 0) rc <= rc + 1'b1;
            if (rep_go || (REPORT != 0 && cal_done && tk == 0 && rc == 2'd3)) begin rown <= 1'b1; stat <= 1'b0; seg <= 0; j <= 0; n <= 0; bd <= 0; bi <= 0; end
            else if (REPORT != 0 && !cal_done && resetn && tk == 0) begin rown <= 1'b1; stat <= 1'b1; sw <= stw; seg <= 0; j <= 0; n <= 0; bd <= 0; bi <= 0; end
        end
        else begin
            if (bd == DIV - 1) begin
                bd <= 0;
                if (bi == 4'd9) begin
                    bi <= 0;
                    if (last) rown <= 1'b0;
                    else case (seg)
                        0: if (n == 4'd4) begin seg <= 1; n <= 0; end else n <= n + 1'b1;
                        1: if (n == (stat ? 4'd8 : 4'd13)) begin n <= 0; if (stat) seg <= 3; else if (j == 3'd7) seg <= 2; else j <= j + 1'b1; end else n <= n + 1'b1;
                        2: if (n == 4'd2) begin seg <= 3; n <= 0; end else n <= n + 1'b1;
                        default: n <= n + 1'b1;
                    endcase
                end else bi <= bi + 1'b1;
            end else bd <= bd + 1'b1;
            if (bd == 0) rtx <= (bi == 0) ? 1'b0 : (bi == 9) ? 1'b1 : ch[bi - 1];
        end
    end
endmodule
