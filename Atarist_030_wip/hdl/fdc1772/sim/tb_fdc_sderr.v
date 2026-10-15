`timescale 1ns/1ps
// ST_SD_HARDEN -> FDC status bench. A minimal SD side answers fdc1772's
// sd_rd/sd_wr; ERR_ON selects which request "gives up" (sd_err level, set when
// that request's ack drops, cleared when the next request starts).
// Checks: clean read/write -> status bit 3 (CRC) clear; give-up -> bit 3 set,
// command still ends (busy clear, irq); next command clears it; a multi-sector
// read stops at the failing sector. CLK_EN scaled to 800 (10x faster disk) to keep the run short.
module tbf;
reg clk=0; always #15.625 clk=~clk;           // 32 MHz
reg [1:0] div=0; always @(posedge clk) div<=div+1; wire en8 = (div==0);
reg rst_n=0;
reg [1:0] a=0; reg sel=0, rw=1; reg [7:0] din=0; wire [7:0] dout;
wire irq, drq; wire [31:0] lba; wire [1:0] sd_rd, sd_wr; wire [7:0] sd_din;
reg ack=0, err=0, strobe=0; reg [8:0] baddr=0; reg [7:0] sdout=0;
reg [1:0] mnt=0;
fdc1772 #(.CLK_EN(16'd800)) dut(.clkcpu(clk),.clk8m_en(en8),.floppy_drive(2'b10),.floppy_side(1'b1),.floppy_reset(rst_n),
 .floppy_step(),.floppy_motor(1'b0),.floppy_ready(),.irq(irq),.drq(drq),.cpu_addr(a),.cpu_sel(sel),.cpu_rw(rw),
 .cpu_din(din),.cpu_dout(dout),.img_type(3'd1),.img_mounted(mnt),.img_wp(2'b00),.img_ds(1'b0),.img_size(32'd737280),
 .sd_lba(lba),.sd_rd(sd_rd),.sd_wr(sd_wr),.sd_ack(ack),.sd_err(err),.sd_buff_addr(baddr),.sd_dout(sdout),.sd_din(sd_din),
 .sd_dout_strobe(strobe));
integer nreq=0, ERR_ON=-1, k;
// SD side
initial forever begin
  @(posedge clk); if(|sd_rd || |sd_wr) begin : r reg w; w=|sd_wr;
    nreq=nreq+1; err<=0; repeat(20) @(posedge clk); ack<=1; repeat(4) @(posedge clk);
    for(k=0;k<512;k=k+1) begin baddr<=k; sdout<=k; if(!w) strobe<=1; @(posedge clk); strobe<=0; @(posedge clk); end
    if(nreq==ERR_ON) err<=1; ack<=0; repeat(4) @(posedge clk);
  end end
task wr(input [1:0] r, input [7:0] v); begin @(posedge clk); a<=r; din<=v; rw<=0; sel<=1; repeat(4) @(posedge clk); sel<=0; rw<=1; repeat(4) @(posedge clk); end endtask
task rd(input [1:0] r, output [7:0] v); begin @(posedge clk); a<=r; rw<=1; sel<=1; repeat(4) @(posedge clk); v=dout; sel<=0; repeat(4) @(posedge clk); end endtask
reg [7:0] st, d; integer bytes, t;
task run(input [7:0] c, input [7:0] s, input [255:0] name); begin
  bytes=0; wr(2,s); wr(0,c); repeat(200) @(posedge clk); t=0;
  rd(0,st);
  while(st[0] && t<40000000) begin
    if(drq) begin if(c[5]) wr(3,8'ha5); else rd(3,d); bytes=bytes+1; end
    rd(0,st); t=t+1; end
  $display("%0s: status %02x (busy %0d, CRC %0d, RNF %0d), %0d bytes, SD requests so far %0d, sector reg %0d", name, st, st[0], st[3], st[4], bytes, nreq, s);
end endtask
initial begin
  repeat(20) @(posedge clk); rst_n=1; mnt=2'b01; repeat(4) @(posedge clk); mnt=0;
  repeat(100) @(posedge clk);
  wr(0,8'h08); repeat(200) @(posedge clk); begin : w0 integer q; q=0; rd(0,st); while(st[0] && q<40000000) begin rd(0,st); q=q+1; end end  // restore
  run(8'h88, 1, "read  sector 1 clean      ");
  ERR_ON = nreq+1;
  run(8'h88, 2, "read  sector 2 SD give-up ");
  run(8'h88, 3, "read  sector 3 clean again");
  ERR_ON = nreq+1;
  run(8'hA8, 4, "write sector 4 SD give-up ");
  run(8'hA8, 5, "write sector 5 clean      ");
  ERR_ON = nreq+2;
  run(8'h98, 1, "multi read from 1, 2nd fails");
  $finish;
end
endmodule
