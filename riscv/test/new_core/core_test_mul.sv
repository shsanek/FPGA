// Test MUL: x1=5, x2=7, x2 = x1 * x2 = 35
module core_test_mul;
    `include "CORE_TB.sv"
    initial begin
        $dumpfile("/tmp/mul_test.vcd");
        $dumpvars(0, core_test_mul);
        // addi x1, x0, 5     00500093
        // addi x2, x0, 7     00700113
        // mul  x2, x1, x2    02208133
        // ebreak              00100073
        mem[0] = 32'h00500093;
        mem[1] = 32'h00700113;
        mem[2] = 32'h02208133;
        mem[3] = 32'h00100073;
        reset = 1; @(posedge clk); @(posedge clk); reset = 0;
        core_stall = 0; cycle_count = 0;
        while (cycle_count < 200) begin
            @(posedge clk); #1;
            cycle_count++;
            // Monitor MULDIV
            if (dut.pipeline_inst.stage4_execute.alu_muldiv.state != 0 ||
                dut.pipeline_inst.stage4_execute.muldiv_done) begin
                $display("C%0d md_st=%0d md_done=%b md_rdy=%b md_rd=%0d md_val=%08X wb_v=%b wb_r=%b",
                    cycle_count,
                    dut.pipeline_inst.stage4_execute.alu_muldiv.state,
                    dut.pipeline_inst.stage4_execute.muldiv_done,
                    dut.pipeline_inst.stage4_execute.muldiv_wb_rdy,
                    dut.pipeline_inst.stage4_execute.alu_muldiv.out_rd_index,
                    dut.pipeline_inst.stage4_execute.alu_muldiv.out_rd_value,
                    dut.pipeline_inst.stage4_execute.next_stage_valid,
                    dut.pipeline_inst.stage4_execute.next_stage_ready);
            end
            if (dut.pipeline_inst.s3_valid && dut.pipeline_inst.s3_ready &&
                dut.pipeline_inst.s3_instruction == 32'h00100073)
                break;
        end
        check_reg(1, 5, "x1=5");
        check_reg(2, 35, "x2=5*7=35");
        $display("core_test_mul: %0d cycles, %0d instrs  %s",
            cycle_count, instr_count, errors == 0 ? "PASSED" : "FAILED");
        $finish;
    end
endmodule
