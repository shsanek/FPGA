// Test: LUI and AUIPC
module test_upper;

    `include "PIPELINE_TB.sv"

    initial begin
        // Program:
        //   0x00: lui   x1, 0x12345    # x1 = 0x12345000
        //   0x04: auipc x2, 0x00001    # x2 = 0x04 + 0x1000 = 0x1004
        //   0x08: lui   x3, 0xFFFFF    # x3 = 0xFFFFF000
        //   0x0C: ebreak

        imem[0] = 32'h123450b7;  // lui   x1, 0x12345
        imem[1] = 32'h00001117;  // auipc x2, 0x00001
        imem[2] = 32'hFFFFF1b7;  // lui   x3, 0xFFFFF
        imem[3] = 32'h00100073;  // ebreak

        init();

        repeat(200) @(posedge clk);

        check_reg(1, 32'h12345000, "lui x1");
        check_reg(2, 32'h00001004, "auipc x2");
        check_reg(3, 32'hFFFFF000, "lui x3");

        if (errors == 0) $display("test_upper: PASSED");
        else $display("test_upper: FAILED (%0d errors)", errors);
        $finish;
    end

endmodule
