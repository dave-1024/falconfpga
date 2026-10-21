//
// sdram.v
//
// sdram controller implementation for the Tang Primer 25k / MiSTer SDRAM
// 
// Copyright (c) 2024 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

module sdram (
	output		  sd_clk, // sd clock
	output		  sd_cke, // clock enable
	inout reg [31:0]  sd_data, // 32 bit bidirectional data bus, only 16 used here
	output reg [12:0] sd_addr, // up to 13 bit multiplexed address bus
	output     [3:0]  sd_dqm, // two byte masks, only 2 used here
	output reg [1:0]  sd_ba, // two banks
	output		  sd_cs, // a single chip select
	output		  sd_we, // write enable
	output		  sd_ras, // row address select
	output		  sd_cas, // columns address select

	// cpu/chipset interface
	input		  clk, // sdram is accessed at 32MHz
	input		  reset_n, // init signal after FPGA config to initialize RAM

	output		  ready, // ram is ready and has been initialized
	input		  refresh, // chipset requests a refresh cycle
	input [15:0]	  din, // data input from chipset/cpu
	output reg [15:0] dout,
	input [21:0]	  addr, // 22 bit word address
	input [1:0]	  ds, // upper/lower data strobe
	input		  cs, // cpu/chipset requests read/wrie
	input		  ecs,        // FalconFPGA F63: a read RAS follows on the next clk edge (early start), 0 = unused
	input		  we,         // cpu/chipset requests write
	input		  zmask       // FalconFPGA: this ST read returns 0 (sampled at CAS; cold-start memvalid mask)
`ifdef TTRAM
	,
	// FalconFPGA TTRAM (docs/TTRAM_DESIGN.md): 32-bit TT-RAM port in banks 1/2.
	// One long word per 250 ns ST slot, slotted into the clocks the ST cycle
	// leaves free (g2..g7 of the 8-clock slot grid); the ST access is unchanged.
	input		  tt_req,     // level, held until tt_ack (clk domain)
	input		  tt_we,
	input [21:0]	  tt_la,      // long word address: TT-RAM byte A23:2
	input [3:0]	  tt_be,      // write lanes, [3] = D31:24 (A1:0 = 00) .. [0] = D7:0
	input [31:0]	  tt_din,
	output reg	  tt_ack = 1'b0, // one clk: write taken (posted) / read: tt_dout complete 3 clk later
	output reg [31:0] tt_dout
`endif
);

assign sd_clk = ~clk;
assign sd_cke = 1'b1;  
   
localparam RASCAS_DELAY   = 3'd1;   // tRCD=15ns -> 1 cycle@32MHz
localparam BURST_LENGTH   = 3'b000; // 000=1, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 1'b0, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------

// The state machine runs at 32Mhz synchronous to the sync signal.
localparam STATE_IDLE      = 3'd0;   // first state in cycle
localparam STATE_CMD_CONT  = STATE_IDLE + RASCAS_DELAY; // command can be continued
localparam STATE_READ      = STATE_CMD_CONT + CAS_LATENCY + 3'd1;
localparam STATE_LAST      = 3'd6;  // last state in cycle
   
// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

reg [2:0] state;
reg [4:0] init_state;

// wait 1ms (32 8Mhz cycles) after FPGA config is done before going
// into normal operation. Initialize the ram in the last 16 reset cycles (cycles 15-0)
assign ready = !(|init_state);
   
// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_NOP             = 3'b111;
localparam CMD_ACTIVE          = 3'b011;
localparam CMD_READ            = 3'b101;
localparam CMD_WRITE           = 3'b100;
localparam CMD_BURST_TERMINATE = 3'b110;
localparam CMD_PRECHARGE       = 3'b010;
localparam CMD_AUTO_REFRESH    = 3'b001;
localparam CMD_LOAD_MODE       = 3'b000;

reg [2:0] sd_cmd;   // current command sent to sd ram
// drive control signals according to current command
assign sd_cs  = 1'b0;   
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];

