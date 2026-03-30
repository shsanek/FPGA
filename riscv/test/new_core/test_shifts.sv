// Test: shift operations (sll, srl, sra, slli, srli, srai)
module test_shifts;

    `include "PIPELINE_TB.sv"

    initial begin
        // Program:
        //   addi  x1, x0, 1         # x1 = 1
        //   slli  x2, x1, 4         # x2 = 1 << 4 = 16
        //   slli  x3, x1, 31        # x3 = 0x80000000
        //   srli  x4, x3, 31        # x4 = 1 (logical shift)
        //   srai  x5, x3, 31        # x5 = 0xFFFFFFFF (arithmetic shift)
        //   addi  x6, x0, -1        # x6 = 0xFFFFFFFF
        //   srli  x7, x6, 16        # x7 = 0x0000FFFF
        //   srai  x8, x6, 16        # x8 = 0xFFFFFFFF
        //   ebreak

        imem[0] = 32'h00100093;  // addi  x1, x0, 1
        imem[1] = 32'h00409113;  // slli  x2, x1, 4
        imem[2] = 32'h01f09193;  // slli  x3, x1, 31
        imem[3] = 32'h01f1d213;  // srli  x4, x3, 31
        imem[4] = 32'h41f1d293;  // srai  x5, x3, 31
        imem[5] = 32'hfff00313;  // addi  x6, x0, -1
        imem[6] = 32'h01035393;  // srli  x7, x6, 16
        imem[7] = 32'h41035413;  // srai  x8, x6, 16
        imem[8] = 32'h00100073;  // ebreak

        init();

        repeat(300) @(posedge clk);

        check_reg(1, 32'h00000001, "x1=1");
        check_reg(2, 32'h00000010, "slli x2=16");
        check_reg(3, 32'h80000000, "slli x3=0x80000000");
        check_reg(4, 32'h00000001, "srli x4=1");
        check_reg(5, 32'hFFFFFFFF, "srai x5=0xFFFFFFFF");
        check_reg(6, 32'hFFFFFFFF, "x6=-1");
        check_reg(7, 32'h0000FFFF, "srli x7");
        check_reg(8, 32'hFFFFFFFF, "srai x8");

        if (errors == 0) $display("test_shifts: PASSED");
        else $display("test_shifts: FAILED (%0d errors)", errors);
        $finish;
    end

endmodule
