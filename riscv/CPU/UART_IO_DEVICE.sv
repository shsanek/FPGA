// Устройство ввода-вывода: UART через DEBUG_CONTROLLER passthrough.
//
// Адресное пространство (биты [3:2] адреса):
//   offset 0x00  TX_DATA  (W) — запись байта для отправки через UART
//                         (R) — последний отправленный байт
//   offset 0x04  RX_DATA  (R) — принятый байт (сбрасывается после чтения)
//   offset 0x08  STATUS   (R) — {30'b0, tx_ready, rx_available}
//
// Запись в TX_DATA блокирует bus (controller_ready=0) до тех пор,
// пока байт не будет принят DEBUG_CONTROLLER'ом и отправлен в TX FIFO.
// CPU pipeline автоматически ждёт в S_DATA_WAIT.
module UART_IO_DEVICE (
    input  wire        clk,
    input  wire        reset,

    // Bus interface (от PERIPHERAL_BUS)
    input  wire [27:0] address,
    input  wire        read_trigger,
    input  wire        write_trigger,
    input  wire [31:0] write_value,
    input  wire [3:0]  mask,
    output wire [31:0] read_value,
    output wire        controller_ready,

    // Passthrough к DEBUG_CONTROLLER
    output wire [7:0]  cpu_tx_byte,
    output wire        cpu_tx_valid,
    input  wire        cpu_tx_ready,

    input  wire [7:0]  cpu_rx_byte,
    input  wire        cpu_rx_valid
);
    // ---------------------------------------------------------------
    // Регистры
    // ---------------------------------------------------------------
    logic [7:0] tx_data_r;
    logic [7:0] rx_data_r;
    logic       rx_avail_r;

    // TX handshake FSM
    typedef enum logic [1:0] {
        TX_IDLE,
        TX_WAIT_ACCEPT,  // ждём cpu_tx_ready=1 (DEBUG заберёт байт)
        TX_WAIT_DONE     // ждём пока DEBUG вернётся в IDLE (cpu_tx_ready=1 снова)
    } tx_state_t;
    tx_state_t tx_state;

    // Выбор регистра
    wire [1:0] reg_sel = address[3:2];
    localparam REG_TX     = 2'd0;
    localparam REG_RX     = 2'd1;
    localparam REG_STATUS = 2'd2;

    // ---------------------------------------------------------------
    // Комбинационное чтение
    // ---------------------------------------------------------------
    reg [31:0] rdata;
    always_comb begin
        case (reg_sel)
            REG_TX:     rdata = {24'b0, tx_data_r};
            REG_RX:     rdata = {24'b0, rx_data_r};
            REG_STATUS: rdata = {30'b0, cpu_tx_ready, rx_avail_r};
            default:    rdata = 32'b0;
        endcase
    end
    assign read_value = rdata;

    // ---------------------------------------------------------------
    // controller_ready: bus свободен когда TX не в процессе отправки
    // ---------------------------------------------------------------
    assign controller_ready = (tx_state == TX_IDLE);

    // ---------------------------------------------------------------
    // TX: удерживаем cpu_tx_valid пока DEBUG не заберёт
    // ---------------------------------------------------------------
    assign cpu_tx_byte  = tx_data_r;
    assign cpu_tx_valid = (tx_state == TX_WAIT_ACCEPT);

    // ---------------------------------------------------------------
    // Последовательная логика
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            tx_data_r  <= 8'h00;
            rx_data_r  <= 8'h00;
            rx_avail_r <= 1'b0;
            tx_state   <= TX_IDLE;
        end else begin

            // --- TX FSM ---
            case (tx_state)
                TX_IDLE: begin
                    if (write_trigger && reg_sel == REG_TX) begin
                        tx_data_r <= write_value[7:0];
                        tx_state  <= TX_WAIT_ACCEPT;
                    end
                end

                TX_WAIT_ACCEPT: begin
                    // cpu_tx_valid=1 удерживается (комбинационно)
                    // Когда DEBUG в S_IDLE и tx_ready → cpu_tx_ready=1
                    // DEBUG заберёт байт и уйдёт в S_CPU_TX
                    if (cpu_tx_ready) begin
                        // DEBUG принял — теперь он в S_CPU_TX (cpu_tx_ready упадёт)
                        tx_state <= TX_WAIT_DONE;
                    end
                end

                TX_WAIT_DONE: begin
                    // Ждём пока DEBUG вернётся в S_IDLE и TX FIFO не полон
                    // (cpu_tx_ready снова станет 1)
                    if (cpu_tx_ready) begin
                        tx_state <= TX_IDLE;
                    end
                end
            endcase

            // --- RX ---
            if (cpu_rx_valid) begin
                rx_data_r  <= cpu_rx_byte;
                rx_avail_r <= 1'b1;
            end

            if (read_trigger && reg_sel == REG_RX)
                rx_avail_r <= 1'b0;
        end
    end

endmodule
