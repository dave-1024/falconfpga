`timescale 1ps/1ps
module probe;
  integer n1=0,n0=0,nx=0,c1=0;
  always @(posedge tb_bus.dut.cpu030.i_wf68k30l.CLK) begin
    case (tb_bus.dut.cpu030.i_wf68k30l.PF_HOLD_Z) 1'b1: n1=n1+1; 1'b0: n0=n0+1; default: nx=nx+1; endcase
  end
  initial #1100000000 $display("PROBE hold1=%0d hold0=%0d holdX=%0d chain=%0d",n1,n0,nx,c1);
endmodule
