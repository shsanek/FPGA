// Устройство ввода-вывода: UART через DEBUG_CONTROLLER passthrough.
//
// Адресное пространство (биты [3:2] адреса):
//   offset 0x00  TX_DATA  (W) — запись байта для отправки через UART
//                         (R) — последний отправленный байт
//   offset 0x04  RX_DATA  (R) — головной байт из RX буфера (pop через 1 такт)
//   offset 0x08  STATUS   (R) — {30'b0, tx_ready, rx_available}
//
// RX буферизирован кольцевым буфером на RX_DEPTH байт (по умолчанию 8).
// Чтение RX_DATA возвращает голову буфера; извлечение (pop) происходит
// через 1 такт, чтобы pipeline успел захватить данные в S_DATA_WAIT.
// При переполнении новый байт отбрасывается.
//
// Запись в TX_DATA блокирует bus (controller_ready=0) до тех пор,
// пока байт не будет принят DEBUG_CONTROLLER'ом и отправлен в TX FIFO.
module UART_IO_DEVICE #(
    parameter RX_DEPTH = 8   // глубина RX буфера (степень двойки)
)(
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
    // Регистры TX
    // ---------------------------------------------------------------
    logic [7:0] tx_data_r;

    typedef enum logic [1:0] {
        TX_IDLE,
        TX_WAIT_ACCEPT,
        TX_WAIT_DONE
    } tx_state_t;
    tx_state_t tx_state;

    // Выбор регистра
    wire [1:0] reg_sel = address[3:2];
    localparam REG_TX     = 2'd0;
    localparam REG_RX     = 2'd1;
    localparam REG_STATUS = 2'd2;

    // ---------------------------------------------------------------
    // RX кольцевой буфер
    // ---------------------------------------------------------------
    localparam RX_ADDR_BITS = $clog2(RX_DEPTH);

    logic [7:0] rx_buf [0:RX_DEPTH-1];
    logic [RX_ADDR_BITS:0] rx_wr_ptr;
    logic [RX_ADDR_BITS:0] rx_rd_ptr;

    wire rx_empty = (rx_wr_ptr == rx_rd_ptr);
    wire rx_full  = (rx_wr_ptr[RX_ADDR_BITS] != rx_rd_ptr[RX_ADDR_BITS]) &&
                    (rx_wr_ptr[RX_ADDR_BITS-1:0] == rx_rd_ptr[RX_ADDR_BITS-1:0]);

    wire [7:0] rx_head = rx_buf[rx_rd_ptr[RX_ADDR_BITS-1:0]];

    // Pop отложен на 1 такт: read_trigger → rx_pop_pending → rx_rd_ptr++
    // Это гарантирует что pipeline захватит данные в S_DATA_WAIT
    // до того как указатель сдвинется.
    logic rx_pop_pending;

    // ---------------------------------------------------------------
    // Комбинационное чтение
    // ---------------------------------------------------------------
    reg [31:0] rdata;
    always_comb begin
        case (reg_sel)
            REG_TX:     rdata = {24'b0, tx_data_r};
            REG_RX:     rdata = {24'b0, rx_head};
            REG_STATUS: rdata = {30'b0, cpu_tx_ready, !rx_empty};
            default:    rdata = 32'b0;
        endcase
    end
    assign read_value = rdata;

    // ---------------------------------------------------------------
    // controller_ready
    // ---------------------------------------------------------------
    assign controller_ready = (tx_state == TX_IDLE);

    // ---------------------------------------------------------------
    // TX
    // ---------------------------------------------------------------
    assign cpu_tx_byte  = tx_data_r;
    assign cpu_tx_valid = (tx_state == TX_WAIT_ACCEPT);

    // ---------------------------------------------------------------
    // Последовательная логика
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            tx_data_r      <= 8'h00;
            tx_state       <= TX_IDLE;
            rx_wr_ptr      <= '0;
            rx_rd_ptr      <= '0;
            rx_pop_pending <= 1'b0;
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
                    if (cpu_tx_ready)
                        tx_state <= TX_WAIT_DONE;
                end
                TX_WAIT_DONE: begin
                    if (cpu_tx_ready)
                        tx_state <= TX_IDLE;
                end
            endcase

            // --- RX push ---
            if (cpu_rx_valid && !rx_full) begin
                rx_buf[rx_wr_ptr[RX_ADDR_BITS-1:0]] <= cpu_rx_byte;
                rx_wr_ptr <= rx_wr_ptr + 1;
            end

            // --- RX pop (отложенный на 1 такт) ---
            rx_pop_pending <= read_trigger && (reg_sel == REG_RX) && !rx_empty;
            if (rx_pop_pending)
                rx_rd_ptr <= rx_rd_ptr + 1;
        end
    end

endmodule
