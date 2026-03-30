module core_test_fib;
    `include "CORE_TB.sv"
    initial begin
        load_program("/tmp/core_test_fib.hex");
        run_program(50000);
        $display("core_test_fib: %0d cycles (fib(20), 18 words)", cycle_count);
        if (errors == 0) $display("core_test_fib: PASSED");
        else $display("core_test_fib: FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
