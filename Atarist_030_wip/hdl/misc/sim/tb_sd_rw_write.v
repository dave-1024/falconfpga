`timescale 1ns/1ps
// sd_rw.v single-block write bench with a simple 4-bit SD card model incl. busy
module tb;
parameter WF = 0;              // WRITE_FIX
parameter BUSY1 = 1200000;     // card busy (sd clocks) after first write
parameter DEAD = 0;
parameter GAP = 0;              // clocks between token end bit and busy            // 1 = card ignores the first 40 CMD24s
reg clk=0, rstn=0; always #31.25 clk=~clk;  // 16 MHz model clock
wire sdclk; tri1 sdcmd; tri1 [3:0] sddat;
reg rstart=0, wstart=0; reg [31:0] sector=0;
wire rbusy, rdone, outen; wire [8:0] outaddr; wire [7:0] outbyte; wire [3:0] card_stat; wire [1:0] card_type;
reg [7:0] buf_[0:511]; reg [7:0] inbyte; always @(posedge clk) inbyte <= buf_[outaddr];
sd_rw #(.CLK_DIV(0),.SIMULATE(1),.WRITE_FIX(WF)) dut(.rstn(rstn),.clk(clk),.sdclk(sdclk),.sdcmd(sdcmd),.sddat(sddat),
 .card_stat(card_stat),.card_type(card_type),.rstart(rstart),.wstart(wstart),.sector(sector),.rbusy(rbusy),.rdone(rdone),
 .outen(outen),.outaddr(outaddr),.outbyte(outbyte),.inbyte(inbyte));
// ---------------- card model ----------------
reg cmd_oe=0, cmd_o=1; assign sdcmd = cmd_oe ? cmd_o : 1'bz;
reg d0_oe=0, d0_o=1;   assign sddat[0] = d0_oe ? d0_o : 1'bz;
integer prg=0, writes=0, ignored=0, crcerr=0;
reg [47:0] c; reg [5:0] ci; reg [31:0] ca;
reg [7:0] mem[0:511];
function [15:0] crc16; input [15:0] r; input b; crc16={r[14:0],r[15]^b}^{3'b0,r[15]^b,6'b0,r[15]^b,5'b0}; endfunction
task resp; input [5:0] idx; input [31:0] arg; input integer nbits; integer k; reg [47:0] r; begin
  r={1'b0,1'b0,idx,arg,7'h00,1'b1};
  repeat(2) @(negedge sdclk);
  cmd_oe=1; for(k=47;k>=0;k=k-1) begin cmd_o=r[k]; @(negedge sdclk); end
  if(nbits>48) begin cmd_o=1; repeat(nbits-48) @(negedge sdclk); end
  cmd_oe=0; end endtask
task getdata; integer n,l; reg [15:0] cr[0:3]; reg [15:0] rx[0:3]; reg [3:0] nb; reg [7:0] b; begin
  for(l=0;l<4;l=l+1) cr[l]=0;
  @(posedge sdclk); while(sddat!==4'b0000) @(posedge sdclk);   // start bit
  for(n=0;n<1024;n=n+1) begin @(posedge sdclk); nb=sddat; for(l=0;l<4;l=l+1) cr[l]=crc16(cr[l],nb[l]);
     if(n[0]==0) b[7:4]=nb; else begin b[3:0]=nb; mem[n>>1]=b; end end
  for(n=15;n>=0;n=n-1) begin @(posedge sdclk); for(l=0;l<4;l=l+1) rx[l][n]=sddat[l]; end
  @(posedge sdclk); // end bit
  for(l=0;l<4;l=l+1) if(rx[l]!==cr[l]) crcerr=crcerr+1;
  // CRC status token 0 010 1 then busy
  repeat(2) @(negedge sdclk);
  d0_oe=1; d0_o=0; @(negedge sdclk); d0_o=0; @(negedge sdclk); d0_o=1; @(negedge sdclk); d0_o=0; @(negedge sdclk);
  d0_o=1; @(negedge sdclk); repeat(GAP) @(negedge sdclk); d0_o=0;
  writes=writes+1; prg=1;
  fork begin repeat((writes==1)?BUSY1:2000) @(negedge sdclk); d0_o=1; @(negedge sdclk); d0_oe=0; prg=0; end join_none
end endtask
initial forever begin
  @(posedge sdclk); if(sdcmd===1'b0) begin
    c=0; c[47]=0; begin : rx integer k; for(k=46;k>=0;k=k-1) begin @(posedge sdclk); c[k]=sdcmd; end end
    ci=c[45:40]; ca=c[39:8];
    case(ci)
      0: ;
      8: resp(8, 32'h1aa, 48);
      55: resp(55, 32'h120, 48);
      41: resp(6'h3f, 32'hc0ff8000, 48);
      2: resp(6'h3f, 0, 136);
      3: resp(3, 32'h12340000, 48);
      7,6,16: resp(ci, 32'h900, 48);
      24: if(prg || (DEAD && ignored<40)) begin ignored=ignored+1; end
          else begin resp(24, 32'h900, 48); getdata; end
      default: resp(ci, 32'h900, 48);
    endcase
  end end
// ---------------- host ----------------
integer i, t0;
task dowrite; input [31:0] s; input [7:0] seed; input integer tmo; begin
  for(i=0;i<512;i=i+1) buf_[i]=i^seed; sector=s;
  @(posedge clk); wstart=1; t0=0;
  while(!rdone && t0<tmo) begin @(posedge clk); t0=t0+1; end
  wstart=0;
  if(rdone) $display("write sec %0d done after %0d clk, card_stat=%0d", s, t0, card_stat);
  else $display("write sec %0d TIMEOUT (helper 'write timeout'), card_stat=%0d sddat_stat=%0d", s, card_stat, dut.sddat_stat);
end endtask
integer ok;
initial begin
  #1000 rstn=1;
  wait(card_stat==4'd8); $display("init READY, card_type=%0d", card_type);   // READY
  dowrite(10, 8'h00, 40000000);
  ok=1; for(i=0;i<512;i=i+1) if(mem[i]!==(i[7:0]^8'h00)) ok=0;
  $display("sector 10 data %s, crcerr=%0d", ok?"MATCH":"BAD", crcerr);
  dowrite(11, 8'h5a, 40000000);
  ok=1; for(i=0;i<512;i=i+1) if(mem[i]!==(i[7:0]^8'h5a)) ok=0;
  $display("sector 11 data %s, writes=%0d ignoredCMD24=%0d crcerr=%0d card_stat=%0d", ok?"MATCH":"BAD", writes, ignored, crcerr, card_stat);
  $finish;
end
endmodule
