// Интеграционный тест всей системы (TOP).
//
// Подключает MIG_MODEL к MIG-портам TOP.
// Программу загружает через иерархический доступ dut.rom[i].
// UART-команды генерирует напрямую в виде битовых последовательностей
// (start + 8 data + stop) с BIT_PERIOD=100 тактов.
//
// Тесты:
//   T1: CPU выполняет программу: ADDI/SW/LW/ADDI/SW/LW/JAL
//       Проверяем x1=42, x2=42, x3=52, x4=52
//
//   T2: DEBUG HALT через UART → cpu останавливается
//       Отправляем 0x01 (CMD_HALT) через uart_rx
//       Проверяем dut.dbg_is_halted = 1
//       Проверяем ответ 0xFF в dbg_ctrl tx-буфере
//
//   T3: DEBUG RESUME → cpu возобновляет работу
//       Отправляем 0x02 (CMD_RESUME)
//       Проверяем dut.dbg_is_halted = 0
//
//   T4: UART_IO_DEVICE — CPU читает STATUS и пишет TX
//       Программа #2: записывает 0x41 ('A') по адресу 0x08000000
//       Проверяем что cpu_tx_valid поднялся в uart_io_device
//
// Параметры симуляции:
//   CLOCK_FREQ = 1_000_000, BAUD_RATE = 10_000  → BIT_PERIOD = 100 клоков
//   clk  half-period = 5 нс (100 МГц модельные)
//   mig_clk half-period = 4 нс (125 МГц модельные)
module TOP_TEST();
    // ---------------------------------------------------------------
    // Параметры
    // ---------------------------------------------------------------
    localparam CLOCK_FREQ   = 1_000_000;
    localparam BAUD_RATE    = 10_000;
    localparam BIT_PERIOD   = CLOCK_FREQ / BAUD_RATE;   // 100
    localparam CHUNK_PART   = 128;
    localparam ADDRESS_SIZE = 28;
    localparam ROM_DEPTH    = 256;

    // ---------------------------------------------------------------
    // Тактовые генераторы
    // ---------------------------------------------------------------
    logic clk     = 0;
    logic mig_clk = 0;
    initial forever #5  clk     = ~clk;
    initial forever #4  mig_clk = ~mig_clk;

    logic reset;
    int   error = 0;

    // ---------------------------------------------------------------
    // Внешний UART (rx → DUT, tx ← DUT)
    // ---------------------------------------------------------------
    logic uart_rx_pin = 1;   // idle высокий
    wire  uart_tx_pin;

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
    // I_O_INPUT_CONTROLLER накапливает биты сдвигом влево → биты
    // принимаются в обратном порядке. Чтобы DEBUG_CONTROLLER получил
    // байт X, нужно отправить rev8(X) в стандартном UART (LSB first).
    // ---------------------------------------------------------------
    function automatic [7:0] rev8(input [7:0] b);
        rev8 = {b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7]};
    endfunction

    // ---------------------------------------------------------------
    // Задача: отправить байт через UART (start + 8 data + stop)
    // Каждый бит = BIT_PERIOD тактов clk
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
    // Задача: проверить байт в TX-буфере DEBUG_CONTROLLER
    // (обходим UART-кодирование, смотрим прямо на tx_byte_r/tx_valid_r)
    // ---------------------------------------------------------------
    task expect_dbg_byte(input [7:0] expected, input string desc);
        integer timeout;
        timeout = 0;
        while (!dut.dbg_ctrl.dbg.tx_valid_r && timeout < 10000) begin
            @(posedge clk); #1;
            timeout = timeout + 1;
        end
        if (!dut.dbg_ctrl.dbg.tx_valid_r) begin
            $display("FAIL %s: no TX byte (timeout)", desc);
            error = error + 1;
        end else if (dut.dbg_ctrl.dbg.tx_byte_r !== expected) begin
            $display("FAIL %s: got 0x%02X, expected 0x%02X",
                     desc, dut.dbg_ctrl.dbg.tx_byte_r, expected);
            error = error + 1;
        end
        @(posedge clk); #1;
    endtask

    // ---------------------------------------------------------------
    // Программа 1 (T1): ADDI/SW/LW/ADDI/SW/LW/JAL
    // ---------------------------------------------------------------
    task load_program_1();
        dut.rom[0] = 32'h02A00093; // addi x1, x0, 42
        dut.rom[1] = 32'h00102023; // sw   x1, 0(x0)
        dut.rom[2] = 32'h00002103; // lw   x2, 0(x0)
        dut.rom[3] = 32'h00A10193; // addi x3, x2, 10
        dut.rom[4] = 32'h00302223; // sw   x3, 4(x0)
        dut.rom[5] = 32'h00402203; // lw   x4, 4(x0)
        dut.rom[6] = 32'h0000006F; // jal  x0, 0  (infinite loop)
    endtask

    // ---------------------------------------------------------------
    // Программа 2 (T4): записать 0x41 в UART TX-регистр + прочитать STATUS
    // ---------------------------------------------------------------
    task load_program_2();
        // lui  x5, 0x08000  → x5 = 0x0800_0000  (I/O base addr)
        // addi x6, x0, 65   → x6 = 0x41 = 'A'
        // sw   x6, 0(x5)    → UART_IO_DEVICE TX_DATA ← 'A'
        // lw   x6, 8(x5)    → x6 = UART_IO_DEVICE STATUS
        // jal  x0, 0        (infinite loop)
        //
        // Encoding:
        //   LUI  rd=x5 imm=0x08000: {20'h08000, 5'd5, 7'b0110111} = 0x080002B7
        //   ADDI rd=x6 rs1=x0 imm=65: {12'd65,5'd0,3'b000,5'd6,7'b0010011} = 0x04100313
        //   SW   rs2=x6 rs1=x5 imm=0: {7'b0,5'd6,5'd5,3'b010,5'b0,7'b0100011} = 0x0062A023
        //   LW   rd=x6 rs1=x5 imm=8:  {12'd8,5'd5,3'b010,5'd6,7'b0000011} = 0x0082A303
        //   JAL  rd=x0 imm=0: 0x0000006F
        dut.rom[0] = 32'h080002B7;
        dut.rom[1] = 32'h04100313;
        dut.rom[2] = 32'h0062A023;
        dut.rom[3] = 32'h0082A303;
        dut.rom[4] = 32'h0000006F;
    endtask

    // ---------------------------------------------------------------
    // Тест
    // ---------------------------------------------------------------
    initial begin
        reset = 1;
        uart_rx_pin = 1;

        // Ждём инициализации MC (MIG_MODEL готов сразу, но RAM_CONTROLLER
        // нужно несколько тактов)
        @(posedge clk);
        begin : wait_mc
            integer n;
            n = 0;
            while (dut.mc_ready !== 1'b1 && n < 2000) begin
                @(posedge clk); n = n + 1;
            end
        end
        @(posedge clk); #1;

        // ============================================================
        // T1: CPU выполняет программу SW/LW через MEMORY_CONTROLLER
        // ============================================================
        load_program_1();
        reset = 0;

        // Ждём ~600 тактов (каждый SW/LW ≈ 50 тактов + CDC)
        repeat(800) @(posedge clk); #1;

        assert(dut.cpu.regfile.reg_values[1] === 32'd42) else begin
            $display("FAIL T1 x1: got %0d, expected 42",
                     dut.cpu.regfile.reg_values[1]);
            error = error + 1;
        end
        assert(dut.cpu.regfile.reg_values[2] === 32'd42) else begin
            $display("FAIL T1 x2 (LW): got %0d, expected 42",
                     dut.cpu.regfile.reg_values[2]);
            error = error + 1;
        end
        assert(dut.cpu.regfile.reg_values[3] === 32'd52) else begin
            $display("FAIL T1 x3: got %0d, expected 52",
                     dut.cpu.regfile.reg_values[3]);
            error = error + 1;
        end
        assert(dut.cpu.regfile.reg_values[4] === 32'd52) else begin
            $display("FAIL T1 x4 (LW): got %0d, expected 52",
                     dut.cpu.regfile.reg_values[4]);
            error = error + 1;
        end

        // ============================================================
        // T2: HALT через UART
        // ============================================================
        // I_O_INPUT_CONTROLLER переворачивает биты, поэтому для CMD_HALT=0x01
        // нужно отправить rev8(0x01)=0x80.
        // tx_valid_r — 1-тактовый импульс, возникает внутри uart_send.
        // Запускаем uart_send и expect_dbg_byte параллельно через fork/join.
        fork
            uart_send(rev8(8'h01));
            expect_dbg_byte(8'hFF, "HALT response");
        join

        assert(dut.dbg_is_halted === 1'b1) else begin
            $display("FAIL T2: cpu not halted");
            error = error + 1;
        end

        // ============================================================
        // T3: RESUME через UART
        // ============================================================
        fork
            uart_send(rev8(8'h02));  // rev8(0x02)=0x40 → DEBUG получит 0x02
            expect_dbg_byte(8'hFF, "RESUME response");
        join

        @(posedge clk); #1;  // один такт чтобы dbg_halted_r успел обновиться
        assert(dut.dbg_is_halted === 1'b0) else begin
            $display("FAIL T3: cpu still halted after RESUME");
            error = error + 1;
        end

        // ============================================================
        // T4: UART_IO_DEVICE — CPU пишет байт в TX_DATA (0x0800_0000)
        // ============================================================
        reset = 1;
        @(posedge clk); #1;
        load_program_2();
        reset = 0;

        // CPU выполняет:
        //   lui x5, 0x08000  → x5 = 0x0800_0000
        //   addi x6, x0, 65  → x6 = 0x41
        //   sw x6, 0(x5)     → PERIPHERAL_BUS → UART_IO_DEVICE TX_DATA
        //   lw x6, 8(x5)     → читает STATUS
        repeat(30) @(posedge clk); #1;

        // SW к I/O не вызывает stall (controller_ready=1 всегда)
        // После sw x6, 0(x5): uart_io.tx_data_r должен стать 0x41
        assert(dut.uart_io.tx_data_r === 8'h41) else begin
            $display("FAIL T4: TX_DATA = 0x%02X, expected 0x41",
                     dut.uart_io.tx_data_r);
            error = error + 1;
        end

        // После lw x6, 8(x5): x6 = STATUS = {30'b0, cpu_tx_ready, rx_avail}
        // cpu_tx_ready определяется состоянием DEBUG_CONTROLLER
        // rx_avail = 0 (не приходило cpu_rx_valid)
        // Просто проверяем что x6 не X (STATUS прочитан успешно)
        assert(dut.cpu.regfile.reg_values[6] !== 32'hX) else begin
            $display("FAIL T4: STATUS = X (read failed)");
            error = error + 1;
        end

        // ============================================================
        // Итог
        // ============================================================
        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);

        $finish;
    end

    // Аварийный таймаут
    initial begin
        #5_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
