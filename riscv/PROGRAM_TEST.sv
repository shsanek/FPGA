// Универсальный тестбенч: загружает скомпилированную RV32I программу,
// запускает её на полной системе (TOP), захватывает UART-вывод.
//
// Plusargs:
//   +HEX_FILE=<path>   — hex-файл программы ($readmemh формат, 32-bit words)
//   +OUT_FILE=<path>   — куда писать захваченный UART-вывод (по умолч. /tmp/prog_out.txt)
//   +TIMEOUT=<cycles>  — максимум тактов (по умолч. 5_000_000)
//
// Программа завершается инструкцией EBREAK (_exit() в runtime.c),
// которая выставляет dbg_is_halted=1 → тестбенч заканчивает симуляцию.
//
// Параметры TOP:
//   ROM_DEPTH = 4096  (16 KB — достаточно для большинства простых программ)
//   CLOCK_FREQ, BAUD_RATE — из параметров модуля
module PROGRAM_TEST ();
    localparam CLOCK_FREQ   = 1_000_000;
    localparam BAUD_RATE    = 10_000;
    localparam CHUNK_PART   = 128;
    localparam ADDRESS_SIZE = 28;
    localparam ROM_DEPTH    = 4096;   // 16 KB instruction ROM

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
    // DUT: TOP
    // ---------------------------------------------------------------
    logic uart_rx_pin = 1;
    wire  uart_tx_pin;

    TOP #(
        .CLOCK_FREQ  (CLOCK_FREQ),
        .BAUD_RATE   (BAUD_RATE),
        .CHUNK_PART  (CHUNK_PART),
        .ADDRESS_SIZE(ADDRESS_SIZE),
        .ROM_DEPTH   (ROM_DEPTH),
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

    // ---------------------------------------------------------------
    // MIG_MODEL
    // ---------------------------------------------------------------
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
    // Захват UART TX-байтов из UART_IO_DEVICE
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

    // cpu_tx_valid — 1-тактовый импульс в UART_IO_DEVICE при записи в TX_DATA
    always @(posedge clk) begin
        if (dut.cpu_tx_valid) begin
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
        integer n;

        // --- Аргументы ---
        if (!$value$plusargs("HEX_FILE=%s", hex_file)) begin
            $display("ERROR: +HEX_FILE=<path> not specified");
            $fclose(out_fd);
            $finish;
        end
        if (!$value$plusargs("TIMEOUT=%d", timeout_cycles))
            timeout_cycles = 5_000_000;

        // --- Ждём готовности MC (MIG_MODEL калибруется быстро) ---
        @(posedge clk);
        n = 0;
        while (dut.mc_ready !== 1'b1 && n < 2000) begin
            @(posedge clk); n = n + 1;
        end
        if (dut.mc_ready !== 1'b1) begin
            $display("ERROR: MEMORY_CONTROLLER not ready after reset");
            $fclose(out_fd);
            $finish;
        end

        // --- Загружаем программу в ROM (instruction fetch) ---
        $readmemh(hex_file, dut.rom);

        // --- Также пре-инициализируем MIG_MODEL для data-доступа к .text/.rodata ---
        // CPU использует Harvard-like архитектуру: инструкции из ROM, данные через MC.
        // Строки (.rodata) и константы (.text) читаются через data port (MEMORY_CONTROLLER).
        // Загружаем те же слова в MIG_MODEL чтобы data reads возвращали правильные байты.
        // MIG_MODEL.mem индексируется по addr[IDX_BITS+3:4]; ROM занимает адреса 0..ROM_DEPTH*4.
        // Каждая 16-байтная строка кэша соответствует 4 ROM-словам.
        begin : preload_mig
            integer w, chunk;
            logic [127:0] chunk_data;
            for (chunk = 0; chunk < ROM_DEPTH / 4; chunk++) begin
                chunk_data = {dut.rom[chunk*4+3],
                              dut.rom[chunk*4+2],
                              dut.rom[chunk*4+1],
                              dut.rom[chunk*4+0]};
                mig.mem[chunk] = chunk_data;
            end
        end
        @(posedge clk); #1;

        // --- Запуск CPU ---
        reset = 0;

        // --- Ждём EBREAK (завершение программы) или timeout ---
        n = 0;
        while (dut.dbg_is_halted !== 1'b1 && n < timeout_cycles) begin
            @(posedge clk);
            n = n + 1;
        end

        // --- Закрываем выходной файл ---
        $fflush(out_fd);
        $fclose(out_fd);

        if (dut.dbg_is_halted !== 1'b1) begin
            $display("PROGRAM_TEST TIMEOUT after %0d cycles", n);
            $finish(1);
        end else begin
            $display("PROGRAM_TEST OK: %0d cycles, %0d bytes output → %s",
                     n, out_byte_count, out_file);
            $finish(0);
        end
    end

    // Аварийный аппаратный таймаут
    initial begin
        #500_000_000;
        $display("PROGRAM_TEST HARD TIMEOUT");
        $fclose(out_fd);
        $finish(1);
    end
endmodule
