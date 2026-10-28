// iverilog -g2012 -o t tb_flash_unstick.v ../flash_unstick.v && vvp t : decode the CS# cycles (bits on IO0 at SCK rise)
`timescale 1ns/1ns
module tb;
  reg clk = 0; always #15.6 clk = ~clk; reg rst = 1;
  wire busy, done, csn, sck, io0, io1_oe;
  flash_unstick dut(.clk(clk), .rst(rst), .busy(busy), .done(done), .csn(csn), .sck(sck), .io0(io0), .io1_oe(io1_oe));
  integer n = 0, k = 0; reg [15:0] v = 0; reg [15:0] got [0:3]; integer bits [0:3];
  always @(posedge sck) begin v = {v[14:0], io0}; n = n + 1; if (!io1_oe && k == 0) $display("FAIL io1 not driven in cycle 0"); end
  always @(posedge csn) if ($time > 100) begin got[k] = v; bits[k] = n; k = k + 1; n = 0; v = 0; end
  initial begin
    #200 rst = 0; wait(done); #100;
    $display("cycles=%0d  c0 %0d bits %h  c1 %0d bits %h  c2 %0d bits %h  done at %0t", k, bits[0], got[0], bits[1], got[1][7:0], bits[2], got[2][7:0], $time);
    if (k == 3 && bits[0] == 16 && got[0] == 16'hFFFF && bits[1] == 8 && got[1][7:0] == 8'h66 && bits[2] == 8 && got[2][7:0] == 8'h99) $display("PASS"); else $display("FAIL");
    $finish;
  end
endmodule
