// mfp.v
//
// Atari ST multi function peripheral (MFP) for the MiST board
// https://github.com/mist-devel/mist-board
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
// Copyright (c) 2019-2020 Gyorgy Szombathelyi
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

module mfp (
	// cpu register interface
	input            clk,
	input            clk_en,
	input            reset,
	input      [7:0] din,
	input            sel,
	input      [4:0] addr,
	input            ds,
	input            rw,
	output reg [7:0] dout,
	output reg       irq,
	input            iack,
	output           dtack,

	// serial rs232 connection to io controller
	output [7:0]     serial_data_out_available,
	output [7:0]     serial_data_in_free,
	input            serial_strobe_out,
	output     [7:0] serial_data_out,
	output    [31:0] serial_status_out,

	input            serial_strobe_in,
	input      [7:0] serial_data_in,

	input            clk_ext,
	input      [1:0] t_i,
	input      [7:0] i,

	// Bring-up only. One clk cycle per Timer C timeout. Silent until
	// software starts the timer. TOS uses Timer C as the 200 Hz tick.
	output           timerc_pulse
);

assign serial_data_in_free = { 4'h0, serial_data_in_space };

wire serial_data_out_fifo_full;
wire serial_data_in_full;

wire write = clk_en & ~bus_selD & bus_sel & ~rw;

assign serial_data_out_available[7:4] = 4'h0;

io_fifo mfp_out_fifo (
	.reset            ( reset ),
	.in_clk           ( clk ),
	.in               ( din ),
	.in_strobe        ( 1'b0 ),
	.in_enable        ( write && (addr == 5'h17) ),
	.out_clk          ( clk ),
	.out              ( serial_data_out ),
	.out_strobe       ( serial_strobe_out ),
	.out_enable       ( 1'b0 ),
	.space            (  ),
	.used             ( serial_data_out_available[3:0] ),
	.empty            (  ),
	.full             ( serial_data_out_fifo_full )
);

reg serial_cpu_data_read;
wire [7:0] serial_data_in_cpu;
wire	   serial_data_in_empty;
wire [3:0] serial_data_in_used;
wire [3:0] serial_data_in_space;
wire	   uart_rx_busy;

reg uart_rx_busyD;
always @(posedge clk) uart_rx_busyD <= uart_rx_busy;
wire uart_rx_busy_ends = !uart_rx_busy && uart_rx_busyD;

io_fifo mfp_in_fifo (
	.reset            ( reset ),
	.in_clk           ( clk ),
	.in               ( serial_data_in ),
	.in_strobe        ( serial_strobe_in ),
	.in_enable        ( 1'b0 ),
	.out_clk          ( clk ),
	.out              ( serial_data_in_cpu ),
	.out_strobe       ( 1'b0 ),
	.out_enable       ( !serial_data_in_empty && uart_rx_busy_ends ),
	.space            ( serial_data_in_space ),
	.used             ( serial_data_in_used ),
	.empty            ( serial_data_in_empty ),
	.full             ( serial_data_in_full )
);

always @(posedge clk) begin
	serial_cpu_data_read <= 1'b0;
	if (clk_en) begin
		if(bus_sel && rw && (addr == 5'h17))
			serial_cpu_data_read <= 1'b1;
	end
end

wire bus_sel = sel & ~ds;
reg  bus_selD;
reg  bus_dtack;

always @(posedge clk) begin
	if (clk_en) begin
		bus_selD <= bus_sel;
		if (bus_selD & bus_sel) bus_dtack <= 1'b1;
		if (~bus_sel) bus_dtack <= 1'b0;
	end
end

reg iack_dtack;
reg iack_sel;
reg iack_ack;
always @(posedge clk) begin
	iack_sel <= 1'b0;
	if (clk_en) begin
		if (iack && !iack_ack && highest_irq_pending_mask != 16'h0000) iack_sel <= 1'b1;
		if (iack_ack) iack_dtack <= 1'b1;
		if (~iack) iack_dtack <= 1'b0;
	end
end

assign dtack = bus_dtack || iack_dtack;

wire [1:0] pulse_mode;
wire [1:0] event_mode;

wire timera_done;
wire [7:0] timera_dat_o;
wire [3:0] timera_ctrl_o;

mfp_timer timer_a (
	.CLK        ( clk                      ),
	.DS         ( ds                       ),
	.XCLK_I     ( clk_ext                  ),
	.RST        ( reset                    ),
	.CTRL_I     ( din[4:0]                 ),
	.CTRL_O     ( timera_ctrl_o            ),
	.CTRL_WE    ( (addr == 5'h0c) && write ),
	.DAT_I      ( din                      ),
	.DAT_O      ( timera_dat_o             ),
	.DAT_WE     ( (addr == 5'h0f) && write ),
	.PULSE_MODE ( pulse_mode[1]            ),
	.EVENT_MODE ( event_mode[1]            ),
	.T_I        ( t_i[0] ^ ~aer[4]         ),
	.T_O        (                          ),
	.T_O_PULSE  ( timera_done              ),
	.SET_DATA_OUT (                        )
);

wire timerb_done;
wire [7:0] timerb_dat_o;
wire [3:0] timerb_ctrl_o;

mfp_timer timer_b (
	.CLK        ( clk                      ),
	.DS         ( ds                       ),
	.XCLK_I     ( clk_ext                  ),
	.RST        ( reset                    ),
	.CTRL_I     ( din[4:0]                 ),
	.CTRL_O     ( timerb_ctrl_o            ),
	.CTRL_WE    ( (addr == 5'h0d) && write ),
	.DAT_I      ( din                      ),
	.DAT_O      ( timerb_dat_o             ),
	.DAT_WE     ( (addr == 5'h10) && write ),
	.PULSE_MODE ( pulse_mode[0]            ),
	.EVENT_MODE ( event_mode[0]            ),
	.T_I        ( t_i[1] ^ ~aer[3]         ),
	.T_O        (                          ),
	.T_O_PULSE  ( timerb_done              ),
	.SET_DATA_OUT (                        )
);

wire timerc_done;
wire [7:0] timerc_dat_o;
wire [3:0] timerc_ctrl_o;

mfp_timer timer_c (
	.CLK        ( clk                      ),
	.DS         ( ds                       ),
	.XCLK_I     ( clk_ext                  ),
	.RST        ( reset                    ),
	.CTRL_I     ( {2'b00, din[6:4]}        ),
	.CTRL_O     ( timerc_ctrl_o            ),
	.CTRL_WE    ( (addr == 5'h0e) && write ),
	.DAT_I      ( din                      ),
	.DAT_O      ( timerc_dat_o             ),
	.DAT_WE     ( (addr == 5'h11) && write ),
	.T_I        ( 1'b0                     ),
	.PULSE_MODE (                          ),
	.EVENT_MODE (                          ),
	.T_O        (                          ),
	.T_O_PULSE  ( timerc_done              )
);
assign timerc_pulse = timerc_done;

wire timerd_done;
wire [7:0] timerd_dat_o;
wire [3:0] timerd_ctrl_o;
wire [7:0] timerd_set_data;

mfp_timer timer_d (
	.CLK        ( clk                      ),
	.DS         ( ds                       ),
	.XCLK_I     ( clk_ext                  ),
	.RST        ( reset                    ),
	.CTRL_I     ( {2'b00, din[2:0]}        ),
	.CTRL_O     ( timerd_ctrl_o            ),
	.CTRL_WE    ( (addr == 5'h0e) && write ),
	.DAT_I      ( din                      ),
	.DAT_O      ( timerd_dat_o             ),
	.DAT_WE     ( (addr == 5'h12) && write ),
	.T_O_PULSE  ( timerd_done              ),
	.T_I        ( 1'b0                     ),
	.PULSE_MODE (                          ),
	.EVENT_MODE (                          ),
	.T_O        (                          ),
	.SET_DATA_OUT ( timerd_set_data        )
);

reg [7:0] aer, ddr, gpip;
reg [15:0] imr, ier;
reg [7:0] vr;

wire irq_trigger = ((ipr & imr) != 16'h0000) && (highest_irq_pending > irq_in_service);
always @(posedge clk) if (clk_en) irq <= irq_trigger;

wire [15:0] ipr;
wire [15:0] isr;
wire [3:0] irq_in_service;
mfp_hbit16 irq_in_service_index (
	.value  ( isr            ),
	.mask   (                ),
	.index  ( irq_in_service )
);

wire  [3:0] highest_irq_pending;
wire [15:0] highest_irq_pending_mask;
mfp_hbit16 irq_pending_index (
	.value  ( ipr & imr                 ),
	.index  ( highest_irq_pending       ),
	.mask   ( highest_irq_pending_mask  )
);

wire [7:0] gpip_cpu_out = (i & ~ddr) | (gpip & ddr);

assign serial_status_out = {
	bitrate[7:0], bitrate[15:8], bitrate[23:16],
	databits, parity, stopbits };

wire [11:0] timerd_state = { timerd_ctrl_o, timerd_set_data };

wire [23:0] bitrate =
	(uart_ctrl[6] !=    1'b1)?24'h800000:
	(timerd_state == 12'h101)?24'd19200:
	(timerd_state == 12'h102)?24'd9600:
	(timerd_state == 12'h104)?24'd4800:
	(timerd_state == 12'h105)?24'd3600:
	(timerd_state == 12'h108)?24'd2400:
	(timerd_state == 12'h10a)?24'd2000:
	(timerd_state == 12'h10b)?24'd1800:
	(timerd_state == 12'h110)?24'd1200:
	(timerd_state == 12'h120)?24'd600:
	(timerd_state == 12'h140)?24'd300:
	(timerd_state == 12'h160)?24'd200:
	(timerd_state == 12'h180)?24'd150:
	(timerd_state == 12'h18f)?24'd134:
	(timerd_state == 12'h1af)?24'd110:
	(timerd_state == 12'h240)?24'd75:
	(timerd_state == 12'h260)?24'd50:
	24'h800001;

wire [1:0] parity =
	(uart_ctrl[1] == 1'b0)?2'h0:
	(uart_ctrl[0] == 1'b0)?2'h1:
	2'h02;

wire [1:0] stopbits =
	(uart_ctrl[3:2] == 2'b00)?2'h3:
	(uart_ctrl[3:2] == 2'b01)?2'h0:
	(uart_ctrl[3:2] == 2'b10)?2'h1:
	2'h2;

wire [3:0] databits =
	(uart_ctrl[5:4] == 2'b00)?4'd8:
	(uart_ctrl[5:4] == 2'b01)?4'd7:
	(uart_ctrl[5:4] == 2'b10)?4'd6:
	4'd5;

reg [1:0] uart_rx_ctrl;
reg [3:0] uart_tx_ctrl;
reg [6:0] uart_ctrl;
reg [7:0] uart_sync_chr;

wire [10:0] uart_prediv =
	   (timerd_ctrl_o[2:0] == 3'b000)?11'd0:
	   (timerd_ctrl_o[2:0] == 3'b001)?11'd40:
	   (timerd_ctrl_o[2:0] == 3'b010)?11'd100:
	   (timerd_ctrl_o[2:0] == 3'b011)?11'd160:
	   (timerd_ctrl_o[2:0] == 3'b100)?11'd500:
	   (timerd_ctrl_o[2:0] == 3'b101)?11'd600:
	   (timerd_ctrl_o[2:0] == 3'b110)?11'd1000:
	   11'd2000;

reg [15:0] uart_rx_prediv_cnt;
reg [15:0] uart_tx_prediv_cnt;
reg [7:0]  uart_tx_delay_cnt;
wire	   uart_tx_busy = uart_tx_delay_cnt != 8'd0;
reg [7:0]  uart_rx_delay_cnt;
assign     uart_rx_busy = uart_rx_delay_cnt != 8'd0;

wire	   serial_data_in_available = !serial_data_in_empty && !uart_rx_busy && !uart_rx_busyD;

always @(posedge clk) begin
   if(clk_ext) begin
      if(uart_rx_prediv_cnt != 16'd0)
	 uart_rx_prediv_cnt <= uart_rx_prediv_cnt - 16'd1;
      else begin
	 uart_rx_prediv_cnt <= { uart_prediv-11'd1, 5'b00000 };
	 if(uart_rx_delay_cnt != 8'd0)
	   uart_rx_delay_cnt <= uart_rx_delay_cnt - 8'd1;
      end
      if(uart_tx_prediv_cnt != 16'd0)
	 uart_tx_prediv_cnt <= uart_tx_prediv_cnt - 16'd1;
      else begin
	 uart_tx_prediv_cnt <= { uart_prediv-11'd1, 5'b00000 };
	 if(uart_tx_delay_cnt != 8'd0)
	   uart_tx_delay_cnt <= uart_tx_delay_cnt - 8'd1;
      end
   end
   if(serial_cpu_data_read && serial_data_in_available) begin
      uart_rx_delay_cnt <= timerd_set_data;
      uart_rx_prediv_cnt <= { uart_prediv-11'd1, 5'b00000 };
   end
   if(clk_en && ~bus_selD && bus_sel && (addr == 5'h17) && !rw) begin
      uart_tx_delay_cnt <= timerd_set_data;
      uart_tx_prediv_cnt <= { uart_prediv-11'd1, 5'b00000 };
   end
end

always @(*) begin
	dout = 8'd0;
	if(bus_sel && rw) begin
		if(addr == 5'h00) dout = gpip_cpu_out;
		if(addr == 5'h01) dout = aer;
		if(addr == 5'h02) dout = ddr;
		if(addr == 5'h03) dout = ier[15:8];
		if(addr == 5'h04) dout = ier[7:0];
		if(addr == 5'h06) dout = ipr[7:0];
		if(addr == 5'h05) dout = ipr[15:8];
		if(addr == 5'h07) dout = isr[15:8];
		if(addr == 5'h08) dout = isr[7:0];
		if(addr == 5'h09) dout = imr[15:8];
		if(addr == 5'h0a) dout = imr[7:0];
		if(addr == 5'h0b) dout = vr;
		if(addr == 5'h0c) dout = { 4'h0, timera_ctrl_o};
		if(addr == 5'h0d) dout = { 4'h0, timerb_ctrl_o};
		if(addr == 5'h0e) dout = { timerc_ctrl_o, timerd_ctrl_o};
		if(addr == 5'h0f) dout = timera_dat_o;
		if(addr == 5'h10) dout = timerb_dat_o;
		if(addr == 5'h11) dout = timerc_dat_o;
		if(addr == 5'h12) dout = timerd_dat_o;
		if(addr == 5'h13) dout = uart_sync_chr;
		if(addr == 5'h14) dout = { uart_ctrl, 1'b0 };
		if(addr == 5'h15) dout = { serial_data_in_available, 5'b00000 , uart_rx_ctrl};
		if(addr == 5'h16) dout = { !serial_data_out_fifo_full && !uart_tx_busy, 3'b000 , uart_tx_ctrl};
		if(addr == 5'h17) dout = serial_data_in_cpu;
	end else if(iack) begin
		dout = irq_vec;
	end
end

wire [7:0] ti_irq_mask = { 3'b000, pulse_mode, 3'b000};
wire [7:0] ti_irq      = { 3'b000, pulse_mode[1] ^ t_i[0], pulse_mode[0] ^ t_i[1], 3'b000};

reg [7:0] irq_vec;
wire [7:0] gpio_irq = ~aer ^ ((i & ~ti_irq_mask) | (ti_irq & ti_irq_mask));
reg [15:0] ipr_reset;
wire uart_rx_irq = serial_data_in_available;
wire uart_tx_irq = !serial_data_out_fifo_full && !serial_strobe_out;
wire [15:0] ipr_set = {
	gpio_irq[7:6], timera_done, uart_rx_irq,
	1'b0, uart_tx_irq, 1'b0, timerb_done,
	gpio_irq[5:4], timerc_done, timerd_done, gpio_irq[3:0]
};

mfp_srff16 ipr_latch (
	.clk    ( clk        ),
	.set    ( ipr_set    ),
	.mask   ( ier        ),
	.reset  ( ipr_reset  ),
	.out    ( ipr        )
);

reg [15:0] isr_reset;
reg [15:0] isr_set;
mfp_srff16 isr_latch (
	.clk    ( clk        ),
	.set    ( isr_set    ),
	.mask   ( 16'hffff   ),
	.reset  ( isr_reset  ),
	.out    ( isr        )
);

always @(posedge clk) begin
	ipr_reset <= 0;
	isr_reset <= 0;
	isr_set <= 0;
	if(reset) begin
		ipr_reset <= 16'hffff;
		isr_reset <= 16'hffff;
		ier <= 16'h0000;
		imr <= 16'h0000;
		isr_set <= 16'h0000;
		iack_ack <= 1'b0;
	end else begin
		if(iack_sel) begin
			ipr_reset[highest_irq_pending] <= 1'b1;
			isr_set <= vr[3]?highest_irq_pending_mask:16'h0000;
			isr_reset <= !vr[3]?highest_irq_pending_mask:16'h0000;
			irq_vec <= { vr[7:4], highest_irq_pending };
			iack_ack <= 1'b1;
		end
		if (~iack) iack_ack <= 1'b0;
		if(write) begin
			if(addr == 5'h00) gpip <= din;
			if(addr == 5'h01) aer <= din;
			if(addr == 5'h02) ddr <= din;
			if(addr == 5'h03) begin
				ier[15:8] <= din;
				ipr_reset[15:8] <= ipr_reset[15:8] | ~din;
			end
			if(addr == 5'h04) begin
				ier[7:0] <= din;
				ipr_reset[7:0] <= ipr_reset[7:0] | ~din;
			end
			if(addr == 5'h05) ipr_reset[15:8] <= ipr_reset[15:8] | ~din;
			if(addr == 5'h06) ipr_reset[7:0]  <= ipr_reset[7:0]  | ~din;
			if(addr == 5'h07) isr_reset[15:8] <= isr_reset[15:8] | ~din;
			if(addr == 5'h08) isr_reset[7:0]  <= isr_reset[7:0]  | ~din;
			if(addr == 5'h09) imr[15:8] <= din;
			if(addr == 5'h0a) imr[7:0]  <= din;
			if(addr == 5'h0b) begin
				vr <= din;
				if (!din[3]) isr_reset <= 16'hffff;
			end
			if(addr == 5'h13) uart_sync_chr <= din[1:0];
			if(addr == 5'h14) uart_ctrl     <= din[7:1];
			if(addr == 5'h15) uart_rx_ctrl  <= din[1:0];
			if(addr == 5'h16) uart_tx_ctrl  <= din[3:0];
		end
	end
end

endmodule
