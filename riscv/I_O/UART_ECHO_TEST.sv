// UART loopback echo test.
// OUTPUT_CONTROLLER.RXD → INPUT_CONTROLLER.TXD (провод).
// Отправляем байты, проверяем что INPUT принимает то же самое.

module UART_ECHO_TEST();
    logic       clk;
    logic       reset;
    int         error = 0;

    // --- TX (OUTPUT) сигналы ---
    logic [7:0] tx_value;
    logic       tx_trigger;
    wire        tx_ready;
    wire        uart_wire;   // loopback: TX.RXD → RX.TXD

    // --- RX (INPUT) сигналы ---
    wire        rx_trigger;
    wire  [7:0] rx_value;

    // Маленький BIT_PERIOD для быстрой симуляции
    localparam BIT_PERIOD = 8;

    I_O_OUTPUT_CONTROLLER #(.BIT_PERIOD(BIT_PERIOD)) tx_ctrl (
        .clk(clk),
        .reset(reset),
        .io_output_value(tx_value),
        .io_output_trigger(tx_trigger),
        .io_output_ready_trigger(tx_ready),
        .RXD(uart_wire)
    );

    I_O_INPUT_CONTROLLER #(.BIT_PERIOD(BIT_PERIOD)) rx_ctrl (
        .clk(clk),
        .reset(reset),
        .TXD(uart_wire),
        .io_input_trigger(rx_trigger),
        .io_input_value(rx_value)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Сколько байт принято
    int rx_count = 0;
    logic [7:0] rx_last;
    always @(posedge clk) begin
        if (rx_trigger) begin
            rx_count <= rx_count + 1;
            rx_last  <= rx_value;
            $display("  RX got: 0x%02h (expected by test)", rx_value);
        end
    end

    // Таск: отправить байт и дождаться приёма
    task automatic send_and_check(input [7:0] data);
        int old_count;
        int timeout;
        old_count = rx_count;

        // Ждём TX ready
        while (!tx_ready) @(posedge clk);

        // Отправляем
        @(posedge clk);
        tx_value   = data;
        tx_trigger = 1;
        @(posedge clk);
        tx_trigger = 0;

        // Ждём приёма (таймаут = BIT_PERIOD * 20 тактов)
        timeout = 0;
        while (rx_count == old_count && timeout < BIT_PERIOD * 20) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (rx_count == old_count) begin
            $display("FAIL: timeout waiting for byte 0x%02h", data);
            error = error + 1;
        end else if (rx_last !== data) begin
            $display("FAIL: sent 0x%02h, got 0x%02h", data, rx_last);
            error = error + 1;
        end else begin
            $display("PASS: echo 0x%02h OK", data);
        end
    endtask

    initial begin
        $dumpfile("UART_ECHO_TEST.vcd");
        $dumpvars(0, UART_ECHO_TEST);

        reset      = 1;
        tx_value   = 0;
        tx_trigger = 0;
        #30;
        reset = 0;

        // Ждём стабилизации (INPUT ждёт стоп-бит)
        #(BIT_PERIOD * 10 * 10);

        $display("=== UART Echo Loopback Test ===");

        send_and_check(8'h00);
        #(BIT_PERIOD * 10 * 5);

        send_and_check(8'hFF);
        #(BIT_PERIOD * 10 * 5);

        send_and_check(8'hAA);
        #(BIT_PERIOD * 10 * 5);

        send_and_check(8'h55);
        #(BIT_PERIOD * 10 * 5);

        send_and_check(8'h01);
        #(BIT_PERIOD * 10 * 5);

        send_and_check(8'h80);
        #(BIT_PERIOD * 10 * 5);

        send_and_check(8'h42);
        #(BIT_PERIOD * 10 * 5);

        $display("=== Done: %0d errors ===", error);
        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);
        $finish;
    end
endmodule
