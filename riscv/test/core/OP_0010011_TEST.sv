module OP_0010011_TEST();
    logic [6:0] funct7;
    logic [2:0] funct3;
    logic [31:0] rs1, imm;
    logic clk;
    logic [31:0] output_value;
    int error = 0;

    OP_0010011 dut (
        .funct7(funct7),
        .funct3(funct3),
        .rs1(rs1),
        .imm(imm),
        .clk(clk),
        .output_value(output_value)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("OP_0010011.vcd");
        $dumpvars(0, OP_0010011_TEST);
        funct7 = 7'b0;

        // ADDI: 10 + 5 = 15
        #5;
        funct3 = 3'd0; rs1 = 32'd10; imm = 32'd5;
        #10; assert(output_value === 32'd15) else error = error + 1;

        // ADDI: знаковый immediate, 10 + (-3) = 7
        funct3 = 3'd0; rs1 = 32'd10; imm = 32'hFFFFFFFF - 32'd2; // -3
        #10; assert(output_value === 32'd7) else error = error + 1;

        // SLLI: 1 << 4 = 16
        funct3 = 3'd1; rs1 = 32'd1; imm = 32'd4;
        #10; assert(output_value === 32'd16) else error = error + 1;

        // SLTI: -1 < 0 → 1
        funct3 = 3'd2; rs1 = 32'hFFFFFFFF; imm = 32'd0;
        #10; assert(output_value === 32'd1) else error = error + 1;

        // SLTI: 1 < 0 → 0
        funct3 = 3'd2; rs1 = 32'd1; imm = 32'd0;
        #10; assert(output_value === 32'd0) else error = error + 1;

        // SLTIU: 0xFFFFFFFF < 0 (unsigned 0) → 0
        funct3 = 3'd3; rs1 = 32'hFFFFFFFF; imm = 32'd0;
        #10; assert(output_value === 32'd0) else error = error + 1;

        // SLTIU: 0 < 1 → 1
        funct3 = 3'd3; rs1 = 32'd0; imm = 32'd1;
        #10; assert(output_value === 32'd1) else error = error + 1;

        // XORI
        funct3 = 3'd4; rs1 = 32'hAAAA_AAAA; imm = 32'h5555_5555;
        #10; assert(output_value === 32'hFFFF_FFFF) else error = error + 1;

        // SRLI: 0xFF00FF00 >> 8 = 0x00FF00FF
        funct7 = 7'b0000000;
        funct3 = 3'd5; rs1 = 32'hFF00FF00; imm = 32'd8;
        #10; assert(output_value === 32'h00FF00FF) else error = error + 1;

        // SRAI: 0xF0000000 >>> 4 = 0xFF000000
        funct7 = 7'b0100000;
        funct3 = 3'd5; rs1 = 32'hF0000000; imm = 32'd4;
        #10; assert(output_value === 32'hFF000000) else error = error + 1;

        // ORI
        funct7 = 7'b0;
        funct3 = 3'd6; rs1 = 32'h0F0F0F0F; imm = 32'hF0F0F0F0;
        #10; assert(output_value === 32'hFFFF_FFFF) else error = error + 1;

        // ANDI
        funct3 = 3'd7; rs1 = 32'hAAAA_AAAA; imm = 32'h0F0F0F0F;
        #10; assert(output_value === 32'h0A0A0A0A) else error = error + 1;

        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);

        $finish;
    end
endmodule
