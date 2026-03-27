// Шина периферийных устройств.
//
// Маршрутизация по биту 27 адреса:
//   address[27] == 0  →  MEMORY_CONTROLLER  (ОЗУ, кэш)
//   address[27] == 1  →  I/O устройства
//
// I/O подразбивка по битам [17:16]:
//   00 → UART_IO_DEVICE   (0x8000000)
//   01 → OLED_IO_DEVICE   (0x8010000)
//   10 → SD_IO_DEVICE     (0x8020000)
//   11 → (свободно)
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

    // UART_IO_DEVICE (downstream)
    output wire [27:0] io_address,
    output wire        io_read_trigger,
    output wire        io_write_trigger,
    output wire [31:0] io_write_value,
    output wire [3:0]  io_mask,
    input  wire [31:0] io_read_value,
    input  wire        io_controller_ready,

    // OLED_IO_DEVICE (downstream)
    output wire [27:0] oled_address,
    output wire        oled_read_trigger,
    output wire        oled_write_trigger,
    output wire [31:0] oled_write_value,
    output wire [3:0]  oled_mask,
    input  wire [31:0] oled_read_value,
    input  wire        oled_controller_ready,

    // SD_IO_DEVICE (downstream)
    output wire [27:0] sd_address,
    output wire        sd_read_trigger,
    output wire        sd_write_trigger,
    output wire [31:0] sd_write_value,
    output wire [3:0]  sd_mask,
    input  wire [31:0] sd_read_value,
    input  wire        sd_controller_ready,

    // TIMER_DEVICE (downstream)
    output wire [27:0] timer_address,
    output wire        timer_read_trigger,
    input  wire [31:0] timer_read_value,
    input  wire        timer_controller_ready
);
    wire io_sel   = address[27];
    wire [1:0] io_dev = address[17:16];

    wire uart_sel  = io_sel & (io_dev == 2'b00);
    wire oled_sel  = io_sel & (io_dev == 2'b01);
    wire sd_sel    = io_sel & (io_dev == 2'b10);
    wire timer_sel = io_sel & (io_dev == 2'b11);

    // --- MEMORY_CONTROLLER ---
    assign mc_address       = address;
    assign mc_read_trigger  = io_sel ? 1'b0 : read_trigger;
    assign mc_write_trigger = io_sel ? 1'b0 : write_trigger;
    assign mc_write_value   = write_value;
    assign mc_mask          = mask;

    // --- UART ---
    assign io_address       = address;
    assign io_read_trigger  = uart_sel ? read_trigger  : 1'b0;
    assign io_write_trigger = uart_sel ? write_trigger : 1'b0;
    assign io_write_value   = write_value;
    assign io_mask          = mask;

    // --- OLED ---
    assign oled_address       = address;
    assign oled_read_trigger  = oled_sel ? read_trigger  : 1'b0;
    assign oled_write_trigger = oled_sel ? write_trigger : 1'b0;
    assign oled_write_value   = write_value;
    assign oled_mask          = mask;

    // --- SD ---
    assign sd_address       = address;
    assign sd_read_trigger  = sd_sel ? read_trigger  : 1'b0;
    assign sd_write_trigger = sd_sel ? write_trigger : 1'b0;
    assign sd_write_value   = write_value;
    assign sd_mask          = mask;

    // --- TIMER ---
    assign timer_address      = address;
    assign timer_read_trigger = timer_sel ? read_trigger : 1'b0;

    // --- Мультиплексирование ответа ---
    assign read_value       = timer_sel ? timer_read_value :
                              sd_sel    ? sd_read_value    :
                              oled_sel  ? oled_read_value  :
                              uart_sel  ? io_read_value    :
                                          mc_read_value;

    assign controller_ready = timer_sel ? timer_controller_ready :
                              sd_sel    ? sd_controller_ready    :
                              oled_sel  ? oled_controller_ready  :
                              uart_sel  ? io_controller_ready    :
                                          mc_controller_ready;

endmodule