// sd_data[31:16] and sd_dqlm[2:3] are unused with MiSTer SDRAM
`ifdef TTRAM
reg        tt_oe   = 1'b0;   // TT write data on the bus
reg        tt_rdwin = 1'b0;  // TT read data window: ST write data off the bus
reg        tt_dqme = 1'b0;   // TT owns DQM
reg [1:0]  tt_dqm  = 2'b00;
reg [15:0] tt_wd   = 16'h0000;
assign sd_data[15:0] = tt_oe ? tt_wd : (tt_rdwin ? 16'bzzzz_zzzz_zzzz_zzzz :
                       ((cs && we) ? din : 16'bzzzz_zzzz_zzzz_zzzz));
assign sd_dqm = { 2'bzz, tt_dqme ? tt_dqm : ((!cs || !we)?2'b00:ds) };
`else
assign sd_data[15:0] = (cs && we) ? din : 16'bzzzz_zzzz_zzzz_zzzz;
assign sd_dqm = { 2'bzz, (!cs || !we)?2'b00:ds };
`endif

reg csD = 1'b0;
`ifdef TTRAM
// ---------------------------------------------------------------------
// FalconFPGA TTRAM engine (docs/TTRAM_DESIGN.md)
// The GSTMCU starts its RAS cycles on a fixed 8-clock grid (video and CPU
// halves of the 500 ns ST cycle are exactly 8 clk apart); the ST cycle here
// is ACTIVE at g0 (g7 with the F63 early start), CAS at g1 (g0), data at
// g3/g4. tg follows that grid from every ST start. A TT access starts at g2,
// uses bank 1/2 only and is over (auto precharge) before the next ST ACTIVE:
//   read : g2 ACT, g3 READ w0, g4 READ w1 +AP (ack), capture w0 g6, w1 g7 (tt_dout)
//   write: g2 ACT (ack: posted), g4 WRITE w0, g5 WRITE w1 +AP
// Command, data and DQM clocks never meet the ST ones (sim/ttram/tb_ttram.v
// checks it with an SDRAM model). ST timing is not changed.
// ---------------------------------------------------------------------
reg  [2:0]  tg = 3'd0;      // slot grid phase of the NEXT edge
reg         tg_ok = 1'b0;   // grid seen at least once
reg  [2:0]  tt_t = 3'd0;    // TT sequence step
reg         tt_busy = 1'b0;
reg         tt_w = 1'b0;
reg  [21:0] tt_a;
reg  [3:0]  tt_b;
reg  [31:0] tt_d;
reg  [15:0] tt_w0;
wire st_norm_start = (init_state == 0) && !(ecs && (state == STATE_IDLE || state == STATE_LAST)) &&
                     (state == STATE_IDLE) && cs && !csD;
