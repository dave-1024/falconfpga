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
//     sel is high and done is low we start AS on enPhi2, keep it low through the next enPhi1
//     (where stBlitter latches writes) and sample the combinational read data on the following
//     enPhi2, then raise done until sel drops.
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
    output wire        irq_n,
    output wire [127:0] dbg,         // HUD: 4 x 32-bit live slots (clk_32, no handshake)
    output wire [255:0] dbg_snap     // HUD: frozen 8-entry blit-start ring (dialog debug)
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
    // stBlitter latches register writes on enPhi1 while AS/UDS/LDS are already
    // low (wrWordSel / ctrlWr). A fixed 2-clock AS window that can start on
    // enPhi1 raises AS on the same edge as the latch, so half of all writes
    // (including $FF8A3C start and TAS) are dropped. Start AS on enPhi2 so the
    // next enPhi1 definitely sees a settled cycle, then sample the
    // combinational read data on the following enPhi2.
    localparam C_IDLE = 2'd0, C_AS = 2'd1, C_FIN = 2'd2, C_ARM = 2'd3;
    reg [1:0]  c_st = C_IDLE;
    always @(posedge clk_32) begin
        if (reset) begin
            c_st <= C_IDLE; c_as_n <= 1'b1; c_uds_n <= 1'b1; c_lds_n <= 1'b1; c_rw <= 1'b1;
            done <= 1'b0; p_cnt <= 2'd0; c_cnt <= 2'd0;
        end else begin
            if (cpu_cyc) p_cnt <= 2'd2;
            else if (p_cnt != 2'd0) p_cnt <= p_cnt - 2'd1;
            case (c_st)
                C_IDLE: begin
                    if (sel && !done && !b_ctrlOe) begin
                        c_a <= {18'h3FE28, a};            // $FF8A00 + a
                        c_rw <= rw; c_uds_n <= !uds; c_lds_n <= !lds;
                        c_cnt <= 2'd0;
                        if (enPhi2) begin
                            c_as_n <= 1'b0; c_st <= C_AS;
                        end else begin
                            c_st <= C_ARM;
                        end
                    end else if (!sel) done <= 1'b0;
                end
                C_ARM: begin
                    if (!sel) begin
                        c_st <= C_IDLE; done <= 1'b0;
                    end else if (enPhi2) begin
                        c_as_n <= 1'b0; c_st <= C_AS;
                    end
                end
                C_AS: begin
                    if (enPhi1) c_cnt <= 2'd1;
                    if (c_cnt == 2'd1 && enPhi2) begin
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
            if (b_ctrlOe && grant_32 && !b_oASn && !b_oDSn && !m_busy && !m_ack) begin
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

    // ---- HUD debug (FAL_01): live, free-running, clk_32 ----
    // slot0 {busy, br_want, bus_grant, grant_32, m_req, m_ack, m_we, ctrlOe, last master byte addr}
    // slot1 {last master WRITE byte addr A23:8, last write data}
    // slot2 {blits started, blits completed}  (busy rising / falling)
    // slot3 {master writes acked (incl. dropped >= $E00000), master reads acked}
    reg [23:1] d_wa = 23'd0;
    reg [15:0] d_wd = 16'd0, d_st = 16'd0, d_dn = 16'd0, d_wc = 16'd0, d_rc = 16'd0;
    reg        d_busy_q = 1'b0;
    always @(posedge clk_32) begin
        d_busy_q <= b_INTn;                       // stBlitter INTn = busy (high while busy)
        if (b_INTn && !d_busy_q) d_st <= d_st + 16'd1;
        if (!b_INTn && d_busy_q) d_dn <= d_dn + 16'd1;
        if (m_req && m_ack) begin
            if (m_we) begin d_wc <= d_wc + 16'd1; d_wa <= m_a; d_wd <= m_wdata; end
            else d_rc <= d_rc + 16'd1;
        end
        if (b_ctrlOe && grant_32 && !b_oASn && !b_oDSn && !m_busy && !m_ack &&
            !b_oRWn && b_oA[23:21] == 3'b111) d_wc <= d_wc + 16'd1;
    end
    // Dialog debug 3 (BLI-9). Replica of stBlitter's own OP/HOP latch, fed from the private bus exactly as
    // stBlitter sees it (enPhi1, FC=101, AS, A23:6=$FF8A00>>6, RW, LDS/UDS, iDBUS=wdata), so r_op/r_hop equal
    // stBlitter's OP/HOP without hierarchical references. s_* are the CPU-side shadows (end of the C_AS window).
    wire       r_sel = (bus_fc == 3'b101) && !bus_as_n && (bus_a[23:6] == 18'h3FE28);
    wire       r_wr  = r_sel && !bus_rw && bus_a[5];
    reg [3:0]  r_op = 4'd0;
    reg [1:0]  r_hop = 2'd0;
    reg [1:0]  s_hop = 2'd0;
    reg [3:0]  s_op = 4'd0;
    reg [2:1]  s_dlo = 2'd0;
    reg [15:0] w1 = 16'd0;
    reg        r_seen = 1'b0, f_dchg = 1'b0, f_lost = 1'b0;
    reg [15:0] n_anom = 16'd0, n_dchg = 16'd0, n_fills = 16'd0;
    reg [7:0]  n_lost = 8'd0, n_own = 8'd0;
    reg [31:0] s_cur = 32'd0, d_first = 32'd0;     // d_first: first data change {a5:1,3'b0, w1[7:0], wdata[15:0]}
    reg        s_needw = 1'b0, s_frozen = 1'b0;
    reg [255:0] s_ring = 256'd0, s_snap = 256'd0;
    wire       c_end = c_st == C_AS && c_cnt == 2'd1 && enPhi2;
    wire       s_go  = c_end && !c_rw && c_a[5:1] == 5'h1E && !c_uds_n && !c_lds_n && wdata[15];
    // entry {shadow OP4, real OP4 at first write, real HOP2, dst A2:1, D=data changed in C_AS, L=lost latch,
    //        Z=some write was $0000, F=some write was $FFFF, writes8 (sat), first write data 15:8}
    wire [255:0] s_ring_n = {s_cur, s_ring[255:32]};
    // dialog fill trigger: the four newest entries are planes 0-3 (dA 0,1,2,3) with HOP 1 and the OPs of
    // VDI pen hw 7 (3,3,3,0) or hw 8 (0,0,0,3); freeze four starts later
    wire [3:0] o0 = s_ring_n[159:156], o1 = s_ring_n[191:188], o2 = s_ring_n[223:220], o3 = s_ring_n[255:252];
    wire       g_pl = s_ring_n[149:148] == 2'd0 && s_ring_n[181:180] == 2'd1 &&
                      s_ring_n[213:212] == 2'd2 && s_ring_n[245:244] == 2'd3 &&
                      s_ring_n[151:150] == 2'd1 && s_ring_n[247:246] == 2'd1;
    wire       g_mix = g_pl && ((o0 == 4'h3 && o1 == 4'h3 && o2 == 4'h3 && o3 == 4'h0) ||
                                (o0 == 4'h0 && o1 == 4'h0 && o2 == 4'h0 && o3 == 4'h3));
    reg  [2:0] s_cd3 = 3'd0;
    always @(posedge clk_32) begin
        // replica of the stBlitter OP/HOP latch
        if (enPhi1 && r_wr && bus_a[4:1] == 4'hD) begin
            if (!bus_uds_n) r_hop <= wdata[9:8];
            if (!bus_lds_n) r_op  <= wdata[3:0];
        end
        // CPU register cycle checks: data stable across the C_AS window, latch seen on the private bus,
        // address/counter writes while the blitter holds BGACK (stBlitter drops those)
        if (c_st == C_AS && c_cnt == 2'd0 && enPhi1) begin
            w1 <= wdata; r_seen <= r_sel && !bus_rw;
            if (r_wr && !bus_uds_n && !bus_lds_n && !b_oBGACKn &&
                (bus_a[4:1] == 4'h9 || bus_a[4:1] == 4'hA || bus_a[4:1] == 4'hB || bus_a[4:1] == 4'hC) &&
                n_own != 8'hFF) n_own <= n_own + 8'd1;
        end
        if (c_end && !c_rw) begin
            if (wdata != w1) begin
                f_dchg <= 1'b1;
                if (n_dchg == 16'd0) d_first <= {c_a[5:1], 3'b000, w1[7:0], wdata};
                if (n_dchg != 16'hFFFF) n_dchg <= n_dchg + 16'd1;
            end
            if (!r_seen) begin f_lost <= 1'b1; if (n_lost != 8'hFF) n_lost <= n_lost + 8'd1; end
            if (c_a[5:1] == 5'h1D) begin
                if (!c_uds_n) s_hop <= wdata[9:8];
                if (!c_lds_n) s_op  <= wdata[3:0];
            end
            if (c_a[5:1] == 5'h1A && !c_lds_n) s_dlo <= wdata[2:1];
        end
        if (s_go) begin
            s_ring   <= s_ring_n;
            s_cur    <= {s_op, 4'h0, 2'b00, s_dlo, f_dchg, f_lost, 2'b00, 8'h00, 8'h00};
            f_dchg   <= 1'b0; f_lost <= 1'b0;
            s_needw  <= 1'b1;
            n_fills  <= n_fills + 16'd1;
            if (g_mix && n_anom != 16'hFFFF) n_anom <= n_anom + 16'd1;
            if (!s_frozen) begin
                if (s_cd3 == 3'd1) begin s_snap <= s_ring_n; s_frozen <= 1'b1; end
                if (s_cd3 != 3'd0) s_cd3 <= s_cd3 - 3'd1;
                else if (g_mix) s_cd3 <= 3'd4;
            end
        end else if (m_req && m_ack && m_we) begin
            if (s_needw) begin
                s_cur[27:22] <= {r_op, r_hop};
                s_cur[7:0]   <= m_wdata[15:8];
                s_needw <= 1'b0;
            end
            if (m_wdata == 16'h0000) s_cur[17] <= 1'b1;
            if (m_wdata == 16'hFFFF) s_cur[16] <= 1'b1;
            if (s_cur[15:8] != 8'hFF) s_cur[15:8] <= s_cur[15:8] + 8'd1;
        end
    end
    assign dbg_snap = s_snap;
    // slot4 flags/last master addr, slot5 {hw7/hw8 dialog fills seen, data changes}, slot6 {lost latches8, BGACK addr writes8,
    // frozen, fills15}, slot7 = first data change {A5:1,000, w1 7:0, final wdata}
    assign dbg = {d_first, {n_lost, n_own, s_frozen, n_fills[14:0]}, {n_anom, n_dchg},
                  {b_INTn, br_want, bus_grant, grant_32, m_req, m_ack, m_we, b_ctrlOe, m_a, 1'b0}};

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
