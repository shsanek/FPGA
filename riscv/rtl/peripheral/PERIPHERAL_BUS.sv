// Шина периферийных устройств.
//
// Маршрутизация по битам адреса (30-битная шина, addr[29:28]):
//   00 → MEMORY_CONTROLLER  (DDR3 256 MB, D-cache)
//   01 → I/O                (UART, OLED, SD, TIMER, SCRATCHPAD)
//   10 → MEMORY_CONTROLLER  (DDR3 stream, 1-entry bypass cache)
//   11 → MEMORY_CONTROLLER  (DDR3 I-cache, read-only BRAM cache)
//
// I/O подразбивка (addr[29:28]=01):
//   addr[18] == 0 → I/O устройства (по addr[17:16])
//   addr[18] == 1 → SCRATCHPAD (BRAM 128 KB)
//
// I/O устройства по битам [17:16]:
//   00 → UART_IO_DEVICE   (0x10000000)
//   01 → OLED_FB_DEVICE   (0x10010000)
//   10 → SD_IO_DEVICE     (0x10020000)
//   11 → TIMER_DEVICE     (0x10030000)
//
// SCRATCHPAD:               (0x10040000)
module PERIPHERAL_BUS (
    // Интерфейс с CPU (upstream) — 29-битная шина
    input  wire [29:0] address,
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
    output wire [1:0]  mc_bus_type,         // BUS_BASE_MEM=00, BUS_STREAM=01, BUS_CODE_CACHE_CORE1=10

    // UART_IO_DEVICE (downstream)
    output wire [27:0] io_address,
    output wire        io_read_trigger,
    output wire        io_write_trigger,
    output wire [31:0] io_write_value,
    output wire [3:0]  io_mask,
    input  wire [31:0] io_read_value,
    input  wire        io_controller_ready,

    // OLED_FB_DEVICE (downstream)
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
    input  wire        timer_controller_ready,

    // SCRATCHPAD (downstream)
    output wire [27:0] sp_address,
    output wire        sp_read_trigger,
    output wire        sp_write_trigger,
    output wire [31:0] sp_write_value,
    output wire [3:0]  sp_mask,
    input  wire [31:0] sp_read_value,
    input  wire        sp_controller_ready
);
    // --- Decode addr[29:28] ---
    wire mem_sel    = ~address[29] & ~address[28];   // 00 — normal DDR (D-cache)
    wire io_sel     = ~address[29] &  address[28];   // 01 — I/O + SCRATCHPAD
    wire stream_sel =  address[29] & ~address[28];   // 10 — stream DDR read
    wire icache_sel =  address[29] &  address[28];   // 11 — I-cache (read-only)
    wire sp_sel     = io_sel & address[18];          // 0x1004_0000+
    wire dev_sel    = io_sel & ~address[18];         // 0x1000_0000–0x1003_FFFF
    wire [1:0] io_dev = address[17:16];

    wire uart_sel  = dev_sel & (io_dev == 2'b00);
    wire oled_sel  = dev_sel & (io_dev == 2'b01);
    wire sd_sel    = dev_sel & (io_dev == 2'b10);
    wire timer_sel = dev_sel & (io_dev == 2'b11);

    // --- MEMORY_CONTROLLER (cached + stream + icache через один порт) ---
    wire mc_sel = mem_sel | stream_sel | icache_sel;
    assign mc_address       = address[27:0];
    assign mc_read_trigger  = mc_sel ? read_trigger  : 1'b0;
    assign mc_write_trigger = mem_sel ? write_trigger : 1'b0;  // stream & icache = read-only
    assign mc_write_value   = write_value;
    assign mc_mask          = mask;
    assign mc_bus_type      = icache_sel ? 2'b10 :   // BUS_CODE_CACHE_CORE1
                              stream_sel ? 2'b01 :   // BUS_STREAM
                                           2'b00;    // BUS_BASE_MEM

    // --- UART ---
    assign io_address       = address[27:0];
    assign io_read_trigger  = uart_sel ? read_trigger  : 1'b0;
    assign io_write_trigger = uart_sel ? write_trigger : 1'b0;
    assign io_write_value   = write_value;
    assign io_mask          = mask;

    // --- OLED ---
    assign oled_address       = address[27:0];
    assign oled_read_trigger  = oled_sel ? read_trigger  : 1'b0;
    assign oled_write_trigger = oled_sel ? write_trigger : 1'b0;
    assign oled_write_value   = write_value;
    assign oled_mask          = mask;

    // --- SD ---
    assign sd_address       = address[27:0];
    assign sd_read_trigger  = sd_sel ? read_trigger  : 1'b0;
    assign sd_write_trigger = sd_sel ? write_trigger : 1'b0;
    assign sd_write_value   = write_value;
    assign sd_mask          = mask;

    // --- TIMER ---
    assign timer_address      = address[27:0];
    assign timer_read_trigger = timer_sel ? read_trigger : 1'b0;

    // --- SCRATCHPAD ---
    assign sp_address       = address[27:0];
    assign sp_read_trigger  = sp_sel ? read_trigger  : 1'b0;
    assign sp_write_trigger = sp_sel ? write_trigger : 1'b0;
    assign sp_write_value   = write_value;
    assign sp_mask          = mask;

    // --- Мультиплексирование ответа ---
    assign read_value       = sp_sel    ? sp_read_value        :
                              timer_sel ? timer_read_value     :
                              sd_sel    ? sd_read_value        :
                              oled_sel  ? oled_read_value      :
                              uart_sel  ? io_read_value        :
                                          mc_read_value;

    assign controller_ready = sp_sel    ? sp_controller_ready     :
                              timer_sel ? timer_controller_ready  :
                              sd_sel    ? sd_controller_ready     :
                              oled_sel  ? oled_controller_ready   :
                              uart_sel  ? io_controller_ready     :
                                          mc_controller_ready;


endmodule
