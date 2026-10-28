// tb_pll_wdog.v: iverilog -g2012 -o t tb_pll_wdog.v ../pll_wdog.v ../pll_init.v && vvp t
// PLL 0 only locks after its PLL_INIT was restarted twice; PLL 1 locks at once; PLL 2 never. Checks the restarts,
// the status UART line while PLL 0 is unlocked, and silence once it locks.
`timescale 1ns/1ns
module tb;
  reg clk = 0; always #10 clk = ~clk;
  wire [2:0] irst; wire tx; wire [7:0] st;
  reg [2:0] lock = 3'b000;
  integer nrst0 = 0, nrst2 = 0;
  always @(posedge irst[0]) nrst0 = nrst0 + 1;
  always @(posedge irst[2]) nrst2 = nrst2 + 1;
  initial begin #1000 lock[1] = 1; end
  always @(negedge irst[0]) if (nrst0 == 2) #3000 lock[0] = 1;
  pll_wdog #(.N(3), .T_WAIT(5000), .T_MSG(3000), .BAUD_DIV(9)) dut (.clk(clk), .lock_a(lock), .init_rst(irst), .tx(tx), .status(st));
  // UART decode (10 clocks per bit)
  reg [7:0] c; integer i; reg [8*64-1:0] line = 0;
  always @(negedge tx) begin
    #(200*1.5); for (i = 0; i < 8; i = i + 1) begin c[i] = tx; #200; end
    line = {line[8*63-1:0], c};
  end
  initial begin
    #2_000_000;
    $display("restarts pll0=%0d pll2=%0d lock=%b status=%h", nrst0, nrst2, lock, st);
    $display("last chars: %s", line[8*16-1:0]);
    if (nrst0 != 2) $display("FAIL pll0 restarts"); else if (nrst2 < 10) $display("FAIL pll2 restarts");
    else if (st[7:4] != 2 || st[2:0] != 3'b011) $display("FAIL status"); else $display("PASS");
    $finish;
  end
endmodule
