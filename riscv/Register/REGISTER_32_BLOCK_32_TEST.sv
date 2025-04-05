module REGISTER_32_BLOCK_32_TEST();
    logic clk = 0;
    logic reset_trigger;
    logic [4:0] rs1, rs2, rd;
    logic write_trigger;
    logic [31:0] write_value;
    logic [31:0] rs1_value, rs2_value;
    int error = 0;

    REGISTER_32_BLOCK_32 dut (
        .clk(clk),
        .reset_trigger(reset_trigger),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .write_trigger(write_trigger),
        .write_value(write_value),
        .rs1_value(rs1_value),
        .rs2_value(rs2_value)
    );

    initial begin
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("REGISTER_32_BLOCK_32.vcd");
        $dumpvars(0, REGISTER_32_BLOCK_32_TEST);

        reset_trigger = 1;
        write_trigger = 0;
        rs1 = 5'd0; rs2 = 5'd1;
        rd   = 5'd0;
        write_value = 32'hFFFFFFFF;
        #10;
        reset_trigger = 0;
        #10;
        assert(rs1_value === 32'b0) else error = error + 1;
        assert(rs2_value === 32'b0) else error = error + 1;

        rd = 5'd0;
        write_value = 32'hDEADBEEF;
        write_trigger = 1;
        rs1 = 5'd0; rs2 = 5'd0;
        #10;
        write_trigger = 0;
        #10;
        assert(rs1_value === 32'b0) else error = error + 1;
        assert(rs2_value === 32'b0) else error = error + 1;

        rd = 5'd3;
        write_value = 32'h12345678;
        write_trigger = 1;
        rs1 = 5'd3; rs2 = 5'd3;
        #10;
        write_trigger = 0;
        #10;
        assert(rs1_value === 32'h12345678) else error = error + 1;
        assert(rs2_value === 32'h12345678) else error = error + 1;

        rd = 5'd10;
        write_value = 32'hABCDEF01;
        write_trigger = 1;
        rs1 = 5'd10; rs2 = 5'd3;
        #10;
        write_trigger = 0;
        #10;
        assert(rs1_value === 32'hABCDEF01) else error = error + 1;
        assert(rs2_value === 32'h12345678) else error = error + 1;

        if(error != 0)
            $display("TEST FAILED: %0d errors", error);
        else
            $display("ALL TESTS PASSED");
            
        $finish;
    end

endmodule
