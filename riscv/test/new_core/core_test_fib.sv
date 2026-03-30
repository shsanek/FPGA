module core_test_fib;
    `include "CORE_TB.sv"
    initial begin
        load_program("/tmp/core_test_fib.hex");
        run_program(500000);
        $display("core_test_fib: %0d cycles, %0d instrs, IPC=%0d.%02d (fib(20), 18 words)",
            cycle_count, instr_count,
            instr_count / cycle_count,
            (instr_count * 100 / cycle_count) % 100);
        if (errors == 0) $display("core_test_fib: PASSED");
        else $display("core_test_fib: FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
