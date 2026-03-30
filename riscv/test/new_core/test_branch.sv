// Test: branch instructions (beq, bne, blt, bge)
module test_branch;

    `include "PIPELINE_TB.sv"

    initial begin
        // Program:
        //   addi x1, x0, 5       # x1 = 5
        //   addi x2, x0, 5       # x2 = 5
        //   addi x3, x0, 10      # x3 = 10
        //   beq  x1, x2, +8      # taken (5==5) → skip next
        //   addi x10, x0, 99     # SKIPPED
        //   addi x10, x0, 1      # x10 = 1 (landed here)
        //   bne  x1, x3, +8      # taken (5!=10) → skip next
        //   addi x11, x0, 99     # SKIPPED
        //   addi x11, x0, 2      # x11 = 2
        //   blt  x1, x3, +8      # taken (5<10) → skip next
        //   addi x12, x0, 99     # SKIPPED
        //   addi x12, x0, 3      # x12 = 3
        //   bge  x3, x1, +8      # taken (10>=5) → skip next
        //   addi x13, x0, 99     # SKIPPED
        //   addi x13, x0, 4      # x13 = 4
        //   ebreak

        imem[0]  = 32'h00500093;  // addi x1, x0, 5
        imem[1]  = 32'h00500113;  // addi x2, x0, 5
        imem[2]  = 32'h00a00193;  // addi x3, x0, 10
        imem[3]  = 32'h00208463;  // beq  x1, x2, +8
        imem[4]  = 32'h06300513;  // addi x10, x0, 99
        imem[5]  = 32'h00100513;  // addi x10, x0, 1
        imem[6]  = 32'h00309463;  // bne  x1, x3, +8
        imem[7]  = 32'h06300593;  // addi x11, x0, 99
        imem[8]  = 32'h00200593;  // addi x11, x0, 2
        imem[9]  = 32'h0030c463;  // blt  x1, x3, +8
        imem[10] = 32'h06300613;  // addi x12, x0, 99
        imem[11] = 32'h00300613;  // addi x12, x0, 3
        imem[12] = 32'h0011d463;  // bge  x3, x1, +8
        imem[13] = 32'h06300693;  // addi x13, x0, 99
        imem[14] = 32'h00400693;  // addi x13, x0, 4
        imem[15] = 32'h00100073;  // ebreak

        init();

        repeat(500) @(posedge clk);

        check_reg(1,  5,  "x1=5");
        check_reg(2,  5,  "x2=5");
        check_reg(3,  10, "x3=10");
        check_reg(10, 1,  "beq taken");
        check_reg(11, 2,  "bne taken");
        check_reg(12, 3,  "blt taken");
        check_reg(13, 4,  "bge taken");

        if (errors == 0) $display("test_branch: PASSED");
        else $display("test_branch: FAILED (%0d errors)", errors);
        $finish;
    end

endmodule
