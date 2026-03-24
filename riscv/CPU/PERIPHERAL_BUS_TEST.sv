// Тест PERIPHERAL_BUS + UART_IO_DEVICE
//
// Симулируем CPU_DATA_ADAPTER: выдаём address/read_trigger/write_trigger напрямую.
// MC-сторона подключена к стабу (controller_ready=1 всегда, read_value=0xDEAD_CAFE).
// DEBUG_CONTROLLER не нужен — просто проверяем сигналы cpu_tx_byte/cpu_tx_valid
// и кормим cpu_rx_byte/cpu_rx_valid снаружи.
//
// Тесты:
//   T1: WRITE TX  — CPU пишет 0x41 в TX (0x08000000), проверяем cpu_tx_valid=1
//   T2: READ STATUS — tx_ready=1, rx_avail=0 → 0x00000002
//   T3: RX от DEBUG — инжектируем cpu_rx_valid, читаем STATUS (rx_avail=1)
//   T4: READ RX_DATA — 0x08000004 → принятый байт
//   T5: WRITE к MC — адрес 0x00000100 (bit27=0) → идёт в MC, не в I/O
//   T6: READ от MC  — mc_read_value = 0xDEAD_CAFE
module PERIPHERAL_BUS_TEST();
    logic clk = 0;
    initial forever #5 clk = ~clk;

    logic reset;
    int   error = 0;

    // ---------------------------------------------------------------
    // Сигналы между "адаптером" и PERIPHERAL_BUS
    // ---------------------------------------------------------------
    logic [27:0] addr;
    logic        rd_trig, wr_trig;
    logic [31:0] wdata;
    logic [3:0]  wmask;
    wire  [31:0] rdata;
    wire         bus_ready;

    // ---------------------------------------------------------------
    // MC-стаб
    // ---------------------------------------------------------------
    wire  [27:0] mc_addr_w;
    wire         mc_rd_w, mc_wr_w;
    wire  [31:0] mc_wdata_w;
    wire  [3:0]  mc_mask_w;
    logic [31:0] mc_rdata    = 32'hDEAD_CAFE;
    logic        mc_ready    = 1;   // MC всегда готов

    // ---------------------------------------------------------------
    // UART_IO_DEVICE сигналы
    // ---------------------------------------------------------------
    wire  [7:0]  cpu_tx_byte;
    wire         cpu_tx_valid;
    logic        cpu_tx_ready = 1;  // DEBUG готов принять
    logic [7:0]  cpu_rx_byte  = 0;
    logic        cpu_rx_valid = 0;

    // I/O side wires to PERIPHERAL_BUS
    wire  [27:0] io_addr_w;
    wire         io_rd_w, io_wr_w;
    wire  [31:0] io_wdata_w;
    wire  [3:0]  io_mask_w;
    wire  [31:0] io_rdata_w;
    wire         io_ready_w;

    // ---------------------------------------------------------------
    // DUT: PERIPHERAL_BUS
    // ---------------------------------------------------------------
    PERIPHERAL_BUS bus (
        .address          (addr),
        .read_trigger     (rd_trig),
        .write_trigger    (wr_trig),
        .write_value      (wdata),
        .mask             (wmask),
        .read_value       (rdata),
        .controller_ready (bus_ready),

        .mc_address       (mc_addr_w),
        .mc_read_trigger  (mc_rd_w),
        .mc_write_trigger (mc_wr_w),
        .mc_write_value   (mc_wdata_w),
        .mc_mask          (mc_mask_w),
        .mc_read_value    (mc_rdata),
        .mc_controller_ready(mc_ready),

        .io_address       (io_addr_w),
        .io_read_trigger  (io_rd_w),
        .io_write_trigger (io_wr_w),
        .io_write_value   (io_wdata_w),
        .io_mask          (io_mask_w),
        .io_read_value    (io_rdata_w),
        .io_controller_ready(io_ready_w)
    );

    // ---------------------------------------------------------------
    // DUT: UART_IO_DEVICE
    // ---------------------------------------------------------------
    UART_IO_DEVICE io_dev (
        .clk             (clk),
        .reset           (reset),
        .address         (io_addr_w),
        .read_trigger    (io_rd_w),
        .write_trigger   (io_wr_w),
        .write_value     (io_wdata_w),
        .mask            (io_mask_w),
        .read_value      (io_rdata_w),
        .controller_ready(io_ready_w),

        .cpu_tx_byte     (cpu_tx_byte),
        .cpu_tx_valid    (cpu_tx_valid),
        .cpu_tx_ready    (cpu_tx_ready),
        .cpu_rx_byte     (cpu_rx_byte),
        .cpu_rx_valid    (cpu_rx_valid)
    );

    // ---------------------------------------------------------------
    // Вспомогательные задачи
    // ---------------------------------------------------------------
    // Эмуляция одного такта S_TRIG адаптера
    task bus_write(input [27:0] a, input [31:0] d, input [3:0] m);
        @(posedge clk); #1;
        addr    = a;
        wdata   = d;
        wmask   = m;
        wr_trig = 1;
        rd_trig = 0;
        @(posedge clk); #1;
        wr_trig = 0;
    endtask

    task bus_read(input [27:0] a, output [31:0] d);
        @(posedge clk); #1;
        addr    = a;
        rd_trig = 1;
        wr_trig = 0;
        @(posedge clk); #1;
        d = rdata;
        rd_trig = 0;
    endtask

    // ---------------------------------------------------------------
    // Тест
    // ---------------------------------------------------------------
    logic [31:0] read_result;

    initial begin
        reset   = 1;
        rd_trig = 0;
        wr_trig = 0;
        addr    = 0;
        wdata   = 0;
        wmask   = 4'hF;
        repeat(3) @(posedge clk); #1;
        reset = 0;
        @(posedge clk); #1;

        // -------------------------------------------------------
        // T1: WRITE TX (addr = 0x0800_0000 → bit27=1, reg_sel=0)
        // -------------------------------------------------------
        bus_write(28'h8000000, 32'h00000041, 4'hF);  // 'A'
        // cpu_tx_valid должен был быть 1 в такте write_trigger
        // Проверяем что cpu_tx_byte = 0x41 (зафиксировано в tx_data_r)
        if (io_dev.tx_data_r !== 8'h41) begin
            $display("FAIL T1: tx_data_r = 0x%02X, expected 0x41", io_dev.tx_data_r);
            error = error + 1;
        end

        // -------------------------------------------------------
        // T2: READ STATUS (addr = 0x0800_0008 → reg_sel=2)
        // tx_ready=1, rx_avail=0 → expected 0x00000002
        // -------------------------------------------------------
        bus_read(28'h8000008, read_result);
        if (read_result !== 32'h0000_0002) begin
            $display("FAIL T2: STATUS = 0x%08X, expected 0x00000002", read_result);
            error = error + 1;
        end

        // -------------------------------------------------------
        // T3: Инжектируем RX-байт от DEBUG_CONTROLLER (cpu_rx_valid)
        // -------------------------------------------------------
        @(posedge clk); #1;
        cpu_rx_byte  = 8'hBB;
        cpu_rx_valid = 1;
        @(posedge clk); #1;
        cpu_rx_valid = 0;

        // Читаем STATUS: rx_avail=1, tx_ready=1 → 0x00000003
        bus_read(28'h8000008, read_result);
        if (read_result !== 32'h0000_0003) begin
            $display("FAIL T3: STATUS after RX = 0x%08X, expected 0x00000003", read_result);
            error = error + 1;
        end

        // -------------------------------------------------------
        // T4: READ RX_DATA (addr = 0x0800_0004 → reg_sel=1)
        // -------------------------------------------------------
        bus_read(28'h8000004, read_result);
        if (read_result[7:0] !== 8'hBB) begin
            $display("FAIL T4: RX_DATA = 0x%02X, expected 0xBB", read_result[7:0]);
            error = error + 1;
        end
        // После чтения rx_avail должен сброситься
        @(posedge clk); #1;  // дать время FF обработать
        if (io_dev.rx_avail_r !== 0) begin
            $display("FAIL T4: rx_avail_r не сброшен после чтения");
            error = error + 1;
        end

        // -------------------------------------------------------
        // T5: WRITE к MC-адресу (bit27=0) — должен идти в MC, не в I/O
        // -------------------------------------------------------
        bus_write(28'h0000100, 32'h12345678, 4'hF);
        // Проверяем что mc_wr_w был 1 в тот такт и io_wr_w был 0
        // Косвенно: tx_data_r не изменился (остался 0x41)
        if (io_dev.tx_data_r !== 8'h41) begin
            $display("FAIL T5: MC write leaked to I/O, tx_data_r = 0x%02X", io_dev.tx_data_r);
            error = error + 1;
        end

        // -------------------------------------------------------
        // T6: READ от MC-адреса
        // -------------------------------------------------------
        bus_read(28'h0000100, read_result);
        if (read_result !== 32'hDEAD_CAFE) begin
            $display("FAIL T6: MC read_value = 0x%08X, expected 0xDEADCAFE", read_result);
            error = error + 1;
        end

        // -------------------------------------------------------
        // Итог
        // -------------------------------------------------------
        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);

        $finish;
    end

    initial begin
        #10000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
