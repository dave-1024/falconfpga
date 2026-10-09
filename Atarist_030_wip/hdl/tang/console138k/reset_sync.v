// reset_sync.v - FalconFPGA: asynchronous-assert / synchronous-deassert reset
// synchroniser (9 Oct 2026).
//
// arst goes high at any time and rst follows at once (no clock needed).
// When arst goes low, rst stays high for STAGES more rising edges of clk and
// then falls in step with clk, so every flop reset by rst leaves reset in the
// same clock cycle and the release is timed (recovery/removal) inside the clk
// domain. Only the async pins of the stage flops see arst itself; that path is
// cut in the SDC (they hold a constant 1 at release, the chain absorbs
// metastability).
module reset_sync #(
    parameter STAGES = 3
) (
    input  wire clk,
    input  wire arst,   // active high, asynchronous
    output wire rst     // active high, deasserts synchronously to clk
);
    (* syn_preserve = 1 *) reg [STAGES-1:0] sync = {STAGES{1'b1}};
    always @(posedge clk or posedge arst)
        if (arst) sync <= {STAGES{1'b1}};
        else      sync <= {sync[STAGES-2:0], 1'b0};
    assign rst = sync[STAGES-1];
endmodule
