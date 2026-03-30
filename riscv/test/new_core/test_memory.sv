// Test: LOAD and STORE (sw, lw, sb, lb, sh, lh)
module test_memory;

    `include "PIPELINE_TB.sv"

    initial begin
        // Data memory base = 0x10000 (mapped to data_mem[0x10000..])
        // Program:
        //   addi x1, x0, 0x55       # x1 = 0x55
        //   lui  x10, 0x10          # x10 = 0x10000 (data base)
        //   sw   x1, 0(x10)         # mem[0x10000] = 0x55
        //   lw   x2, 0(x10)         # x2 = 0x55
        //   addi x3, x0, 0x1234     # won't fit — use lui+addi
        //   lui  x3, 0x00001        # x3 = 0x1000
        //   addi x3, x3, 0x234      # x3 = 0x1234
        //   sh   x3, 4(x10)         # mem[0x10004] = 0x1234 (halfword)
        //   lh   x4, 4(x10)         # x4 = 0x1234 (sign-ext)
        //   addi x5, x0, 0xAB       # x5 = 0xAB
        //   sb   x5, 8(x10)         # mem[0x10008] = 0xAB (byte)
        //   lb   x6, 8(x10)         # x6 = 0xFFFFFFAB (sign-ext)
        //   lbu  x7, 8(x10)         # x7 = 0x000000AB (zero-ext)
        //   ebreak

        imem[0]  = 32'h05500093;  // addi x1, x0, 0x55
        imem[1]  = 32'h00010537;  // lui  x10, 0x10
        imem[2]  = 32'h00152023;  // sw   x1, 0(x10)
        imem[3]  = 32'h00052103;  // lw   x2, 0(x10)
        imem[4]  = 32'h000011b7;  // lui  x3, 0x00001
        imem[5]  = 32'h23418193;  // addi x3, x3, 0x234
        imem[6]  = 32'h00351223;  // sh   x3, 4(x10)
        imem[7]  = 32'h00451203;  // lh   x4, 4(x10)
        imem[8]  = 32'h0ab00293;  // addi x5, x0, 0xAB — wait, 0xAB > 0x7F, need negative
        // Actually 0xAB = 171, fits in 12-bit signed (-2048..2047)
        // But 0xAB in sign-extended imm = 0x000000AB (positive). lb will sign-extend byte 0xAB = -85 → 0xFFFFFFAB
        imem[8]  = 32'h0ab00293;  // addi x5, x0, 171
        imem[9]  = 32'h00550423;  // sb   x5, 8(x10)
        imem[10] = 32'h00850303;  // lb   x6, 8(x10)
        imem[11] = 32'h00854383;  // lbu  x7, 8(x10)
        imem[12] = 32'h00100073;  // ebreak

        init();

        repeat(5) @(posedge clk);
        // Trace pipeline state
        // Check data_mem after program runs
        repeat(800) @(posedge clk);
        $display("data_mem[0x10000]=%02X %02X %02X %02X",
                 data_mem[32'h10000], data_mem[32'h10001], data_mem[32'h10002], data_mem[32'h10003]);
        $display("x1=%08X x2=%08X x10=%08X", regfile[1], regfile[2], regfile[10]);

        for (int t = 0; t < 30; t++) begin
            @(posedge clk); #1;
            $display("T[%0d]: mem_state=%0d mem_valid=%b bus_rd=%b bus_wr=%b bus_addr=%08X bus_rdy=%b opcode=%07b sel_mem=%b",
                     t,
                     dut.stage4_execute.alu_memory.state,
                     dut.stage4_execute.memory_valid,
                     dmem_read, dmem_write, dmem_addr, dmem_ready,
                     dut.stage4_execute.prev_instruction[6:0],
                     dut.stage4_execute.sel_memory);
        end
        repeat(800) @(posedge clk);

        check_reg(1,  32'h55,       "x1=0x55");
        check_reg(2,  32'h55,       "lw x2");
        check_reg(4,  32'h1234,     "lh x4");
        check_reg(6,  32'hFFFFFFAB, "lb x6 sign-ext");
        check_reg(7,  32'h000000AB, "lbu x7 zero-ext");

        if (errors == 0) $display("test_memory: PASSED");
        else $display("test_memory: FAILED (%0d errors)", errors);
        $finish;
    end

endmodule
