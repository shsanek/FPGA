module TOP_V2_QUICK_TEST;

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
        .ICACHE_DEPTH(64), .ICACHE_WAYS(1), .OLED_BRAM_DEPTH(256)
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

    // Load program into MIG memory
    task automatic load_program(input string hex_file);
        reg [31:0] words [0:65535];
        integer i;
        for (i = 0; i < 65536; i++) words[i] = 32'h00000013;
        $readmemh(hex_file, words);
        for (i = 0; i < 16384; i++)
            mig.mem[i] = {words[i*4+3], words[i*4+2], words[i*4+1], words[i*4+0]};
    endtask

    initial begin
        load_program("/tmp/core_test_fib.hex");
        reset = 1;
        @(posedge clk); @(posedge clk); @(posedge clk);
        reset = 0;

        // Wait for FLASH_LOADER to finish (it fails since no real flash)
        $display("Waiting for flash_loader to finish...");
        while (dut.boot_active) @(posedge clk);
        $display("Flash done at cycle %0t, sending set_pc=0", $time/10);

        // Force set_pc to start execution from address 0
        // (flash_loader does set_pc on success, but on failure it doesn't)
        @(posedge clk);
        // Use ext_set_pc through the debug path
        test_new_pc = 32'h0;
        test_set_pc = 1;
        @(posedge clk);
        test_set_pc = 0;
        $display("Pipeline started");

        for (int c = 0; c < 50000; c++) begin
            @(posedge clk); #1;
            // Periodic status
            if (c % 500 == 0)
                $display("C%0d ic=%0d pc=%08X instr=%08X empty=%b flash=%b",
                    c, dut.core_instr_count,
                    dut.dbg_current_pc, dut.dbg_current_instr,
                    dut.pipeline_empty, dut.boot_active);
            // Detect EBREAK
            if (dut.core.pipeline_inst.s3_valid &&
                dut.core.pipeline_inst.s3_ready &&
                dut.core.pipeline_inst.s3_instruction == 32'h00100073) begin
                $display("EBREAK at cycle %0d, %0d instrs", c, dut.core_instr_count);
                break;
            end
        end
        $display("Done");
        $finish;
    end
endmodule
