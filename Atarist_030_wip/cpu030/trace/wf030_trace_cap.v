// wf030_trace_cap.v - FalconFPGA diag-trace (debug only, `define WF030_TRACE).
// Observation only: records WF68K30L bus cycles and prefetch-queue/decoder
// events into a ring (written through the w* port into wf030_trace_view's
// RAM) and freezes it a few entries after a trigger. Nothing here drives the
// CPU or the bus.
//
// Runs on clk_cpu (16 MHz). One 144-bit entry per clk_cpu edge on which
// something happens: end of a bus cycle (AS negated), OPCODE_RDY to the
// decoder, a pipe flush, BUSY_EXH changing, Q_DUMMY rising.
//   [143:132] ts       clk_cpu count mod 4096
//   [131:125] flags    6 bus_end, 5 opc_rdy, 4 flush_rise, 3 exh_chg,
//                      2 dummy_rise, 1 trigger entry, 0 iack cycle
//   [124:101] A23:0    of the bus cycle that ended (latched at AS)
//   [100:98]  FC       [97] RWn  [96:95] SIZ  [94] DSACK seen  [93] BERR seen
//   [92:77]   D31:16   read data (last sample with AS low) or write data
//   [76:61]   OPCODE_TO_CORE
//   [60:38]   PC_L 23:1 (requested opcode word address)
//   [37:35]   Q_CNT  [34] OPC_RD [33] OPCODE_RDY [32] Q_DISMISS [31] IPIPE_FLUSH
//   [30] Q_HIT [29] Q_MISS [28] Q_DUMMY [27] BUSY_EXH
//   [26:24]   IPL2n:0n (as given to the CPU)
//   [23:0]    PC 23:0
// Trigger (only once armed, 2^30 clk_cpu = 67 s after the CPU reset):
//   src 0 HALT_OUTn low (double bus fault)
//   src 1 program fetch at E21D38 right after fetches in E21D40-E21D5F
//         (TOS 2.06 AES trap #2 handler: rts back to its own entry, DEBUG2)
//   src 2 BERR on a non-CPU-space cycle below $E00000 or with A31:24 other
//         than 00/FF (TOS probes $FFF00039 etc. with BERR as the normal answer)
//   src 3 program fetch outside RAM (0-3FFFFF), ROM (E00000-E3FFFF), cart
//         (FA0000-FBFFFF), or with A31:24 /= 0
//   src 4 no level-4 (VBL) IACK for 2^22 clk_cpu (262 ms) - late trigger
//   src 5 manual: the CPU reads scan code $62 (Help make) from the IKBD ACIA
//         ($FFFC02) - press Help (helper 'key help') to freeze the ring
// After the trigger 64 more entries are recorded, then the ring stops.
// Writes to $0088-$008B, $0404-$0407, $6ABC-$6AC3 are also copied to a
// 16-entry watch ring (same entry format).
module wf030_trace_cap #(
    parameter ARM_BIT = 30            // armed 2^ARM_BIT clk_cpu after the CPU reset (sim: small)
) (
    input  wire         clk,          // clk_cpu
    input  wire         rst_n,        // cpu_rst_n
    input  wire [31:0]  cpu_adr,
    input  wire [2:0]   cpu_fc,
    input  wire         cpu_rwn,
    input  wire [1:0]   cpu_size,
    input  wire         cpu_asn,
    input  wire [1:0]   cpu_dsackn,
    input  wire         cpu_berrn,
    input  wire [15:0]  cpu_din,      // D31:16
    input  wire [15:0]  cpu_dout,     // D31:16
    input  wire         cpu_halt_outn,
    input  wire [2:0]   ipl_n,
    input  wire [79:0]  dbg,
    output reg          we      = 1'b0,
    output reg  [11:0]  waddr   = 12'd0,
    output reg  [143:0] wdata   = 144'd0,
    output reg          wwe     = 1'b0,   // watch ring write
    output reg  [3:0]   wwaddr  = 4'd0,
    output reg  [143:0] wwdata  = 144'd0,
    output wire [47:0]  status
);
    // ---- core observation ----
    wire [15:0] opw    = dbg[15:0];
    wire [22:0] pcl    = dbg[38:16];
    wire [23:0] pc     = dbg[62:39];
    wire        flush  = dbg[63];
    wire        bexh   = dbg[64];
    wire [2:0]  qcnt   = dbg[68:66];
    wire        ordy   = dbg[69];
    wire        qdis   = dbg[70];
    wire        qhit   = dbg[71];
    wire        qmiss  = dbg[72];
    wire        qdum   = dbg[73];
    wire        opcrd  = dbg[74];

    // ---- bus cycle tracking ----
    reg         as_d = 1'b1;
    reg  [31:0] b_adr = 32'd0;
    reg  [2:0]  b_fc = 3'd0;
    reg         b_rwn = 1'b1;
    reg  [1:0]  b_siz = 2'b00;
    reg         b_dsk = 1'b0, b_ber = 1'b0;
    reg  [15:0] b_din = 16'd0, b_dout = 16'd0;
    wire        as_fall = as_d & ~cpu_asn;
    wire        as_rise = ~as_d & cpu_asn;
    always @(posedge clk) begin
        as_d <= cpu_asn;
        if (as_fall) begin
            b_adr <= cpu_adr; b_fc <= cpu_fc; b_rwn <= cpu_rwn; b_siz <= cpu_size;
            b_dsk <= 1'b0; b_ber <= 1'b0;
        end
        if (~cpu_asn) begin
            b_din  <= cpu_din;
            b_dout <= cpu_dout;
            if (cpu_dsackn != 2'b11) b_dsk <= 1'b1;
            if (~cpu_berrn)          b_ber <= 1'b1;
        end
    end
    wire iack_cyc = (b_fc == 3'b111) & (b_adr[19:16] == 4'hF);
    wire prog_cyc = (b_fc[1:0] == 2'b10);

    // ---- event detection ----
    reg flush_d = 1'b0, bexh_d = 1'b0, qdum_d = 1'b0;
    always @(posedge clk) begin flush_d <= flush; bexh_d <= bexh; qdum_d <= qdum; end
    wire e_bus  = as_rise;
    wire e_opc  = ordy;
    wire e_fl   = flush & ~flush_d;
    wire e_exh  = bexh ^ bexh_d;
    wire e_dum  = qdum & ~qdum_d;
    wire ev     = e_bus | e_opc | e_fl | e_exh | e_dum;

    // ---- arming, trigger ----
    reg  [ARM_BIT:0] arm_cnt = 0;
    wire        armed = arm_cnt[ARM_BIT];
    reg  [23:0] last_pf = 24'd0;
    reg  [22:0] vbl_cnt = 23'd0;
    reg         trig = 1'b0;
    reg  [5:0]  trig_src = 6'd0;
    reg  [11:0] trig_addr = 12'd0;
    reg  [6:0]  post = 7'd0;
    reg         stopped = 1'b0;
    reg         wrapped = 1'b0;
    reg  [11:0] ts = 12'd0;
    reg  [4:0]  wcount = 5'd0;

    wire bad_hi   = (b_adr[31:24] != 8'h00);
    wire t_halt   = ~cpu_halt_outn;
    wire t_loop   = e_bus & prog_cyc & (b_adr[23:0] == 24'hE21D38) &
                    (last_pf >= 24'hE21D40) & (last_pf < 24'hE21D60);
    wire hi_ok    = (b_adr[31:24] == 8'h00) | (b_adr[31:24] == 8'hFF);
    wire t_berr   = e_bus & b_ber & (b_fc != 3'b111) & (~hi_ok | (b_adr[23:0] < 24'hE00000));
    wire t_help   = e_bus & b_rwn & (b_fc[1:0] == 2'b01) & (b_adr[23:0] == 24'hFFFC02) &
                    (b_din[15:8] == 8'h62);
    wire pf_ok    = ~bad_hi & ((b_adr[23:0] < 24'h400000) |
                               ((b_adr[23:0] >= 24'hE00000) & (b_adr[23:0] < 24'hE40000)) |
                               ((b_adr[23:0] >= 24'hFA0000) & (b_adr[23:0] < 24'hFC0000)));
    wire t_pf     = e_bus & prog_cyc & ~pf_ok;
    wire t_vbl    = vbl_cnt[22];
    wire [5:0] t_any = {t_help, t_vbl, t_pf, t_berr, t_loop, t_halt};
    wire fire     = armed & ~trig & (t_any != 6'd0);

    wire watch    = e_bus & ~b_rwn & (b_fc[1:0] == 2'b01) & ~bad_hi &
                    ((b_adr[23:2] == 22'h000022) | (b_adr[23:2] == 22'h000101) |
                     (b_adr[23:2] == 22'h001AAF) | (b_adr[23:2] == 22'h001AB0));

    wire [143:0] entry = {
        ts,
        e_bus, e_opc, e_fl, e_exh, e_dum, fire, (e_bus & iack_cyc),
        b_adr[23:0], b_fc, b_rwn, b_siz, b_dsk, b_ber,
        (b_rwn ? b_din : b_dout),
        opw, pcl, qcnt, opcrd, ordy, qdis, flush, qhit, qmiss, qdum, bexh,
        ipl_n, pc };

    reg  [11:0] ptr = 12'd0;     // next ring slot
    reg  [3:0]  wptr = 4'd0;     // next watch slot
    always @(posedge clk) begin
        we  <= 1'b0;
        wwe <= 1'b0;
        if (!rst_n) begin
            arm_cnt <= 0; trig <= 1'b0; trig_src <= 6'd0; trig_addr <= 12'd0;
            post <= 7'd0; stopped <= 1'b0; wrapped <= 1'b0; ptr <= 12'd0;
            wptr <= 4'd0; wcount <= 5'd0;
            vbl_cnt <= 23'd0; last_pf <= 24'd0; ts <= 12'd0;
        end else begin
            ts <= ts + 12'd1;
            if (~armed) arm_cnt <= arm_cnt + 1'b1;
            if (e_bus & prog_cyc) last_pf <= b_adr[23:0];
            if (e_bus & iack_cyc & (b_adr[3:1] == 3'd4)) vbl_cnt <= 23'd0;
            else if (~vbl_cnt[22]) vbl_cnt <= vbl_cnt + 23'd1;

            if (fire) begin
                trig <= 1'b1; trig_src <= t_any; trig_addr <= ptr;
            end
            if (~stopped) begin
                if (ev | fire) begin
                    we <= 1'b1; waddr <= ptr; wdata <= entry; ptr <= ptr + 12'd1;
                    if (ptr == 12'hFFF) wrapped <= 1'b1;
                    if (trig) begin
                        post <= post + 7'd1;
                        if (post == 7'd63) stopped <= 1'b1;
                    end
                end else if (trig & t_vbl & (post == 7'd0)) begin
                    stopped <= 1'b1;        // VBL timeout: the loop is already in the ring
                end
                if (watch) begin
                    wwe <= 1'b1; wwaddr <= wptr; wwdata <= entry; wptr <= wptr + 4'd1;
                    if (wcount != 5'd16) wcount <= wcount + 5'd1;
                end
            end
        end
    end

    // status (48 bits): 47 trig, 46 armed, 45 stopped, 44 wrapped, 43..38 src,
    // 37..36 0, 35..24 trigger slot, 23..12 next ring slot, 11..7 watch count,
    // 6..3 next watch slot, 2..0 = 101 (marker)
    assign status = {trig, armed, stopped, wrapped, trig_src, 2'b00,
                     trig_addr, ptr, wcount, wptr, 3'b101};
endmodule
