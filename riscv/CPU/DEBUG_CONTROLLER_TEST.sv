// Тест DEBUG_CONTROLLER
//
// Подключаем DEBUG_CONTROLLER к:
//   - stub-CPU (simple registers for dbg_is_halted, dbg_current_pc, dbg_current_instr)
//   - stub-MEMORY (mc_dbg_ready pulses after 2 clocks, returns fixed data)
//
// Байты шлём напрямую (rx_valid/rx_byte), TX проверяем сразу.
// tx_ready держим =1 (TX не занят).
module DEBUG_CONTROLLER_TEST();
    logic clk = 0;
    initial forever #5 clk = ~clk;

    logic reset;
    int   error = 0;

    // ---------------------------------------------------------------
    // RX-инжектор
    // ---------------------------------------------------------------
    logic [7:0] rx_byte;
    logic       rx_valid;

    // TX-сборщик
    wire  [7:0] tx_byte;
    wire        tx_valid;
    logic       tx_ready;

    // CPU stub
    logic        cpu_halted = 0;
    logic [31:0] cpu_pc     = 32'hDEAD_0004;
    logic [31:0] cpu_instr  = 32'h00A00093;  // addi x1, x0, 10
    wire         dbg_halt_w, dbg_step_w;

    // MC stub
    logic        mc_ready = 0;
    logic [31:0] mc_rdata = 32'hCAFE_BABE;
    wire  [27:0] mc_addr_w;
    wire         mc_rd_w, mc_wr_w;

    // ---------------------------------------------------------------
    // DUT
    // ---------------------------------------------------------------
    DEBUG_CONTROLLER #(.DEBUG_ENABLE(1)) dut (
        .clk              (clk),
        .reset            (reset),
        .rx_byte          (rx_byte),
        .rx_valid         (rx_valid),
        .tx_byte          (tx_byte),
        .tx_valid         (tx_valid),
        .tx_ready         (tx_ready),
        .dbg_halt         (dbg_halt_w),
        .dbg_step         (dbg_step_w),
        .dbg_set_pc       (),
        .dbg_new_pc       (),
        .dbg_is_halted    (cpu_halted),
        .dbg_current_pc   (cpu_pc),
        .dbg_current_instr(cpu_instr),
        .mc_dbg_address   (mc_addr_w),
        .mc_dbg_read_trigger (mc_rd_w),
        .mc_dbg_write_trigger(mc_wr_w),
        .dbg_bus_request  (),
        .dbg_bus_granted  (1'b1),
        .mc_dbg_write_data(),
        .mc_dbg_read_data (mc_rdata),
        .mc_dbg_ready     (mc_ready),
        // CPU passthrough — в этом тесте не используется
        .cpu_rx_byte      (),
        .cpu_rx_valid     (),
        .cpu_tx_byte      (8'h00),
        .cpu_tx_valid     (1'b0),
        .cpu_tx_ready     ()
    );

    // CPU stub: встаёт когда dbg_halt выставлен
    always_ff @(posedge clk)
        if (dbg_halt_w)  cpu_halted <= 1;
        else             cpu_halted <= 0;

    // MC stub: готовность через 3 такта после первого фронта запроса
    logic [1:0] mc_cnt;
    logic       mc_rd_prev, mc_wr_prev;
    always_ff @(posedge clk) begin
        if (reset) begin
            mc_cnt     <= 0;
            mc_rd_prev <= 0;
            mc_wr_prev <= 0;
            mc_ready   <= 0;
        end else begin
            mc_ready   <= 0;
            mc_rd_prev <= mc_rd_w;
            mc_wr_prev <= mc_wr_w;
            // Запускаем только по фронту (чтобы не сбрасывать счётчик каждый цикл)
            if ((mc_rd_w && !mc_rd_prev) || (mc_wr_w && !mc_wr_prev)) begin
                mc_cnt <= 3;
            end else if (mc_cnt > 0) begin
                mc_cnt <= mc_cnt - 1;
                if (mc_cnt == 1) mc_ready <= 1;
            end
        end
    end

    // ---------------------------------------------------------------
    // Вспомогательные задачи
    // ---------------------------------------------------------------
    // Отправить 1 байт в DUT
    task send_byte(input [7:0] b);
        @(posedge clk); #1;
        rx_byte  = b;
        rx_valid = 1;
        @(posedge clk); #1;
        rx_valid = 0;
    endtask

    // Ждать следующий TX-байт и проверить значение
    task expect_byte(input [7:0] expected, input string desc);
        integer timeout;
        timeout = 0;
        // Ждём пока tx_valid станет 1
        while (!tx_valid && timeout < 200) begin
            @(posedge clk); #1;
            timeout = timeout + 1;
        end
        if (!tx_valid) begin
            $display("FAIL %s: no TX byte (timeout)", desc); error = error + 1;
        end else if (tx_byte !== expected) begin
            $display("FAIL %s: got 0x%02X, expected 0x%02X", desc, tx_byte, expected); error = error + 1;
        end
        // Продвигаемся ВПЕРЁД чтобы следующий вызов не поймал тот же импульс
        @(posedge clk); #1;
    endtask

    // ---------------------------------------------------------------
    // Тест
    // ---------------------------------------------------------------
    initial begin
        reset    = 1;
        rx_valid = 0;
        rx_byte  = 0;
        tx_ready = 1;

        repeat(3) @(posedge clk); #1;
        reset = 0;
        @(posedge clk); #1;

        // --------------------------------------------------------
        // T1: HALT → 0xFF
        // --------------------------------------------------------
        send_byte(8'h01);  // CMD_HALT
        // CPU stub встаёт после 1 такта с dbg_halt=1
        expect_byte(8'hFF, "HALT response");
        assert(cpu_halted === 1) else begin
            $display("FAIL HALT: cpu_halted=%0b", cpu_halted); error = error + 1;
        end

        // --------------------------------------------------------
        // T2: RESUME → 0xFF
        // --------------------------------------------------------
        send_byte(8'h02);  // CMD_RESUME
        expect_byte(8'hFF, "RESUME response");
        @(posedge clk); #1;
        assert(cpu_halted === 0) else begin
            $display("FAIL RESUME: cpu still halted"); error = error + 1;
        end

        // --------------------------------------------------------
        // T3: HALT снова, потом STEP → PC(4B) + INSTR(4B)
        // --------------------------------------------------------
        send_byte(8'h01);  // HALT
        expect_byte(8'hFF, "HALT2 response");

        send_byte(8'h03);  // CMD_STEP
        // Ожидаем PC = 0xDEAD0004 little-endian
        expect_byte(8'h04, "STEP PC[7:0]");
        expect_byte(8'h00, "STEP PC[15:8]");
        expect_byte(8'hAD, "STEP PC[23:16]");
        expect_byte(8'hDE, "STEP PC[31:24]");
        // INSTR = 0x00A00093 little-endian
        expect_byte(8'h93, "STEP INSTR[7:0]");
        expect_byte(8'h00, "STEP INSTR[15:8]");
        expect_byte(8'hA0, "STEP INSTR[23:16]");
        expect_byte(8'h00, "STEP INSTR[31:24]");

        // --------------------------------------------------------
        // T4: READ_MEM addr=0x0000_0010 → 0xCAFEBABE
        // --------------------------------------------------------
        send_byte(8'h04);              // CMD_READ_MEM
        send_byte(8'h10); send_byte(8'h00);  // addr little-endian
        send_byte(8'h00); send_byte(8'h00);
        // ждём mc_ready (stub: 3 такта после trigger)
        expect_byte(8'hBE, "READ_MEM [7:0]");
        expect_byte(8'hBA, "READ_MEM [15:8]");
        expect_byte(8'hFE, "READ_MEM [23:16]");
        expect_byte(8'hCA, "READ_MEM [31:24]");

        // --------------------------------------------------------
        // T5: WRITE_MEM addr=0x0000_0020, data=0x12345678 → 0xFF
        // --------------------------------------------------------
        send_byte(8'h05);              // CMD_WRITE_MEM
        send_byte(8'h20); send_byte(8'h00); send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h78); send_byte(8'h56); send_byte(8'h34); send_byte(8'h12);
        expect_byte(8'hFF, "WRITE_MEM response");

        // --------------------------------------------------------
        // Итог
        // --------------------------------------------------------
        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);

        $finish;
    end

    // Аварийный таймаут
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
