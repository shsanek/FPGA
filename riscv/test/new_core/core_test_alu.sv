module core_test_alu;
    `include "CORE_TB.sv"
    initial begin
        load_program("/tmp/core_test_alu.hex");
        run_program(5000);
        $display("core_test_alu: %0d cycles, %0d instrs, IPC=%0d.%02d",
            cycle_count, instr_count,
            instr_count / cycle_count,
            (instr_count * 100 / cycle_count) % 100);
        if (errors == 0) $display("core_test_alu: PASSED");
        else $display("core_test_alu: FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
