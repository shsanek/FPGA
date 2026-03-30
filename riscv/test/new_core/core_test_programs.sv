// Runs all program tests sequentially, reports cycles/instrs/IPC for each.
module core_test_programs;
    `include "CORE_PROGRAM_TB.sv"

    int total_errors = 0;

    task automatic run_test(input string name, input string hex_file, input int max_cyc);
        int test_errors;
        errors = 0;
        uart_len = 0;
        load_program(hex_file);
        run_program(max_cyc);

        if (cycle_count >= max_cyc) begin
            errors++;
        end else begin
            check_no_fail();
            check_output_ok();
        end

        test_errors = errors;
        total_errors += test_errors;

        $display("%s: %0d cycles, %0d instrs, IPC=%0d.%02d  %s",
            name, cycle_count, instr_count,
            (instr_count > 0 && cycle_count > 0) ? instr_count / cycle_count : 0,
            (instr_count > 0 && cycle_count > 0) ? (instr_count * 100 / cycle_count) % 100 : 0,
            (test_errors == 0) ? "PASSED" : "FAILED");
    endtask

    initial begin
        run_test("test_alu",        "/tmp/test_alu.hex",        5000000);
        run_test("test_branch",     "/tmp/test_branch.hex",     5000000);
        run_test("test_jump",       "/tmp/test_jump.hex",       5000000);
        run_test("test_upper",      "/tmp/test_upper.hex",      5000000);
        run_test("test_mem",        "/tmp/test_mem.hex",        5000000);
        run_test("test_muldiv_hw",  "/tmp/test_muldiv_hw.hex",  50000000);

        $display("---");
        if (total_errors == 0) $display("ALL PROGRAM TESTS PASSED");
        else $display("SOME TESTS FAILED (%0d total errors)", total_errors);
        $finish;
    end
endmodule
