`timescale 1ns/1ps
module tb;
  reg clk=0; always #5 clk=~clk;
  reg rst=1; reg ae=1; reg as=1;
  wire own, tx;
  cpu_heartbeat #(.CLK_HZ(1_000_000),.BAUD(50_000)) dut(.ext_busy(1'b0),.go_ext(),.clk(clk),.rst(rst),.ae_tx(ae),.flags({1'b1,as,6'h05}),.c030(4'h9),.rom_idx(17'h00000),.rom_data(16'h602E),.trace({8'hA5,32'h00FF8E01,104'd0,24'hE00030}),.own(own),.tx(tx));
  always #1000 as=~as;
  integer i; reg [7:0] c; reg [8*40:1] line; integer n=0;
  initial begin #100 rst=0; end
  initial begin
    wait(own);
    repeat(39) begin
      @(negedge tx); #(10*20/2); c=0;
      for(i=0;i<8;i=i+1) begin #(10*20); c[i]=tx; end
      #(10*20); $write("%c",c); n=n+1;
    end
    $finish;
  end
endmodule
