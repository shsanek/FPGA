// FPGA top-level wrapper: connects TOP (RISC-V system) with MIG 7 Series IP.
//
// External pins:
//   sys_clk_i  — 100 MHz single-ended clock (E3)
//   uart_rx/tx — FTDI UART
//   ddr3_*     — DDR3L memory (MT41K128M16JT-125)
//
// Clocking (two clock domains):
//   sys_clk_i (100 MHz) — CPU and all logic in TOP (via BUFG)
//   ui_clk (~81.25 MHz) — MIG user interface, used by RAM_CONTROLLER mig_ui_clk domain

module FPGA_TOP (
    // System clock (100 MHz, pin E3)
    input  wire        sys_clk_i,

    // UART
    input  wire        uart_rx,
    output wire        uart_tx,

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
    output wire [0:0]  ddr3_odt
);

    // ---------------------------------------------------------------
    // 200 MHz reference clock for MIG IDELAYCTRL
    // PLL: 100 MHz × 10 / 5 = 200 MHz (VCO = 1000 MHz)
    // ---------------------------------------------------------------
    wire clk_200_unbuf;
    wire clk_200;
    wire pll_locked;
    wire pll_fb;

    PLLE2_BASE #(
        .CLKFBOUT_MULT  (10),       // VCO = 100 × 10 = 1000 MHz
        .CLKOUT0_DIVIDE (5),        // 1000 / 5 = 200 MHz
        .CLKIN1_PERIOD   (10.0),    // 100 MHz = 10 ns
        .DIVCLK_DIVIDE  (1)
    ) pll_refclk (
        .CLKOUT0  (clk_200_unbuf),
        .CLKFBOUT (pll_fb),
        .CLKIN1   (sys_clk_i),
        .CLKFBIN  (pll_fb),
        .PWRDWN   (1'b0),
        .RST      (1'b0),
        .LOCKED   (pll_locked),
        // Unused outputs
        .CLKOUT1  (),
        .CLKOUT2  (),
        .CLKOUT3  (),
        .CLKOUT4  (),
        .CLKOUT5  ()
    );

    BUFG bufg_clk200 (.I(clk_200_unbuf), .O(clk_200));

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
    // MIG 7 Series IP
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

        // Clock & reset
        .sys_clk_i           (sys_clk_i),
        .clk_ref_i           (clk_200),
        .sys_rst             (1'b0),        // ACTIVE HIGH, always inactive

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
    // TOP (RISC-V system)
    // Two clock domains:
    //   clk        = sys_clk_i (100 MHz) — CPU, UART, caches
    //   mig_ui_clk = ui_clk (~81.25 MHz) — RAM_CONTROLLER MIG side
    // ---------------------------------------------------------------
    TOP #(
        .CLOCK_FREQ   (100_000_000),  // sys_clk_i = 100 MHz
        .BAUD_RATE    (115_200),
        .CHUNK_PART   (128),
        .ADDRESS_SIZE (28),
        .DATA_SIZE    (32),
        .ROM_DEPTH    (256),
        .DEBUG_ENABLE (1)
    ) u_top (
        .clk                    (sys_clk_i),
        .reset                  (ui_clk_sync_rst),

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
        .mig_app_rd_data_end    (app_rd_data_end)
    );

endmodule
