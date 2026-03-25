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
    output wire [0:0]  ddr3_odt
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
        .ROM_DEPTH    (4096),
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
        .mig_app_rd_data_end    (app_rd_data_end)
    );

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

    assign led[0] = heartbeat_cnt[25];  // ~1.2 Hz blink at 81.25 MHz
    assign led[1] = clk_wiz_locked;
    assign led[2] = init_calib_complete;
    assign led[3] = ~sys_reset;

endmodule
