module OP_0110011_TEST();
    logic [6:0] funct7;
    logic [2:0] funct3;
    logic [31:0] rs1, rs2;
    logic clk;

    logic [31:0] output_value;

    int error = 0;

    OP_0110011 dut (
        .funct7(funct7),
        .funct3(funct3),
        .rs1(rs1),
        .rs2(rs2),
        .clk(clk),
        .output_value(output_value)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("OP_0110011.vcd");
        $dumpvars(0, OP_0110011_TEST);

        #5
        funct3 = 3'd0;
        funct7 = 7'b0000000;
        rs1 = 32'd10;
        rs2 = 32'd5;
        #10
        assert(output_value === 32'd15) else error = error + 1;

        funct3 = 3'd0;
        funct7 = 7'b0100000;
        rs1 = 32'd10;
        rs2 = 32'd5;
        #10
        assert(output_value === 32'd5) else error = error + 1;

        funct3 = 3'd1;
        rs1 = 32'd1;
        rs2 = 32'd3;
        #10
        assert(output_value === 32'd8) else error = error + 1;

        funct3 = 3'd2;
        rs1 = 32'hFFFFFFFF;
        rs2 = 32'd0;
        #10
        assert(output_value === 32'd1) else error = error + 1;

        funct3 = 3'd3;
        rs1 = 32'hFFFFFFFF;
        rs2 = 32'd0;
        #10
        assert(output_value === 32'd0) else error = error + 1;

        funct3 = 3'd4;
        rs1 = 32'hAAAA_AAAA;
        rs2 = 32'h5555_5555;
        #10
        assert(output_value === 32'hFFFF_FFFF) else error = error + 1;

        funct3 = 3'd5;
        funct7 = 7'b0000000;
        rs1 = 32'hFF00FF00;
        rs2 = 32'd8; 
        #10
        assert(output_value === 32'h00FF00FF) else error = error + 1;

        funct3 = 3'd5;
        funct7 = 7'b0100000;
        rs1 = 32'hF0000000;  
        rs2 = 32'd4;
        #10
        assert(output_value === 32'hFF000000) else error = error + 1;

        funct3 = 3'd6;
        rs1 = 32'h0F0F0F0F;
        rs2 = 32'hF0F0F0F0;
        #10
        assert(output_value === 32'hFFFFFFFF) else error = error + 1;

        funct3 = 3'd7;
        rs1 = 32'hAAAA_AAAA;
        rs2 = 32'h0F0F0F0F;
        #10
        assert(output_value === 32'h0A0A0A0A) else error = error + 1;

        if(error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);
            
        $finish;
    end

endmodule
