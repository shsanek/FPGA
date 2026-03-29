// PERIPHERAL_BUS_V2 — 128-bit address decoder with standard bus interface.
//
// Upstream: standard 128-bit bus slave (from MULTICORE_MUX / CORE_BUS_ARBITER).
// Downstream: standard 128-bit bus to each device.
//   - MEMORY_CONTROLLER_V2: native 128-bit
//   - I/O devices (UART, OLED, SD, TIMER, SCRATCHPAD): via BUS_128_TO_32
//
// Address map:
//   bit30=0 (0x0000_0000 – 0x3FFF_FFFF) → MEMORY_CONTROLLER
//       bit29=0: normal D-cache path
//       bit29=1: stream (bypass cache)
//   bit30=1 (0x4000_0000+) → I/O devices (by [19:16]):
//       0x4000_xxxx → UART
//       0x4001_xxxx → OLED
//       0x4002_xxxx → SD
//       0x4003_xxxx → TIMER
//       0x4004_xxxx → SCRATCHPAD

module PERIPHERAL_BUS_V2 (
    input wire clk,
    input wire reset,

    // === Upstream: standard 128-bit bus slave ===
    input  wire [31:0]  bus_address,
    input  wire         bus_read,
    input  wire         bus_write,
    input  wire [127:0] bus_write_data,
    input  wire [15:0]  bus_write_mask,
    output wire         bus_ready,
    output wire [127:0] bus_read_data,
    output wire         bus_read_valid,

    // === MEMORY_CONTROLLER_V2: native 128-bit bus ===
    output wire [31:0]  mc_bus_address,
    output wire         mc_bus_read,
    output wire         mc_bus_write,
    output wire [127:0] mc_bus_write_data,
    output wire [15:0]  mc_bus_write_mask,
    input  wire         mc_bus_ready,
    input  wire [127:0] mc_bus_read_data,
    input  wire         mc_bus_read_valid,

    // === UART_IO_DEVICE: 32-bit device interface ===
    output wire [31:0]  uart_address,
    output wire         uart_read,
    output wire         uart_write,
    output wire [31:0]  uart_write_data,
    output wire [3:0]   uart_write_mask,
    input  wire [31:0]  uart_read_data,
    input  wire         uart_ready,

    // === OLED_FB_DEVICE: 32-bit device interface ===
    output wire [31:0]  oled_address,
    output wire         oled_read,
    output wire         oled_write,
    output wire [31:0]  oled_write_data,
    output wire [3:0]   oled_write_mask,
    input  wire [31:0]  oled_read_data,
    input  wire         oled_ready,

    // === SD_IO_DEVICE: 32-bit device interface ===
    output wire [31:0]  sd_address,
    output wire         sd_read,
    output wire         sd_write,
    output wire [31:0]  sd_write_data,
    output wire [3:0]   sd_write_mask,
    input  wire [31:0]  sd_read_data,
    input  wire         sd_ready,

    // === TIMER_DEVICE: 32-bit device interface ===
    output wire [31:0]  timer_address,
    output wire         timer_read,
    output wire         timer_write,
    output wire [31:0]  timer_write_data,
    output wire [3:0]   timer_write_mask,
    input  wire [31:0]  timer_read_data,
    input  wire         timer_ready,

    // === SCRATCHPAD: 32-bit device interface ===
    output wire [31:0]  sp_address,
    output wire         sp_read,
    output wire         sp_write,
    output wire [31:0]  sp_write_data,
    output wire [3:0]   sp_write_mask,
    input  wire [31:0]  sp_read_data,
    input  wire         sp_ready
);

    // =========================================================
    // Address decode
    // =========================================================
    wire mc_sel    = !bus_address[30];                          // 0x0000_0000 – 0x3FFF_FFFF
    wire io_sel    =  bus_address[30];                          // 0x4000_0000+

    wire uart_sel  = io_sel && (bus_address[19:16] == 4'h0);  // 0x4000_xxxx
    wire oled_sel  = io_sel && (bus_address[19:16] == 4'h1);  // 0x4001_xxxx
    wire sd_sel    = io_sel && (bus_address[19:16] == 4'h2);  // 0x4002_xxxx
    wire timer_sel = io_sel && (bus_address[19:16] == 4'h3);  // 0x4003_xxxx
    wire sp_sel    = io_sel && (bus_address[19:16] >= 4'h4);  // 0x4004_xxxx+

    // =========================================================
    // MEMORY_CONTROLLER: native 128-bit, direct pass-through
    // =========================================================
    assign mc_bus_address    = bus_address;
    assign mc_bus_read       = mc_sel ? bus_read  : 1'b0;
    assign mc_bus_write      = mc_sel ? bus_write : 1'b0;
    assign mc_bus_write_data = bus_write_data;
    assign mc_bus_write_mask = bus_write_mask;

    // =========================================================
    // I/O devices: 128→32 via BUS_128_TO_32 converters
    // =========================================================

    // --- Internal 128-bit bus wires per device (converter ↔ decoder) ---
    wire         uart_128_ready, oled_128_ready, sd_128_ready, timer_128_ready, sp_128_ready;
    wire [127:0] uart_128_read_data, oled_128_read_data, sd_128_read_data, timer_128_read_data, sp_128_read_data;
    wire         uart_128_read_valid, oled_128_read_valid, sd_128_read_valid, timer_128_read_valid, sp_128_read_valid;

    // --- UART converter ---
    BUS_128_TO_32 uart_conv (
        .clk(clk), .reset(reset),
        .bus_address    (bus_address),
        .bus_read       (uart_sel ? bus_read  : 1'b0),
        .bus_write      (uart_sel ? bus_write : 1'b0),
        .bus_write_data (bus_write_data),
        .bus_write_mask (bus_write_mask),
        .bus_ready      (uart_128_ready),
        .bus_read_data  (uart_128_read_data),
        .bus_read_valid (uart_128_read_valid),
        .dev_address    (uart_address),
        .dev_read       (uart_read),
        .dev_write      (uart_write),
        .dev_write_data (uart_write_data),
        .dev_write_mask (uart_write_mask),
        .dev_read_data  (uart_read_data),
        .dev_ready      (uart_ready)
    );

    // --- OLED converter ---
    BUS_128_TO_32 oled_conv (
        .clk(clk), .reset(reset),
        .bus_address    (bus_address),
        .bus_read       (oled_sel ? bus_read  : 1'b0),
        .bus_write      (oled_sel ? bus_write : 1'b0),
        .bus_write_data (bus_write_data),
        .bus_write_mask (bus_write_mask),
        .bus_ready      (oled_128_ready),
        .bus_read_data  (oled_128_read_data),
        .bus_read_valid (oled_128_read_valid),
        .dev_address    (oled_address),
        .dev_read       (oled_read),
        .dev_write      (oled_write),
        .dev_write_data (oled_write_data),
        .dev_write_mask (oled_write_mask),
        .dev_read_data  (oled_read_data),
        .dev_ready      (oled_ready)
    );

    // --- SD converter ---
    BUS_128_TO_32 sd_conv (
        .clk(clk), .reset(reset),
        .bus_address    (bus_address),
        .bus_read       (sd_sel ? bus_read  : 1'b0),
        .bus_write      (sd_sel ? bus_write : 1'b0),
        .bus_write_data (bus_write_data),
        .bus_write_mask (bus_write_mask),
        .bus_ready      (sd_128_ready),
        .bus_read_data  (sd_128_read_data),
        .bus_read_valid (sd_128_read_valid),
        .dev_address    (sd_address),
        .dev_read       (sd_read),
        .dev_write      (sd_write),
        .dev_write_data (sd_write_data),
        .dev_write_mask (sd_write_mask),
        .dev_read_data  (sd_read_data),
        .dev_ready      (sd_ready)
    );

    // --- TIMER converter ---
    BUS_128_TO_32 timer_conv (
        .clk(clk), .reset(reset),
        .bus_address    (bus_address),
        .bus_read       (timer_sel ? bus_read  : 1'b0),
        .bus_write      (timer_sel ? bus_write : 1'b0),
        .bus_write_data (bus_write_data),
        .bus_write_mask (bus_write_mask),
        .bus_ready      (timer_128_ready),
        .bus_read_data  (timer_128_read_data),
        .bus_read_valid (timer_128_read_valid),
        .dev_address    (timer_address),
        .dev_read       (timer_read),
        .dev_write      (timer_write),
        .dev_write_data (timer_write_data),
        .dev_write_mask (timer_write_mask),
        .dev_read_data  (timer_read_data),
        .dev_ready      (timer_ready)
    );

    // --- SCRATCHPAD converter ---
    BUS_128_TO_32 sp_conv (
        .clk(clk), .reset(reset),
        .bus_address    (bus_address),
        .bus_read       (sp_sel ? bus_read  : 1'b0),
        .bus_write      (sp_sel ? bus_write : 1'b0),
        .bus_write_data (bus_write_data),
        .bus_write_mask (bus_write_mask),
        .bus_ready      (sp_128_ready),
        .bus_read_data  (sp_128_read_data),
        .bus_read_valid (sp_128_read_valid),
        .dev_address    (sp_address),
        .dev_read       (sp_read),
        .dev_write      (sp_write),
        .dev_write_data (sp_write_data),
        .dev_write_mask (sp_write_mask),
        .dev_read_data  (sp_read_data),
        .dev_ready      (sp_ready)
    );

    // =========================================================
    // Response mux (upstream ← selected device)
    // =========================================================
    // All devices must be ready — prevents sending to a device
    // whose address appears on the bus while another device is busy
    assign bus_ready = mc_bus_ready
                     & uart_128_ready
                     & oled_128_ready
                     & sd_128_ready
                     & timer_128_ready
                     & sp_128_ready;

    assign bus_read_data = mc_sel    ? mc_bus_read_data      :
                           uart_sel  ? uart_128_read_data    :
                           oled_sel  ? oled_128_read_data    :
                           sd_sel    ? sd_128_read_data      :
                           timer_sel ? timer_128_read_data   :
                           sp_sel    ? sp_128_read_data      :
                                       128'b0;

    assign bus_read_valid = mc_sel    ? mc_bus_read_valid     :
                            uart_sel  ? uart_128_read_valid   :
                            oled_sel  ? oled_128_read_valid   :
                            sd_sel    ? sd_128_read_valid     :
                            timer_sel ? timer_128_read_valid  :
                            sp_sel    ? sp_128_read_valid     :
                                        1'b0;

endmodule
