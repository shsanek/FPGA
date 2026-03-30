module core_test_mem;
    `include "CORE_TB.sv"
    initial begin
        load_program("/tmp/core_test_mem.hex");
        run_program(5000);
        $display("core_test_mem: %0d cycles (store/load array, 23 words)", cycle_count);
        if (errors == 0) $display("core_test_mem: PASSED");
        else $display("core_test_mem: FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
