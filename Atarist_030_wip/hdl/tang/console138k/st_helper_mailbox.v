// ===========================================================================
// st_helper_mailbox.v - ST <-> AE350 helper mailbox (build option ST_HELPER)
//
// A 32-byte register block in ST I/O space at $FFFB00-$FFFB1F (mirrored at
// $FFFFFB00 etc. by the 24-bit address mirror of the 030 bridge; A31:24 are
// not decoded). Supervisor data accesses only, like every ST I/O register:
// a user-mode access is not selected and gets the GSTMCU bus error.
// Registers are bytes on the odd addresses (D7:0, LDS), like the MFP; a word
// read returns $FF in D15:8. Decoded in atarist.v (`ifdef ST_HELPER).
//
//   $FFFB01 ID      R   'H' ($48)
//   $FFFB03 VER     R   $01
//   $FFFB05 STATUS  R   b0 TXRDY   TX FIFO has room
//                       b1 RXAVL   RX FIFO not empty
//                       b2 HUP     helper running (signalled flash-done)
//                       b3 HFAIL   helper boot failed, AE350 held in reset
//                       b4 RXOVR   sticky: byte dropped, RX FIFO was full
//                       b5 TXIDLE  TX FIFO empty and last byte fully sent
//                       b6 RXFERR  sticky: framing error on the helper TX
//   $FFFB07 TXDATA  W   queue one byte for the helper (dropped if full)
//                   R   free TX FIFO slots (0..16)
//   $FFFB09 RXDATA  R   next byte from the helper (removed from the FIFO
//                       at the END of the read cycle); $00 when empty
//   $FFFB0B RXCOUNT R   bytes waiting in the RX FIFO (saturates at 255)
//   $FFFB0D CTRL    W   b0 flush RX FIFO, b1 clear RXOVR/RXFERR,
//                       b2 flush TX FIFO; reads $00
//   $FFFB0F HGPIO   R   AE350 GPIO[7:0] (stable value; $A5 = flash done)
//   $FFFB11 BOOT    R   boot result: $00 helper up, $01 DDR3 timeout,
//                       $02 no flash-done, $03 S1 skip, $04 CS# never idle,
//                       $FF still booting (never seen by TOS)
//   $FFFB13-$FFFB1F SCRATCH0-6  R/W  ST-side scratch bytes (bus test)
//
// Transport to the AE350. The AE350 SoC as generated for this board has no
// AHB/APB slave port towards the fabric (only the Extended AHB *Master*
// port, through which the fabric masters into SoC memory). So the mailbox
// talks to the helper through the helper's own UART2, entirely inside the
// FPGA:
//   ST -> helper: TX FIFO (16 bytes) -> 8N1 115200 serialiser -> UART2_RXD
//   helper -> ST: UART2_TXD (the same line that goes to U15, so everything
//                 the helper prints is also on David's terminal) ->
//                 deserialiser -> RX FIFO (256 bytes, BSRAM)
// Both ends are in the clk32 domain; the only asynchronous input is
// UART2_TXD (2-flop synchroniser, then a 16x-style mid-bit sampler). UART2
// samples our RXD with its own oversampling clock. There is no multi-bit
// clock-domain crossing at all.
//
// Baud: fabric 32 MHz / 278 = 115108 (-0.08 %); AE350 50 MHz / (16 * 27) =
// 115741 (+0.47 %). 0.55 % mismatch, about 5 % of a bit after 10 bits.
// ===========================================================================
module st_helper_mailbox #(
    parameter [8:0] BAUD_DIV  = 9'd277,   // period - 1, clk32 cycles
    parameter [8:0] BAUD_HALF = 9'd138
)(
    input  wire        clk,          // clk32
    input  wire        rst,          // por

    // ST bus (atarist.v ext_io_*), all clk32 synchronous
    input  wire        cs,           // AS & supervisor data & $FFFB00-$FFFB1F
    input  wire        uds_n,
    input  wire        lds_n,
    input  wire        rw,
    input  wire [4:1]  a,
    input  wire [15:0] wdata,
    output wire [15:0] rdata,
    output reg         dtack,

    // helper side
    input  wire        ae_txd_a,     // AE350 UART2_TXD (async)
    output reg         ae_rxd,       // AE350 UART2_RXD
    input  wire        ae_run,       // AE350 out of reset
    input  wire        helper_up,
    input  wire        helper_fail,
    input  wire [7:0]  boot_code,
    input  wire [7:0]  ae_gpio
);
    // ---------------- bus handshake (MFP style) ----------------
    wire bsel = cs & (~uds_n | ~lds_n);
    reg  bsel_d;
    always @(posedge clk) begin
        bsel_d <= bsel;
        if (rst || !bsel) dtack <= 1'b0;
        else if (bsel_d)  dtack <= 1'b1;
    end
    // acc_stb: exactly one clk32 cycle per bus cycle, the cycle before DTACK
    // rises (>= 1 cycle after the select, so the registered RX FIFO read
    // port has caught up with a pop made at the end of the previous cycle).
    // Reads are snapshotted into rd_hold here, so the data the bridge latches
    // with DTACK never changes inside a bus cycle.
    wire acc_stb   = bsel & bsel_d & ~dtack;
    wire wr_stb    = acc_stb & ~rw & ~lds_n;               // one pulse per write
    wire rd_stb    = acc_stb &  rw;

    // ---------------- FIFOs ----------------
    reg  [7:0] tx_mem [0:15];
    reg  [4:0] tx_wr, tx_rd;                    // 5-bit: wrap flag
    wire [4:0] tx_cnt  = tx_wr - tx_rd;
    wire       tx_full = (tx_cnt == 5'd16);
    wire       tx_empty = (tx_cnt == 5'd0);

    reg  [7:0] rx_mem [0:255];
    reg  [8:0] rx_wr, rx_rd;
    wire [8:0] rx_cnt = rx_wr - rx_rd;
    reg  [7:0] rx_q;                            // registered BSRAM read of rx_mem[rx_rd]
    reg        rx_avail;                        // aligned with rx_q
    reg  [7:0] rx_cnt_sat;

    reg  [7:0] scratch [0:6];
    reg        rx_ovr, rx_ferr;
    reg        rx_pop_pend;
    reg  [7:0] rd_hold;
    reg  [7:0] rmux;                            // read mux, see the end of the file

    // ---------------- helper UART: TX to UART2_RXD ----------------
    reg  [8:0] tdiv;
    reg  [3:0] tbit;                            // 0 idle, 1 start, 2-9 data, 10 stop
    reg  [7:0] tsh;
    wire       tx_pop = (tbit == 4'd0) & ~tx_empty;
    always @(posedge clk) begin
        if (rst) begin
            tbit <= 4'd0; tdiv <= 9'd0; ae_rxd <= 1'b1; tsh <= 8'hFF;
        end else if (tbit == 4'd0) begin
            ae_rxd <= 1'b1;
            if (!tx_empty) begin
                tsh    <= tx_mem[tx_rd[3:0]];
                ae_rxd <= 1'b0;                 // start bit
                tbit   <= 4'd1;
                tdiv   <= 9'd0;
            end
        end else if (tdiv != BAUD_DIV) begin
            tdiv <= tdiv + 9'd1;
        end else begin
            tdiv <= 9'd0;
            if (tbit <= 4'd8) begin
                ae_rxd <= tsh[0];
                tsh    <= {1'b1, tsh[7:1]};
                tbit   <= tbit + 4'd1;
            end else if (tbit == 4'd9) begin
                ae_rxd <= 1'b1;                 // stop bit
                tbit   <= 4'd10;
            end else
                tbit   <= 4'd0;                 // stop bit done
        end
    end
    wire tx_idle = tx_empty & (tbit == 4'd0);

    // ---------------- helper UART: RX from UART2_TXD ----------------
    reg  [1:0] rxs;
    always @(posedge clk) rxs <= {rxs[0], ae_txd_a};
    wire rxd = rxs[1] | ~ae_run;                // AE350 in reset: line idle
    reg  [2:0] rst_st;                          // 0 idle 1 start 2 data 3 stop 4 wait-high
    reg  [8:0] rcnt;
    reg  [2:0] rbits;
    reg  [7:0] rsh;
    reg        rx_push;
    reg        rx_ferr_set;
    always @(posedge clk) begin
        rx_push <= 1'b0;
        rx_ferr_set <= 1'b0;
        if (rst) begin
            rst_st <= 3'd4; rcnt <= 9'd0; rbits <= 3'd0; rsh <= 8'd0;
        end else case (rst_st)
        3'd0: if (!rxd) begin rst_st <= 3'd1; rcnt <= BAUD_HALF; end
        3'd1: if (rcnt != 9'd0) rcnt <= rcnt - 9'd1;
              else if (rxd) rst_st <= 3'd0;     // glitch, not a start bit
              else begin rst_st <= 3'd2; rcnt <= BAUD_DIV; rbits <= 3'd0; end
        3'd2: if (rcnt != 9'd0) rcnt <= rcnt - 9'd1;
              else begin
                  rsh   <= {rxd, rsh[7:1]};     // LSB first
                  rcnt  <= BAUD_DIV;
                  rbits <= rbits + 3'd1;
                  if (rbits == 3'd7) rst_st <= 3'd3;
              end
        3'd3: if (rcnt != 9'd0) rcnt <= rcnt - 9'd1;
              else if (rxd) begin rx_push <= 1'b1; rst_st <= 3'd0; end
              else begin rx_ferr_set <= 1'b1; rst_st <= 3'd4; end
        default: if (rxd) rst_st <= 3'd0;       // wait for the line to idle
        endcase
    end

    // ---------------- FIFO / register state ----------------
    // RX FIFO storage and registered read port (BSRAM)
    always @(posedge clk) begin
        if (rx_push && rx_cnt != 9'd256) rx_mem[rx_wr[7:0]] <= rsh;
        rx_q <= rx_mem[rx_rd[7:0]];
    end
    // TX FIFO storage (LUT RAM, asynchronous read by the serialiser)
    always @(posedge clk)
        if (wr_stb && a == 4'd3 && !tx_full) tx_mem[tx_wr[3:0]] <= wdata[7:0];

    integer i;
    always @(posedge clk) begin
        rx_avail   <= (rx_cnt != 9'd0);          // aligned with rx_q
        rx_cnt_sat <= (rx_cnt > 9'd255) ? 8'd255 : rx_cnt[7:0];
        if (rst) begin
            tx_wr <= 5'd0; tx_rd <= 5'd0; rx_wr <= 9'd0; rx_rd <= 9'd0;
            rx_ovr <= 1'b0; rx_ferr <= 1'b0; rx_pop_pend <= 1'b0; rd_hold <= 8'h00;
            for (i = 0; i < 7; i = i + 1) scratch[i] <= 8'h00;
        end else begin
            // RX producer
            if (rx_push) begin
                if (rx_cnt != 9'd256) rx_wr <= rx_wr + 9'd1;
                else                  rx_ovr <= 1'b1;
            end
            if (rx_ferr_set) rx_ferr <= 1'b1;
            // TX consumer
            if (tx_pop) tx_rd <= tx_rd + 5'd1;
            // bus read: snapshot (see acc_stb)
            if (rd_stb) begin
                rd_hold <= rmux;
                    if (!lds_n && a == 4'd4 && rx_avail) rx_pop_pend <= 1'b1;
            end
            // RXDATA: remove the byte when the read cycle has ended
            if (rx_pop_pend && !bsel) begin
                rx_pop_pend <= 1'b0;
                rx_rd <= rx_rd + 9'd1;
            end
            // bus writes
            if (wr_stb) begin
                case (a)
                4'd3: if (!tx_full) tx_wr <= tx_wr + 5'd1;
                4'd6: begin
                    if (wdata[0]) rx_rd <= rx_wr;
                    if (wdata[1]) begin rx_ovr <= 1'b0; rx_ferr <= 1'b0; end
                    if (wdata[2]) tx_wr <= tx_rd + (tx_pop ? 5'd1 : 5'd0);
                end
                4'd9, 4'd10, 4'd11, 4'd12, 4'd13, 4'd14, 4'd15:
                    scratch[a - 4'd9] <= wdata[7:0];
                default: ;
                endcase
            end
        end
    end

    // ---------------- read mux ----------------
    wire [7:0] status = { 1'b0, rx_ferr, tx_idle, rx_ovr, helper_fail, helper_up,
                          rx_avail, ~tx_full };
    always @* begin
        case (a)
        4'd0: rmux = 8'h48;                         // 'H'
        4'd1: rmux = 8'h01;
        4'd2: rmux = status;
        4'd3: rmux = {3'd0, 5'd16 - tx_cnt};
        4'd4: rmux = rx_avail ? rx_q : 8'h00;
        4'd5: rmux = rx_cnt_sat;
        4'd6: rmux = 8'h00;
        4'd7: rmux = ae_gpio;
        4'd8: rmux = boot_code;
        default: rmux = scratch[a - 4'd9];
        endcase
    end
    assign rdata = {8'hFF, rd_hold};
endmodule
