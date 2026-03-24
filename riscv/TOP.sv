// Верхний модуль системы RISC-V.
//
// Состав:
//   CPU_SINGLE_CYCLE   — однотактовый RV32I процессор
//   CPU_DATA_ADAPTER   — FSM-адаптер: CPU data port ↔ PERIPHERAL_BUS
//   PERIPHERAL_BUS     — маршрутизатор (addr[27]=0→MC, addr[27]=1→I/O)
//   MEMORY_CONTROLLER  — кэш 4×CHUNK (128 бит), интерфейс с RAM
//   RAM_CONTROLLER     — MIG7-интерфейс (DDR SDRAM)
//   UART_IO_DEVICE     — memory-mapped UART регистры (TX/RX/STATUS)
//   DEBUG_CONTROLLER   — отладочный UART-протокол (HALT/RESUME/STEP/MEM)
//   I_O_INPUT_CONTROLLER  — физический UART RX (serial → byte)
//   I_O_OUTPUT_CONTROLLER — физический UART TX (byte → serial)
//   Instruction ROM    — 32-битный ROM размером ROM_DEPTH слов (NOP по умолчанию)
//
// Адресная карта (28-битный адрес из CPU_DATA_ADAPTER):
//   0x000_0000 – 0x7FF_FFFF  →  MEMORY_CONTROLLER (ОЗУ)
//   0x800_0000 – 0xFFF_FFFF  →  I/O (UART_IO_DEVICE)
//     0x800_0000 : TX_DATA   (W/R)
//     0x800_0004 : RX_DATA   (R)
//     0x800_0008 : STATUS    (R) {…, tx_ready, rx_avail}
//
// Синтез: mig_* порты подключаются к Xilinx MIG7 IP core.
// Симуляция: подключить MIG_MODEL к mig_* портам в тестбенче.
module TOP #(
    parameter CLOCK_FREQ   = 100_000_000,
    parameter BAUD_RATE    = 115_200,
    parameter CHUNK_PART   = 128,
    parameter ADDRESS_SIZE = 28,
    parameter DATA_SIZE    = 32,
    parameter ROM_DEPTH    = 256,
    parameter DEBUG_ENABLE = 1
)(
    input  wire clk,
    input  wire reset,

    // Физический UART (через FTDI или аналог)
    input  wire uart_rx,   // serial in:  PC TXD  → FPGA
    output wire uart_tx,   // serial out: FPGA TXD → PC

    // MIG7 DDR-интерфейс (для синтеза; в тестбенче — MIG_MODEL)
    input  wire                      mig_ui_clk,
    input  wire                      mig_init_calib_complete,
    input  wire                      mig_app_rdy,
    output wire [ADDRESS_SIZE-1:0]   mig_app_addr,
    output wire [2:0]                mig_app_cmd,
    output wire                      mig_app_en,
    output wire [CHUNK_PART-1:0]     mig_app_wdf_data,
    output wire                      mig_app_wdf_wren,
    output wire                      mig_app_wdf_end,
    output wire [(CHUNK_PART/8-1):0] mig_app_wdf_mask,
    input  wire                      mig_app_wdf_rdy,
    input  wire [CHUNK_PART-1:0]     mig_app_rd_data,
    input  wire                      mig_app_rd_data_valid,
    input  wire                      mig_app_rd_data_end
);
    localparam MASK_SIZE  = DATA_SIZE / 8;
    localparam BIT_PERIOD = CLOCK_FREQ / BAUD_RATE;

    // ---------------------------------------------------------------
    // Instruction ROM (слова по 32 бит, default = NOP)
    // В тестбенче содержимое задаётся через иерархический доступ:
    //   dut.rom[i] = instruction;
    // Для синтеза используй $readmemh("program.hex", rom) или замени
    // на Block RAM IP.
    // ---------------------------------------------------------------
    logic [31:0] rom [0:ROM_DEPTH-1];
    wire  [31:0] instr_addr;
    wire  [31:0] instr_data = rom[instr_addr[$clog2(ROM_DEPTH)+1 : 2]];

    initial begin
        for (int i = 0; i < ROM_DEPTH; i++) rom[i] = 32'h0000_0013; // NOP
    end

    // ---------------------------------------------------------------
    // CPU ↔ CPU_DATA_ADAPTER
    // ---------------------------------------------------------------
    wire        cpu_mem_read_en, cpu_mem_write_en;
    wire [31:0] cpu_mem_addr, cpu_mem_write_data, cpu_mem_read_data;
    wire [3:0]  cpu_mem_byte_mask;
    wire        cpu_mem_stall;

    // ---------------------------------------------------------------
    // CPU_DATA_ADAPTER ↔ PERIPHERAL_BUS
    // ---------------------------------------------------------------
    wire [27:0] bus_addr;
    wire        bus_rd, bus_wr;
    wire [31:0] bus_wr_data, bus_rd_data;
    wire [3:0]  bus_mask;
    wire        bus_ready;

    // ---------------------------------------------------------------
    // PERIPHERAL_BUS ↔ MEMORY_CONTROLLER
    // ---------------------------------------------------------------
    wire [ADDRESS_SIZE-1:0] mc_addr;
    wire        mc_rd, mc_wr;
    wire [31:0] mc_wr_data, mc_rd_data;
    wire [3:0]  mc_mask;
    wire        mc_ready;
    wire        mc_contains_addr;  // не используется снаружи

    // ---------------------------------------------------------------
    // PERIPHERAL_BUS ↔ UART_IO_DEVICE
    // ---------------------------------------------------------------
    wire [27:0] io_addr;
    wire        io_rd, io_wr;
    wire [31:0] io_wr_data, io_rd_data;
    wire [3:0]  io_mask;
    wire        io_ready;

    // ---------------------------------------------------------------
    // MEMORY_CONTROLLER ↔ RAM_CONTROLLER
    // ---------------------------------------------------------------
    wire        ram_ready;
    wire        ram_wr_trig;
    wire [CHUNK_PART-1:0]   ram_wr_val;
    wire [ADDRESS_SIZE-1:0] ram_wr_addr;
    wire        ram_rd_trig;
    wire [CHUNK_PART-1:0]   ram_rd_val;
    wire [ADDRESS_SIZE-1:0] ram_rd_addr;
    wire        ram_rd_ready;

    // ---------------------------------------------------------------
    // DEBUG_CONTROLLER ↔ CPU / MEMORY_CONTROLLER / UART_IO_DEVICE
    // ---------------------------------------------------------------
    wire        dbg_halt, dbg_step;
    wire        dbg_is_halted;
    wire [31:0] dbg_current_pc, dbg_current_instr;

    wire [ADDRESS_SIZE-1:0] mc_dbg_addr;
    wire        mc_dbg_rd, mc_dbg_wr;
    wire [31:0] mc_dbg_wr_data, mc_dbg_rd_data;
    wire [MASK_SIZE-1:0]    mc_dbg_mask;
    wire        mc_dbg_ready;

    wire [7:0]  cpu_rx_byte;
    wire        cpu_rx_valid;
    wire [7:0]  cpu_tx_byte;
    wire        cpu_tx_valid, cpu_tx_ready;

    // ---------------------------------------------------------------
    // UART byte interface
    // ---------------------------------------------------------------
    wire [7:0]  uart_rx_byte;
    wire        uart_rx_valid;
    wire [7:0]  uart_tx_byte;
    wire        uart_tx_valid;
    wire        uart_tx_ready;

    // ---------------------------------------------------------------
    // Инстанцирование
    // ---------------------------------------------------------------

    // --- UART RX: физический сигнал → байт ---
    I_O_INPUT_CONTROLLER #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE (BAUD_RATE),
        .BIT_PERIOD(BIT_PERIOD)
    ) uart_in (
        .clk              (clk),
        .TXD              (uart_rx),
        .io_input_trigger (uart_rx_valid),
        .io_input_value   (uart_rx_byte)
    );

    // --- UART TX: байт → физический сигнал ---
    I_O_OUTPUT_CONTROLLER #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE (BAUD_RATE),
        .BIT_PERIOD(BIT_PERIOD)
    ) uart_out (
        .clk                    (clk),
        .io_output_value        (uart_tx_byte),
        .io_output_trigger      (uart_tx_valid),
        .io_output_ready_trigger(uart_tx_ready),
        .RXD                    (uart_tx)
    );

    // --- DEBUG_CONTROLLER ---
    DEBUG_CONTROLLER #(.DEBUG_ENABLE(DEBUG_ENABLE)) dbg_ctrl (
        .clk               (clk),
        .reset             (reset),
        .rx_byte           (uart_rx_byte),
        .rx_valid          (uart_rx_valid),
        .tx_byte           (uart_tx_byte),
        .tx_valid          (uart_tx_valid),
        .tx_ready          (uart_tx_ready),
        .dbg_halt          (dbg_halt),
        .dbg_step          (dbg_step),
        .dbg_is_halted     (dbg_is_halted),
        .dbg_current_pc    (dbg_current_pc),
        .dbg_current_instr (dbg_current_instr),
        .mc_dbg_address    (mc_dbg_addr),
        .mc_dbg_read_trigger (mc_dbg_rd),
        .mc_dbg_write_trigger(mc_dbg_wr),
        .mc_dbg_write_data (mc_dbg_wr_data),
        .mc_dbg_mask       (mc_dbg_mask),
        .mc_dbg_read_data  (mc_dbg_rd_data),
        .mc_dbg_ready      (mc_dbg_ready),
        .cpu_rx_byte       (cpu_rx_byte),
        .cpu_rx_valid      (cpu_rx_valid),
        .cpu_tx_byte       (cpu_tx_byte),
        .cpu_tx_valid      (cpu_tx_valid),
        .cpu_tx_ready      (cpu_tx_ready)
    );

    // --- CPU ---
    CPU_SINGLE_CYCLE #(.DEBUG_ENABLE(DEBUG_ENABLE)) cpu (
        .clk               (clk),
        .reset             (reset),
        .instr_addr        (instr_addr),
        .instr_data        (instr_data),
        .mem_read_en       (cpu_mem_read_en),
        .mem_write_en      (cpu_mem_write_en),
        .mem_addr          (cpu_mem_addr),
        .mem_write_data    (cpu_mem_write_data),
        .mem_byte_mask     (cpu_mem_byte_mask),
        .mem_read_data     (cpu_mem_read_data),
        .mem_stall         (cpu_mem_stall),
        .dbg_halt          (dbg_halt),
        .dbg_step          (dbg_step),
        .dbg_is_halted     (dbg_is_halted),
        .dbg_current_pc    (dbg_current_pc),
        .dbg_current_instr (dbg_current_instr)
    );

    // --- CPU_DATA_ADAPTER ---
    CPU_DATA_ADAPTER adapter (
        .clk               (clk),
        .reset             (reset),
        .mem_read_en       (cpu_mem_read_en),
        .mem_write_en      (cpu_mem_write_en),
        .mem_addr          (cpu_mem_addr),
        .mem_write_data    (cpu_mem_write_data),
        .mem_byte_mask     (cpu_mem_byte_mask),
        .mem_read_data     (cpu_mem_read_data),
        .stall             (cpu_mem_stall),
        .mc_address        (bus_addr),
        .mc_read_trigger   (bus_rd),
        .mc_write_trigger  (bus_wr),
        .mc_write_value    (bus_wr_data),
        .mc_mask           (bus_mask),
        .mc_read_value     (bus_rd_data),
        .mc_controller_ready(bus_ready)
    );

    // --- PERIPHERAL_BUS ---
    PERIPHERAL_BUS pbus (
        .address           (bus_addr),
        .read_trigger      (bus_rd),
        .write_trigger     (bus_wr),
        .write_value       (bus_wr_data),
        .mask              (bus_mask),
        .read_value        (bus_rd_data),
        .controller_ready  (bus_ready),

        .mc_address        (mc_addr),
        .mc_read_trigger   (mc_rd),
        .mc_write_trigger  (mc_wr),
        .mc_write_value    (mc_wr_data),
        .mc_mask           (mc_mask),
        .mc_read_value     (mc_rd_data),
        .mc_controller_ready(mc_ready),

        .io_address        (io_addr),
        .io_read_trigger   (io_rd),
        .io_write_trigger  (io_wr),
        .io_write_value    (io_wr_data),
        .io_mask           (io_mask),
        .io_read_value     (io_rd_data),
        .io_controller_ready(io_ready)
    );

    // --- UART_IO_DEVICE ---
    UART_IO_DEVICE uart_io (
        .clk               (clk),
        .reset             (reset),
        .address           (io_addr),
        .read_trigger      (io_rd),
        .write_trigger     (io_wr),
        .write_value       (io_wr_data),
        .mask              (io_mask),
        .read_value        (io_rd_data),
        .controller_ready  (io_ready),
        .cpu_tx_byte       (cpu_tx_byte),
        .cpu_tx_valid      (cpu_tx_valid),
        .cpu_tx_ready      (cpu_tx_ready),
        .cpu_rx_byte       (cpu_rx_byte),
        .cpu_rx_valid      (cpu_rx_valid)
    );

    // --- MEMORY_CONTROLLER ---
    MEMORY_CONTROLLER #(
        .CHUNK_PART  (CHUNK_PART),
        .DATA_SIZE   (DATA_SIZE),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) mem_ctrl (
        .clk                 (clk),
        .ram_controller_ready(ram_ready),
        .ram_write_trigger   (ram_wr_trig),
        .ram_write_value     (ram_wr_val),
        .ram_write_address   (ram_wr_addr),
        .ram_read_trigger    (ram_rd_trig),
        .ram_read_value      (ram_rd_val),
        .ram_read_address    (ram_rd_addr),
        .ram_read_value_ready(ram_rd_ready),
        .controller_ready    (mc_ready),
        .address             (mc_addr),
        .mask                (mc_mask),
        .write_trigger       (mc_wr),
        .write_value         (mc_wr_data),
        .read_trigger        (mc_rd),
        .read_value          (mc_rd_data),
        .contains_address    (mc_contains_addr),
        .dbg_read_trigger    (mc_dbg_rd),
        .dbg_write_trigger   (mc_dbg_wr),
        .dbg_address         (mc_dbg_addr),
        .dbg_write_data      (mc_dbg_wr_data),
        .dbg_mask            (mc_dbg_mask),
        .dbg_read_data       (mc_dbg_rd_data),
        .dbg_ready           (mc_dbg_ready)
    );

    // --- RAM_CONTROLLER ---
    RAM_CONTROLLER #(
        .CHUNK_PART  (CHUNK_PART),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) ram_ctrl (
        .clk                    (clk),
        .controller_ready       (ram_ready),
        .error                  (),
        .write_trigger          (ram_wr_trig),
        .write_value            (ram_wr_val),
        .write_address          (ram_wr_addr),
        .read_trigger           (ram_rd_trig),
        .read_value             (ram_rd_val),
        .read_address           (ram_rd_addr),
        .read_value_ready       (ram_rd_ready),
        .led0                   (),
        .mig_app_addr           (mig_app_addr),
        .mig_app_cmd            (mig_app_cmd),
        .mig_app_en             (mig_app_en),
        .mig_app_wdf_data       (mig_app_wdf_data),
        .mig_app_wdf_end        (mig_app_wdf_end),
        .mig_app_wdf_mask       (mig_app_wdf_mask),
        .mig_app_wdf_wren       (mig_app_wdf_wren),
        .mig_app_wdf_rdy        (mig_app_wdf_rdy),
        .mig_app_rd_data        (mig_app_rd_data),
        .mig_app_rd_data_end    (mig_app_rd_data_end),
        .mig_app_rd_data_valid  (mig_app_rd_data_valid),
        .mig_app_rdy            (mig_app_rdy),
        .mig_ui_clk             (mig_ui_clk),
        .mig_init_calib_complete(mig_init_calib_complete)
    );

endmodule
