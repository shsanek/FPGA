// Устройство ввода-вывода: UART через DEBUG_CONTROLLER passthrough.
//
// Адресное пространство (относительно base-адреса устройства, биты [3:2]):
//   offset 0x00  TX_DATA  (W) — запись байта для отправки через UART
//                         (R) — последний отправленный байт
//   offset 0x04  RX_DATA  (R) — принятый байт (сбрасывается после чтения)
//   offset 0x08  STATUS   (R) — {30'b0, tx_ready, rx_available}
//
// Интерфейс с PERIPHERAL_BUS: read_trigger/write_trigger — 1-тактовые импульсы.
// controller_ready = 1 всегда (операции завершаются за 1 такт).
//
// Интерфейс с DEBUG_CONTROLLER passthrough:
//   cpu_tx_byte/cpu_tx_valid — отправить байт в физический UART
//   cpu_tx_ready             — DEBUG_CONTROLLER готов забрать байт
//   cpu_rx_byte/cpu_rx_valid — байт пришедший с физического UART
module UART_IO_DEVICE (
    input  wire        clk,
    input  wire        reset,

    // Bus interface (от PERIPHERAL_BUS)
    input  wire [27:0] address,        // полный адрес; биты [3:2] выбирают регистр
    input  wire        read_trigger,   // 1-тактовый импульс: CPU читает
    input  wire        write_trigger,  // 1-тактовый импульс: CPU пишет
    input  wire [31:0] write_value,
    input  wire [3:0]  mask,           // не используется (word-aligned регистры)
    output wire [31:0] read_value,
    output wire        controller_ready, // всегда 1

    // Passthrough к DEBUG_CONTROLLER
    output wire [7:0]  cpu_tx_byte,
    output wire        cpu_tx_valid,   // 1-тактовый импульс: отправить байт
    input  wire        cpu_tx_ready,   // DEBUG готов принять байт

    input  wire [7:0]  cpu_rx_byte,    // байт от DEBUG_CONTROLLER
    input  wire        cpu_rx_valid    // 1-тактовый импульс: новый байт
);
    // ---------------------------------------------------------------
    // Регистры
    // ---------------------------------------------------------------
    logic [7:0] tx_data_r;   // последний записанный TX-байт
    logic [7:0] rx_data_r;   // принятый RX-байт
    logic       rx_avail_r;  // флаг: в буфере есть данные

    // Выбор регистра по битам [3:2] адреса
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
    assign read_value       = rdata;
    assign controller_ready = 1'b1;

    // ---------------------------------------------------------------
    // TX: CPU пишет байт → passthrough к DEBUG_CONTROLLER
    // ---------------------------------------------------------------
    // Передаём текущий write_value напрямую — tx_data_r уже обновится только
    // в следующем такте, поэтому использовать его здесь нельзя.
    assign cpu_tx_byte  = write_value[7:0];
    assign cpu_tx_valid = write_trigger && (reg_sel == REG_TX);

    // ---------------------------------------------------------------
    // Последовательная логика
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            tx_data_r  <= 8'h00;
            rx_data_r  <= 8'h00;
            rx_avail_r <= 1'b0;
        end else begin
            // TX: сохраняем последний отправленный байт
            if (write_trigger && reg_sel == REG_TX)
                tx_data_r <= write_value[7:0];

            // RX: принять новый байт от DEBUG_CONTROLLER
            if (cpu_rx_valid) begin
                rx_data_r  <= cpu_rx_byte;
                rx_avail_r <= 1'b1;
            end

            // Чтение RX_DATA сбрасывает флаг
            if (read_trigger && reg_sel == REG_RX)
                rx_avail_r <= 1'b0;
        end
    end

endmodule
