// FPGA top-level wrapper: connects TOP (RISC-V system) with MIG 7 Series IP.
//
// External pins:
//   sys_clk_i  — 100 MHz single-ended clock (E3)
//   uart_rx/tx — FTDI UART
//   ddr3_*     — DDR3L memory (MT41K128M16JT-125)
//
// Clocking:
//   clk_wiz_0: 100 MHz → clk_out1 (200 MHz), clk_out2 (81.25 MHz), clk_out3 (325 MHz)
//   clk_out1 (200 MHz)  → MIG clk_ref_i (IDELAYCTRL reference)
//   clk_out2 (81.25 MHz) → TOP.clk (CPU, UART, caches)
//   clk_out3 (325 MHz)  → MIG sys_clk_i (DDR PHY clock source)
//   ui_clk (~81.25 MHz) → TOP.mig_ui_clk (RAM_CONTROLLER MIG side)

module FPGA_TOP (
    // System clock (100 MHz, pin E3)
    input  wire        sys_clk_i,

    // UART
    input  wire        uart_rx,
    output wire        uart_tx,

    // Debug LEDs
    output wire [3:0]  led,

    // DDR3 physical pins (directly to MIG)
    inout  wire [15:0] ddr3_dq,
    inout  wire [1:0]  ddr3_dqs_n,
    inout  wire [1:0]  ddr3_dqs_p,
    output wire [13:0] ddr3_addr,
    output wire [2:0]  ddr3_ba,
    output wire        ddr3_ras_n,
    output wire        ddr3_cas_n,
    output wire        ddr3_we_n,
    output wire        ddr3_reset_n,
    output wire [0:0]  ddr3_ck_p,
    output wire [0:0]  ddr3_ck_n,
    output wire [0:0]  ddr3_cke,
    output wire [0:0]  ddr3_cs_n,
    output wire [1:0]  ddr3_dm,
    output wire [0:0]  ddr3_odt,

    // PMOD JA — PmodOLEDrgb
    output wire        ja_oled_cs_n,    // JA[0] pin 1
    output wire        ja_oled_mosi,    // JA[1] pin 2
    // JA[2] pin 3 = NC
    output wire        ja_oled_sck,     // JA[3] pin 4
    output wire        ja_oled_dc,      // JA[4] pin 7
    output wire        ja_oled_res_n,   // JA[5] pin 8
    output wire        ja_oled_vccen,   // JA[6] pin 9
    output wire        ja_oled_pmoden,  // JA[7] pin 10

    // PMOD JC — PmodMicroSD
    output wire        jc_sd_cs_n,     // JC[0] pin 1
    output wire        jc_sd_mosi,     // JC[1] pin 2
    input  wire        jc_sd_miso,     // JC[2] pin 3
    output wire        jc_sd_sck,      // JC[3] pin 4
    // JC[4] pin 7 = DAT1 (unused in SPI)
    // JC[5] pin 8 = DAT2 (unused in SPI)
    input  wire        jc_sd_cd_n,     // JC[6] pin 9  card detect
    // JC[7] pin 10 = NC

    // Onboard QSPI Flash (for FLASH_LOADER boot)
    output wire        flash_cs_n,     // L13 (FCS_B)
    output wire        flash_mosi,     // K17 (DQ0)
    input  wire        flash_miso,     // K18 (DQ1)
    output wire        flash_sck,      // L16
    output wire        flash_wp_n,     // L14 (DQ2, tie high)
    output wire        flash_hold_n,   // M14 (DQ3, tie high)

    // RGB LED0 — boot status indicator
    output wire        led0_r,
    output wire        led0_g,
    output wire        led0_b,

    // RGB LED1 — SD activity (R=write, G=read, B=idle)
    output wire        led1_r,
    output wire        led1_g,
    output wire        led1_b
);

    // ---------------------------------------------------------------
    // Clocking Wizard: 100 MHz → 200 MHz + 81.25 MHz + 325 MHz
    // ---------------------------------------------------------------
    wire clk_200;           // MIG IDELAYCTRL reference
    wire clk_cpu;           // CPU clock (~81.25 MHz)
    wire clk_325;           // MIG DDR PHY clock
    wire clk_wiz_locked;

    clk_wiz_0 u_clk_wiz (
        .clk_in1  (sys_clk_i),
        .clk_out1 (clk_200),
        .clk_out2 (clk_cpu),
        .clk_out3 (clk_325),
        .locked   (clk_wiz_locked),
        .reset    (1'b0)
    );

    // ---------------------------------------------------------------
    // MIG ↔ TOP interconnect wires
    // ---------------------------------------------------------------
    wire        ui_clk;
    wire        ui_clk_sync_rst;
    wire        init_calib_complete;

    wire [27:0]  app_addr;
    wire [2:0]   app_cmd;
    wire         app_en;
    wire [127:0] app_wdf_data;
    wire         app_wdf_end;
    wire [15:0]  app_wdf_mask;
    wire         app_wdf_wren;
    wire         app_wdf_rdy;
    wire [127:0] app_rd_data;
    wire         app_rd_data_end;
    wire         app_rd_data_valid;
    wire         app_rdy;

    // ---------------------------------------------------------------
    // MIG 7 Series IP (both clocks from clk_wiz, No Buffer mode)
    // ---------------------------------------------------------------
    mig_7series_0 u_mig (
        // DDR3 physical
        .ddr3_dq             (ddr3_dq),
        .ddr3_dqs_n          (ddr3_dqs_n),
        .ddr3_dqs_p          (ddr3_dqs_p),
        .ddr3_addr           (ddr3_addr),
        .ddr3_ba             (ddr3_ba),
        .ddr3_ras_n          (ddr3_ras_n),
        .ddr3_cas_n          (ddr3_cas_n),
        .ddr3_we_n           (ddr3_we_n),
        .ddr3_reset_n        (ddr3_reset_n),
        .ddr3_ck_p           (ddr3_ck_p),
        .ddr3_ck_n           (ddr3_ck_n),
        .ddr3_cke            (ddr3_cke),
        .ddr3_cs_n           (ddr3_cs_n),
        .ddr3_dm             (ddr3_dm),
        .ddr3_odt            (ddr3_odt),

        // Clock & reset (No Buffer mode — clocks from clk_wiz)
        .sys_clk_i           (clk_325),
        .clk_ref_i           (clk_200),
        .sys_rst             (~clk_wiz_locked),  // hold reset until clk_wiz locked

        // User interface clock
        .ui_clk              (ui_clk),
        .ui_clk_sync_rst     (ui_clk_sync_rst),
        .init_calib_complete (init_calib_complete),

        // Application interface
        .app_addr            (app_addr),
        .app_cmd             (app_cmd),
        .app_en              (app_en),
        .app_wdf_data        (app_wdf_data),
        .app_wdf_end         (app_wdf_end),
        .app_wdf_mask        (app_wdf_mask),
        .app_wdf_wren        (app_wdf_wren),
        .app_wdf_rdy         (app_wdf_rdy),
        .app_rd_data         (app_rd_data),
        .app_rd_data_end     (app_rd_data_end),
        .app_rd_data_valid   (app_rd_data_valid),
        .app_rdy             (app_rdy),

        // Unused requests — tie low
        .app_sr_req          (1'b0),
        .app_ref_req         (1'b0),
        .app_zq_req          (1'b0),
        .app_sr_active       (),
        .app_ref_ack         (),
        .app_zq_ack          (),

        // Temperature (not using XADC, tie to 0)
        .device_temp_i       (12'b0),
        .device_temp         ()
    );

    // ---------------------------------------------------------------
    // Reset: wait for clk_wiz to lock
    // (MIG calibration is handled by RAM_CONTROLLER via init_calib_complete)
    // ---------------------------------------------------------------
    wire sys_reset = ~clk_wiz_locked;

    // QSPI flash WP# and HOLD# — inactive (active low)
    assign flash_wp_n   = 1'b1;
    assign flash_hold_n = 1'b1;

    // ---------------------------------------------------------------
    // TOP (RISC-V system)
    // Two clock domains:
    //   clk        = clk_cpu (81.25 MHz) — CPU, UART, caches
    //   mig_ui_clk = ui_clk (~81.25 MHz) — RAM_CONTROLLER MIG side
    // ---------------------------------------------------------------
    TOP #(
        .CLOCK_FREQ   (81_250_000),
        .BAUD_RATE    (115_200),
        .CHUNK_PART   (128),
        .ADDRESS_SIZE (28),
        .DATA_SIZE    (32),
        .DEBUG_ENABLE (1)
    ) u_top (
        .clk                    (clk_cpu),
        .reset                  (sys_reset),

        .uart_rx                (uart_rx),
        .uart_tx                (uart_tx),

        // MIG user interface
        .mig_ui_clk             (ui_clk),
        .mig_init_calib_complete(init_calib_complete),
        .mig_app_rdy            (app_rdy),
        .mig_app_addr           (app_addr),
        .mig_app_cmd            (app_cmd),
        .mig_app_en             (app_en),
        .mig_app_wdf_data       (app_wdf_data),
        .mig_app_wdf_wren       (app_wdf_wren),
        .mig_app_wdf_end        (app_wdf_end),
        .mig_app_wdf_mask       (app_wdf_mask),
        .mig_app_wdf_rdy        (app_wdf_rdy),
        .mig_app_rd_data        (app_rd_data),
        .mig_app_rd_data_valid  (app_rd_data_valid),
        .mig_app_rd_data_end    (app_rd_data_end),

        // OLED
        .oled_cs_n              (ja_oled_cs_n),
        .oled_mosi              (ja_oled_mosi),
        .oled_sck               (ja_oled_sck),
        .oled_dc                (ja_oled_dc),
        .oled_res_n             (ja_oled_res_n),
        .oled_vccen             (ja_oled_vccen),
        .oled_pmoden            (ja_oled_pmoden),

        // SD
        .sd_cs_n                (jc_sd_cs_n),
        .sd_mosi                (jc_sd_mosi),
        .sd_miso                (jc_sd_miso),
        .sd_sck                 (jc_sd_sck),
        .sd_cd_n                (jc_sd_cd_n),

        // QSPI Flash
        .flash_cs_n             (flash_cs_n),
        .flash_mosi             (flash_mosi),
        .flash_miso             (flash_miso),
        .flash_sck              (flash_sck),

        // Boot status
        .boot_active            (boot_active_w),
        .boot_error             (boot_error_w),

        .sd_bus_read            (sd_bus_read_w),
        .sd_bus_write           (sd_bus_write_w)
    );

    wire sd_bus_read_w;
    wire sd_bus_write_w;

    // ---------------------------------------------------------------
    // Boot status wire
    // ---------------------------------------------------------------
    wire boot_active_w;
    wire boot_error_w;

    // ---------------------------------------------------------------
    // RGB LED0 — boot status
    //   Yellow   = waiting for DDR (active, calib not done)
    //   Blue     = loading from flash (active, DDR ready)
    //   Green    = done, CPU running
    //   Red      = error (bad magic / no payload)
    // ---------------------------------------------------------------
    assign led0_r = boot_error_w | (boot_active_w & ~init_calib_complete & ~boot_error_w);
    assign led0_g = (~boot_error_w & ~boot_active_w) | (boot_active_w & ~init_calib_complete & ~boot_error_w);
    assign led0_b = boot_active_w & init_calib_complete & ~boot_error_w;

    // ---------------------------------------------------------------
    // Debug LEDs
    //   led[0] = clk_cpu heartbeat (blink ~1 Hz)
    //   led[1] = clk_wiz_locked
    //   led[2] = init_calib_complete (MIG DDR3 ready)
    //   led[3] = ~sys_reset (system running)
    // ---------------------------------------------------------------
    reg [25:0] heartbeat_cnt;
    always @(posedge clk_cpu) begin
        if (sys_reset)
            heartbeat_cnt <= 0;
        else
            heartbeat_cnt <= heartbeat_cnt + 1;
    end

    assign led[0] = ~boot_active_w & ~boot_error_w;  // горит когда загрузка завершена
    assign led[1] = clk_wiz_locked;
    assign led[2] = init_calib_complete;
    assign led[3] = ~sys_reset;

    // ---------------------------------------------------------------
    // RGB LED1 — SD activity (вспышки 0.05с = ~4M тактов при 81.25 MHz)
    //   Green  = SD read access
    //   Red    = SD write access
    //   Off    = idle
    // ---------------------------------------------------------------
    localparam FLASH_TICKS = 81_250_000 / 20;  // 0.05с = 4_062_500 тактов

    reg [21:0] sd_rd_timer;  // 22 бит хватает для ~4M
    reg [21:0] sd_wr_timer;

    always @(posedge clk_cpu) begin
        if (sys_reset) begin
            sd_rd_timer <= 0;
            sd_wr_timer <= 0;
        end else begin
            // SD read flash
            if (sd_bus_read_w)
                sd_rd_timer <= FLASH_TICKS[21:0];
            else if (sd_rd_timer != 0)
                sd_rd_timer <= sd_rd_timer - 1;

            // SD write flash
            if (sd_bus_write_w)
                sd_wr_timer <= FLASH_TICKS[21:0];
            else if (sd_wr_timer != 0)
                sd_wr_timer <= sd_wr_timer - 1;
        end
    end

    assign led1_g = (sd_rd_timer != 0);  // зелёный — чтение SD
    assign led1_r = (sd_wr_timer != 0);  // красный — запись SD
    assign led1_b = 1'b0;

endmodule
