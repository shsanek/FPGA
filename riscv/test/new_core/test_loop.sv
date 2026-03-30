// Test: simple loop (sum 1..10)
module test_loop;

    `include "PIPELINE_TB.sv"

    initial begin
        // Program: sum = 0; for i=1..10: sum += i
        //   addi x1, x0, 0        # x1 = sum = 0
        //   addi x2, x0, 1        # x2 = i = 1
        //   addi x3, x0, 11       # x3 = limit = 11
        // loop:
        //   add  x1, x1, x2       # sum += i
        //   addi x2, x2, 1        # i++
        //   blt  x2, x3, -8       # if i < 11 goto loop
        //   ebreak

        imem[0] = 32'h00000093;  // addi x1, x0, 0
        imem[1] = 32'h00100113;  // addi x2, x0, 1
        imem[2] = 32'h00b00193;  // addi x3, x0, 11
        // loop at 0x0C:
        imem[3] = 32'h002080b3;  // add  x1, x1, x2
        imem[4] = 32'h00110113;  // addi x2, x2, 1
        imem[5] = 32'hfe314ce3;  // blt  x2, x3, -8 (back to imem[3])
        imem[6] = 32'h00100073;  // ebreak

        init();

        repeat(5000) @(posedge clk);

        check_reg(1, 55, "sum 1..10 = 55");
        check_reg(2, 11, "i final = 11");

        if (errors == 0) $display("test_loop: PASSED");
        else $display("test_loop: FAILED (%0d errors)", errors);
        $finish;
    end

endmodule
