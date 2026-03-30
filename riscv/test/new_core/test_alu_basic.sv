// Test: basic ALU operations (addi, add, sub, and, or, xor, slt)
module test_alu_basic;

    `include "PIPELINE_TB.sv"

    initial begin
        // Program:
        //   addi x1, x0, 10      # x1 = 10
        //   addi x2, x0, 20      # x2 = 20
        //   add  x3, x1, x2      # x3 = 30
        //   sub  x4, x2, x1      # x4 = 10
        //   and  x5, x1, x2      # x5 = 10 & 20 = 0
        //   or   x6, x1, x2      # x6 = 10 | 20 = 30
        //   xor  x7, x1, x2      # x7 = 10 ^ 20 = 30
        //   slt  x8, x1, x2      # x8 = 1 (10 < 20)
        //   slt  x9, x2, x1      # x9 = 0 (20 < 10 = false)
        //   ebreak

        imem[0]  = 32'h00a00093;  // addi x1, x0, 10
        imem[1]  = 32'h01400113;  // addi x2, x0, 20
        imem[2]  = 32'h002081b3;  // add  x3, x1, x2
        imem[3]  = 32'h40110233;  // sub  x4, x2, x1
        imem[4]  = 32'h0020f2b3;  // and  x5, x1, x2
        imem[5]  = 32'h0020e333;  // or   x6, x1, x2
        imem[6]  = 32'h0020c3b3;  // xor  x7, x1, x2
        imem[7]  = 32'h0020a433;  // slt  x8, x1, x2
        imem[8]  = 32'h001124b3;  // slt  x9, x2, x1
        imem[9]  = 32'h00100073;  // ebreak

        init();

        repeat(200) @(posedge clk);

        check_reg(1, 10, "addi x1");
        check_reg(2, 20, "addi x2");
        check_reg(3, 30, "add x3");
        check_reg(4, 10, "sub x4");
        check_reg(5, 0,  "and x5");
        check_reg(6, 30, "or x6");
        check_reg(7, 30, "xor x7");
        check_reg(8, 1,  "slt x8");
        check_reg(9, 0,  "slt x9");

        if (errors == 0) $display("test_alu_basic: PASSED");
        else $display("test_alu_basic: FAILED (%0d errors)", errors);
        $finish;
    end

endmodule
