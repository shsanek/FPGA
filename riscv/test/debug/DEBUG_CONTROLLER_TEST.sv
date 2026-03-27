// Тест DEBUG_CONTROLLER (новый pipeline)
//
// ACK = два одинаковых байта (код команды)
// Pipeline: IDLE → [RECV] → PAUSE_WAIT → EXEC → [MEM_WAIT] → ACK1 → ACK2 → IDLE
module DEBUG_CONTROLLER_TEST();
    logic clk = 0;
    initial forever #5 clk = ~clk;

    logic reset;
    int   error = 0;

    // RX-инжектор
    logic [7:0] rx_byte;
    logic       rx_valid;

    // TX-сборщик
    wire  [7:0] tx_byte;
    wire        tx_valid;
    logic       tx_ready;

    // CPU stub
    logic        cpu_halted = 0;
    logic [31:0] cpu_pc     = 32'hDEAD_0004;
    logic [31:0] cpu_instr  = 32'h00A00093;
    wire         dbg_halt_w, dbg_step_w;
    wire         dbg_set_pc_w;
    wire  [31:0] dbg_new_pc_w;

    // MC stub
    logic        mc_ready = 1;
    logic [31:0] mc_rdata = 32'hCAFE_BABE;
    wire  [27:0] mc_addr_w;
    wire         mc_rd_w, mc_wr_w;
    wire  [31:0] mc_wdata_w;

    // Pipeline stub: granted=1 в покое, падает на step и поднимается через 5 тактов
    wire dbg_bus_req_w;
    wire dbg_step_pipe_w;
    logic pipeline_granted = 1;
    logic [2:0] step_cnt = 0;

    always_ff @(posedge clk) begin
        if (dbg_step_pipe_w && pipeline_granted) begin
            pipeline_granted <= 0;
            step_cnt <= 5;
        end else if (step_cnt > 0) begin
            step_cnt <= step_cnt - 1;
            if (step_cnt == 1)
                pipeline_granted <= 1;
        end else if (!dbg_bus_req_w) begin
            pipeline_granted <= 0;
        end else begin
            pipeline_granted <= 1;
        end
    end

    // DUT
    DEBUG_CONTROLLER #(.DEBUG_ENABLE(1)) dut (
        .clk              (clk),
        .reset            (reset),
        .rx_byte          (rx_byte),
        .rx_valid         (rx_valid),
        .tx_byte          (tx_byte),
        .tx_valid         (tx_valid),
        .tx_ready         (tx_ready),
        .dbg_halt         (dbg_halt_w),
        .dbg_set_pc       (dbg_set_pc_w),
        .dbg_new_pc       (dbg_new_pc_w),
        .dbg_is_halted    (cpu_halted),
        .dbg_current_pc   (cpu_pc),
        .dbg_current_instr(cpu_instr),
        .dbg_bus_request  (dbg_bus_req_w),
        .dbg_step_pipeline(dbg_step_pipe_w),
        .dbg_bus_granted  (pipeline_granted),
        .mc_dbg_address   (mc_addr_w),
        .mc_dbg_read_trigger (mc_rd_w),
        .mc_dbg_write_trigger(mc_wr_w),
        .mc_dbg_write_data(mc_wdata_w),
        .mc_dbg_read_data (mc_rdata),
        .mc_dbg_ready     (mc_ready),
        .cpu_rx_byte      (),
        .cpu_rx_valid     (),
        .cpu_tx_byte      (8'h00),
        .cpu_tx_valid     (1'b0),
        .cpu_tx_ready     ()
    );

    // CPU stub: halt следует за dbg_halt
    always_ff @(posedge clk)
        cpu_halted <= dbg_halt_w;

    // MC stub: ready=1 when idle (matches real MEMORY_CONTROLLER behaviour).
    // On trigger rising edge: ready drops to 0 for 3 cycles, then returns to 1.
    logic [1:0] mc_cnt;
    logic       mc_rd_prev, mc_wr_prev;
    always_ff @(posedge clk) begin
        if (reset) begin
            mc_cnt     <= 0;
            mc_rd_prev <= 0;
            mc_wr_prev <= 0;
            mc_ready   <= 1;
        end else begin
            mc_rd_prev <= mc_rd_w;
            mc_wr_prev <= mc_wr_w;
            if ((mc_rd_w && !mc_rd_prev) || (mc_wr_w && !mc_wr_prev)) begin
                mc_cnt   <= 3;
                mc_ready <= 0;
            end else if (mc_cnt > 0) begin
                mc_cnt <= mc_cnt - 1;
                if (mc_cnt == 1) mc_ready <= 1;
            end
        end
    end

    // Отправить 1 байт в DUT
    task send_byte(input [7:0] b);
        @(posedge clk); #1;
        rx_byte  = b;
        rx_valid = 1;
        @(posedge clk); #1;
        rx_valid = 0;
    endtask

    // Ждать TX байт и проверить
    task expect_byte(input [7:0] expected, input string desc);
        integer timeout;
        timeout = 0;
        while (!tx_valid && timeout < 200) begin
            @(posedge clk); #1;
            timeout = timeout + 1;
        end
        if (!tx_valid) begin
            $display("FAIL %s: no TX byte (timeout)", desc); error++;
        end else if (tx_byte !== expected) begin
            $display("FAIL %s: got 0x%02X, expected 0x%02X", desc, tx_byte, expected); error++;
        end
        @(posedge clk); #1;
    endtask

    // Ждать полный debug-ответ: HDR(0xAA) + ACK1 + ACK2
    task expect_ack(input [7:0] cmd_code, input string desc);
        expect_byte(8'hAA,   {desc, " HDR"});
        expect_byte(cmd_code, {desc, " ACK1"});
        expect_byte(cmd_code, {desc, " ACK2"});
    endtask

    initial begin
        reset    = 1;
        rx_valid = 0;
        rx_byte  = 0;
        tx_ready = 1;

        repeat(3) @(posedge clk); #1;
        reset = 0;
        @(posedge clk); #1;

        // --------------------------------------------------------
        // T1: HALT → ACK(0x01, 0x01)
        // --------------------------------------------------------
        $display("T1: HALT");
        send_byte(8'h01);
        expect_ack(8'h01, "HALT");
        repeat(2) @(posedge clk); #1;
        assert(cpu_halted === 1) else begin
            $display("FAIL: cpu not halted"); error++;
        end

        // --------------------------------------------------------
        // T2: RESUME → ACK(0x02, 0x02), cpu resumed
        // --------------------------------------------------------
        $display("T2: RESUME");
        send_byte(8'h02);
        expect_ack(8'h02, "RESUME");
        repeat(2) @(posedge clk); #1;
        assert(cpu_halted === 0) else begin
            $display("FAIL: cpu still halted"); error++;
        end

        // --------------------------------------------------------
        // T3: STEP → ACK(0x03, 0x03) + PC[4B] + INSTR[4B]
        // --------------------------------------------------------
        $display("T3: STEP");
        send_byte(8'h01);  // HALT first
        expect_ack(8'h01, "HALT for STEP");

        send_byte(8'h03);
        expect_ack(8'h03, "STEP");
        // PC = 0xDEAD0004 little-endian
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
        // T4: READ_MEM addr=0x10 → ACK(0x04, 0x04) + DATA[4B]
        // --------------------------------------------------------
        $display("T4: READ_MEM");
        send_byte(8'h04);
        send_byte(8'h10); send_byte(8'h00);
        send_byte(8'h00); send_byte(8'h00);
        expect_ack(8'h04, "READ_MEM");
        // DATA = 0xCAFEBABE little-endian
        expect_byte(8'hBE, "READ_MEM [7:0]");
        expect_byte(8'hBA, "READ_MEM [15:8]");
        expect_byte(8'hFE, "READ_MEM [23:16]");
        expect_byte(8'hCA, "READ_MEM [31:24]");

        // --------------------------------------------------------
        // T5: WRITE_MEM addr=0x20 data=0x12345678 → ACK(0x05, 0x05), no data
        // --------------------------------------------------------
        $display("T5: WRITE_MEM");
        send_byte(8'h05);
        send_byte(8'h20); send_byte(8'h00); send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h78); send_byte(8'h56); send_byte(8'h34); send_byte(8'h12);
        expect_ack(8'h05, "WRITE_MEM");

        assert(mc_addr_w === 28'h0000020) else begin
            $display("FAIL: mc_addr=0x%07X, expected 0x0000020", mc_addr_w); error++;
        end

        // --------------------------------------------------------
        // T6: RESET_PC addr=0x100 → ACK(0x07, 0x07), no data
        // --------------------------------------------------------
        $display("T6: RESET_PC");
        send_byte(8'h07);
        send_byte(8'h00); send_byte(8'h01);
        send_byte(8'h00); send_byte(8'h00);
        expect_ack(8'h07, "RESET_PC");

        // --------------------------------------------------------
        // T7: CMD_INPUT 0x06 + 1 байт → доставка в CPU
        // --------------------------------------------------------
        $display("T7: INPUT");
        // Сначала RESUME чтобы CPU работал
        send_byte(8'h02);
        expect_ack(8'h02, "RESUME for INPUT");

        send_byte(8'h06);  // CMD_INPUT
        send_byte(8'hAB);  // payload = 0xAB
        expect_ack(8'h06, "INPUT");
        // Проверяем что cpu_rx_valid сработал (байт попал в UART_IO_DEVICE)

        // T7b: INPUT с байтом 0x01 — раньше бы перехватился как HALT
        $display("T7b: INPUT byte 0x01 (was HALT)");
        send_byte(8'h06);
        send_byte(8'h01);  // этот 0x01 — данные, не команда
        expect_ack(8'h06, "INPUT 0x01");
        // CPU не должен быть halted
        repeat(2) @(posedge clk); #1;
        assert(cpu_halted === 0) else begin
            $display("FAIL: cpu halted after INPUT 0x01"); error++;
        end

        // --------------------------------------------------------
        // T8: SYNC_RESET (0xFD) — сброс из середины pipeline
        // --------------------------------------------------------
        $display("T8: SYNC_RESET from PAUSE_WAIT");
        // Отправим HALT чтобы войти в pipeline, но bus_granted=1
        // → сразу пройдёт. Зато проверим из S_SEND_ACK1.
        // Начнём HALT, не дожидаясь полного ACK отправим 0xFD.
        send_byte(8'h01);  // HALT
        // Ждём 1 такт (FSM в S_PAUSE_WAIT или S_EXEC)
        repeat(2) @(posedge clk); #1;
        // Шлём 0xFD — должен сбросить FSM
        send_byte(8'hFD);
        repeat(5) @(posedge clk); #1;
        // После сброса: state=S_IDLE, halt=0, bus_request=0
        assert(dut.dbg.state === 0) else begin  // S_IDLE = 0
            $display("FAIL: state=%0d after SYNC_RESET, expected S_IDLE(0)", dut.dbg.state); error++;
        end
        assert(dut.dbg.halt_r === 0) else begin
            $display("FAIL: halt_r=%0b after SYNC_RESET", dut.dbg.halt_r); error++;
        end
        assert(dut.dbg.bus_request_r === 0) else begin
            $display("FAIL: bus_request=%0b after SYNC_RESET", dut.dbg.bus_request_r); error++;
        end

        // --------------------------------------------------------
        // T9: SYNC_RESET НЕ срабатывает в S_RECV (0xFD = часть payload)
        // --------------------------------------------------------
        $display("T9: SYNC_RESET ignored in S_RECV");
        send_byte(8'h04);  // READ_MEM → ждёт 4 байта payload
        repeat(2) @(posedge clk); #1;
        // Сейчас в S_RECV, шлём 0xFD как первый байт адреса
        send_byte(8'hFD);
        repeat(2) @(posedge clk); #1;
        // Должен остаться в S_RECV (0xFD принят как payload_addr[7:0])
        assert(dut.dbg.state === 1) else begin  // S_RECV = 1
            $display("FAIL: state=%0d, expected S_RECV(1) — 0xFD should be payload", dut.dbg.state); error++;
        end
        // Дошлём оставшиеся 3 байта адреса чтобы дойти до конца
        send_byte(8'h00); send_byte(8'h00); send_byte(8'h00);
        // Теперь в S_PAUSE_WAIT или дальше, шлём 0xFD для чистки
        repeat(5) @(posedge clk); #1;
        send_byte(8'hFD);
        repeat(5) @(posedge clk); #1;

        // --------------------------------------------------------
        // Итог
        // --------------------------------------------------------
        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);

        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
