// ===========================================================================
// st_helper_cart_rom.v - ST_HELPER_CART self-test cartridge ROM ($FA0000)
//
// 512 x 16 (1 KB) block RAM ROM, contents from st_helper_cart.hex, which
// helper_fw/st_test/build.sh generates from mbxcart.s (committed, because
// the laptop has no m68k toolchain). Same $readmemh pattern as the IKBD ROM.
//
// The GSTMCU acknowledges ROM4 ($FAxxxx) reads at once, as for the TOS ROM,
// and the 68030 bridge latches the data at the end of the ST bus cycle, so
// a registered read (one clk32 cycle after the address) is in time and
// keeps the ROM out of the clk_cpu030 data path (a combinational case ROM
// cost 2300 LUTs and failed clk_cpu030 timing).
// ===========================================================================
module st_helper_cart_rom (
    input  wire        clk,     // clk32
    input  wire [9:1]  a,
    output reg  [15:0] d
);
    reg [15:0] rom [0:511];
    initial $readmemh("st_helper_cart.hex", rom);
    always @(posedge clk) d <= rom[a];
endmodule
