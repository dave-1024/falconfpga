// tb_ldrate.v - FAL_01: tos_loader at the board's SD byte rate (sd_card CLK_DIV 0: 1 byte / 4 clk32)
// into falcon_sdram_arb + real sdram.v + sdram_model, with optional scanout traffic; reads every
// loaded word back through the CPU port and counts mismatches.
// iverilog -g2012 -DNSEC=32 tb_ldrate.v ../hdl/top/tos_loader.v ../hdl/bus/falcon_sdram_arb.v $ST/hdl/tang/mega138kpro/sdram.v $ST/hdl/cpu030/sim/ttram/sdram_model.v
`timescale 1ns/1ps
`ifndef NSEC
`define NSEC 32
`endif
`ifndef BYTECLK
`define BYTECLK 4
`endif
module tb_ldrate;
  reg clk=0; always #15.625 clk=~clk;
  reg por=1;
  wire [31:0] sd_dq; wire [12:0] sd_a; wire [1:0] sd_ba; wire [3:0] sd_dqm;
  wire sd_cs, sd_we, sd_ras, sd_cas, sd_clk, sd_cke, ready;
  wire cs_i, we_i, rf, ecs, rd2; wire [21:0] wa; wire [1:0] ds, stba; wire [15:0] din, dout, dout2;
  reg vid_req=0; reg [23:1] vid_a=0; wire vid_ack; wire [15:0] vid_q, vid_q2;
  wire ld_req; wire [23:1] ld_a; wire [15:0] ld_d; wire ld_ack;
  reg cpu_req=0, cpu_we=0; reg [23:1] cpu_a=0; reg [1:0] cpu_be=3; reg [15:0] cpu_d=0; wire cpu_ack; wire [15:0] cpu_q;
  falcon_sdram_arb arb(.clk(clk),.reset(por),.ram_ready(ready),.sd_cs(cs_i),.sd_we(we_i),.sd_refresh(rf),.sd_ecs(ecs),
    .sd_addr(wa),.sd_ds(ds),.sd_din(din),.sd_dout(dout),.sd_dout2(dout2),.sd_rd2(rd2),.sd_ba(stba),
    .vid_req(vid_req),.vid_a(vid_a),.vid_ack(vid_ack),.vid_q(vid_q),.vid_q2(vid_q2),
    .dma_req(1'b0),.dma_we(1'b0),.dma_a(23'd0),.dma_d(16'd0),.dma_ack(),.dma_q(),
    .ld_req(ld_req),.ld_a(ld_a),.ld_d(ld_d),.ld_ack(ld_ack),
    .cpu_req(cpu_req),.cpu_a(cpu_a),.cpu_we(cpu_we),.cpu_be(cpu_be),.cpu_d(cpu_d),.cpu_ack(cpu_ack),.cpu_q(cpu_q));
  sdram u_sd(.sd_clk(sd_clk),.sd_cke(sd_cke),.sd_data(sd_dq),.sd_addr(sd_a),.sd_dqm(sd_dqm),.sd_ba(sd_ba),
    .sd_cs(sd_cs),.sd_we(sd_we),.sd_ras(sd_ras),.sd_cas(sd_cas),.clk(clk),.reset_n(~por),.ready(ready),
    .refresh(rf),.din(din),.dout(dout),.dout2(dout2),.addr(wa),.ds(ds),.cs(cs_i),.ecs(ecs),.we(we_i),.zmask(1'b0),.st_ba(stba),.st_rd2(rd2));
  wire [31:0] m_err;
  sdram_model mdl(.clk(clk),.cmd({sd_ras,sd_cas,sd_we}),.a(sd_a),.ba(sd_ba),.dqm(sd_dqm[1:0]),.dq(sd_dq[15:0]),.ctl_oe(1'b0),.errors(m_err));
  reg vid_on = 0;
  always @(posedge clk) if (ready && !por) begin
    if (vid_on && !vid_req && !vid_ack && ($random & 3)==0) begin vid_req<=1; vid_a <= 23'h6FC000 + ($random & 23'h3FFE); end
    else if (vid_req && vid_ack) vid_req<=0;
  end
  // loader + SD byte source
  reg mnt=0; reg sd_ack=0; reg [8:0] sba=0; reg [7:0] sdo=0; reg stb=0;
  wire [31:0] lba; wire sd_rd, cpu_reset, err, busy; wire [9:0] sect; wire [31:0] crc;
  tos_loader ld(.clk(clk),.reset(por),.img_mounted(mnt),.img_size(32'd524288),.sd_lba(lba),.sd_rd(sd_rd),.sd_ack(sd_ack),
    .sd_buff_addr(sba),.sd_dout(sdo),.sd_dout_strobe(stb),.ram_req(ld_req),.ram_a(ld_a),.ram_wdata(ld_d),.ram_ack(ld_ack),
    .cpu_reset(cpu_reset),.err(err),.busy(busy),.sect(sect),.crc(crc));
  function [7:0] pb(input [31:0] l, input [8:0] i);   // byte i of sector l; sector 0 bytes 8..11 = 00E00000
    pb = (l==0 && i>=8 && i<=11) ? ((i==9) ? 8'hE0 : 8'h00) : (l[7:0]*8'd37 ^ i[7:0] ^ {7'd0,i[8]}*8'h5B ^ 8'hA5);
  endfunction
  integer s, b, k, bad=0, n=0; reg [15:0] q, w;
  initial begin
    if ($test$plusargs("vid")) vid_on = 1;
    repeat(20) @(posedge clk); por=0; while(!ready) @(posedge clk);
    repeat(5) @(posedge clk); mnt<=1; @(posedge clk); mnt<=0;
    for (s=0; s<`NSEC; s=s+1) begin
      while(!sd_rd) @(posedge clk);
      repeat(3) @(posedge clk); sd_ack<=1; repeat(40) @(posedge clk);
      for (b=0;b<512;b=b+1) begin
        sba<=b; sdo<=pb(s,b); stb<=1; @(posedge clk); stb<=0;
        repeat(`BYTECLK-1) @(posedge clk);
      end
      repeat(10) @(posedge clk); sd_ack<=0;
      repeat(20) @(posedge clk);
    end
    repeat(4000) @(posedge clk);
    // read back through the CPU port (loader still holds cpu_reset at NSEC<1024: port is free of ld traffic)
    for (s=0; s<`NSEC; s=s+1) for (b=0;b<512;b=b+2) begin
      cpu_a = {5'b11100, s[9:0], b[8:1]}; cpu_we=0; cpu_req=1;
      @(posedge clk) while(!cpu_ack) @(posedge clk); q=cpu_q; cpu_req=0; @(posedge clk) while(cpu_ack) @(posedge clk);
      w = {pb(s,b), pb(s,b+1)}; n=n+1;
      if (q !== w) begin bad=bad+1; if (bad<10) $display("MISS sect %0d word %0d: got %h want %h", s, b/2, q, w); end
    end
    $display("BYTECLK=%0d vid=%0d: checked %0d words, bad %0d, model errors %0d", `BYTECLK, vid_on, n, bad, m_err);
    $display("%s", (bad==0 && m_err==0) ? "LDRATE PASS" : "LDRATE FAIL");
    $finish;
  end
endmodule
