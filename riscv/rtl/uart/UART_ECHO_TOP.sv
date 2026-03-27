// Minimal UART echo: принимает байт по UART, отправляет его обратно.
// Использует clk_wiz_0 (81.25 MHz), без MIG/DDR.
// LED[0] = heartbeat, LED[1] = locked, LED[2] = rx получен, LED[3] = tx busy

module UART_ECHO_TOP (
    input  wire       sys_clk_i,    // 100 MHz (E3)
    input  wire       uart_rx,      // UART RX (A9)
    output wire       uart_tx,      // UART TX (D10)
    output wire [3:0] led
);

    // ---------------------------------------------------------------
    // Clock: 100 MHz → 81.25 MHz (как в основном проекте)
    // ---------------------------------------------------------------
    wire clk_200, clk_cpu, clk_325, clk_wiz_locked;

    clk_wiz_0 u_clk_wiz (
        .clk_in1  (sys_clk_i),
        .clk_out1 (clk_200),
        .clk_out2 (clk_cpu),
        .clk_out3 (clk_325),
        .locked   (clk_wiz_locked),
        .reset    (1'b0)
    );

    wire reset = ~clk_wiz_locked;

    // ---------------------------------------------------------------
    // UART RX (SIMPLE_UART_RX — надёжный, с 2-FF sync)
    // ---------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_valid;

    SIMPLE_UART_RX #(
        .CLOCK_FREQ(81_250_000),
        .BAUD_RATE (115_200)
    ) u_rx (
        .clk      (clk_cpu),
        .reset    (reset),
        .rx       (uart_rx),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

    // ---------------------------------------------------------------
    // UART TX (I_O_OUTPUT_CONTROLLER)
    // ---------------------------------------------------------------
    localparam BIT_PERIOD = 81_250_000 / 115_200;

    wire       tx_ready;

    reg  [7:0] tx_value;
    reg        tx_trigger;

    I_O_OUTPUT_CONTROLLER #(
        .CLOCK_FREQ(81_250_000),
        .BAUD_RATE (115_200),
        .BIT_PERIOD(BIT_PERIOD)
    ) u_tx (
        .clk                    (clk_cpu),
        .reset                  (reset),
        .io_output_value        (tx_value),
        .io_output_trigger      (tx_trigger),
        .io_output_ready_trigger(tx_ready),
        .RXD                    (uart_tx)
    );

    // ---------------------------------------------------------------
    // Echo FSM: RX → FIFO (маленький) → TX
    // ---------------------------------------------------------------
    // Простой 16-байт кольцевой буфер чтобы не терять байты
    reg [7:0] fifo [0:15];
    reg [3:0] wr_ptr, rd_ptr;
    wire      fifo_empty = (wr_ptr == rd_ptr);

    // Запись в FIFO при rx_valid
    always @(posedge clk_cpu) begin
        if (reset) begin
            wr_ptr <= 0;
        end else if (rx_valid) begin
            fifo[wr_ptr] <= rx_data;
            wr_ptr       <= wr_ptr + 1;
        end
    end

    // Чтение из FIFO → TX
    always @(posedge clk_cpu) begin
        if (reset) begin
            rd_ptr     <= 0;
            tx_trigger <= 0;
            tx_value   <= 0;
        end else begin
            tx_trigger <= 0;
            if (!fifo_empty && tx_ready && !tx_trigger) begin
                tx_value   <= fifo[rd_ptr];
                tx_trigger <= 1;
                rd_ptr     <= rd_ptr + 1;
            end
        end
    end

    // ---------------------------------------------------------------
    // Debug LEDs
    // ---------------------------------------------------------------
    reg [25:0] heartbeat;
    always @(posedge clk_cpu) begin
        if (reset) heartbeat <= 0;
        else       heartbeat <= heartbeat + 1;
    end

    // Счётчик принятых байт для LED[2] — мигает при получении
    reg [23:0] rx_led_cnt;
    always @(posedge clk_cpu) begin
        if (reset)
            rx_led_cnt <= 0;
        else if (rx_valid)
            rx_led_cnt <= 24'hFF_FFFF;  // зажечь ~0.2 сек
        else if (rx_led_cnt != 0)
            rx_led_cnt <= rx_led_cnt - 1;
    end

    assign led[0] = heartbeat[25];      // ~1.2 Hz heartbeat
    assign led[1] = clk_wiz_locked;     // clock OK
    assign led[2] = (rx_led_cnt != 0);  // вспыхивает при приёме
    assign led[3] = ~tx_ready;          // горит когда TX занят

endmodule