wire st_ecs_start  = (init_state == 0) && ecs && (state == STATE_IDLE || state == STATE_LAST);
wire [1:0] tt_bank = tt_a[21] ? 2'b10 : 2'b01;
wire tt_go = (init_state == 0) && tg_ok && (tg == 3'd2) && tt_req && !tt_busy && !tt_ack &&
             (state == 3'd0 || state == 3'd2 || state == 3'd3) && !st_norm_start && !st_ecs_start;

`endif

reg zmask_q = 1'b0;
always @(posedge clk) begin
   sd_cmd <= CMD_NOP;  // default: idle

   // init state machines runs once reset ends
   if(!reset_n) begin
      init_state <= 5'h1f;
      state <= STATE_IDLE;      
   end else begin
      if(init_state != 0)
        state <= state + 3'd1;
      
      if((state == STATE_LAST) && (init_state != 0))
        init_state <= init_state - 5'd1;
   end
   
   if(init_state != 0) begin
      csD <= 1'b0;     
      
      // initialization takes place at the end of the reset
      if(state == STATE_IDLE) begin
	 
	 if(init_state == 13) begin
	    sd_cmd <= CMD_PRECHARGE;
	    sd_addr[10] <= 1'b1;      // precharge all banks
	 end
	 
	 if(init_state == 2) begin
	    sd_cmd <= CMD_LOAD_MODE;
	    sd_addr <= MODE;
	 end
	 
      end
   end else begin
      csD <= cs;
      
      // normal operation, start on ... 
      // FalconFPGA F63: RAM early start. The chipset flags (ecs) that a read
      // RAS starts on the next clock; the row is opened now instead of one
      // clock after RAS, so dout is valid 2 clocks earlier (4 clocks after
      // RAS). Taken in the idle state or in the last state of the previous
      // cycle (ACTIVE to ACTIVE then 7 clocks, the previous READ has
      // auto-precharged long before). The RAS edge that follows finds the
      // state machine busy and is ignored, as during any cycle.
      if(ecs && (state == STATE_IDLE || state == STATE_LAST)) begin
        sd_cmd <= CMD_ACTIVE;
        sd_addr <= addr[21:9];
        sd_ba <= 2'b00;
        state <= 3'd1;
      end else
      if(state == STATE_IDLE) begin
        // ... rising edge of cs
        if (cs && !csD) begin
          if(!refresh) begin
            // RAS phase
            sd_cmd <= CMD_ACTIVE;
            sd_addr <= addr[21:9];  // 8 Megawords = 16 Megabytes per bank
            sd_ba <= 2'b00;         // use one of the four banks only (and one of the two rams)
            state <= 3'd1;
          end else
            sd_cmd <= CMD_AUTO_REFRESH;
        end
      end else begin
        // always advance state unless we are in idle state
        state <= state + 3'd1;
	 
        // -------------------  cpu/chipset read/write ----------------------

        // CAS phase 
        if(state == STATE_CMD_CONT) begin
            sd_cmd <= we?CMD_WRITE:CMD_READ;
            sd_addr <= { 4'b0010, addr[8:0] };
            zmask_q <= zmask;
        end

        if(state > STATE_CMD_CONT && state < STATE_READ)
            sd_cmd <= CMD_NOP;
      
        // read phase
        if(state == STATE_READ && !we) begin
            dout <= zmask_q ? 16'h0000 : sd_data[15:0];
        end
      end
   end
`ifdef TTRAM

   tg <= tg + 3'd1;
   if (st_ecs_start)       begin tg <= 3'd0; tg_ok <= 1'b1; end   // this edge is g7
   else if (st_norm_start) begin tg <= 3'd1; tg_ok <= 1'b1; end   // this edge is g0
   tt_ack <= 1'b0;
   if (!reset_n) begin
      tt_busy <= 1'b0; tt_oe <= 1'b0; tt_rdwin <= 1'b0; tt_dqme <= 1'b0; tg_ok <= 1'b0;
   end else if (tt_go) begin
      tt_busy <= 1'b1; tt_t <= 3'd1;
      tt_w <= tt_we; tt_a <= tt_la; tt_b <= tt_be; tt_d <= tt_din;
      sd_cmd  <= CMD_ACTIVE;
      sd_addr <= tt_la[20:8];
      sd_ba   <= tt_la[21] ? 2'b10 : 2'b01;
      tt_dqme <= 1'b1; tt_dqm <= 2'b00;
      tt_rdwin <= !tt_we;
      tt_ack  <= tt_we;   // L2: a write is posted (data held in tt_d), the 030 may end its cycle now
   end else if (tt_busy) begin
      tt_t <= tt_t + 3'd1;
      if (!tt_w) begin
         case (tt_t)
         3'd1: begin sd_cmd <= CMD_READ; sd_addr <= {4'b0000, tt_a[7:0], 1'b0}; sd_ba <= tt_bank; end
         3'd2: begin sd_cmd <= CMD_READ; sd_addr <= {4'b0010, tt_a[7:0], 1'b1}; sd_ba <= tt_bank;
                     tt_ack <= 1'b1; end   // L2: early ack, tt_dout is complete 3 edges later (see bridge)
         3'd4: tt_w0 <= sd_data[15:0];
         3'd5: begin tt_dout <= {tt_w0, sd_data[15:0]}; tt_busy <= 1'b0;
                     tt_rdwin <= 1'b0; tt_dqme <= 1'b0; end
         default: ;
         endcase
      end else begin
         case (tt_t)
         // [C7] TT7: WRITE w0/w1 at g5/g6 (were g4/g5). An ST read with CAS at g1 (CL2) has the chip
         // driving DQ until just after g4 (tOH): a TT WRITE at g4 drove DQ against it, corrupting w0
         // (bus bench: stacked return address read back with X in D27:24).
         3'd3: begin sd_cmd <= CMD_WRITE; sd_addr <= {4'b0000, tt_a[7:0], 1'b0}; sd_ba <= tt_bank;
                     tt_oe <= 1'b1; tt_wd <= tt_d[31:16]; tt_dqm <= ~tt_b[3:2]; end
         3'd4: begin sd_cmd <= CMD_WRITE; sd_addr <= {4'b0010, tt_a[7:0], 1'b1}; sd_ba <= tt_bank;
                     tt_wd <= tt_d[15:0]; tt_dqm <= ~tt_b[1:0]; end
         3'd5: begin tt_oe <= 1'b0; tt_dqme <= 1'b0; tt_busy <= 1'b0; end
         default: ;
         endcase
      end
   end
`endif
end
   
endmodule
