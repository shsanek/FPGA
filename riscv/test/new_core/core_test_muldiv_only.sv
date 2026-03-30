module core_test_muldiv_only;
    `include "CORE_PROGRAM_TB.sv"
    initial begin
        load_program("/tmp/test_muldiv_hw.hex");
        run_program(50000000);
        // Print full UART output
        $write("UART[%0d]: ", uart_len);
        for (int i = 0; i < uart_len && i < 4096; i++)
            $write("%c", uart_buf[i]);
        $display("");
        $display("muldiv: %0d cycles, %0d instrs, IPC=%0d.%02d",
            cycle_count, instr_count,
            instr_count / cycle_count,
            (instr_count * 100 / cycle_count) % 100);
        $finish;
    end
endmodule
