`include "defs.vh"
// alive.v: minimal board check (no PLL, no DCE): raw 50 MHz clk on V22, "ALIVE n" CR LF at 115200 on U15
// every 0.5 s, LEDs G11/U12 blink alternately. Option PLL=1 adds one PLL + PLL_INIT and reports "PLL l" (lock).
module top (input clk, output uart_ext_tx, output [1:0] leds_n);
    reg [24:0] t = 0; reg [15:0] cnt = 0; reg go = 0;
    always @(posedge clk) begin go <= 0; if (t == 25'd24_999_999) begin t <= 0; cnt <= cnt + 1; go <= 1; end else t <= t + 1; end
    assign leds_n = cnt[0] ? 2'b10 : 2'b01;
`ifdef WITH_PLL
    wire c0, plock;
    gowin_pll_hdmi u_pll (.clkin(clk), .init_clk(clk), .clkout0(c0), .lock(plock));
    reg [1:0] ls = 0; always @(posedge clk) ls <= {ls[0], plock};
    wire [7:0] tag3 = ls[1] ? "1" : "0";
`else
    wire [7:0] tag3 = " ";
`endif
    function [7:0] hx(input [3:0] v); hx = v < 10 ? 8'h30 + v : 8'h37 + v; endfunction
    reg [3:0] ci = 15; reg [7:0] ch;
    always @(*) case (ci)
        0: ch = "A"; 1: ch = "L"; 2: ch = "I"; 3: ch = "V"; 4: ch = "E"; 5: ch = " ";
        6: ch = hx(cnt[15:12]); 7: ch = hx(cnt[11:8]); 8: ch = hx(cnt[7:4]); 9: ch = hx(cnt[3:0]);
        10: ch = " "; 11: ch = tag3; 12: ch = 8'h0D; default: ch = 8'h0A; endcase
    reg [8:0] div = 0; reg [3:0] nb = 0; reg [9:0] sh = 10'h3FF; reg txr = 1;
    assign uart_ext_tx = txr;
    always @(posedge clk) begin
        if (nb != 0) begin
            if (div != 9'd433) div <= div + 1; else begin div <= 0; txr <= sh[0]; sh <= {1'b1, sh[9:1]}; nb <= nb - 1; end
        end else if (ci != 15) begin sh <= {1'b1, ch, 1'b0}; nb <= 10; div <= 0; ci <= (ci == 13) ? 15 : ci + 1; end
        else begin txr <= 1; if (go) ci <= 0; end
    end
endmodule
