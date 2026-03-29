// PROGRAM_TEST_V2 — integration test for TOP_V2.
//
// Loads RV32I program via UART debug protocol, runs it, captures output.
// Flow: HALT → WRITE_MEM × N → RESET_PC(0) → RESUME → wait EBREAK
//
// Plusargs:
//   +HEX_FILE=<path>   — hex file ($readmemh, 32-bit words)
//   +OUT_FILE=<path>    — UART output capture (default /tmp/prog_out.txt)
//   +TIMEOUT=<cycles>   — max cycles (default 5_000_000)
module PROGRAM_TEST_V2 ();
    localparam CLOCK_FREQ   = 1_000_000;
    localparam BAUD_RATE    = 10_000;
    localparam BIT_PERIOD   = CLOCK_FREQ / BAUD_RATE;
    localparam MAX_WORDS    = 4096;

    logic clk     = 0;
    logic mig_clk = 0;
    initial forever #5  clk     = ~clk;
    initial forever #4  mig_clk = ~mig_clk;

    logic reset = 1;

    // MIG interface
    wire [27:0]  mig_app_addr;
    wire [2:0]   mig_app_cmd;
    wire         mig_app_en;
    wire [127:0] mig_app_wdf_data;
    wire         mig_app_wdf_wren, mig_app_wdf_end;
    wire [15:0]  mig_app_wdf_mask;
    wire         mig_app_wdf_rdy;
    wire [127:0] mig_app_rd_data;
    wire         mig_app_rd_data_valid, mig_app_rd_data_end;
    wire         mig_app_rdy;
    wire         mig_init_calib_complete;

    // DUT
    logic uart_rx_pin = 1;
    wire  uart_tx_pin;
    wire  flash_cs_n, flash_sck, flash_mosi, flash_miso;
    wire  sd_cs_n, sd_mosi, sd_sck;

    TOP_V2 #(
        .CLOCK_FREQ  (CLOCK_FREQ),
        .BAUD_RATE   (BAUD_RATE),
        .DEBUG_ENABLE(1),
        .MCV2_DEPTH  (16),
        .MCV2_WAYS   (1),
        .OLED_BRAM_DEPTH(16)
    ) dut (
        .clk                    (clk),
        .reset                  (reset),
        .uart_rx                (uart_rx_pin),
        .uart_tx                (uart_tx_pin),
        .mig_ui_clk             (mig_clk),
        .mig_init_calib_complete(mig_init_calib_complete),
        .mig_app_rdy            (mig_app_rdy),
        .mig_app_addr           (mig_app_addr),
        .mig_app_cmd            (mig_app_cmd),
        .mig_app_en             (mig_app_en),
        .mig_app_wdf_data       (mig_app_wdf_data),
        .mig_app_wdf_wren       (mig_app_wdf_wren),
        .mig_app_wdf_end        (mig_app_wdf_end),
        .mig_app_wdf_mask       (mig_app_wdf_mask),
        .mig_app_wdf_rdy        (mig_app_wdf_rdy),
        .mig_app_rd_data        (mig_app_rd_data),
        .mig_app_rd_data_valid  (mig_app_rd_data_valid),
        .mig_app_rd_data_end    (mig_app_rd_data_end),
        .oled_cs_n(), .oled_mosi(), .oled_sck(), .oled_dc(),
        .oled_res_n(), .oled_vccen(), .oled_pmoden(),
        .sd_cs_n(sd_cs_n), .sd_mosi(sd_mosi), .sd_miso(1'b1),
        .sd_sck(sd_sck), .sd_cd_n(1'b1),
        .flash_cs_n(flash_cs_n), .flash_mosi(flash_mosi),
        .flash_miso(flash_miso), .flash_sck(flash_sck)
    );

    // SPI flash mock
    SPI_FLASH_STUB flash_mock (
        .cs_n(flash_cs_n), .sck(flash_sck), .mosi(flash_mosi), .miso(flash_miso)
    );

    MIG_MODEL #(.CHUNK_PART(128), .ADDRESS_SIZE(28)) mig (
        .mig_ui_clk(mig_clk),
        .mig_init_calib_complete(mig_init_calib_complete),
        .mig_app_rdy(mig_app_rdy), .mig_app_en(mig_app_en),
        .mig_app_cmd(mig_app_cmd), .mig_app_addr(mig_app_addr),
        .mig_app_wdf_data(mig_app_wdf_data), .mig_app_wdf_wren(mig_app_wdf_wren),
        .mig_app_wdf_end(mig_app_wdf_end), .mig_app_wdf_rdy(mig_app_wdf_rdy),
        .mig_app_rd_data(mig_app_rd_data),
        .mig_app_rd_data_valid(mig_app_rd_data_valid),
        .mig_app_rd_data_end(mig_app_rd_data_end)
    );

    // ---------------------------------------------------------------
    // UART bit-bang
    // ---------------------------------------------------------------
    task uart_send(input [7:0] data);
        integer i;
        uart_rx_pin = 0;
        repeat(BIT_PERIOD) @(posedge clk);
        for (i = 0; i < 8; i++) begin
            uart_rx_pin = data[i];
            repeat(BIT_PERIOD) @(posedge clk);
        end
        uart_rx_pin = 1;
        repeat(BIT_PERIOD) @(posedge clk);
    endtask

    // ---------------------------------------------------------------
    // Debug response capture
    // ---------------------------------------------------------------
    logic [7:0] dbg_resp_fifo [0:63];
    integer     dbg_resp_wr_ptr = 0;
    integer     dbg_resp_rd_ptr = 0;

    always @(posedge clk) begin
        if (dut.dbg_ctrl.dbg.tx_valid_r) begin
            dbg_resp_fifo[dbg_resp_wr_ptr[5:0]] = dut.dbg_ctrl.dbg.tx_byte_r;
            dbg_resp_wr_ptr = dbg_resp_wr_ptr + 1;
        end
    end

    task wait_dbg_response(input integer n_bytes);
        integer timeout;
        timeout = 0;
        while ((dbg_resp_wr_ptr - dbg_resp_rd_ptr) < n_bytes && timeout < 100000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        dbg_resp_rd_ptr = dbg_resp_rd_ptr + n_bytes;
    endtask

    task read_dbg_response(input integer n_bytes, output logic [31:0] result);
        integer timeout, i;
        result = 0;
        timeout = 0;
        while ((dbg_resp_wr_ptr - dbg_resp_rd_ptr) < n_bytes && timeout < 100000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        for (i = 0; i < n_bytes; i++) begin
            result[i*8 +: 8] = dbg_resp_fifo[dbg_resp_rd_ptr[5:0]];
            dbg_resp_rd_ptr = dbg_resp_rd_ptr + 1;
        end
    endtask

    // ---------------------------------------------------------------
    // Debug commands
    // ---------------------------------------------------------------
    task dbg_halt();
        uart_send(8'h01);
        wait_dbg_response(3);
    endtask

    task dbg_resume();
        uart_send(8'h02);
        wait_dbg_response(3);
    endtask

    task dbg_write_mem(input [31:0] addr, input [31:0] data);
        uart_send(8'h05);
        uart_send(addr[7:0]);  uart_send(addr[15:8]);
        uart_send(addr[23:16]); uart_send(addr[31:24]);
        uart_send(data[7:0]);  uart_send(data[15:8]);
        uart_send(data[23:16]); uart_send(data[31:24]);
        wait_dbg_response(3);
    endtask

    task dbg_reset_pc(input [31:0] addr);
        uart_send(8'h07);
        uart_send(addr[7:0]);  uart_send(addr[15:8]);
        uart_send(addr[23:16]); uart_send(addr[31:24]);
        wait_dbg_response(3);
    endtask

    // ---------------------------------------------------------------
    // CPU TX output capture
    // ---------------------------------------------------------------
    string   out_file;
    integer  out_fd;
    integer  out_byte_count;

    initial begin
        if (!$value$plusargs("OUT_FILE=%s", out_file))
            out_file = "/tmp/prog_out.txt";
        out_fd = $fopen(out_file, "w");
        if (!out_fd) begin
            $display("ERROR: cannot open OUT_FILE=%s", out_file);
            $finish;
        end
        out_byte_count = 0;
    end

    logic cpu_tx_prev = 0;
    always @(posedge clk) begin
        cpu_tx_prev <= dut.cpu_tx_valid;
        if (dut.cpu_tx_valid && !cpu_tx_prev) begin
            $fwrite(out_fd, "%c", dut.cpu_tx_byte[7:0]);
            out_byte_count = out_byte_count + 1;
        end
    end

    // ---------------------------------------------------------------
    // Main test
    // ---------------------------------------------------------------
    initial begin
        string  hex_file;
        integer timeout_cycles;
        integer n, word_count;
        logic [31:0] words [0:MAX_WORDS-1];

        if (!$value$plusargs("HEX_FILE=%s", hex_file)) begin
            $display("ERROR: +HEX_FILE=<path> not specified");
            $fclose(out_fd);
            $finish;
        end
        if (!$value$plusargs("TIMEOUT=%d", timeout_cycles))
            timeout_cycles = 5_000_000;

        for (n = 0; n < MAX_WORDS; n++) words[n] = 32'h0000_0013;
        $readmemh(hex_file, words);

        word_count = 0;
        for (n = MAX_WORDS - 1; n >= 0; n = n - 1) begin
            if (words[n] !== 32'h0000_0013) begin
                word_count = n + 1;
                n = -1;
            end
        end
        if (word_count == 0) word_count = 1;
        $display("PROGRAM_TEST_V2: loading %0d words from %s", word_count, hex_file);

        // Reset
        #100;
        reset = 0;
        #100;

        // HALT
        dbg_halt();
        repeat(50) @(posedge clk);
        $display("HALTED: PC=0x%08X", dut.cpu.pc);

        // Load program
        for (n = 0; n < word_count; n++) begin
            dbg_write_mem(n * 4, words[n]);
        end
        $display("Loaded %0d words", word_count);

        // Reset PC
        dbg_reset_pc(32'h0);
        repeat(50) @(posedge clk);
        $display("PC reset to 0x%08X", dut.cpu.pc);

        // Resume
        dbg_resume();

        // Debug: trace first 20 cycles after resume
        for (n = 0; n < 20; n++) begin
            @(posedge clk); #1;
            $display("TRACE[%0d]: PC=%08X da_state=%0d if_ready=%b if_rd=%b arb_state=%0d bus128_rd=%b bus128_ready=%b mc_ready=%b",
                     n, dut.cpu.pc,
                     dut.data_adapter.state,
                     dut.if128_ready,
                     dut.if128_rd,
                     dut.arbiter.state,
                     dut.bus128_rd,
                     dut.bus128_ready,
                     dut.mc_bus_ready);
        end

        // Wait for EBREAK (halted) or timeout
        n = 0;
        while (dut.dbg_is_halted !== 1'b1 && n < timeout_cycles) begin
            @(posedge clk);
            n = n + 1;
        end

        $fflush(out_fd);
        $fclose(out_fd);

        if (dut.dbg_is_halted !== 1'b1) begin
            $display("PROGRAM_TEST_V2 TIMEOUT after %0d cycles", n);
            $finish(1);
        end else begin
            $display("PROGRAM_TEST_V2 OK: %0d cycles, %0d bytes output -> %s",
                     n, out_byte_count, out_file);
            $finish(0);
        end
    end

    initial begin
        #2_000_000_000;
        $display("PROGRAM_TEST_V2 HARD TIMEOUT");
        $fclose(out_fd);
        $finish(1);
    end
endmodule
