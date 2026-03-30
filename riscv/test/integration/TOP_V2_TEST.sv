// TOP_V2_TEST — integration test: full system with MIG_MODEL.
// Loads each program into MIG memory, waits for flash_loader,
// pulses set_pc, runs until EBREAK, checks UART output.

module TOP_V2_TEST;

    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;

    wire [27:0] mig_app_addr;
    wire [2:0]  mig_app_cmd;
    wire        mig_app_en;
    wire [127:0] mig_app_wdf_data;
    wire        mig_app_wdf_wren, mig_app_wdf_end;
    wire [15:0] mig_app_wdf_mask;
    wire        mig_app_rdy, mig_app_wdf_rdy;
    wire [127:0] mig_app_rd_data;
    wire        mig_app_rd_data_valid, mig_app_rd_data_end;
    wire        mig_init_calib_complete;
    wire uart_tx_pin;
    wire oled_cs_n, oled_mosi, oled_sck, oled_dc, oled_res_n, oled_vccen, oled_pmoden;
    wire sd_cs_n, sd_mosi, sd_sck;
    wire flash_cs_n, flash_mosi, flash_sck;
    wire boot_active, boot_error, sd_bus_read, sd_bus_write;

    reg [31:0] test_new_pc = 0;
    reg        test_set_pc = 0;

    TOP_V2 #(
        .CLOCK_FREQ(100_000_000), .BAUD_RATE(115_200),
        .DEBUG_ENABLE(0), .MCV2_DEPTH(64), .MCV2_WAYS(1),
        .ICACHE_DEPTH(128), .ICACHE_WAYS(1), .OLED_BRAM_DEPTH(256)
    ) dut (
        .clk(clk), .reset(reset),
        .uart_rx(1'b1), .uart_tx(uart_tx_pin),
        .mig_ui_clk(clk),
        .mig_init_calib_complete(mig_init_calib_complete),
        .mig_app_rdy(mig_app_rdy),
        .mig_app_addr(mig_app_addr), .mig_app_cmd(mig_app_cmd), .mig_app_en(mig_app_en),
        .mig_app_wdf_data(mig_app_wdf_data), .mig_app_wdf_wren(mig_app_wdf_wren),
        .mig_app_wdf_end(mig_app_wdf_end), .mig_app_wdf_mask(mig_app_wdf_mask),
        .mig_app_wdf_rdy(mig_app_wdf_rdy),
        .mig_app_rd_data(mig_app_rd_data),
        .mig_app_rd_data_valid(mig_app_rd_data_valid),
        .mig_app_rd_data_end(mig_app_rd_data_end),
        .oled_cs_n(oled_cs_n), .oled_mosi(oled_mosi), .oled_sck(oled_sck),
        .oled_dc(oled_dc), .oled_res_n(oled_res_n), .oled_vccen(oled_vccen),
        .oled_pmoden(oled_pmoden),
        .sd_cs_n(sd_cs_n), .sd_mosi(sd_mosi), .sd_sck(sd_sck),
        .sd_miso(1'b1), .sd_cd_n(1'b1),
        .flash_cs_n(flash_cs_n), .flash_mosi(flash_mosi), .flash_sck(flash_sck),
        .flash_miso(1'b1),
        .boot_active(boot_active), .boot_error(boot_error),
        .sd_bus_read(sd_bus_read), .sd_bus_write(sd_bus_write),
        .ext_test_new_pc(test_new_pc), .ext_test_set_pc(test_set_pc)
    );

    MIG_MODEL #(.MEM_DEPTH(16384)) mig (
        .mig_ui_clk(clk),
        .mig_init_calib_complete(mig_init_calib_complete),
        .mig_app_rdy(mig_app_rdy),
        .mig_app_en(mig_app_en), .mig_app_cmd(mig_app_cmd), .mig_app_addr(mig_app_addr),
        .mig_app_wdf_data(mig_app_wdf_data), .mig_app_wdf_wren(mig_app_wdf_wren),
        .mig_app_wdf_end(mig_app_wdf_end), .mig_app_wdf_rdy(mig_app_wdf_rdy),
        .mig_app_rd_data(mig_app_rd_data),
        .mig_app_rd_data_valid(mig_app_rd_data_valid),
        .mig_app_rd_data_end(mig_app_rd_data_end)
    );

    // UART capture: snoop UART_IO_DEVICE TX writes
    reg [7:0] uart_buf [0:4095];
    int uart_len;

    always @(posedge clk) begin
        if (dut.uart_io.write_trigger && dut.uart_io.address[3:2] == 2'd0) begin
            if (uart_len < 4096) begin
                uart_buf[uart_len] <= dut.uart_io.write_value[7:0];
                uart_len <= uart_len + 1;
            end
        end
    end

    // Load program
    reg [31:0] prog_words [0:65535];

    task automatic load_and_run(input string name, input string hex_file, input int max_cyc);
        int cycle_count, err;
        err = 0;
        uart_len = 0;

        // Load
        for (int i = 0; i < 65536; i++) prog_words[i] = 32'h00000013;
        $readmemh(hex_file, prog_words);
        for (int i = 0; i < 16384; i++)
            mig.mem[i] = {prog_words[i*4+3], prog_words[i*4+2], prog_words[i*4+1], prog_words[i*4+0]};

        // Reset
        reset = 1;
        @(posedge clk); @(posedge clk); @(posedge clk);
        reset = 0;

        // Wait flash_loader
        while (boot_active) @(posedge clk);

        // Start CPU
        test_new_pc = 32'h0;
        test_set_pc = 1;
        @(posedge clk);
        test_set_pc = 0;

        // Run
        cycle_count = 0;
        while (cycle_count < max_cyc) begin
            @(posedge clk); #1;
            cycle_count++;
            if (dut.core.pipeline_inst.s3_valid &&
                dut.core.pipeline_inst.s3_ready &&
                dut.core.pipeline_inst.s3_instruction == 32'h00100073)
                break;
        end

        if (cycle_count >= max_cyc) begin
            $display("%s: TIMEOUT after %0d cycles (ic=%0d)", name, max_cyc, dut.core_instr_count);
            err = 1;
        end else begin
            // Check UART for FAIL
            for (int i = 0; i < uart_len - 3; i++)
                if (uart_buf[i]=="F" && uart_buf[i+1]=="A" && uart_buf[i+2]=="I" && uart_buf[i+3]=="L") begin
                    err = 1;
                    $display("%s: FAIL in UART output", name);
                end
        end

        $display("%s: %0d cycles, %0d instrs, IPC=%0d.%02d  %s",
            name, cycle_count, dut.core_instr_count,
            dut.core_instr_count / cycle_count,
            (dut.core_instr_count * 100 / cycle_count) % 100,
            err == 0 ? "PASSED" : "FAILED");
    endtask

    initial begin
        load_and_run("test_alu",       "/tmp/test_alu.hex",       500_000);
        load_and_run("test_branch",    "/tmp/test_branch.hex",    500_000);
        load_and_run("test_jump",      "/tmp/test_jump.hex",      500_000);
        load_and_run("test_upper",     "/tmp/test_upper.hex",     500_000);
        load_and_run("test_mem",       "/tmp/test_mem.hex",       500_000);
        load_and_run("test_muldiv_hw", "/tmp/test_muldiv_hw.hex", 500_000);
        $display("---");
        $display("Done");
        $finish;
    end

endmodule
