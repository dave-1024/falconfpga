// Pin-level stand-in for the WF68K30L netlist (TT-RAM bench only): the bench
// drives the 030 bus outputs through hierarchical references (tb_ttram.v).
module WF68K30L_TOP (
    input CLK, input CLK_N, output [31:0] ADR_OUT, input [31:0] DATA_IN, output [31:0] DATA_OUT,
    output DATA_EN, input BERRn, input RESET_INn, output RESET_OUT, input HALT_INn, output HALT_OUTn,
    output [2:0] FC_OUT, input AVECn, input [2:0] IPLn, output IPENDn, input [1:0] DSACKn,
    output [1:0] SIZE, output ASn, output RWn, output RMCn, output DSn, output ECSn, output OCSn,
    output DBENn, output BUS_EN, input STERMn, input CIINn, input CDISn, input CBACKn, output CBREQn,
    output CIOUTn, output STATUSn, output REFILLn, input BRn, output BGn, input BGACKn, output MMU_ON);
    assign MMU_ON = 1'b0;
    reg [31:0] adr = 0, dout = 0; reg [2:0] fc = 3'd5; reg [1:0] size = 0; reg asn = 1, rwn = 1;
    assign ADR_OUT = adr; assign DATA_OUT = dout; assign FC_OUT = fc; assign SIZE = size;
    assign ASn = asn; assign RWn = rwn; assign DSn = asn;
    assign DATA_EN = 0; assign RESET_OUT = 0; assign HALT_OUTn = 1; assign IPENDn = 1; assign RMCn = 1;
    assign ECSn = 1; assign OCSn = 1; assign DBENn = 1; assign BUS_EN = 1; assign CBREQn = 1;
    assign CIOUTn = 1; assign STATUSn = 1; assign REFILLn = 1; assign BGn = 1;
endmodule
