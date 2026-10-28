`timescale 1ns/1ps
module IDDR(output reg Q0, output reg Q1, input D, input CLK);
 reg a,b,c,d,e; initial begin Q0=0;Q1=0;end
 always @(posedge CLK) begin a<=D; b<=a; Q0<=b; d<=e; Q1<=d; end
 always @(negedge CLK) e<=D;
endmodule
// flash model: dual-IO continuous read; data = f(address); output changes TCO after SCK falling edge
module fm #(parameter real TCO=7.0, parameter real SKD=3.0)(input sck_i, input csn, input [1:0] io_o, input [1:0] oe, output [1:0] io_i);
 wire sck; assign #(SKD) sck = sck_i;
 integer n; reg [21:0] a; reg [1:0] q = 0; reg [15:0] dat;
 function [15:0] f(input [21:0] x); f = (x==0) ? 16'h602E : x[15:0]*16'h9E37 ^ (x[15:0]>>3) ^ 16'h5A5A; endfunction
 always @(negedge csn) n = 0;
 // 8 cmd clocks first time only handled by host; host in dspi mode sends from state 8: 12 addr clocks + 4 M clocks, then 8 data clocks
 reg dsp=0; integer base;
 always @(posedge sck) if (!csn) begin
   if (!dsp) begin n=n+1; if (n==8) begin dsp=1; n=0; end end
   else begin
     if (n<12) a = {a[19:0], io_o};
     n=n+1;
   end
 end
 always @(negedge sck) if (!csn && dsp && n>=16 && n<24) begin
   dat = f({a[20:0],1'b0}>>1); q <= #(TCO) dat[15-2*(n-16) -: 2];
 end
 assign #(1.5) io_i = q;
endmodule
module tb; reg clk=0; always #5 clk=~clk; wire sck; assign #2.5 sck = clk; // 22.5 deg-ish later + pad
 reg rn=0; wire [15:0] d; wire mcs, rdy, rown, rtx; wire [1:0] o, oe, i;
 flash_cal #(.SCAN_WORDS(64),.REPORT(1),.CLK_HZ(1152000)) u(.clk(clk),.resetn(rn),.ready(rdy),.scan_base(22'h0),.address(22'h0),.cs(1'b0),.dout(d),.mspi_cs(mcs),.mspi_io_o(o),.mspi_io_oe(oe),.mspi_io_i(i),.busy(),.rown(rown),.rtx(rtx));
 fm #(.TCO(`TCO)) f(.sck_i(sck),.csn(mcs),.io_o(o),.oe(oe),.io_i(i));
 initial begin #50 rn=1; wait(rdy); #10; $display("TCO=%0d ok=%b p=%0d crcs %h %h %h %h %h %h %h %h",`TCO,u.ok,u.p,u.crc[0],u.crc[1],u.crc[2],u.crc[3],u.crc[4],u.crc[5],u.crc[6],u.crc[7]); $finish; end
 initial #50000000 begin $display("timeout"); $finish; end
endmodule
