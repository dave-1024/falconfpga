`timescale 1ns/1ps
module tb;
  reg clk=0; always #5 clk=~clk;
  reg hn=1; wire own,tx; integer i,n; reg [7:0] c;
  reg [639:0] regs; integer j;
  initial begin for(j=0;j<20;j=j+1) regs[32*j+:32]=32'h11110000+j; end
  cpu_dump #(.CLK_HZ(100_000),.BAUD(10_000)) d(.clk(clk),.halt_n(hn),.regs(regs),.sr(16'h2700),.pmmu({32'h80D04447,256'd0}),
    .berr_adr(32'h00FF8E01),.berr_info(8'hD4),.go(1'b1),.own(own),.tx(tx));
  initial begin #1000 hn=0; wait(own);
    for(n=0;n<6+33*13;n=n+1) begin @(negedge tx); #50; for(i=0;i<8;i=i+1) begin #100; c[i]=tx; end #100; $write("%c",c); end
    $finish; end
endmodule
