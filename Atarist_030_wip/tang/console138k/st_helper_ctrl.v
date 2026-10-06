// ===========================================================================
// st_helper_ctrl.v - boot-then-release of the external SPI NOR flash
// (Atarist_030_wip, build option ST_HELPER, build_st_helper.tcl only)
//
// One flash chip, two masters, ONE handover, never back:
//
//   power-up -> ST (030, chipset, ST flash controller) held in reset,
//               flash pads on the AE350 RISC-V SoC
//            -> DDR3 trains -> 20 ms -> AE350 released. Its boot loader
//               (0x80000000 = flash XIP window) copies ready.bin /
//               helper_mailbox.bin from flash 0x0600000 into DDR and jumps
//               there. main() drives GPIO[7:0] = 0xA5 = "done with flash".
//            -> fabric sees 0xA5 (stable), waits until the AE350's flash
//               CS# has been high for 8 us, then flips flash_to_st. The ST
//               flash controller is still in reset (its CS# is high too),
//               so CS# is high on both sides of the mux when it switches.
//            -> 2 us later the ST is released: the ST flash controller runs
//               its init (16 ones on IO0, exits any continuous-read mode),
//               flash_ready rises and TOS 2.06 boots from 0x500000.
//
//   flash_to_st is a sticky register: once set it is only cleared by
//   power-up (por). After it is set the AE350 flash ports never reach the
//   flash balls again (CS# goes nowhere; CLK/MOSI/MISO become the
//   FPGA-Companion link to mcu_spi once helper_up is set, see
//   st_helper_mculink.v), so whatever the AE350 does later it cannot reach
//   the flash or disturb a TOS ROM fetch. The AE350 runs from DDR3.
//
//   Fallback (the desktop must always boot): if DDR3 does not train within
//   T_DDR, or the firmware does not signal 0xA5 within T_HS after its
//   reset is released, or the AE350 CS# never goes idle, or S1 is pressed
//   during the helper boot, the AE350 is put (back) into reset, the fabric
//   waits 1 ms (CS# high), flips the flash to the ST and boots TOS without
//   the helper. Worst case the desktop starts ~T_DDR + T_HS later than the
//   desktop build (about 6 s); normally it is delayed by DDR3 training
//   plus 20 ms plus the helper's copy (well under a second).
//
// Why this is safe where the earlier runtime mux (988c846, 5630a36) was not:
//   * those muxes put an always-driven assign between the ST flash
//     controller and the IO1/IO0 balls. The ST controller reads the flash
//     in DUAL I/O mode (0xBB, flash_dspi.v): IO1 (mspi_do, R22) and IO0
//     are bidirectional. Behind a plain assign the FPGA drove IO1 while the
//     flash was driving it, so every TOS word read back wrong and nothing
//     booted. Here the ST controller's output enables reach the pad buffers
//     (top.sv builds the IOBUFs with the ST's own OE), so the dual-I/O
//     turnaround is exactly as in the desktop build.
//   * the switch happens once, while both CS# are high and the ST is in
//     reset, instead of at run time under a live controller.
//   * the ST flash controller is (re)initialised AFTER the switch, so the
//     flash state left by the AE350 does not matter.
//
// Fabric letters on U15 (115200 8N1, only while the AE350 is in reset, so
// they never collide with the AE350's own text):
//   "STH" CR LF  fabric up (lead, pin and baud are good)
//   'D'          DDR3 trained          'X' DDR3 did not train (T_DDR)
//   'R'          AE350 reset released, the next text is the AE350's own
//   'T' CR LF    no 0xA5 from the firmware within T_HS: AE350 reset again,
//                desktop boots without the helper
//   'C' CR LF    AE350 CS# never idle AND 0xA5 gone: AE350 reset, desktop
//                boots. (CS# still low 1 ms after a valid 0xA5 is not a
//                failure: the switch is forced, BOOT = 5, see S_CSIDLE.)
//   'K' CR LF    S1 pressed: helper skipped, desktop boots
//   ('X' is also followed by CR LF and the desktop boot.)
//
// boot_code (mailbox register BOOT): 0 = helper running, 1 = DDR3 timeout,
// 2 = handshake timeout, 3 = S1 skip, 4 = CS# never idle (0xA5 lost),
// 5 = helper running, switch forced with the AE350 CS# still low,
// $FF = booting.
//
// All logic is in the clk32 domain. Asynchronous inputs (DDR3 init, AE350
// GPIO, AE350 flash CS#, S1) go through 2-flop synchronisers; the 8-bit
// GPIO value is only trusted after 4 identical consecutive samples.
// ===========================================================================
module st_helper_ctrl #(
    parameter integer CLK_HZ   = 32_000_000,
    parameter [31:0] T_DDR     = 32'd128_000_000, // 4 s   DDR3 training limit
    parameter [31:0] T_DEB     = 32'd640_000,     // 20 ms DDR3_INIT stable (hybrid key_debounce)
    parameter [31:0] T_HS      = 32'd64_000_000,  // 2 s   firmware must signal 0xA5
    parameter [31:0] T_CSIDLE  = 32'd256,         // 8 us  AE350 CS# high before the switch
    parameter [31:0] T_CSMAX   = 32'd32_000,      // 1 ms  then switch anyway if 0xA5 is still there
    parameter [31:0] T_RSTWAIT = 32'd32_000,      // 1 ms  after re-asserting AE350 reset
    parameter [31:0] T_SETTLE  = 32'd64,          // 2 us  after the switch, before ST release
    parameter [7:0]  HS_CODE   = 8'hA5,
    parameter [8:0]  BAUD_DIV  = 9'd277           // 32 MHz / 278 = 115108 baud
)(
    input  wire       clk,          // clk32
    input  wire       rst,          // por (PLL not locked)

    input  wire       ddr3_init_a,  // DDR3_INIT from the SoC (async)
    input  wire [7:0] ae_gpio_a,    // AE350 GPIO[7:0] (APB domain, async)
    input  wire       ae_csn_a,     // AE350 FLASH_SPI_CSN (async)
    input  wire       s1_n_a,       // S1 button, low = pressed (async)

    output reg        ae_run,       // AE350 POR_RSTN/HW_RSTN
    output reg        flash_to_st,  // 1 = flash pads belong to the ST (sticky)
    output reg        st_release,   // 1 = release the ST and its flash controller
    output reg        helper_up,    // AE350 signalled 0xA5 and owns DDR3 code
    output reg        helper_fail,  // fallback taken, AE350 held in reset
    output reg  [7:0] boot_code,
    output wire [7:0] ae_gpio,      // synchronised, stable GPIO[7:0]
    output wire       fab_tx        // fabric UART letters (idle high)
);
    // ---------------- synchronisers ----------------
    reg [1:0] ddr_s, csn_s, s1_s;
    reg [7:0] g_s0, g_s1, g_prev, g_stable;
    reg [1:0] g_same;
    always @(posedge clk) begin
        ddr_s <= {ddr_s[0], ddr3_init_a};
        csn_s <= {csn_s[0], ae_csn_a};
        s1_s  <= {s1_s[0], s1_n_a};
        g_s0  <= ae_gpio_a;
        g_s1  <= g_s0;
        g_prev <= g_s1;
        if (g_s1 == g_prev) begin
            if (g_same != 2'b11) g_same <= g_same + 2'b01;
            else                 g_stable <= g_s1;
        end else
            g_same <= 2'b00;
    end
    assign ae_gpio = g_stable;
    wire ddr_ok   = ddr_s[1];
    wire csn_high = csn_s[1];
    wire s1_press = ~s1_s[1];

    // ---------------- tiny UART for the letters ----------------
    reg  [8:0] u_div;
    reg  [3:0] u_bit;       // 0 = idle
    reg  [8:0] u_sh;        // {data, start}
    reg        u_tx;
    reg        u_go;
    reg  [7:0] u_char;
    wire       u_busy = (u_bit != 4'd0) | u_go;
    assign fab_tx = u_tx;
    always @(posedge clk) begin
        if (rst) begin
            u_div <= 9'd0; u_bit <= 4'd0; u_tx <= 1'b1; u_sh <= 9'h1FF;
        end else if (u_bit == 4'd0) begin
            u_tx <= 1'b1;
            if (u_go) begin
                u_sh  <= {u_char, 1'b0};
                u_bit <= 4'd1;
                u_div <= 9'd0;
            end
        end else if (u_div != BAUD_DIV) begin
            u_div <= u_div + 9'd1;
        end else begin
            u_div <= 9'd0;
            if (u_bit == 4'd1) u_tx <= 1'b0;            // start bit
            else if (u_bit <= 4'd9) u_tx <= u_sh[u_bit - 4'd1];
            else u_tx <= 1'b1;                           // stop bit
            u_bit <= (u_bit == 4'd10) ? 4'd11 : u_bit + 4'd1;
            if (u_bit == 4'd11) u_bit <= 4'd0;           // one full stop bit sent
        end
    end

    // ---------------- boot FSM ----------------
    localparam [3:0] S_BANNER = 4'd0, S_DDR = 4'd1, S_DEB = 4'd2, S_RLET = 4'd3,
                     S_WAITHS = 4'd4, S_CSIDLE = 4'd5, S_SETTLE = 4'd6, S_RUN = 4'd7,
                     S_FAIL = 4'd8, S_FSWITCH = 4'd9, S_FLET = 4'd10, S_DEAD = 4'd11;
    reg [3:0]  st;
    reg [31:0] t;          // state timer
    reg [31:0] tc;         // CS# idle counter
    reg [2:0]  msg;        // letter index within a short message
    reg [1:0]  hs_cnt;
    reg [7:0]  fail_letter;
    reg        cs_forced;  // switched after T_CSMAX with CS# still low


    always @(posedge clk) begin
        if (rst) begin
            st <= S_BANNER; t <= 32'd0; tc <= 32'd0; msg <= 3'd0; hs_cnt <= 2'd0;
            ae_run <= 1'b0; flash_to_st <= 1'b0; st_release <= 1'b0;
            helper_up <= 1'b0; helper_fail <= 1'b0; boot_code <= 8'hFF;
            u_go <= 1'b0; u_char <= 8'h00; fail_letter <= 8'h00; cs_forced <= 1'b0;
        end else begin
            u_go <= 1'b0;
            if (t != 32'hFFFF_FFFF) t <= t + 32'd1;
            case (st)
            S_BANNER: if (!u_busy) begin
                case (msg)
                3'd0: begin u_char <= 8'h53; u_go <= 1'b1; end   // S
                3'd1: begin u_char <= 8'h54; u_go <= 1'b1; end   // T
                3'd2: begin u_char <= 8'h48; u_go <= 1'b1; end   // H
                3'd3: begin u_char <= 8'h0D; u_go <= 1'b1; end
                default: begin u_char <= 8'h0A; u_go <= 1'b1; end
                endcase
                if (msg == 3'd4) begin msg <= 3'd0; st <= S_DDR; t <= 32'd0; end
                else msg <= msg + 3'd1;
            end
            S_DDR: begin
                if (s1_press) begin
                    boot_code <= 8'd3; fail_letter <= 8'h4B; st <= S_FAIL; t <= 32'd0;  // K
                end else if (ddr_ok) begin
                    if (!u_busy) begin begin u_char <= 8'h44; u_go <= 1'b1; end st <= S_DEB; t <= 32'd0; end     // D
                end else if (t >= T_DDR) begin
                    boot_code <= 8'd1; fail_letter <= 8'h58; st <= S_FAIL; t <= 32'd0; // X
                end
            end
            S_DEB: begin
                if (s1_press) begin
                    boot_code <= 8'd3; fail_letter <= 8'h4B; st <= S_FAIL; t <= 32'd0;
                end else if (!ddr_ok) begin
                    t <= 32'd0;                                  // restart the 20 ms
                end else if (t >= T_DEB && !u_busy) begin
                    begin u_char <= 8'h52; u_go <= 1'b1; end                                 // R
                    st <= S_RLET; t <= 32'd0;
                end
            end
            S_RLET: if (!u_busy) begin                           // 'R' fully sent
                ae_run <= 1'b1;                                  // U15 now carries AE350 text
                st <= S_WAITHS; t <= 32'd0; hs_cnt <= 2'd0;
            end
            S_WAITHS: begin
                if (s1_press) begin
                    boot_code <= 8'd3; fail_letter <= 8'h4B; st <= S_FAIL; t <= 32'd0;
                end else if (ae_gpio == HS_CODE) begin
                    st <= S_CSIDLE; t <= 32'd0; tc <= 32'd0;
                end else if (t >= T_HS) begin
                    boot_code <= 8'd2; fail_letter <= 8'h54; st <= S_FAIL; t <= 32'd0; // T
                end
            end
            S_CSIDLE: begin
                if (!csn_high) tc <= 32'd0;
                else if (tc != 32'hFFFF_FFFF) tc <= tc + 32'd1;
                if (csn_high && tc >= T_CSIDLE) begin
                    flash_to_st <= 1'b1;                         // the one-way switch
                    st <= S_SETTLE; t <= 32'd0;
                end else if (t >= T_CSMAX) begin
                    // CS# not idle 1 ms after 0xA5. Seen on hardware (6 Oct
                    // 2026): the AE350 flash controller can leave CS# low
                    // after its last memory-mapped read although the CPU
                    // runs from DDR3. The firmware has said it is done with
                    // the flash (0xA5 is still there, checked again here),
                    // so switch anyway: the flash sees CS# rise (the ST's
                    // CS# is high, the ST is in reset), which ends any read,
                    // and the ST flash controller re-initialises the flash
                    // (16 ones on IO0 also leave a continuous-read mode).
                    if (ae_gpio == HS_CODE) begin
                        flash_to_st <= 1'b1;
                        cs_forced   <= 1'b1;
                        st <= S_SETTLE; t <= 32'd0;
                    end else begin
                        boot_code <= 8'd4; fail_letter <= 8'h43; st <= S_FAIL; t <= 32'd0; // C
                    end
                end
            end
            S_SETTLE: if (t >= T_SETTLE) begin
                st_release <= 1'b1;
                helper_up  <= 1'b1;
                boot_code  <= cs_forced ? 8'd5 : 8'd0;
                st <= S_RUN;
            end
            S_RUN: ;                                             // stay here until power-off
            // ---------------- fallback: boot the desktop without the helper -----
            S_FAIL: begin
                ae_run <= 1'b0;                                  // AE350 (back) into reset
                if (t >= T_RSTWAIT) begin                        // its CS# is high now
                    flash_to_st <= 1'b1;
                    st <= S_FSWITCH; t <= 32'd0;
                end
            end
            S_FSWITCH: if (t >= T_SETTLE) begin
                st_release  <= 1'b1;
                helper_fail <= 1'b1;
                st <= S_FLET; msg <= 3'd0;
            end
            S_FLET: if (!u_busy) begin                           // fabric owns U15 again
                case (msg)
                3'd0: begin u_char <= fail_letter; u_go <= 1'b1; end
                3'd1: begin u_char <= 8'h0D; u_go <= 1'b1; end
                default: begin u_char <= 8'h0A; u_go <= 1'b1; end
                endcase
                if (msg == 3'd2) st <= S_DEAD;
                else msg <= msg + 3'd1;
            end
            default: ;                                           // S_DEAD
            endcase
        end
    end
endmodule
