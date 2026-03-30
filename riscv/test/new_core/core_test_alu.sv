module core_test_alu;
    `include "CORE_TB.sv"
    initial begin
        load_program("/tmp/core_test_alu.hex");
        run_program(5000);
        $display("core_test_alu: %0d cycles (37 words)", cycle_count);
        if (errors == 0) $display("core_test_alu: PASSED");
        else $display("core_test_alu: FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
