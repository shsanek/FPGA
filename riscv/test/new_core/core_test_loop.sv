module core_test_loop;
    `include "CORE_TB.sv"
    initial begin
        load_program("/tmp/core_test_loop.hex");
        run_program(50000);
        $display("core_test_loop: %0d cycles (sum 1..100, ~303 instrs)", cycle_count);
        // Check sum = 5050 by peeking at stack (volatile stores to stack)
        if (errors == 0) $display("core_test_loop: PASSED");
        else $display("core_test_loop: FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
