// ============================================================================
// tmds_encoder.v -- standard DVI 8b/10b TMDS encoder (one channel)
// Textbook implementation of the DVI 1.0 spec encoder: transition-minimised
// XOR/XNOR stage, then DC-balance stage with running disparity.
// FalconFPGA project, Tang Console 138K.  MIT licence.
// ============================================================================
module tmds_encoder (
    input  wire       clk,       // pixel clock
    input  wire       de,        // active video
    input  wire [1:0] ctrl,      // {c1,c0} sync bits during blanking
    input  wire [7:0] din,       // pixel byte
    output reg  [9:0] dout
);
    // stage 1: transition minimisation
    wire [3:0] n1d = din[0]+din[1]+din[2]+din[3]+din[4]+din[5]+din[6]+din[7];
    wire use_xnor = (n1d > 4'd4) || (n1d == 4'd4 && din[0] == 1'b0);

    wire [8:0] q_m;
    assign q_m[0] = din[0];
    assign q_m[1] = use_xnor ? ~(q_m[0] ^ din[1]) : (q_m[0] ^ din[1]);
    assign q_m[2] = use_xnor ? ~(q_m[1] ^ din[2]) : (q_m[1] ^ din[2]);
    assign q_m[3] = use_xnor ? ~(q_m[2] ^ din[3]) : (q_m[2] ^ din[3]);
    assign q_m[4] = use_xnor ? ~(q_m[3] ^ din[4]) : (q_m[3] ^ din[4]);
    assign q_m[5] = use_xnor ? ~(q_m[4] ^ din[5]) : (q_m[4] ^ din[5]);
    assign q_m[6] = use_xnor ? ~(q_m[5] ^ din[6]) : (q_m[5] ^ din[6]);
    assign q_m[7] = use_xnor ? ~(q_m[6] ^ din[7]) : (q_m[6] ^ din[7]);
    assign q_m[8] = ~use_xnor;

    // stage 2: DC balance
    wire [3:0] n1qm = q_m[0]+q_m[1]+q_m[2]+q_m[3]+q_m[4]+q_m[5]+q_m[6]+q_m[7];
    wire [3:0] n0qm = 4'd8 - n1qm;
    reg signed [4:0] disparity;

    always @(posedge clk) begin
        if (!de) begin
            disparity <= 5'sd0;
            case (ctrl)
                2'b00: dout <= 10'b1101010100;
                2'b01: dout <= 10'b0010101011;
                2'b10: dout <= 10'b0101010100;
                default: dout <= 10'b1010101011;
            endcase
        end else begin
            if (disparity == 0 || n1qm == n0qm) begin
                dout <= { ~q_m[8], q_m[8], q_m[8] ? q_m[7:0] : ~q_m[7:0] };
                disparity <= q_m[8] ? disparity + $signed({1'b0,n1qm}) - $signed({1'b0,n0qm})
                                    : disparity + $signed({1'b0,n0qm}) - $signed({1'b0,n1qm});
            end else if ((disparity > 0 && n1qm > n0qm) ||
                         (disparity < 0 && n0qm > n1qm)) begin
                dout <= { 1'b1, q_m[8], ~q_m[7:0] };
                disparity <= disparity + $signed({3'b0,q_m[8],1'b0})
                                       + $signed({1'b0,n0qm}) - $signed({1'b0,n1qm});
            end else begin
                dout <= { 1'b0, q_m[8], q_m[7:0] };
                disparity <= disparity - $signed({3'b0,~q_m[8],1'b0})
                                       + $signed({1'b0,n1qm}) - $signed({1'b0,n0qm});
            end
        end
    end
endmodule
