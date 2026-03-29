// TOP_V2 — System top with 128-bit bus, MEMORY_CONTROLLER_V2, no blitter.
//
// CPU_PIPELINE_ADAPTER (32-bit) → BUS_32_TO_128 → PERIPHERAL_BUS_V2 (128-bit)
//   → MEMORY_CONTROLLER_V2 (native 128-bit, D-cache + DDR)
//   → I/O devices via BUS_128_TO_32 (UART, OLED, SD, TIMER, SCRATCHPAD)
//
// Blitter disabled (SCRATCHPAD bus master tied off).

module TOP_V2 #(
    parameter CLOCK_FREQ   = 100_000_000,
    parameter BAUD_RATE    = 115_200,
    parameter DEBUG_ENABLE = 1,
    parameter MCV2_DEPTH   = 256,
    parameter MCV2_WAYS    = 1,
    parameter OLED_BRAM_DEPTH = 12288
)(
    input  wire clk,
    input  wire reset,

    // UART
    input  wire uart_rx,
    output wire uart_tx,

    // MIG7 DDR
    input  wire        mig_ui_clk,
    input  wire        mig_init_calib_complete,
    input  wire        mig_app_rdy,
    output wire [27:0] mig_app_addr,
    output wire [2:0]  mig_app_cmd,
    output wire        mig_app_en,
    output wire [127:0] mig_app_wdf_data,
    output wire        mig_app_wdf_wren,
    output wire        mig_app_wdf_end,
    output wire [15:0] mig_app_wdf_mask,
    input  wire        mig_app_wdf_rdy,
    input  wire [127:0] mig_app_rd_data,
    input  wire        mig_app_rd_data_valid,
    input  wire        mig_app_rd_data_end,

    // OLED
    output wire oled_cs_n, oled_mosi, oled_sck, oled_dc,
    output wire oled_res_n, oled_vccen, oled_pmoden,

    // SD
    output wire sd_cs_n, sd_mosi, sd_sck,
    input  wire sd_miso, sd_cd_n,

    // QSPI Flash
    output wire flash_cs_n, flash_mosi, flash_sck,
    input  wire flash_miso,

    // Status
    output wire boot_active, boot_error,
    output wire sd_bus_read, sd_bus_write
);
    localparam ADDRESS_SIZE = 28;
    localparam DATA_SIZE = 32;
    localparam MASK_SIZE = DATA_SIZE / 8;
    localparam BIT_PERIOD = CLOCK_FREQ / BAUD_RATE;

    // ===============================================================
    // CPU ↔ Data Adapter (MEM stage only, no IF)
    // ===============================================================
    wire [31:0] instr_addr, instr_data;
    wire        instr_stall_w;
    wire        cpu_mem_read_en, cpu_mem_write_en;
    wire [31:0] cpu_mem_addr, cpu_mem_write_data, cpu_mem_read_data;
    wire [3:0]  cpu_mem_byte_mask;
    wire        cpu_mem_stall;

    // Data adapter → 32-bit bus
    wire [31:0] data_bus32_addr;
    wire        data_bus32_rd, data_bus32_wr;
    wire [31:0] data_bus32_wr_data, data_bus32_rd_data;
    wire [3:0]  data_bus32_mask;
    wire        data_bus32_ready;
    wire        data_bus32_read_valid;

    // 32-bit data bus (after debug/flash mux)
    wire [31:0] mux32_addr;
    wire        mux32_rd, mux32_wr;
    wire [31:0] mux32_wr_data, mux32_rd_data;
    wire [3:0]  mux32_mask;
    wire        mux32_ready;
    wire        mux32_read_valid;

    // Data path: 32→128 (MEM stage + debug + flash → 128-bit)
    wire [31:0]  data128_addr;
    wire         data128_rd, data128_wr;
    wire [127:0] data128_wr_data, data128_rd_data;
    wire [15:0]  data128_mask;
    wire         data128_ready;
    wire         data128_read_valid;

    // ===============================================================
    // I_CACHE (MCV2 READ_ONLY=1) — instruction fetch
    // ===============================================================
    wire [31:0]  if128_addr;
    wire         if128_rd;

    // I_CACHE miss → external (bus master) → BUS_ARBITER port1
    wire [31:0]  icache_ext_addr;
    wire         icache_ext_rd, icache_ext_wr;
    wire [127:0] icache_ext_wr_data, icache_ext_rd_data;
    wire [15:0]  icache_ext_wr_mask;
    wire         icache_ext_ready;
    wire         icache_ext_read_valid;

    // ===============================================================
    // BUS_ARBITER output → PERIPHERAL_BUS_V2 (128-bit)
    // ===============================================================
    wire [31:0]  bus128_addr;
    wire         bus128_rd, bus128_wr;
    wire [127:0] bus128_wr_data, bus128_rd_data;
    wire [15:0]  bus128_mask;
    wire         bus128_ready;
    wire         bus128_read_valid;

    // ===============================================================
    // PERIPHERAL_BUS_V2 ↔ MEMORY_CONTROLLER_V2
    // ===============================================================
    wire [31:0]  mc_bus_addr;
    wire         mc_bus_rd, mc_bus_wr;
    wire [127:0] mc_bus_wr_data, mc_bus_rd_data;
    wire [15:0]  mc_bus_mask;
    wire         mc_bus_ready;
    wire         mc_bus_read_valid;

    // MCV2 external ↔ RAM_CONTROLLER
    wire [31:0]  mcv2_ext_addr;
    wire         mcv2_ext_rd, mcv2_ext_wr;
    wire [127:0] mcv2_ext_wr_data, mcv2_ext_rd_data;
    wire [15:0]  mcv2_ext_wr_mask;
    wire         mcv2_ext_ready;
    wire         mcv2_ext_read_valid;

    // RAM_CONTROLLER wires
    wire        ram_ready, ram_rd_ready;
    wire        ram_wr_trig, ram_rd_trig;
    wire [127:0] ram_wr_val, ram_rd_val;
    wire [ADDRESS_SIZE-1:0] ram_wr_addr, ram_rd_addr;

    // ===============================================================
    // PERIPHERAL_BUS_V2 ↔ I/O devices (32-bit)
    // ===============================================================
    wire [31:0] io_addr,   oled_addr_w,  sd_addr_w,  timer_addr_w, sp_addr_w;
    wire        io_rd,     oled_rd_w,    sd_rd_w,    timer_rd_w,   sp_rd_w;
    wire        io_wr,     oled_wr_w,    sd_wr_w,    timer_wr_w,   sp_wr_w;
    wire [31:0] io_wr_data, oled_wr_data, sd_wr_data, timer_wr_data, sp_wr_data;
    wire [3:0]  io_mask,   oled_mask_w,  sd_mask_w,  timer_mask_w, sp_mask_w;
    wire [31:0] io_rd_data, oled_rd_data, sd_rd_data, timer_rd_data, sp_rd_data;
    wire        io_ready,  oled_ready,   sd_ready,   timer_ready,  sp_ready;

    // ===============================================================
    // Debug / Flash
    // ===============================================================
    wire        dbg_halt, dbg_set_pc, dbg_bus_request, dbg_step_pipeline;
    wire [31:0] dbg_new_pc, dbg_current_pc, dbg_current_instr;
    wire        dbg_is_halted, pipeline_paused;
    wire [29:0] mc_dbg_addr;
    wire        mc_dbg_rd, mc_dbg_wr;
    wire [31:0] mc_dbg_wr_data;

    wire        flash_bus_request, flash_active, flash_error;
    wire [ADDRESS_SIZE-1:0] mc_flash_addr;
    wire        mc_flash_wr;
    wire [31:0] mc_flash_wr_data;
    wire [MASK_SIZE-1:0] mc_flash_mask;
    wire        flash_set_pc;
    wire [31:0] flash_new_pc;

    wire [7:0] cpu_rx_byte, cpu_tx_byte;
    wire       cpu_rx_valid, cpu_tx_valid, cpu_tx_ready;

    // ===============================================================
    // UART RX/TX infrastructure (same as old TOP)
    // ===============================================================
    wire [7:0] raw_rx_byte; wire raw_rx_valid;
    SIMPLE_UART_RX #(.CLOCK_FREQ(CLOCK_FREQ), .BAUD_RATE(BAUD_RATE)) uart_in (
        .clk(clk), .reset(reset), .rx(uart_rx),
        .rx_data(raw_rx_byte), .rx_valid(raw_rx_valid)
    );

    wire [7:0] rx_fifo_data; wire rx_fifo_empty, rx_fifo_full;
    reg rx_fifo_rd_en;
    UART_FIFO #(.DEPTH(4)) rx_fifo (
        .clk(clk), .reset(reset),
        .wr_data(raw_rx_byte), .wr_en(raw_rx_valid), .full(rx_fifo_full),
        .rd_data(rx_fifo_data), .rd_en(rx_fifo_rd_en), .empty(rx_fifo_empty)
    );

    wire dbg_rx_ready;
    wire fifo_head_is_fd = (rx_fifo_data == 8'hFD);
    reg rx_fifo_valid_r; reg [7:0] rx_fifo_captured;
    wire [7:0] uart_rx_byte = rx_fifo_captured;
    wire uart_rx_valid = rx_fifo_valid_r;

    always @(posedge clk) begin
        if (reset) begin
            rx_fifo_rd_en <= 0; rx_fifo_valid_r <= 0; rx_fifo_captured <= 0;
        end else begin
            rx_fifo_valid_r <= 0; rx_fifo_rd_en <= 0;
            if (!rx_fifo_empty && !rx_fifo_rd_en && !rx_fifo_valid_r
                && (dbg_rx_ready || fifo_head_is_fd))
                rx_fifo_rd_en <= 1;
            if (rx_fifo_rd_en) begin
                rx_fifo_captured <= rx_fifo_data;
                rx_fifo_valid_r <= 1;
            end
        end
    end

    wire raw_tx_ready; wire [7:0] raw_tx_byte; wire raw_tx_valid;
    I_O_OUTPUT_CONTROLLER #(
        .CLOCK_FREQ(CLOCK_FREQ), .BAUD_RATE(BAUD_RATE), .BIT_PERIOD(BIT_PERIOD)
    ) uart_out (
        .clk(clk), .reset(reset),
        .io_output_value(raw_tx_byte), .io_output_trigger(raw_tx_valid),
        .io_output_ready_trigger(raw_tx_ready), .RXD(uart_tx)
    );

    wire [7:0] tx_fifo_data; wire tx_fifo_empty, tx_fifo_full;
    reg tx_fifo_rd_en;
    wire [7:0] uart_tx_byte; wire uart_tx_valid;
    wire uart_tx_ready = !tx_fifo_full;

    UART_FIFO #(.DEPTH(4)) tx_fifo (
        .clk(clk), .reset(reset),
        .wr_data(uart_tx_byte), .wr_en(uart_tx_valid), .full(tx_fifo_full),
        .rd_data(tx_fifo_data), .rd_en(tx_fifo_rd_en), .empty(tx_fifo_empty)
    );

    reg tx_fifo_sending; reg [7:0] tx_fifo_captured;
    always @(posedge clk) begin
        if (reset) begin
            tx_fifo_rd_en <= 0; tx_fifo_sending <= 0; tx_fifo_captured <= 0;
        end else begin
            tx_fifo_rd_en <= 0; tx_fifo_sending <= 0;
            if (!tx_fifo_empty && raw_tx_ready && !tx_fifo_rd_en && !tx_fifo_sending)
                tx_fifo_rd_en <= 1;
            if (tx_fifo_rd_en) begin
                tx_fifo_captured <= tx_fifo_data;
                tx_fifo_sending <= 1;
            end
        end
    end
    assign raw_tx_byte = tx_fifo_captured;
    assign raw_tx_valid = tx_fifo_sending;

    // ===============================================================
    // DEBUG_CONTROLLER
    // ===============================================================
    wire mc_dbg_ready = (!flash_active & pipeline_paused) ? mux32_ready : 1'b0;
    wire [31:0] mc_dbg_rd_data = mux32_rd_data;

    DEBUG_CONTROLLER #(.DEBUG_ENABLE(DEBUG_ENABLE), .ADDRESS_SIZE(30)) dbg_ctrl (
        .clk(clk), .reset(reset),
        .rx_byte(uart_rx_byte), .rx_valid(uart_rx_valid),
        .tx_byte(uart_tx_byte), .tx_valid(uart_tx_valid), .tx_ready(uart_tx_ready),
        .dbg_halt(dbg_halt), .dbg_set_pc(dbg_set_pc), .dbg_new_pc(dbg_new_pc),
        .dbg_is_halted(dbg_is_halted),
        .dbg_current_pc(dbg_current_pc), .dbg_current_instr(dbg_current_instr),
        .dbg_bus_request(dbg_bus_request), .dbg_step_pipeline(dbg_step_pipeline),
        .dbg_bus_granted(pipeline_paused),
        .mc_dbg_address(mc_dbg_addr), .mc_dbg_read_trigger(mc_dbg_rd),
        .mc_dbg_write_trigger(mc_dbg_wr), .mc_dbg_write_data(mc_dbg_wr_data),
        .mc_dbg_read_data(mc_dbg_rd_data), .mc_dbg_ready(mc_dbg_ready),
        .cpu_rx_byte(cpu_rx_byte), .cpu_rx_valid(cpu_rx_valid),
        .cpu_tx_byte(cpu_tx_byte), .cpu_tx_valid(cpu_tx_valid),
        .cpu_tx_ready(cpu_tx_ready), .rx_ready(dbg_rx_ready)
    );

    // ===============================================================
    // CPU
    // ===============================================================
    wire combined_set_pc = flash_set_pc | dbg_set_pc;
    wire [31:0] combined_new_pc = flash_set_pc ? flash_new_pc : dbg_new_pc;

    CPU_SINGLE_CYCLE #(.DEBUG_ENABLE(DEBUG_ENABLE)) cpu (
        .clk(clk), .reset(reset),
        .instr_addr(instr_addr), .instr_data(instr_data),
        .mem_read_en(cpu_mem_read_en), .mem_write_en(cpu_mem_write_en),
        .mem_addr(cpu_mem_addr), .mem_write_data(cpu_mem_write_data),
        .mem_byte_mask(cpu_mem_byte_mask), .mem_read_data(cpu_mem_read_data),
        .mem_stall(cpu_mem_stall), .instr_stall(instr_stall_w),
        .dbg_set_pc(combined_set_pc), .dbg_new_pc(combined_new_pc),
        .dbg_is_halted(dbg_is_halted),
        .dbg_current_pc(dbg_current_pc), .dbg_current_instr(dbg_current_instr)
    );

    // ===============================================================
    // I_CACHE: CPU IF → IF_ADAPTER → BUS_32_TO_128 → MCV2(RO=1)
    // ===============================================================
    // IF adapter: generates read pulses when PC changes
    wire [31:0] if32_addr;
    wire        if32_rd;
    wire [31:0] if32_rd_data;
    wire        if32_ready;
    wire        if32_rd_valid;

    CPU_IF_ADAPTER if_adapter (
        .clk(clk), .reset(reset),
        .instr_addr(instr_addr), .instr_data(instr_data),
        .instr_stall(instr_stall_w),
        .bus_address(if32_addr), .bus_read(if32_rd),
        .bus_read_data(if32_rd_data),
        .bus_ready(if32_ready), .bus_read_valid(if32_rd_valid),
        .flush(combined_set_pc)
    );

    // 32→128 converter for I_CACHE
    wire         icache_bus_ready;
    wire [127:0] icache_bus_rd_data;
    wire         icache_bus_rd_valid;

    BUS_32_TO_128 if_conv (
        .cpu_address   (if32_addr),
        .cpu_read      (if32_rd),
        .cpu_write     (1'b0),
        .cpu_write_data(32'b0),
        .cpu_write_mask(4'b0),
        .cpu_read_data (if32_rd_data),
        .cpu_ready     (if32_ready),
        .cpu_read_valid(if32_rd_valid),
        .bus_address   (if128_addr),
        .bus_read      (if128_rd),
        .bus_write     (),
        .bus_write_data(),
        .bus_write_mask(),
        .bus_ready     (icache_bus_ready),
        .bus_read_data (icache_bus_rd_data),
        .bus_read_valid(icache_bus_rd_valid)
    );

    MEMORY_CONTROLLER_V2 #(
        .DEPTH(MCV2_DEPTH), .WAYS(MCV2_WAYS), .READ_ONLY(1)
    ) icache (
        .clk(clk), .reset(reset || combined_set_pc),  // flush I_CACHE on PC change
        // Upstream: from IF converter
        .bus_address(if128_addr), .bus_read(if128_rd), .bus_write(1'b0),
        .bus_write_data(128'b0), .bus_write_mask(16'b0),
        .bus_ready(icache_bus_ready), .bus_read_data(icache_bus_rd_data),
        .bus_read_valid(icache_bus_rd_valid),
        // Downstream: miss → BUS_ARBITER port1
        .external_address(icache_ext_addr), .external_read(icache_ext_rd),
        .external_write(icache_ext_wr), .external_write_data(icache_ext_wr_data),
        .external_write_mask(icache_ext_wr_mask),
        .external_ready(icache_ext_ready), .external_read_data(icache_ext_rd_data),
        .external_read_valid(icache_ext_read_valid)
    );

    // ===============================================================
    // CPU_DATA_ADAPTER_V2 (MEM stage only)
    // ===============================================================
    CPU_DATA_ADAPTER_V2 data_adapter (
        .clk(clk), .reset(reset),
        .mem_read_en(cpu_mem_read_en), .mem_write_en(cpu_mem_write_en),
        .mem_addr(cpu_mem_addr), .mem_write_data(cpu_mem_write_data),
        .mem_byte_mask(cpu_mem_byte_mask), .mem_read_data(cpu_mem_read_data),
        .mem_stall(cpu_mem_stall),
        .bus_address(data_bus32_addr), .bus_read(data_bus32_rd),
        .bus_write(data_bus32_wr), .bus_write_data(data_bus32_wr_data),
        .bus_write_mask(data_bus32_mask), .bus_read_data(data_bus32_rd_data),
        .bus_ready(data_bus32_ready),
        .flush(combined_set_pc),
        .pause(dbg_bus_request | flash_bus_request),
        .paused(pipeline_paused), .step(dbg_step_pipeline)
    );

    // ===============================================================
    // 32-bit Bus Mux: flash > debug > data_adapter
    // ===============================================================
    wire mc_flash_ready = flash_active ? mux32_ready : 1'b0;

    assign mux32_addr    = flash_active    ? {4'b0, mc_flash_addr[27:0]} :
                           pipeline_paused ? {2'b0, mc_dbg_addr}         :
                                             data_bus32_addr;
    assign mux32_rd      = flash_active    ? 1'b0           :
                           pipeline_paused ? mc_dbg_rd       : data_bus32_rd;
    assign mux32_wr      = flash_active    ? mc_flash_wr     :
                           pipeline_paused ? mc_dbg_wr        : data_bus32_wr;
    assign mux32_wr_data = flash_active    ? mc_flash_wr_data :
                           pipeline_paused ? mc_dbg_wr_data   : data_bus32_wr_data;
    assign mux32_mask    = flash_active    ? mc_flash_mask          :
                           pipeline_paused ? {MASK_SIZE{1'b1}}     : data_bus32_mask;

    assign data_bus32_rd_data = mux32_rd_data;
    assign data_bus32_ready   = (!flash_active & !pipeline_paused) ? mux32_ready : 1'b0;

    // ===============================================================
    // BUS_32_TO_128: data path 32→128 (MEM + debug + flash)
    // ===============================================================
    BUS_32_TO_128 data_conv (
        .cpu_address   (mux32_addr),
        .cpu_read      (mux32_rd),
        .cpu_write     (mux32_wr),
        .cpu_write_data(mux32_wr_data),
        .cpu_write_mask(mux32_mask),
        .cpu_read_data (mux32_rd_data),
        .cpu_ready     (mux32_ready),
        .cpu_read_valid(mux32_read_valid),
        .bus_address   (data128_addr),
        .bus_read      (data128_rd),
        .bus_write     (data128_wr),
        .bus_write_data(data128_wr_data),
        .bus_write_mask(data128_mask),
        .bus_ready     (data128_ready),
        .bus_read_data (data128_rd_data),
        .bus_read_valid(data128_read_valid)
    );

    // ===============================================================
    // BUS_ARBITER: data (port0, priority) + I_CACHE miss (port1)
    // ===============================================================
    BUS_ARBITER arbiter (
        .clk(clk), .reset(reset),
        // Port 0: data path (MEM + debug + flash)
        .p0_address(data128_addr), .p0_read(data128_rd), .p0_write(data128_wr),
        .p0_write_data(data128_wr_data), .p0_write_mask(data128_mask),
        .p0_ready(data128_ready), .p0_read_data(data128_rd_data),
        .p0_read_valid(data128_read_valid),
        // Port 1: I_CACHE miss (read-only)
        .p1_address(icache_ext_addr), .p1_read(icache_ext_rd), .p1_write(icache_ext_wr),
        .p1_write_data(icache_ext_wr_data), .p1_write_mask(icache_ext_wr_mask),
        .p1_ready(icache_ext_ready), .p1_read_data(icache_ext_rd_data),
        .p1_read_valid(icache_ext_read_valid),
        // Downstream → PERIPHERAL_BUS_V2
        .bus_address(bus128_addr), .bus_read(bus128_rd), .bus_write(bus128_wr),
        .bus_write_data(bus128_wr_data), .bus_write_mask(bus128_mask),
        .bus_ready(bus128_ready), .bus_read_data(bus128_rd_data),
        .bus_read_valid(bus128_read_valid)
    );

    // ===============================================================
    // PERIPHERAL_BUS_V2 (128-bit address decoder)
    // ===============================================================
    PERIPHERAL_BUS_V2 pbus (
        .clk(clk), .reset(reset),
        // Upstream 128-bit
        .bus_address(bus128_addr), .bus_read(bus128_rd), .bus_write(bus128_wr),
        .bus_write_data(bus128_wr_data), .bus_write_mask(bus128_mask),
        .bus_ready(bus128_ready), .bus_read_data(bus128_rd_data),
        .bus_read_valid(bus128_read_valid),
        // MEMORY_CONTROLLER_V2 (native 128-bit)
        .mc_bus_address(mc_bus_addr), .mc_bus_read(mc_bus_rd), .mc_bus_write(mc_bus_wr),
        .mc_bus_write_data(mc_bus_wr_data), .mc_bus_write_mask(mc_bus_mask),
        .mc_bus_ready(mc_bus_ready), .mc_bus_read_data(mc_bus_rd_data),
        .mc_bus_read_valid(mc_bus_read_valid),
        // I/O devices (32-bit)
        .uart_address(io_addr), .uart_read(io_rd), .uart_write(io_wr),
        .uart_write_data(io_wr_data), .uart_write_mask(io_mask),
        .uart_read_data(io_rd_data), .uart_ready(io_ready),
        .oled_address(oled_addr_w), .oled_read(oled_rd_w), .oled_write(oled_wr_w),
        .oled_write_data(oled_wr_data), .oled_write_mask(oled_mask_w),
        .oled_read_data(oled_rd_data), .oled_ready(oled_ready),
        .sd_address(sd_addr_w), .sd_read(sd_rd_w), .sd_write(sd_wr_w),
        .sd_write_data(sd_wr_data), .sd_write_mask(sd_mask_w),
        .sd_read_data(sd_rd_data), .sd_ready(sd_ready),
        .timer_address(timer_addr_w), .timer_read(timer_rd_w), .timer_write(timer_wr_w),
        .timer_write_data(timer_wr_data), .timer_write_mask(timer_mask_w),
        .timer_read_data(timer_rd_data), .timer_ready(timer_ready),
        .sp_address(sp_addr_w), .sp_read(sp_rd_w), .sp_write(sp_wr_w),
        .sp_write_data(sp_wr_data), .sp_write_mask(sp_mask_w),
        .sp_read_data(sp_rd_data), .sp_ready(sp_ready)
    );

    // ===============================================================
    // MEMORY_CONTROLLER_V2 (D-cache + DDR)
    // ===============================================================
    MEMORY_CONTROLLER_V2 #(
        .DEPTH(MCV2_DEPTH), .WAYS(MCV2_WAYS), .READ_ONLY(0)
    ) mem_ctrl (
        .clk(clk), .reset(reset),
        // Bus slave (from PERIPHERAL_BUS_V2)
        .bus_address(mc_bus_addr), .bus_read(mc_bus_rd), .bus_write(mc_bus_wr),
        .bus_write_data(mc_bus_wr_data), .bus_write_mask(mc_bus_mask),
        .bus_ready(mc_bus_ready), .bus_read_data(mc_bus_rd_data),
        .bus_read_valid(mc_bus_read_valid),
        // Bus master (to RAM_CONTROLLER)
        .external_address(mcv2_ext_addr), .external_read(mcv2_ext_rd),
        .external_write(mcv2_ext_wr), .external_write_data(mcv2_ext_wr_data),
        .external_write_mask(mcv2_ext_wr_mask),
        .external_ready(mcv2_ext_ready), .external_read_data(mcv2_ext_rd_data),
        .external_read_valid(mcv2_ext_read_valid)
    );

    // ===============================================================
    // MCV2 external → RAM_CONTROLLER adapter
    // ===============================================================
    assign ram_rd_trig = mcv2_ext_rd;
    assign ram_rd_addr = mcv2_ext_addr[ADDRESS_SIZE-1:0];
    assign ram_wr_trig = mcv2_ext_wr;
    assign ram_wr_addr = mcv2_ext_addr[ADDRESS_SIZE-1:0];
    assign ram_wr_val  = mcv2_ext_wr_data;
    assign mcv2_ext_ready      = ram_ready;
    assign mcv2_ext_rd_data    = ram_rd_val;
    assign mcv2_ext_read_valid = ram_rd_ready;

    // ===============================================================
    // RAM_CONTROLLER (DDR3 via MIG7)
    // ===============================================================
    RAM_CONTROLLER #(.CHUNK_PART(128), .ADDRESS_SIZE(ADDRESS_SIZE)) ram_ctrl (
        .clk(clk), .reset(reset),
        .controller_ready(ram_ready), .error(),
        .write_trigger(ram_wr_trig), .write_value(ram_wr_val), .write_address(ram_wr_addr),
        .read_trigger(ram_rd_trig), .read_value(ram_rd_val),
        .read_address(ram_rd_addr), .read_value_ready(ram_rd_ready),
        .led0(),
        .mig_app_addr(mig_app_addr), .mig_app_cmd(mig_app_cmd), .mig_app_en(mig_app_en),
        .mig_app_wdf_data(mig_app_wdf_data), .mig_app_wdf_end(mig_app_wdf_end),
        .mig_app_wdf_mask(mig_app_wdf_mask), .mig_app_wdf_wren(mig_app_wdf_wren),
        .mig_app_wdf_rdy(mig_app_wdf_rdy),
        .mig_app_rd_data(mig_app_rd_data), .mig_app_rd_data_end(mig_app_rd_data_end),
        .mig_app_rd_data_valid(mig_app_rd_data_valid), .mig_app_rdy(mig_app_rdy),
        .mig_ui_clk(mig_ui_clk), .mig_init_calib_complete(mig_init_calib_complete)
    );

    // ===============================================================
    // I/O Devices (32-bit, unchanged)
    // ===============================================================

    UART_IO_DEVICE uart_io (
        .clk(clk), .reset(reset),
        .address(io_addr[27:0]), .read_trigger(io_rd), .write_trigger(io_wr),
        .write_value(io_wr_data), .mask(io_mask), .read_value(io_rd_data),
        .controller_ready(io_ready),
        .cpu_tx_byte(cpu_tx_byte), .cpu_tx_valid(cpu_tx_valid), .cpu_tx_ready(cpu_tx_ready),
        .cpu_rx_byte(cpu_rx_byte), .cpu_rx_valid(cpu_rx_valid)
    );

    OLED_FB_DEVICE #(.BRAM_DEPTH(OLED_BRAM_DEPTH)) oled_fb (
        .clk(clk), .reset(reset),
        .address(oled_addr_w[27:0]), .read_trigger(oled_rd_w), .write_trigger(oled_wr_w),
        .write_value(oled_wr_data), .mask(oled_mask_w), .read_value(oled_rd_data),
        .controller_ready(oled_ready),
        .oled_sck(oled_sck), .oled_mosi(oled_mosi), .oled_cs_n(oled_cs_n),
        .oled_dc(oled_dc), .oled_res_n(oled_res_n),
        .oled_vccen(oled_vccen), .oled_pmoden(oled_pmoden)
    );

    SD_IO_DEVICE sd_io (
        .clk(clk), .reset(reset),
        .address(sd_addr_w[27:0]), .read_trigger(sd_rd_w), .write_trigger(sd_wr_w),
        .write_value(sd_wr_data), .mask(sd_mask_w), .read_value(sd_rd_data),
        .controller_ready(sd_ready),
        .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .sd_cs_n(sd_cs_n), .sd_cd_n(sd_cd_n)
    );

    TIMER_DEVICE #(.CLOCK_FREQ(CLOCK_FREQ)) timer_dev (
        .clk(clk), .reset(reset),
        .address(timer_addr_w[27:0]), .read_trigger(timer_rd_w),
        .read_value(timer_rd_data), .controller_ready(timer_ready)
    );

    SCRATCHPAD scratchpad (
        .clk(clk), .reset(reset),
        .address(sp_addr_w[27:0]), .read_trigger(sp_rd_w), .write_trigger(sp_wr_w),
        .write_value(sp_wr_data), .mask(sp_mask_w), .read_value(sp_rd_data),
        .controller_ready(sp_ready),
        // Blitter disabled
        .blitter_active(), .blitter_bus_addr(), .blitter_bus_rd(),
        .blitter_bus_wr(), .blitter_bus_wr_data(), .blitter_bus_mask(),
        .blitter_bus_data(32'b0), .blitter_bus_ready(1'b0)
    );

    // ===============================================================
    // FLASH_LOADER
    // ===============================================================
    FLASH_LOADER #(.ADDRESS_SIZE(ADDRESS_SIZE), .DATA_SIZE(DATA_SIZE)) flash_loader (
        .clk(clk), .reset(reset),
        .ddr_ready(mig_init_calib_complete),
        .bus_request(flash_bus_request),
        .bus_granted(pipeline_paused & flash_active),
        .mc_address(mc_flash_addr), .mc_write_trigger(mc_flash_wr),
        .mc_write_data(mc_flash_wr_data), .mc_write_mask(mc_flash_mask),
        .mc_ready(mc_flash_ready),
        .set_pc(flash_set_pc), .new_pc(flash_new_pc),
        .flash_cs_n(flash_cs_n), .flash_sck(flash_sck),
        .flash_mosi(flash_mosi), .flash_miso(flash_miso),
        .active(flash_active), .error(flash_error)
    );

    assign boot_active  = flash_active;
    assign boot_error   = flash_error;
    assign sd_bus_read  = sd_rd_w;
    assign sd_bus_write = sd_wr_w;

endmodule
