`timescale 1ns/1ns
module tbd;
reg clk=0, rstn=0; always #15 clk=~clk;
reg ds=0, dst=0; reg [7:0] din=0; wire [7:0] dout;
reg [7:0] rs=0, ws=0; reg [31:0] rsec=0;
sd_card #(.DEBUG_LOG(1)) u(.rstn(rstn),.clk(clk),.sdcmd_in(1'b1),.sddat_in(4'hf),
 .data_strobe(ds),.data_start(dst),.data_in(din),.data_out(dout),.iack(1'b0),
 .rstart(rs),.wstart(ws),.rsector(rsec),.inbyte(8'h0));
task xfer(input start, input [7:0] b, output [7:0] r); begin
  @(posedge clk); r=dout; ds<=1; dst<=start; din<=b; @(posedge clk); ds<=0; dst<=0; repeat(8) @(posedge clk); end endtask
reg [7:0] r; integer i; reg [7:0] buf_[0:14];
task cmd(input [7:0] c); begin xfer(1,c,r); end endtask
initial begin
  repeat(5) @(posedge clk); rstn<=1; repeat(5) @(posedge clk);
  // cmd 4 insert drive0 size 737280 (0x0B4000)
  cmd(4); xfer(0,0,r); xfer(0,0,r); xfer(0,8'h0b,r); xfer(0,8'h40,r); xfer(0,8'h00,r);
  // cmd 6 direct drive0 base 44440 (0xAD98)
  cmd(6); xfer(0,0,r); xfer(0,0,r); xfer(0,8'h00,r); xfer(0,8'had,r); xfer(0,8'h98,r);
  repeat(5) @(posedge clk);
  for(i=0;i<2;i=i+1) begin
    cmd(9); xfer(0,i,r); begin : rd integer k; for(k=0;k<15;k=k+1) begin xfer(0,0,r); buf_[k]=r; end end
    $display("e%0d: wc=%0d rc=%0d seq=%0d flags=%02x a=%0d b=%0d", i, {buf_[0],buf_[1]}, {buf_[2],buf_[3]}, {buf_[4],buf_[5]}, buf_[6],
      {buf_[7],buf_[8],buf_[9],buf_[10]}, {buf_[11],buf_[12],buf_[13],buf_[14]});
  end
  cmd(10); xfer(0,0,r); begin : rd2 integer k; for(k=0;k<15;k=k+1) begin xfer(0,0,r); buf_[k]=r; end end
  $display("state: base0=%0d base1=%0d creq=%0d mreq=%0d", {buf_[0],buf_[1],buf_[2],buf_[3]}, {buf_[4],buf_[5],buf_[6],buf_[7]}, buf_[8], buf_[9]);
  $finish;
end
endmodule
