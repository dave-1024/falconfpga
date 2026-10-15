`timescale 1ns/1ps
// ST_SD_HARDEN bench for sd_rw.v (WRITE_FIX=1). Card model faults:
//  REJ   = n : the first n data blocks get a "CRC error" token (0 101 1)
//  DEAD24= 1 : the card never answers CMD24
//  RDEAD = n : the first n CMD17s are answered but no data block follows
// Checks: no hang, a re-init (CMD0) per recovery, request re-issued, data
// correct after recovery, done + error after the 2 re-init budget.
module tbh;
parameter HARDEN = 1, REJ = 0, DEAD24 = 0, RDEAD = 0;
reg clk=0, rstn=0; always #31.25 clk=~clk;
wire sdclk; tri1 sdcmd; tri1 [3:0] sddat;
reg rstart=0, wstart=0; reg [31:0] sector=0;
wire rbusy, rdone, outen; wire [8:0] outaddr; wire [7:0] outbyte; wire [3:0] card_stat; wire [1:0] card_type; wire [55:0] dbg;
reg [7:0] buf_[0:511]; reg [7:0] inbyte; always @(posedge clk) inbyte <= buf_[outaddr];
reg [7:0] rd[0:511]; always @(posedge clk) if(outen) rd[outaddr] <= outbyte;
sd_rw #(.CLK_DIV(0),.SIMULATE(1),.WRITE_FIX(1),.HARDEN(HARDEN)) dut(.rstn(rstn),.clk(clk),.sdclk(sdclk),.sdcmd(sdcmd),.sddat(sddat),
 .card_stat(card_stat),.card_type(card_type),.dbg_state(dbg),.rstart(rstart),.wstart(wstart),.sector(sector),.rbusy(rbusy),.rdone(rdone),
 .outen(outen),.outaddr(outaddr),.outbyte(outbyte),.inbyte(inbyte));
reg cmd_oe=0, cmd_o=1; assign sdcmd = cmd_oe ? cmd_o : 1'bz;
reg [3:0] d_oe=0, d_o=4'hf; assign sddat[0]=d_oe[0]?d_o[0]:1'bz; assign sddat[1]=d_oe[1]?d_o[1]:1'bz;
assign sddat[2]=d_oe[2]?d_o[2]:1'bz; assign sddat[3]=d_oe[3]?d_o[3]:1'bz;
integer prg=0, blocks=0, rejected=0, cmd0s=0, cmd17s=0, rdropped=0, n24=0;
reg [47:0] c; reg [5:0] ci; reg [31:0] ca; reg [31:0] wsec;
reg [7:0] mem[0:4095];   // 8 sectors
wire rej_now = (blocks+1 <= REJ);
task resp; input [5:0] idx; input [31:0] arg; input integer nbits; integer k; reg [47:0] r; begin
  r={1'b0,1'b0,idx,arg,7'h00,1'b1};
  repeat(2) @(negedge sdclk);
  cmd_oe=1; for(k=47;k>=0;k=k-1) begin cmd_o=r[k]; @(negedge sdclk); end
  if(nbits>48) begin cmd_o=1; repeat(nbits-48) @(negedge sdclk); end
  cmd_oe=0; end endtask
task getdata; integer n; reg [3:0] nb; reg [7:0] b; reg rej; begin
  @(posedge sdclk); while(sddat!==4'b0000) @(posedge sdclk);
  for(n=0;n<1024;n=n+1) begin @(posedge sdclk); nb=sddat; if(n[0]==0) b[7:4]=nb; else begin b[3:0]=nb; if(!rej_now) mem[(wsec%8)*512+(n>>1)]=b; end end
  repeat(17) @(posedge sdclk);
  blocks=blocks+1; rej = (blocks <= REJ); if(rej) rejected=rejected+1;
  repeat(2) @(negedge sdclk);
  d_oe[0]=1; d_o[0]=0; @(negedge sdclk);
  if(rej) begin d_o[0]=1; @(negedge sdclk); d_o[0]=0; @(negedge sdclk); d_o[0]=1; @(negedge sdclk); end   // 101
  else    begin d_o[0]=0; @(negedge sdclk); d_o[0]=1; @(negedge sdclk); d_o[0]=0; @(negedge sdclk); end   // 010
  d_o[0]=1; @(negedge sdclk); d_o[0]=0; prg=1;
  repeat(200) @(negedge sdclk); d_o[0]=1; @(negedge sdclk); d_oe[0]=0; prg=0;
end endtask
task senddata; input [31:0] s; integer n; begin
  repeat(20) @(negedge sdclk);
  d_oe=4'hf; d_o=4'h0; @(negedge sdclk);
  for(n=0;n<1024;n=n+1) begin d_o = n[0] ? mem[(s%8)*512+(n>>1)][3:0] : mem[(s%8)*512+(n>>1)][7:4]; @(negedge sdclk); end
  d_o=4'h0; repeat(16) @(negedge sdclk); d_o=4'hf; @(negedge sdclk); d_oe=0;
end endtask
initial forever begin
  @(posedge sdclk); if(sdcmd===1'b0) begin
    c=0; begin : rx integer k; for(k=46;k>=0;k=k-1) begin @(posedge sdclk); c[k]=sdcmd; end end
    ci=c[45:40]; ca=c[39:8];
    case(ci)
      0: begin cmd0s=cmd0s+1; end
      8: resp(8, 32'h1aa, 48);
      55: resp(55, 32'h120, 48);
      41: resp(6'h3f, 32'hc0ff8000, 48);
      2: resp(6'h3f, 0, 136);
      3: resp(3, 32'h12340000, 48);
      7,6,16: resp(ci, 32'h900, 48);
      24: begin n24=n24+1; if(!DEAD24 && !prg) begin wsec=ca; resp(24, 32'h900, 48); getdata; end end
      17: begin cmd17s=cmd17s+1; resp(17, 32'h900, 48);
            if(cmd17s <= RDEAD) rdropped=rdropped+1; else senddata(ca); end
      default: resp(ci, 32'h900, 48);
    endcase
  end end
integer i, t0, ok, e0; reg gaveup=0; always @(posedge clk) if(rdone && dbg[55]) gaveup<=1;
task req; input w; input [31:0] s; input [7:0] seed; begin
  for(i=0;i<512;i=i+1) buf_[i]=i^seed; sector=s; e0=dut.rec_cnt; gaveup=0;
  @(posedge clk); if(w) wstart=1; else rstart=1; t0=0;
  while(!rdone && t0<200000000) begin @(posedge clk); t0=t0+1; end
  ok=rdone; wstart=0; rstart=0;
  @(posedge clk); $display("%s sec %0d: %s%s after %0d clk, recoveries %0d, CMD0s %0d, card_stat %0d", w?"write":"read ", s,
           ok|gaveup?"done":"HANG", gaveup?" +GIVE-UP (sd_err)":"", t0, dut.rec_cnt-e0, cmd0s, card_stat);
  wait(card_stat==4'd8 || t0>=200000000); repeat(10) @(posedge clk);
end endtask
initial begin
  #1000 rstn=1;
  wait(card_stat==4'd8);
  req(1, 3, 8'h5a);
  ok=1; for(i=0;i<512;i=i+1) if(mem[3*512+i]!==(i[7:0]^8'h5a)) ok=0;
  $display("  card sector 3 %s; blocks %0d rejected %0d CMD24s %0d", ok?"MATCH":"not written", blocks, rejected, n24);
  req(0, 3, 8'h00);
  ok=1; for(i=0;i<512;i=i+1) if(rd[i]!==mem[3*512+i] || ^rd[i]===1'bx) ok=0;
  $display("  read back %s; CMD17s %0d dropped %0d", ok?"MATCH":"BAD", cmd17s, rdropped);
  $finish;
end
endmodule
