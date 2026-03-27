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
//   0x800_0000 – 0x800_FFFF  →  UART_IO_DEVICE
//     0x800_0000 : TX_DATA   (W/R)
//     0x800_0004 : RX_DATA   (R)
//     0x800_0008 : STATUS    (R) {…, tx_ready, rx_avail}
//   0x801_0000 – 0x801_FFFF  →  OLED_IO_DEVICE (PmodOLEDrgb SSD1331)
//     0x801_0000 : DATA      (W)   — SPI byte
//     0x801_0004 : CONTROL   (W/R) — {PMODEN, VCCEN, RES, DC, CS}
//     0x801_0008 : STATUS    (R)   — {…, spi_busy, 0}
//     0x801_000C : DIVIDER   (W/R) — SPI clock divider
//   0x802_0000 – 0x802_FFFF  →  SD_IO_DEVICE (PmodMicroSD, SPI mode)
//     0x802_0000 : DATA      (W/R) — SPI byte TX/RX (full-duplex)
//     0x802_0004 : CONTROL   (W/R) — {CS}
//     0x802_0008 : STATUS    (R)   — {…, card_detect, spi_busy, 0}
//     0x802_000C : DIVIDER   (W/R) — SPI clock divider
//
// Синтез: mig_* порты подключаются к Xilinx MIG7 IP core.
// Симуляция: подключить MIG_MODEL к mig_* портам в тестбенче.
module TOP #(
    parameter CLOCK_FREQ   = 100_000_000,
    parameter BAUD_RATE    = 115_200,
    parameter CHUNK_PART   = 128,
    parameter ADDRESS_SIZE = 28,
    parameter DATA_SIZE    = 32,
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
    input  wire                      mig_app_rd_data_end,

    // OLED (PmodOLEDrgb, SSD1331)
    output wire        oled_cs_n,
    output wire        oled_mosi,
    output wire        oled_sck,
    output wire        oled_dc,
    output wire        oled_res_n,
    output wire        oled_vccen,
    output wire        oled_pmoden,

    // SD (PmodMicroSD, SPI mode)
    output wire        sd_cs_n,
    output wire        sd_mosi,
    input  wire        sd_miso,
    output wire        sd_sck,
    input  wire        sd_cd_n,      // card detect (0=inserted)

    // QSPI Flash (onboard, for FLASH_LOADER)
    output wire        flash_cs_n,
    output wire        flash_mosi,
    input  wire        flash_miso,
    output wire        flash_sck,

    // Boot status
    output wire        boot_active,      // 1 = FLASH_LOADER ещё работает
    output wire        boot_error        // 1 = bad magic / no payload
);
    localparam MASK_SIZE  = DATA_SIZE / 8;
    localparam BIT_PERIOD = CLOCK_FREQ / BAUD_RATE;

    // ---------------------------------------------------------------
    // CPU ↔ CPU_PIPELINE_ADAPTER
    // ---------------------------------------------------------------
    wire [31:0] instr_addr;
    wire [31:0] instr_data;
    wire        instr_stall_w;
    wire        cpu_mem_read_en, cpu_mem_write_en;
    wire [31:0] cpu_mem_addr, cpu_mem_write_data, cpu_mem_read_data;
    wire [3:0]  cpu_mem_byte_mask;
    wire        cpu_mem_stall;

    // ---------------------------------------------------------------
    // CPU_PIPELINE_ADAPTER outputs (before debug mux)
    // ---------------------------------------------------------------
    wire [27:0] pipe_addr;
    wire        pipe_rd, pipe_wr;
    wire [31:0] pipe_wr_data;
    wire [3:0]  pipe_mask;

    // ---------------------------------------------------------------
    // Bus (after debug mux) ↔ PERIPHERAL_BUS
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
    // PERIPHERAL_BUS ↔ OLED_IO_DEVICE
    // ---------------------------------------------------------------
    wire [27:0] oled_addr;
    wire        oled_rd, oled_wr;
    wire [31:0] oled_wr_data, oled_rd_data;
    wire [3:0]  oled_mask;
    wire        oled_ready;

    // ---------------------------------------------------------------
    // PERIPHERAL_BUS ↔ SD_IO_DEVICE
    // ---------------------------------------------------------------
    wire [27:0] sd_addr;
    wire        sd_rd, sd_wr;
    wire [31:0] sd_wr_data, sd_rd_data;
    wire [3:0]  sd_mask_w;
    wire        sd_ready;

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
    // DEBUG_CONTROLLER ↔ CPU
    // ---------------------------------------------------------------
    wire        dbg_halt;
    wire        dbg_set_pc;
    wire [31:0] dbg_new_pc;
    wire        dbg_is_halted;
    wire        dbg_bus_request;
    wire        dbg_step_pipeline;
    wire        pipeline_paused;
    wire [31:0] dbg_current_pc, dbg_current_instr;

    // ---------------------------------------------------------------
    // DEBUG_CONTROLLER memory port (muxed with CPU onto bus)
    // ---------------------------------------------------------------
    wire [ADDRESS_SIZE-1:0] mc_dbg_addr;
    wire        mc_dbg_rd, mc_dbg_wr;
    wire [31:0] mc_dbg_wr_data, mc_dbg_rd_data;
    wire        mc_dbg_ready;

    wire [7:0]  cpu_rx_byte;
    wire        cpu_rx_valid;
    wire [7:0]  cpu_tx_byte;
    wire        cpu_tx_valid, cpu_tx_ready;

    // ---------------------------------------------------------------
    // FLASH_LOADER (boot from QSPI flash)
    // ---------------------------------------------------------------
    wire        flash_bus_request;
    wire        flash_active;
    wire [ADDRESS_SIZE-1:0] mc_flash_addr;
    wire        mc_flash_wr;
    wire [31:0] mc_flash_wr_data;
    wire [MASK_SIZE-1:0] mc_flash_mask;
    wire        mc_flash_ready;
    wire        flash_set_pc;
    wire [31:0] flash_new_pc;

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
    wire [7:0] raw_rx_byte;
    wire       raw_rx_valid;

    SIMPLE_UART_RX #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) uart_in (
        .clk       (clk),
        .reset     (reset),
        .rx        (uart_rx),
        .rx_data   (raw_rx_byte),
        .rx_valid  (raw_rx_valid)
    );

    // --- RX FIFO (4 байта): UART RX → DEBUG_CONTROLLER ---
    // При переполнении байт пропускается (wr_en && !full)
    wire [7:0] rx_fifo_data;
    wire       rx_fifo_empty;
    wire       rx_fifo_full;
    reg        rx_fifo_rd_en;

    UART_FIFO #(.DEPTH(4)) rx_fifo (
        .clk     (clk),
        .reset   (reset),
        .wr_data (raw_rx_byte),
        .wr_en   (raw_rx_valid),    // если full — байт пропускается
        .full    (rx_fifo_full),
        .rd_data (rx_fifo_data),
        .rd_en   (rx_fifo_rd_en),
        .empty   (rx_fifo_empty)
    );

    // Выдача из RX FIFO — valid/ready handshake с DEBUG_CONTROLLER
    // Попаем из FIFO если DEBUG готов (rx_ready) ИЛИ голова = 0xFD (SYNC_RESET)
    wire       dbg_rx_ready;       // от DEBUG_CONTROLLER
    wire       fifo_head_is_fd = (rx_fifo_data == 8'hFD);

    reg        rx_fifo_valid_r;
    reg  [7:0] rx_fifo_captured;
    always @(posedge clk) begin
        if (reset) begin
            rx_fifo_rd_en    <= 0;
            rx_fifo_valid_r  <= 0;
            rx_fifo_captured <= 0;
        end else begin
            rx_fifo_valid_r <= 0;
            rx_fifo_rd_en   <= 0;
            if (!rx_fifo_empty && !rx_fifo_rd_en && !rx_fifo_valid_r
                && (dbg_rx_ready || fifo_head_is_fd)) begin
                rx_fifo_rd_en <= 1;
            end
            if (rx_fifo_rd_en) begin
                rx_fifo_captured <= rx_fifo_data;
                rx_fifo_valid_r  <= 1;
            end
        end
    end

    assign uart_rx_byte  = rx_fifo_captured;
    assign uart_rx_valid = rx_fifo_valid_r;

    // --- UART TX: байт → физический сигнал ---
    wire        raw_tx_ready;
    wire [7:0]  raw_tx_byte;
    wire        raw_tx_valid;

    I_O_OUTPUT_CONTROLLER #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE (BAUD_RATE),
        .BIT_PERIOD(BIT_PERIOD)
    ) uart_out (
        .clk                    (clk),
        .reset                  (reset),
        .io_output_value        (raw_tx_byte),
        .io_output_trigger      (raw_tx_valid),
        .io_output_ready_trigger(raw_tx_ready),
        .RXD                    (uart_tx)
    );

    // --- TX FIFO (4 байта): DEBUG_CONTROLLER → UART TX ---
    wire [7:0] tx_fifo_data;
    wire       tx_fifo_empty;
    wire       tx_fifo_full;
    reg        tx_fifo_rd_en;

    UART_FIFO #(.DEPTH(4)) tx_fifo (
        .clk     (clk),
        .reset   (reset),
        .wr_data (uart_tx_byte),
        .wr_en   (uart_tx_valid),   // если full — байт пропускается
        .full    (tx_fifo_full),
        .rd_data (tx_fifo_data),
        .rd_en   (tx_fifo_rd_en),
        .empty   (tx_fifo_empty)
    );

    // Выдача из TX FIFO → UART TX
    reg        tx_fifo_sending;
    reg  [7:0] tx_fifo_captured;
    always @(posedge clk) begin
        if (reset) begin
            tx_fifo_rd_en    <= 0;
            tx_fifo_sending  <= 0;
            tx_fifo_captured <= 0;
        end else begin
            tx_fifo_rd_en   <= 0;
            tx_fifo_sending <= 0;
            if (!tx_fifo_empty && raw_tx_ready && !tx_fifo_rd_en && !tx_fifo_sending) begin
                tx_fifo_rd_en <= 1;
            end
            if (tx_fifo_rd_en) begin
                tx_fifo_captured <= tx_fifo_data;  // захват до NBA
                tx_fifo_sending  <= 1;
            end
        end
    end

    assign raw_tx_byte  = tx_fifo_captured;
    assign raw_tx_valid = tx_fifo_sending;

    // DEBUG_CONTROLLER видит TX ready когда FIFO не полон
    assign uart_tx_ready = !tx_fifo_full;

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
        .dbg_set_pc        (dbg_set_pc),
        .dbg_new_pc        (dbg_new_pc),
        .dbg_is_halted     (dbg_is_halted),
        .dbg_current_pc    (dbg_current_pc),
        .dbg_current_instr (dbg_current_instr),
        .dbg_bus_request   (dbg_bus_request),
        .dbg_step_pipeline (dbg_step_pipeline),
        .dbg_bus_granted   (pipeline_paused),
        .mc_dbg_address    (mc_dbg_addr),
        .mc_dbg_read_trigger (mc_dbg_rd),
        .mc_dbg_write_trigger(mc_dbg_wr),
        .mc_dbg_write_data (mc_dbg_wr_data),
        .mc_dbg_read_data  (mc_dbg_rd_data),
        .mc_dbg_ready      (mc_dbg_ready),
        .cpu_rx_byte       (cpu_rx_byte),
        .cpu_rx_valid      (cpu_rx_valid),
        .cpu_tx_byte       (cpu_tx_byte),
        .cpu_tx_valid      (cpu_tx_valid),
        .cpu_tx_ready      (cpu_tx_ready),
        .rx_ready          (dbg_rx_ready)
    );

    // --- CPU ---
    // set_pc mux: flash_loader has priority during boot
    wire        combined_set_pc = flash_set_pc | dbg_set_pc;
    wire [31:0] combined_new_pc = flash_set_pc ? flash_new_pc : dbg_new_pc;

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
        .instr_stall       (instr_stall_w),
        .dbg_set_pc        (combined_set_pc),
        .dbg_new_pc        (combined_new_pc),
        .dbg_is_halted     (dbg_is_halted),
        .dbg_current_pc    (dbg_current_pc),
        .dbg_current_instr (dbg_current_instr)
    );

    // --- CPU_PIPELINE_ADAPTER (instruction fetch + data access) ---
    CPU_PIPELINE_ADAPTER pipeline (
        .clk               (clk),
        .reset             (reset),
        .instr_addr        (instr_addr),
        .instr_data        (instr_data),
        .instr_stall       (instr_stall_w),
        .mem_read_en       (cpu_mem_read_en),
        .mem_write_en      (cpu_mem_write_en),
        .mem_addr          (cpu_mem_addr),
        .mem_write_data    (cpu_mem_write_data),
        .mem_byte_mask     (cpu_mem_byte_mask),
        .mem_read_data     (cpu_mem_read_data),
        .mem_stall         (cpu_mem_stall),
        .mc_address        (pipe_addr),
        .mc_read_trigger   (pipe_rd),
        .mc_write_trigger  (pipe_wr),
        .mc_write_value    (pipe_wr_data),
        .mc_mask           (pipe_mask),
        .mc_read_value     (bus_rd_data),
        .mc_controller_ready(bus_ready),
        .flush             (combined_set_pc),
        .pause             (dbg_bus_request | flash_bus_request),
        .paused            (pipeline_paused),
        .step              (dbg_step_pipeline)
    );

    // --- FLASH_LOADER / DEBUG / CPU BUS MUX ---
    // Priority: flash_loader (boot) > debug > pipeline.
    // flash_active=1 only during boot. After DONE, flash is transparent.

    assign bus_addr    = flash_active    ? mc_flash_addr[27:0]   :
                         pipeline_paused ? mc_dbg_addr[27:0]     : pipe_addr;
    assign bus_rd      = flash_active    ? 1'b0                  :
                         pipeline_paused ? mc_dbg_rd             : pipe_rd;
    assign bus_wr      = flash_active    ? mc_flash_wr           :
                         pipeline_paused ? mc_dbg_wr             : pipe_wr;
    assign bus_wr_data = flash_active    ? mc_flash_wr_data      :
                         pipeline_paused ? mc_dbg_wr_data        : pipe_wr_data;
    assign bus_mask    = flash_active    ? mc_flash_mask          :
                         pipeline_paused ? {MASK_SIZE{1'b1}}     : pipe_mask;

    assign mc_dbg_rd_data = bus_rd_data;
    assign mc_dbg_ready   = (!flash_active & pipeline_paused) ? bus_ready : 1'b0;
    assign mc_flash_ready = flash_active ? bus_ready : 1'b0;

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
        .io_controller_ready(io_ready),

        .oled_address        (oled_addr),
        .oled_read_trigger   (oled_rd),
        .oled_write_trigger  (oled_wr),
        .oled_write_value    (oled_wr_data),
        .oled_mask           (oled_mask),
        .oled_read_value     (oled_rd_data),
        .oled_controller_ready(oled_ready),

        .sd_address          (sd_addr),
        .sd_read_trigger     (sd_rd),
        .sd_write_trigger    (sd_wr),
        .sd_write_value      (sd_wr_data),
        .sd_mask             (sd_mask_w),
        .sd_read_value       (sd_rd_data),
        .sd_controller_ready (sd_ready)
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

    // --- OLED_IO_DEVICE ---
    OLED_IO_DEVICE oled_io (
        .clk               (clk),
        .reset             (reset),
        .address           (oled_addr),
        .read_trigger      (oled_rd),
        .write_trigger     (oled_wr),
        .write_value       (oled_wr_data),
        .mask              (oled_mask),
        .read_value        (oled_rd_data),
        .controller_ready  (oled_ready),
        .oled_sck          (oled_sck),
        .oled_mosi         (oled_mosi),
        .oled_cs_n         (oled_cs_n),
        .oled_dc           (oled_dc),
        .oled_res_n        (oled_res_n),
        .oled_vccen        (oled_vccen),
        .oled_pmoden       (oled_pmoden)
    );

    // --- SD_IO_DEVICE ---
    SD_IO_DEVICE sd_io (
        .clk               (clk),
        .reset             (reset),
        .address           (sd_addr),
        .read_trigger      (sd_rd),
        .write_trigger     (sd_wr),
        .write_value       (sd_wr_data),
        .mask              (sd_mask_w),
        .read_value        (sd_rd_data),
        .controller_ready  (sd_ready),
        .sd_sck            (sd_sck),
        .sd_mosi           (sd_mosi),
        .sd_miso           (sd_miso),
        .sd_cs_n           (sd_cs_n),
        .sd_cd_n           (sd_cd_n)
    );

    // --- FLASH_LOADER (boot from QSPI flash) ---
    FLASH_LOADER #(
        .ADDRESS_SIZE (ADDRESS_SIZE),
        .DATA_SIZE    (DATA_SIZE)
    ) flash_loader (
        .clk              (clk),
        .reset            (reset),
        .ddr_ready        (mig_init_calib_complete),
        .bus_request      (flash_bus_request),
        .bus_granted      (pipeline_paused & flash_active),
        .mc_address       (mc_flash_addr),
        .mc_write_trigger (mc_flash_wr),
        .mc_write_data    (mc_flash_wr_data),
        .mc_write_mask    (mc_flash_mask),
        .mc_ready         (mc_flash_ready),
        .set_pc           (flash_set_pc),
        .new_pc           (flash_new_pc),
        .flash_cs_n       (flash_cs_n),
        .flash_sck        (flash_sck),
        .flash_mosi       (flash_mosi),
        .flash_miso       (flash_miso),
        .active           (flash_active),
        .error            (flash_error)
    );

    // --- MEMORY_CONTROLLER ---
    MEMORY_CONTROLLER #(
        .CHUNK_PART  (CHUNK_PART),
        .DATA_SIZE   (DATA_SIZE),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) mem_ctrl (
        .clk                 (clk),
        .reset               (reset),
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
        .contains_address    (mc_contains_addr)
    );

    // --- RAM_CONTROLLER ---
    RAM_CONTROLLER #(
        .CHUNK_PART  (CHUNK_PART),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) ram_ctrl (
        .clk                    (clk),
        .reset                  (reset),
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

    wire flash_error;
    assign boot_active = flash_active;
    assign boot_error  = flash_error;

endmodule
