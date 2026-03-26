// Универсальный тестбенч: загружает RV32I программу через UART debug
// протокол (как на реальном железе), запускает, захватывает вывод.
//
// Поток: HALT → WRITE_MEM × N → RESET_PC(0) → RESUME → ждём EBREAK
//
// Plusargs:
//   +HEX_FILE=<path>   — hex-файл программы ($readmemh, 32-bit words)
//   +OUT_FILE=<path>   — куда писать UART-вывод
//   +TIMEOUT=<cycles>  — макс. тактов (по умолч. 5_000_000)
module PROGRAM_TEST ();
    localparam CLOCK_FREQ   = 1_000_000;
    localparam BAUD_RATE    = 10_000;
    localparam BIT_PERIOD   = CLOCK_FREQ / BAUD_RATE; // 100
    localparam CHUNK_PART   = 128;
    localparam ADDRESS_SIZE = 28;
    localparam MAX_WORDS    = 4096;

    // ---------------------------------------------------------------
    // Тактовые генераторы
    // ---------------------------------------------------------------
    logic clk     = 0;
    logic mig_clk = 0;
    initial forever #5  clk     = ~clk;
    initial forever #4  mig_clk = ~mig_clk;

    logic reset = 1;

    // ---------------------------------------------------------------
    // MIG интерфейс
    // ---------------------------------------------------------------
    wire [ADDRESS_SIZE-1:0]   mig_app_addr;
    wire [2:0]                mig_app_cmd;
    wire                      mig_app_en;
    wire [CHUNK_PART-1:0]     mig_app_wdf_data;
    wire                      mig_app_wdf_wren;
    wire                      mig_app_wdf_end;
    wire [(CHUNK_PART/8-1):0] mig_app_wdf_mask;
    wire                      mig_app_wdf_rdy;
    wire [CHUNK_PART-1:0]     mig_app_rd_data;
    wire                      mig_app_rd_data_valid;
    wire                      mig_app_rd_data_end;
    wire                      mig_app_rdy;
    wire                      mig_init_calib_complete;

    // ---------------------------------------------------------------
    // DUT: TOP (без ROM)
    // ---------------------------------------------------------------
    logic uart_rx_pin = 1;
    wire  uart_tx_pin;

    TOP #(
        .CLOCK_FREQ  (CLOCK_FREQ),
        .BAUD_RATE   (BAUD_RATE),
        .CHUNK_PART  (CHUNK_PART),
        .ADDRESS_SIZE(ADDRESS_SIZE),
        .DEBUG_ENABLE(1)
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
        .mig_app_rd_data_end    (mig_app_rd_data_end)
    );

    MIG_MODEL #(
        .CHUNK_PART  (CHUNK_PART),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) mig (
        .mig_ui_clk             (mig_clk),
        .mig_init_calib_complete(mig_init_calib_complete),
        .mig_app_rdy            (mig_app_rdy),
        .mig_app_en             (mig_app_en),
        .mig_app_cmd            (mig_app_cmd),
        .mig_app_addr           (mig_app_addr),
        .mig_app_wdf_data       (mig_app_wdf_data),
        .mig_app_wdf_wren       (mig_app_wdf_wren),
        .mig_app_wdf_end        (mig_app_wdf_end),
        .mig_app_wdf_rdy        (mig_app_wdf_rdy),
        .mig_app_rd_data        (mig_app_rd_data),
        .mig_app_rd_data_valid  (mig_app_rd_data_valid),
        .mig_app_rd_data_end    (mig_app_rd_data_end)
    );

    // ---------------------------------------------------------------
    // UART bit-bang: отправить 1 байт (start + 8 data LSB first + stop)
    // ---------------------------------------------------------------
    task uart_send(input [7:0] data);
        integer i;
        uart_rx_pin = 0;                          // start bit
        repeat(BIT_PERIOD) @(posedge clk);
        for (i = 0; i < 8; i++) begin
            uart_rx_pin = data[i];                // LSB first
            repeat(BIT_PERIOD) @(posedge clk);
        end
        uart_rx_pin = 1;                          // stop bit
        repeat(BIT_PERIOD) @(posedge clk);
    endtask

    // ---------------------------------------------------------------
    // Debug response FIFO — ловим все tx_valid_r в background
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
    // Debug команды через UART
    // ---------------------------------------------------------------
    // ACK = 0xAA + CMD + CMD = 3 байта
    // ACK + DATA = 3 + N байт

    task dbg_halt();
        uart_send(8'h01);
        wait_dbg_response(3); // 0xAA 0x01 0x01
    endtask

    task dbg_resume();
        uart_send(8'h02);
        wait_dbg_response(3); // 0xAA 0x02 0x02
    endtask

    task dbg_write_mem(input [31:0] addr, input [31:0] data);
        uart_send(8'h05);
        uart_send(addr[7:0]);
        uart_send(addr[15:8]);
        uart_send(addr[23:16]);
        uart_send(addr[31:24]);
        uart_send(data[7:0]);
        uart_send(data[15:8]);
        uart_send(data[23:16]);
        uart_send(data[31:24]);
        wait_dbg_response(3); // 0xAA 0x05 0x05
    endtask

    task dbg_reset_pc(input [31:0] addr);
        uart_send(8'h07);
        uart_send(addr[7:0]);
        uart_send(addr[15:8]);
        uart_send(addr[23:16]);
        uart_send(addr[31:24]);
        wait_dbg_response(3); // 0xAA 0x07 0x07
    endtask

    // ---------------------------------------------------------------
    // Захват UART TX-байтов (CPU passthrough вывод)
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

    // cpu_tx_valid теперь уровень (TX_WAIT_ACCEPT), ловим только фронт
    logic cpu_tx_prev = 0;
    always @(posedge clk) begin
        cpu_tx_prev <= dut.cpu_tx_valid;
        if (dut.cpu_tx_valid && !cpu_tx_prev) begin
            $fwrite(out_fd, "%c", dut.cpu_tx_byte[7:0]);
            out_byte_count = out_byte_count + 1;
        end
    end

    // ---------------------------------------------------------------
    // Главный процесс
    // ---------------------------------------------------------------
    initial begin
        string  hex_file;
        integer timeout_cycles;
        integer n, word_count;

        logic [31:0] words [0:MAX_WORDS-1];

        // --- Аргументы ---
        if (!$value$plusargs("HEX_FILE=%s", hex_file)) begin
            $display("ERROR: +HEX_FILE=<path> not specified");
            $fclose(out_fd);
            $finish;
        end
        if (!$value$plusargs("TIMEOUT=%d", timeout_cycles))
            timeout_cycles = 5_000_000;

        // --- Загрузить hex в массив ---
        for (n = 0; n < MAX_WORDS; n++) words[n] = 32'h0000_0013; // NOP
        $readmemh(hex_file, words);

        // Посчитать непустые слова
        word_count = 0;
        for (n = MAX_WORDS - 1; n >= 0; n = n - 1) begin
            if (words[n] !== 32'h0000_0013) begin
                word_count = n + 1;
                n = -1; // break
            end
        end
        if (word_count == 0) word_count = 1;
        $display("PROGRAM_TEST: loading %0d words from %s", word_count, hex_file);

        // --- Снимаем reset, ждём готовности ---
        #100;
        reset = 0;
        #100;

        // --- HALT CPU ---
        dbg_halt();
        repeat(50) @(posedge clk);
        $display("DEBUG after HALT: halted=%b PC=0x%08X", dut.dbg_is_halted, dut.cpu.pc);

        // --- Загрузить программу через WRITE_MEM ---
        for (n = 0; n < word_count; n++) begin
            $display("DEBUG: writing addr=0x%08X data=0x%08X", n*4, words[n]);
            dbg_write_mem(n * 4, words[n]);
            $display("DEBUG: write done, bus_wr_data=0x%08X mc_dbg_wr_data=0x%08X",
                     dut.bus_wr_data, dut.dbg_ctrl.dbg.mc_data_r);
        end

        // --- Direct peek at cache ---
        $display("DEBUG: c0 v=%b a=0x%06X d0=0x%08X d1=0x%08X", dut.mem_ctrl.storage_pool.gen_storage[0].storage_inst.chunk_valid, dut.mem_ctrl.storage_pool.gen_storage[0].storage_inst.chunk_addr, dut.mem_ctrl.storage_pool.gen_storage[0].storage_inst.chunk_data0, dut.mem_ctrl.storage_pool.gen_storage[0].storage_inst.chunk_data1);
        $display("DEBUG: c1 v=%b a=0x%06X d0=0x%08X d1=0x%08X", dut.mem_ctrl.storage_pool.gen_storage[1].storage_inst.chunk_valid, dut.mem_ctrl.storage_pool.gen_storage[1].storage_inst.chunk_addr, dut.mem_ctrl.storage_pool.gen_storage[1].storage_inst.chunk_data0, dut.mem_ctrl.storage_pool.gen_storage[1].storage_inst.chunk_data1);
        $display("DEBUG: c2 v=%b a=0x%06X d0=0x%08X d1=0x%08X", dut.mem_ctrl.storage_pool.gen_storage[2].storage_inst.chunk_valid, dut.mem_ctrl.storage_pool.gen_storage[2].storage_inst.chunk_addr, dut.mem_ctrl.storage_pool.gen_storage[2].storage_inst.chunk_data0, dut.mem_ctrl.storage_pool.gen_storage[2].storage_inst.chunk_data1);
        $display("DEBUG: c3 v=%b a=0x%06X d0=0x%08X d1=0x%08X", dut.mem_ctrl.storage_pool.gen_storage[3].storage_inst.chunk_valid, dut.mem_ctrl.storage_pool.gen_storage[3].storage_inst.chunk_addr, dut.mem_ctrl.storage_pool.gen_storage[3].storage_inst.chunk_data0, dut.mem_ctrl.storage_pool.gen_storage[3].storage_inst.chunk_data1);
        $display("DEBUG: MIG[0]=0x%032X", mig.mem[0]);
        // Direct cache read test
        $display("DEBUG: MC read_value=0x%08X contains=%b out_addr=0x%07X",
                 dut.mem_ctrl.storage_pool.read_value,
                 dut.mem_ctrl.storage_pool.contains_address,
                 dut.mem_ctrl.output_address);
        $display("DEBUG: PBUS read_value=0x%08X mc_read_value=0x%08X io_sel=%b",
                 dut.pbus.read_value, dut.pbus.mc_read_value, dut.pbus.io_sel);

        // --- Verify write: read back addr 0 through debug ---
        uart_send(8'h04); // CMD_READ_MEM
        uart_send(8'h00); uart_send(8'h00); uart_send(8'h00); uart_send(8'h00);
        begin
            logic [31:0] readback;
            wait_dbg_response(3);            // skip ACK: 0xAA 0x04 0x04
            read_dbg_response(4, readback);  // read DATA[31:0]
            $display("DEBUG: readback addr 0x00 = 0x%08X (expect 0x%08X)", readback, words[0]);
        end

        // --- Reset PC to 0 ---
        $display("DEBUG before RESET_PC: halted=%b PC=0x%08X", dut.dbg_is_halted, dut.cpu.pc);
        dbg_reset_pc(32'h0);
        repeat(50) @(posedge clk);
        $display("DEBUG after RESET_PC: halted=%b PC=0x%08X", dut.dbg_is_halted, dut.cpu.pc);

        // --- Check MC state before resume ---
        $display("DEBUG before RESUME: bus_ready=%b mc_ready=%b pipeline=%0d",
                 dut.bus_ready, dut.mc_ready, dut.pipeline.state);

        // --- RESUME CPU ---
        dbg_resume();

        // --- Debug: покажем состояние после resume ---
        repeat(100) @(posedge clk);
        $display("DEBUG: PC=0x%08X instr=0x%08X halted=%b pipeline_state=%0d",
                 dut.cpu.pc, dut.pipeline.instr_reg,
                 dut.dbg_is_halted, dut.pipeline.state);
        $display("DEBUG: mc_ready=%b mc_addr=0x%07X mc_rd=%b mc_wr=%b",
                 dut.pbus.controller_ready, dut.pipeline.mc_address,
                 dut.pipeline.mc_read_trigger, dut.pipeline.mc_write_trigger);

        // --- Watch first fetches + EBREAK state ---
        for (int fi = 0; fi < 3; fi++) begin
            @(posedge clk); #1;
            while (dut.pipeline.state != 2) begin  // 2 = S_EXECUTE
                @(posedge clk); #1;
                if ($time > 500000) begin fi = 3; break; end
            end
            $display("DEBUG exec[%0d]: PC=0x%08X instr=0x%08X ebreak=%b halted=%b stall=%b",
                     fi, dut.cpu.pc, dut.pipeline.instr_reg,
                     dut.cpu.is_ebreak, dut.cpu.dbg_is_halted,
                     dut.cpu.cpu_stall);
            @(posedge clk); // let it advance
        end

        // --- Ждём EBREAK или timeout ---
        n = 0;
        while (dut.dbg_is_halted !== 1'b1 && n < timeout_cycles) begin
            @(posedge clk);
            n = n + 1;
        end

        // --- Результат ---
        $fflush(out_fd);
        $fclose(out_fd);

        if (dut.dbg_is_halted !== 1'b1) begin
            $display("PROGRAM_TEST TIMEOUT after %0d cycles", n);
            $finish(1);
        end else begin
            $display("PROGRAM_TEST OK: %0d cycles, %0d bytes output -> %s",
                     n, out_byte_count, out_file);
            $finish(0);
        end
    end

    // Аварийный таймаут
    initial begin
        #2_000_000_000;
        $display("PROGRAM_TEST HARD TIMEOUT");
        $fclose(out_fd);
        $finish(1);
    end
endmodule
