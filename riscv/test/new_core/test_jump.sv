// Test: JAL and JALR
module test_jump;

    `include "PIPELINE_TB.sv"

    initial begin
        // Program:
        //   0x00: jal  x1, +12      # x1 = 4, jump to 0x0C
        //   0x04: addi x10, x0, 99  # SKIPPED
        //   0x08: addi x10, x0, 99  # SKIPPED
        //   0x0C: addi x2, x0, 42   # x2 = 42 (landed here)
        //   0x10: addi x3, x0, 0x24 # x3 = 0x24 (target for jalr)
        //   0x14: jalr x4, x3, 0    # x4 = 0x18, jump to 0x24
        //   0x18: addi x11, x0, 99  # SKIPPED
        //   0x1C: addi x11, x0, 99  # SKIPPED
        //   0x20: addi x11, x0, 99  # SKIPPED
        //   0x24: addi x5, x0, 7    # x5 = 7 (landed here)
        //   0x28: ebreak

        imem[0]  = 32'h00c000ef;  // jal  x1, +12
        imem[1]  = 32'h06300513;  // addi x10, x0, 99
        imem[2]  = 32'h06300513;  // addi x10, x0, 99
        imem[3]  = 32'h02a00113;  // addi x2, x0, 42
        imem[4]  = 32'h02400193;  // addi x3, x0, 0x24
        imem[5]  = 32'h00018267;  // jalr x4, x3, 0
        imem[6]  = 32'h06300593;  // addi x11, x0, 99
        imem[7]  = 32'h06300593;  // addi x11, x0, 99
        imem[8]  = 32'h06300593;  // addi x11, x0, 99
        imem[9]  = 32'h00700293;  // addi x5, x0, 7
        imem[10] = 32'h00100073;  // ebreak

        init();

        repeat(500) @(posedge clk);

        check_reg(1,  4,    "jal x1=pc+4");
        check_reg(2,  42,   "x2=42 after jal");
        check_reg(4,  32'h18, "jalr x4=pc+4");
        check_reg(5,  7,    "x5=7 after jalr");
        check_reg(10, 0,    "x10 skipped by jal");
        check_reg(11, 0,    "x11 skipped by jalr");

        if (errors == 0) $display("test_jump: PASSED");
        else $display("test_jump: FAILED (%0d errors)", errors);
        $finish;
    end

endmodule
