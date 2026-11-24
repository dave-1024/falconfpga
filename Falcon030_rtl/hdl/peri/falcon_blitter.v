// falcon_blitter.v - FAL_01: Falcon blitter at $FF8A00-$FF8A3F (replaces the instant-complete stub)
//
// FalconFPGA, Falcon030_rtl. Copyright (C) 2026 FalconFPGA project (dave-1024).
// SPDX-License-Identifier: GPL-3.0-or-later  (this wrapper only; stBlitter.sv keeps its own header)
//
// Reuses the proven FX ST/STE blitter (Atarist_030_wip/hdl/atarist/stBlitter.sv, Jorge Cwik,
// shared by path, unchanged; board-tested on the ST core with BLTTEST/BLTMASK). It is a 68000-bus
// part, so this block gives it a small private 68000-style bus on clk_32 (enPhi1/enPhi2 alternate
// every clk_32 = 16 MHz bus, like atarist.v with cpu_16mhz_enable):
//   - CPU register cycles: falcon_core routes $FF8A00-$FF8A3F as a clk_32 ("io_ext") cycle. While
//     sel is high and done is low we drive AS/UDS/LDS/RW/A/D with FC=101 for 2 clk_32 (exactly one
//     enPhi1 edge, where stBlitter latches), take the read data, then raise done until sel drops.
//   - Bus arbitration: stBlitter's BR (oBRn) / BGACK (busOwned) become br_want (level to clk_cpu).
//     falcon_bus grants (bus_grant, clk_cpu) only between CPU cycles and then starts no new cycle
//     until br_want drops: the same effect as BR/BG/BGACK on the 030, without touching WF68K30L.
//     bus_grant (synchronised) drives BGIn. iBGACKn/iBRn are 1 (no other masters).
//   - Shared (non-HOG) mode: stBlitter counts AS edges of all bus masters (64 blitter / 64 CPU).
//     falcon_bus toggles cpu_cyc_tog on every CPU cycle start; each toggle puts a 2-clock AS pulse
//     (A=0, not selected) on the private bus so the count includes CPU cycles.
//   - Master cycles: when the blitter owns the bus and AS+DS are low, one request to the SDRAM
//     arbiter CPU port (falcon_soc muxes it with bus_grant), 4-phase (req until ack, no new req
//     while ack is high). DTACK low until AS rises. Writes at or above $E00000 (ROM copy / IO) are
//     dropped and acknowledged, like falcon_bus ROM writes; reads go to SDRAM (ROM reads: M11g).
//   - INTn (low = done) goes to MFP GPIP3 like the ST/Falcon.
module falcon_blitter (
    input  wire        clk_32,
    input  wire        reset,          // por | user_reset (sync, clk_32)
    input  wire        pwr_up,         // por
    // CPU register port (levels from falcon_core, clk_cpu registered, held for the IO cycle)
    input  wire        sel,
    input  wire [5:1]  a,
    input  wire        rw,             // 1 = read
    input  wire        uds, lds,
    input  wire [15:0] wdata,
    output reg  [15:0] rdata,
    output reg         done,
    // arbitration with falcon_bus (clk_cpu)
    output wire        br_want,        // blitter wants / owns the bus
    input  wire        bus_grant,      // falcon_bus: CPU is parked
    input  wire        cpu_cyc_tog,    // toggles on each CPU bus cycle start
    // SDRAM arbiter port (clk_32), used only while grant_32 is high
    output wire        grant_32,
    output reg         m_req,
    output reg  [23:1] m_a,
    output reg         m_we,
    output reg  [15:0] m_wdata,
    input  wire        m_ack,
    input  wire [15:0] m_rdata,
    output wire        irq_n
);
    // 16 MHz bus phases
    reg ph = 1'b0;
    always @(posedge clk_32) ph <= reset ? 1'b0 : ~ph;
    wire enPhi1 = ~ph, enPhi2 = ph;

    reg [1:0] g_s = 2'b00;
    always @(posedge clk_32) g_s <= {g_s[0], bus_grant};
    assign grant_32 = g_s[1];

    reg [2:0] tog_s = 3'b000;
    always @(posedge clk_32) tog_s <= {tog_s[1:0], cpu_cyc_tog};
    wire cpu_cyc = tog_s[2] ^ tog_s[1];

    // stBlitter outputs
    wire b_ctrlOe, b_dataOe, b_oASn, b_oDSn, b_oRWn, b_oDTACKn, b_sel, b_oBRn, b_oBGACKn, b_INTn, b_BGOn;
    wire [23:1] b_oA;
    wire [15:0] b_oD;

    // private bus, CPU side
    reg        c_as_n = 1'b1;
    reg        c_uds_n = 1'b1, c_lds_n = 1'b1, c_rw = 1'b1;
    reg [23:1] c_a = 23'd0;
    reg [1:0]  c_cnt;
    reg [1:0]  p_cnt = 2'd0;          // pseudo AS for CPU cycles
    localparam C_IDLE = 2'd0, C_AS = 2'd1, C_FIN = 2'd2;
    reg [1:0]  c_st = C_IDLE;
    always @(posedge clk_32) begin
        if (reset) begin
            c_st <= C_IDLE; c_as_n <= 1'b1; c_uds_n <= 1'b1; c_lds_n <= 1'b1; c_rw <= 1'b1;
            done <= 1'b0; p_cnt <= 2'd0;
        end else begin
            case (c_st)
                C_IDLE: begin
                    if (sel && !done && !b_ctrlOe) begin
                        c_a <= {18'h3FE28, a};            // $FF8A00 + a
                        c_rw <= rw; c_uds_n <= !uds; c_lds_n <= !lds;
                        c_as_n <= 1'b0; c_cnt <= 2'd0; c_st <= C_AS;
                    end else if (!sel) done <= 1'b0;
                    if (cpu_cyc) p_cnt <= 2'd2;
                    else if (p_cnt != 2'd0) p_cnt <= p_cnt - 2'd1;
                end
                C_AS: begin
                    c_cnt <= c_cnt + 2'd1;
                    if (c_cnt == 2'd1) begin
                        rdata <= b_oD;
                        c_as_n <= 1'b1; c_uds_n <= 1'b1; c_lds_n <= 1'b1; c_rw <= 1'b1;
                        c_st <= C_FIN;
                    end
                end
                C_FIN: begin done <= 1'b1; c_st <= C_IDLE; end
                default: c_st <= C_IDLE;
            endcase
        end
    end
    wire p_as_n = (p_cnt == 2'd0);

    // mux: blitter master or CPU register / pseudo cycles
    wire        bus_as_n  = b_ctrlOe ? b_oASn : (c_as_n & p_as_n);
    wire        bus_rw    = b_ctrlOe ? b_oRWn : (c_as_n ? 1'b1 : c_rw);
    wire        bus_uds_n = b_ctrlOe ? b_oDSn : c_uds_n;
    wire        bus_lds_n = b_ctrlOe ? b_oDSn : c_lds_n;
    wire [23:1] bus_a     = b_ctrlOe ? b_oA   : (c_as_n ? 23'd0 : c_a);
    wire [2:0]  bus_fc    = b_ctrlOe ? 3'b101 : (c_as_n ? 3'b000 : 3'b101);

    // master cycles -> SDRAM arbiter
    reg        m_busy = 1'b0;          // request issued for this AS
    reg        m_dtack_n = 1'b1;
    reg [15:0] m_q = 16'd0;
    always @(posedge clk_32) begin
        if (reset) begin
            m_req <= 1'b0; m_busy <= 1'b0; m_dtack_n <= 1'b1; m_we <= 1'b0;
        end else begin
            if (!b_ctrlOe || b_oASn) begin
                m_dtack_n <= 1'b1;
                if (!m_req) m_busy <= 1'b0;
            end
            if (b_ctrlOe && !b_oASn && !b_oDSn && !m_busy && !m_ack) begin
                m_busy <= 1'b1;
                m_a <= b_oA; m_we <= !b_oRWn; m_wdata <= b_oD;
                if (!b_oRWn && b_oA[23:21] == 3'b111) m_dtack_n <= 1'b0;   // >= $E00000: drop write
                else m_req <= 1'b1;
            end
            if (m_req && m_ack) begin
                m_req <= 1'b0; m_q <= m_rdata; m_dtack_n <= 1'b0;
            end
        end
    end

    assign br_want = !b_oBRn || !b_oBGACKn;
    assign irq_n   = b_INTn;

    stBlitter blt (
        .clk(clk_32), .aRESETn(!reset), .pwrUp(pwr_up),
        .enPhi1(enPhi1), .enPhi2(enPhi2),
        .ASn(bus_as_n), .RWn(bus_rw), .LDSn(bus_lds_n), .UDSn(bus_uds_n),
        .FC0(bus_fc[0]), .FC1(bus_fc[1]), .FC2(bus_fc[2]),
        .BERRn(1'b1), .iDTACKn(m_dtack_n),
        .ctrlOe(b_ctrlOe), .dataOe(b_dataOe), .oASn(b_oASn), .oDSn(b_oDSn), .oRWn(b_oRWn),
        .oDTACKn(b_oDTACKn), .selected(b_sel),
        .iBRn(1'b1), .BGIn(!grant_32), .iBGACKn(1'b1),
        .oBRn(b_oBRn), .oBGACKn(b_oBGACKn), .INTn(b_INTn), .BGOn(b_BGOn),
        .dmaInput(m_q),
        .iABUS(bus_a), .oABUS(b_oA),
        .iDBUS(wdata), .oDBUS(b_oD)
    );
endmodule
