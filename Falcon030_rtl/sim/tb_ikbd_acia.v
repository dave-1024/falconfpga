// tb_ikbd_acia.v - iverilog check of the Hybrid030-style keyboard ACIA stub
`timescale 1ns/1ps
module tb_ikbd_acia;
    reg        clk, reset, sel, rs, rw;
    reg  [7:0] din;
    wire [7:0] dout;
    wire       irq;

    falcon_ikbd_acia uut (
        .clk(clk), .reset(reset), .sel(sel), .rs(rs), .rw(rw),
        .din(din), .dout(dout), .irq(irq)
    );

    always #5 clk = ~clk;

    integer errors;
    task cycle;  // one pbus-style access: sel high for a few clocks
        input       is_rs, is_rw;
        input [7:0] d;
        begin
            @(posedge clk);
            rs <= is_rs; rw <= is_rw; din <= d; sel <= 1'b1;
            repeat (4) @(posedge clk);
            sel <= 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        errors = 0;
        clk = 0; reset = 1; sel = 0; rs = 0; rw = 1; din = 0;
        repeat (4) @(posedge clk);
        reset = 0;
        repeat (2) @(posedge clk);

        // status after reset: TDRE, no RDRF, no IRQ
        cycle(0, 1, 0);
        if (dout !== 8'h02) begin $display("FAIL: sr after reset %02x", dout); errors = errors+1; end
        if (irq !== 1'b0)   begin $display("FAIL: irq after reset"); errors = errors+1; end

        // master reset $03, then a dummy control $96, then IKBD $80 $01
        cycle(0, 0, 8'h03);
        cycle(0, 0, 8'h96);
        cycle(1, 0, 8'h80);
        cycle(1, 0, 8'h01);

        // allow the reply to be delivered into RDR
        repeat (4) @(posedge clk);
        cycle(0, 1, 0);
        if (dout !== 8'h83) begin $display("FAIL: sr after $80 $01 %02x (want 83)", dout); errors = errors+1; end
        if (irq !== 1'b1)   begin $display("FAIL: irq should be high"); errors = errors+1; end
        cycle(1, 1, 0);
        if (dout !== 8'hF1) begin $display("FAIL: version %02x (want F1)", dout); errors = errors+1; end
        // RDRF cleared
        cycle(0, 1, 0);
        if (dout !== 8'h02) begin $display("FAIL: sr after read %02x", dout); errors = errors+1; end
        if (irq !== 1'b0)   begin $display("FAIL: irq after read"); errors = errors+1; end

        // $1C clock: seven bytes starting with $FC
        cycle(1, 0, 8'h1C);
        repeat (4) @(posedge clk);
        cycle(1, 1, 0);
        if (dout !== 8'hFC) begin $display("FAIL: clock hdr %02x", dout); errors = errors+1; end
        cycle(1, 1, 0);
        if (dout !== 8'h99) begin $display("FAIL: clock b1 %02x", dout); errors = errors+1; end
        // drain the rest
        repeat (5) cycle(1, 1, 0);
        cycle(0, 1, 0);
        if (dout[0] !== 1'b0) begin $display("FAIL: leftover RDRF %02x", dout); errors = errors+1; end

        if (errors == 0) $display("ALL PASS");
        else $display("FAILED %0d", errors);
        $finish;
    end
endmodule
