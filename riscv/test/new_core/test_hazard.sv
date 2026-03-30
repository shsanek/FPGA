// Test: data hazard (RAW — read after write)
module test_hazard;

    `include "PIPELINE_TB.sv"

    initial begin
        // Program: back-to-back dependency chain
        //   addi x1, x0, 1       # x1 = 1
        //   addi x2, x1, 1       # x2 = x1 + 1 = 2  (RAW hazard on x1)
        //   addi x3, x2, 1       # x3 = x2 + 1 = 3  (RAW hazard on x2)
        //   addi x4, x3, 1       # x4 = x3 + 1 = 4  (RAW hazard on x3)
        //   add  x5, x1, x4      # x5 = 1 + 4 = 5   (RAW on x1 and x4)
        //   ebreak

        imem[0] = 32'h00100093;  // addi x1, x0, 1
        imem[1] = 32'h00108113;  // addi x2, x1, 1
        imem[2] = 32'h00110193;  // addi x3, x2, 1
        imem[3] = 32'h00118213;  // addi x4, x3, 1
        imem[4] = 32'h004082b3;  // add  x5, x1, x4
        imem[5] = 32'h00100073;  // ebreak

        init();

        repeat(500) @(posedge clk);

        check_reg(1, 1, "x1=1");
        check_reg(2, 2, "x2=2 (hazard x1)");
        check_reg(3, 3, "x3=3 (hazard x2)");
        check_reg(4, 4, "x4=4 (hazard x3)");
        check_reg(5, 5, "x5=5 (hazard x1,x4)");

        if (errors == 0) $display("test_hazard: PASSED");
        else $display("test_hazard: FAILED (%0d errors)", errors);
        $finish;
    end

endmodule
