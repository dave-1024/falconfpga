// tb_alias.v - FAL_01: falcon_sdram_arb + real sdram.v + sdram_model (W9825 4 banks x 8K rows x 512 cols):
// probes every CPU address bit, vectors/sysvars/TOS, then clears $DF8000-$DFFFFF (TOS screen clear) and checks nothing aliased.
// iverilog -g2012 tb_alias.v ../hdl/bus/falcon_sdram_arb.v ../hdl/tang/mega138kpro/sdram.v ../hdl/cpu030/sim/ttram/sdram_model.v
`timescale 1ns/1ps
module tb_alias;
  reg clk=0; always #15.625 clk=~clk;
  reg por=1;
  wire [31:0] sd_dq; wire [12:0] sd_a; wire [1:0] sd_ba; wire [3:0] sd_dqm;
  wire sd_cs, sd_we, sd_ras, sd_cas, sd_clk, sd_cke, ready;
  wire cs_i, we_i, rf, ecs, rd2; wire [21:0] wa; wire [1:0] ds, stba; wire [15:0] din, dout, dout2;
  reg vid_req=0; reg [23:1] vid_a=0; wire vid_ack; wire [15:0] vid_q, vid_q2;
  reg ld_req=0; reg [23:1] ld_a=0; reg [15:0] ld_d=0; wire ld_ack;
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
  // background scanout bursts from $DF8000 (like VBAS) to exercise st_rd2
  always @(posedge clk) if (ready && !por) begin
    if (!vid_req && !vid_ack && ($random & 3)==0) begin vid_req<=1; vid_a <= 23'h6FC000 + ($random & 23'h3FFE); end
    else if (vid_req && vid_ack) vid_req<=0;
  end
  task ldw(input [23:0] a, input [15:0] d); begin ld_a=a[23:1]; ld_d=d; ld_req=1; @(posedge clk) while(!ld_ack) @(posedge clk); ld_req=0; @(posedge clk) while(ld_ack) @(posedge clk); end endtask
  task cw(input [23:0] a, input [15:0] d); begin cpu_a=a[23:1]; cpu_d=d; cpu_we=1; cpu_be=3; cpu_req=1; @(posedge clk) while(!cpu_ack) @(posedge clk); cpu_req=0; @(posedge clk) while(cpu_ack) @(posedge clk); end endtask
  task cr(input [23:0] a, output [15:0] q); begin cpu_a=a[23:1]; cpu_we=0; cpu_req=1; @(posedge clk) while(!cpu_ack) @(posedge clk); q=cpu_q; cpu_req=0; @(posedge clk) while(cpu_ack) @(posedge clk); end endtask
  function [15:0] pat(input [23:0] a); pat = a[23:8] ^ {a[7:0],a[15:8]} ^ 16'h5A3C; endfunction
  integer i, bad=0, n=0; reg [15:0] q; reg [23:0] a;
  reg [23:0] probes [0:63]; integer np=0;
  initial begin
    // probes: every single address bit, TOS words, vectors, sysvars, around 14 MB top
    for (i=1;i<24;i=i+1) begin probes[np]=24'd1<<i; np=np+1; end
    probes[np]=24'h000008; np=np+1; probes[np]=24'h00042E; np=np+1; probes[np]=24'h000700; np=np+1;
    probes[np]=24'h0007F8; np=np+1; probes[np]=24'hE00000; np=np+1; probes[np]=24'hE00002; np=np+1;
    probes[np]=24'hE00C1C; np=np+1; probes[np]=24'hE0398C; np=np+1; probes[np]=24'hE7FFFE; np=np+1;
    probes[np]=24'h5F8000; np=np+1; probes[np]=24'h1F8000; np=np+1; probes[np]=24'h9F8000; np=np+1;
    probes[np]=24'hCF8000; np=np+1; probes[np]=24'h7F8000; np=np+1; probes[np]=24'h3F8000; np=np+1;
    probes[np]=24'hDF7FFE; np=np+1; probes[np]=24'h600000; np=np+1; probes[np]=24'h200000; np=np+1;
    repeat(20) @(posedge clk); por=0; while(!ready) @(posedge clk);
    // loader writes TOS-region probes, CPU writes RAM probes
    for (i=0;i<np;i=i+1) if (probes[i]>=24'hE00000) ldw(probes[i], pat(probes[i])); else cw(probes[i], pat(probes[i]));
    // screen clear $DF8000-$DFFFFF with 0 (16K words), like TOS after VBAS
    for (a=24'hDF8000; a<24'hE00000; a=a+2) cw(a, 16'h0000);
    for (i=0;i<np;i=i+1) begin
      if (probes[i] >= 24'hDF8000 && probes[i] < 24'hE00000) ; else begin
        cr(probes[i], q); n=n+1;
        if (q !== pat(probes[i])) begin bad=bad+1; $display("ALIAS/CORRUPT at %h: got %h want %h", probes[i], q, pat(probes[i])); end
      end
    end
    // verify clear readback
    for (a=24'hDF8000; a<24'hE00000; a=a+24'h202) begin cr(a,q); n=n+1; if (q!==0) begin bad=bad+1; $display("clear miss %h=%h",a,q); end end
    $display("checked %0d, bad %0d, model errors %0d", n, bad, m_err);
    $display("%s", (bad==0 && m_err==0) ? "ALIAS TEST PASS" : "ALIAS TEST FAIL");
    $finish;
  end
endmodule
