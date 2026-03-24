// Шина периферийных устройств.
//
// Маршрутизация по биту 27 адреса:
//   address[27] == 0  →  MEMORY_CONTROLLER  (ОЗУ, кэш)
//   address[27] == 1  →  I/O устройства (UART_IO_DEVICE и др.)
//
// В этой реализации один I/O-слот (UART_IO_DEVICE).
// controller_ready мультиплексируется от выбранного устройства.
module PERIPHERAL_BUS (
    // Интерфейс с CPU_DATA_ADAPTER (upstream)
    input  wire [27:0] address,
    input  wire        read_trigger,
    input  wire        write_trigger,
    input  wire [31:0] write_value,
    input  wire [3:0]  mask,
    output wire [31:0] read_value,
    output wire        controller_ready,

    // MEMORY_CONTROLLER (downstream)
    output wire [27:0] mc_address,
    output wire        mc_read_trigger,
    output wire        mc_write_trigger,
    output wire [31:0] mc_write_value,
    output wire [3:0]  mc_mask,
    input  wire [31:0] mc_read_value,
    input  wire        mc_controller_ready,

    // I/O (UART_IO_DEVICE, downstream)
    output wire [27:0] io_address,
    output wire        io_read_trigger,
    output wire        io_write_trigger,
    output wire [31:0] io_write_value,
    output wire [3:0]  io_mask,
    input  wire [31:0] io_read_value,
    input  wire        io_controller_ready
);
    wire io_sel = address[27];   // 1 → I/O

    // Маршрутизация триггеров
    assign mc_address       = address;
    assign mc_read_trigger  = io_sel ? 1'b0 : read_trigger;
    assign mc_write_trigger = io_sel ? 1'b0 : write_trigger;
    assign mc_write_value   = write_value;
    assign mc_mask          = mask;

    assign io_address       = address;
    assign io_read_trigger  = io_sel ? read_trigger  : 1'b0;
    assign io_write_trigger = io_sel ? write_trigger : 1'b0;
    assign io_write_value   = write_value;
    assign io_mask          = mask;

    // Мультиплексирование ответа
    assign read_value       = io_sel ? io_read_value       : mc_read_value;
    assign controller_ready = io_sel ? io_controller_ready : mc_controller_ready;

endmodule
