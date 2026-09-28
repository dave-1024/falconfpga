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
	output [7:0]     serial_data_out_available,  // bytes available
	output [7:0]     serial_data_in_free,        // free buffer available
	input            serial_strobe_out,
	output     [7:0] serial_data_out,
	output    [31:0] serial_status_out,

	// serial rs223 connection from io controller
	input            serial_strobe_in,
	input      [7:0] serial_data_in,

	// inputs
	input            clk_ext,   // external 2.457MHz
	input      [1:0] t_i,  // timer input
	input      [7:0] i,    // input port

	// Bring-up only. One clk cycle per Timer C timeout. Silent until
	// software starts the timer. TOS uses Timer C as the 200 Hz tick.
	output           timerc_pulse
);

// report the available unused space in the input fifo
assign serial_data_in_free = { 4'h0, serial_data_in_space };   

wire serial_data_out_fifo_full;
wire serial_data_in_full;

wire write = clk_en & ~bus_selD & bus_sel & ~rw;
PLACEHOLDER