// =====================================================================
// falcon_timebase.v  --  m10: hardware timebase for FalconFPGA
//
// A programmable timer block on the existing 50 MHz AHB_CLK domain. No
// PLL, no new clock domain, no CDC: every rate is an integer counter
// period off 50.000 MHz, and the periods are sub-ppm exact for the
// rates that matter (hz_200 = /250000 = 0.0 ppm; VBL 60Hz = /833333 =
// +0.4 ppm; VBL 50Hz = /1000000 = 0.0 ppm).
//
// The block maintains three free-running quantities and publishes a
// snapshot to a small DDR3 mailbox (via the HID AHB writer's spare
// event slot) at a fixed cadence:
//   - tick200 : increments at 200 Hz            (Timer C / hz_200 root)
//   - tickvbl : increments at the VBL rate      (blink/VBL cadence)
//   - cyc50   : free-running 50 MHz cycle count  (mtime cross-check)
//
// Periods are parameters here (firmware default matches), and also
// runtime-writable through the config strobe so firmware can trim the
// 0.4 ppm VBL or switch 60<->50 Hz without a reflash.
//
// Firmware consumes the published tick200/tickvbl as the authoritative
// timer source; if this block is absent (older bitstream) the mailbox
// slot stays zero and firmware falls back to its wall-locked-mcycle
// timers -- so a bitstream rollback needs no firmware change.
//
// This module is intentionally pure synchronous logic: its correctness
// is fully checkable in Icarus (tb_falcon_timebase.v). PLL lock, clock
// routing, etc. do not apply -- there is no new clock here.
// =====================================================================
module falcon_timebase #(
    parameter [31:0] PERIOD_200 = 32'd250000,   // 50e6/200  exact
    parameter [31:0] PERIOD_VBL = 32'd833333,   // 50e6/60    +0.4ppm
    parameter [31:0] PUBLISH_DIV = 32'd50000    // publish snapshot @1kHz
)(
    input  wire        clk,        // 50 MHz AHB_CLK
    input  wire        rstn,

    // optional runtime period trim (firmware -> fabric). Pulse cfg_we
    // for one clk with cfg_sel/cfg_val set; 0 sel = 200, 1 = VBL.
    input  wire        cfg_we,
    input  wire        cfg_sel,
    input  wire [31:0] cfg_val,

    // published snapshot, updated every PUBLISH_DIV cycles. Consumed by
    // the HID AHB writer as an extra event record.
    output reg  [31:0] tick200,
    output reg  [31:0] tickvbl,
    output reg  [31:0] cyc50,
    output reg         snap_stb    // 1-clk strobe when a new snapshot is ready
);
    reg [31:0] per200, pervbl;
    reg [31:0] cnt200, cntvbl, cntpub;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            per200 <= PERIOD_200;
            pervbl <= PERIOD_VBL;
            cnt200 <= 32'd0; cntvbl <= 32'd0; cntpub <= 32'd0;
            tick200 <= 32'd0; tickvbl <= 32'd0; cyc50 <= 32'd0;
            snap_stb <= 1'b0;
        end else begin
            snap_stb <= 1'b0;

            // runtime period trim
            if (cfg_we) begin
                if (cfg_sel) pervbl <= cfg_val;
                else         per200 <= cfg_val;
            end

            // free-running 50 MHz cycle counter
            cyc50 <= cyc50 + 32'd1;

            // hz_200 tick
            if (cnt200 >= per200 - 32'd1) begin
                cnt200  <= 32'd0;
                tick200 <= tick200 + 32'd1;
            end else begin
                cnt200 <= cnt200 + 32'd1;
            end

            // VBL tick
            if (cntvbl >= pervbl - 32'd1) begin
                cntvbl  <= 32'd0;
                tickvbl <= tickvbl + 32'd1;
            end else begin
                cntvbl <= cntvbl + 32'd1;
            end

            // publish cadence
            if (cntpub >= PUBLISH_DIV - 32'd1) begin
                cntpub   <= 32'd0;
                snap_stb <= 1'b1;
            end else begin
                cntpub <= cntpub + 32'd1;
            end
        end
    end
endmodule
