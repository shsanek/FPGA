module top_controller #(
    parameter CHUNK_PART    = 128,
    parameter ADDRESS_SIZE  = 28,
    parameter DATA_SIZE     = 32,
    parameter MASK_SIZE     = DATA_SIZE/8
)(
    input  wire clk,
    input  wire RXD,
    output wire TXD,
    output logic [2:0] led0,

    // MIG INTERFACE
    output logic [ADDRESS_SIZE-1:0] mig_app_addr,
    output logic [2:0]              mig_app_cmd,
    output logic                    mig_app_en,
    output logic [CHUNK_PART-1:0]   mig_app_wdf_data,
    output logic                    mig_app_wdf_end,
    output wire [(CHUNK_PART/8-1):0] mig_app_wdf_mask,
    output logic                    mig_app_wdf_wren,
    input  wire                     mig_app_wdf_rdy,
    input  wire [CHUNK_PART-1:0]    mig_app_rd_data,
    input  wire                     mig_app_rd_data_end,
    input  wire                     mig_app_rd_data_valid,
    input  wire                     mig_app_rdy,
    input  wire                     mig_ui_clk,
    input  wire                     mig_init_calib_complete
);

    // Instantiate RAM_CONTROLLER (MIG wrapper)
    wire controller_ready;
    wire [3:0] error;
    wire mem2ram_write_trigger;
    wire [CHUNK_PART-1:0] mem2ram_write_value;
    wire [ADDRESS_SIZE-1:0] mem2ram_write_address;
    wire mem2ram_read_trigger;
    wire [ADDRESS_SIZE-1:0] mem2ram_read_address;
    wire [CHUNK_PART-1:0] ram2mem_read_value;
    wire ram2mem_read_ready;

    RAM_CONTROLLER #(
        .CHUNK_PART(CHUNK_PART),
        .ADDRESS_SIZE(ADDRESS_SIZE),
        .CHUNK_COUNT(4)
    ) ram_ctrl (
        .clk               (clk),
        .controller_ready  (controller_ready),
        .error             (error),
        .write_trigger     (mem2ram_write_trigger),
        .write_value       (mem2ram_write_value),
        .write_address     (mem2ram_write_address),
        .read_trigger      (mem2ram_read_trigger),
        .read_address      (mem2ram_read_address),
        .read_value        (ram2mem_read_value),
        .read_value_ready  (ram2mem_read_ready),
        .led0              (led0),
        // MIG interface ports
        .mig_app_addr      (mig_app_addr),
        .mig_app_cmd       (mig_app_cmd),
        .mig_app_en        (mig_app_en),
        .mig_app_wdf_data  (mig_app_wdf_data),
        .mig_app_wdf_end   (mig_app_wdf_end),
        .mig_app_wdf_mask  (mig_app_wdf_mask),
        .mig_app_wdf_wren  (mig_app_wdf_wren),
        .mig_app_wdf_rdy   (mig_app_wdf_rdy),
        .mig_app_rd_data   (mig_app_rd_data),
        .mig_app_rd_data_end(mig_app_rd_data_end),
        .mig_app_rd_data_valid(mig_app_rd_data_valid),
        .mig_app_rdy       (mig_app_rdy),
        .mig_ui_clk        (mig_ui_clk),
        .mig_init_calib_complete(mig_init_calib_complete)
    );

    // Instantiate MEMORY_CONTROLLER (cache)
    wire test2mem_write_trigger;
    wire [ADDRESS_SIZE-1:0] test2mem_address;
    wire [MASK_SIZE-1:0]    test2mem_mask;
    wire test2mem_read_trigger;
    wire [DATA_SIZE-1:0]    test2mem_read_data;
    wire [DATA_SIZE-1:0]    test2mem_write_value;

    MEMORY_CONTROLLER #(
        .CHUNK_PART(CHUNK_PART),
        .DATA_SIZE(DATA_SIZE),
        .MASK_SIZE(MASK_SIZE),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) mem_ctrl (
        .clk                   (clk),
        .ram_controller_ready  (controller_ready),
        // to RAM
        .ram_write_trigger     (mem2ram_write_trigger),
        .ram_write_value       (mem2ram_write_value),
        .ram_write_address     (mem2ram_write_address),
        .ram_read_trigger      (mem2ram_read_trigger),
        .ram_read_value        (ram2mem_read_value),
        .ram_read_address      (mem2ram_read_address),
        .ram_read_value_ready  (ram2mem_read_ready),
        // external test interface
        .controller_ready      (),
        .address               (test2mem_address),
        .mask                  (test2mem_mask),
        .write_trigger         (test2mem_write_trigger),
        .write_value           (test2mem_write_value),
        .command_address       (),
        .read_command          (),
        .contains_command_address(),
        .read_trigger          (test2mem_read_trigger),
        .read_value            (test2mem_read_data),
        .contains_address      ()
    );

    // UART I/O instantiation
    wire io_in_trig;
    wire [7:0] io_in_val;
    wire io_out_ready_trigger;
    wire io_out_trig;
    wire [7:0] io_out_val;

    I_O_INPUT_CONTROLLER io_in(
        .clk(clk),
        .TXD(RXD),
        .io_input_trigger(io_in_trig),
        .io_input_value(io_in_val)
    );

    I_O_OUTPUT_CONTROLLER io_out(
        .clk(clk),
        .io_output_value(io_out_val),
        .io_output_trigger(io_out_trig),
        .io_output_ready_trigger(io_out_ready_trigger),
        .RXD(TXD)
    );

    cll_up clk_u(.clk(clk), .out(clk_ui_ram));

    // Test controller connections to MEMORY_CONTROLLER
    memory_test_controller #(
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) test_ctrl (
        .clk(clk),
        .io_in_trig(io_in_trig),
        .io_in_val(io_in_val),
        .controller_ready(controller_ready),
        .mem_value(test2mem_read_data),
        .mem_address(test2mem_address),
        .mem_read_trigger(test2mem_read_trigger),
        .mem_write_trigger(test2mem_write_trigger),
        .mem_write_value(test2mem_write_value),
        .io_out_val(io_out_val),
        .io_out_trig(io_out_trig),
        .io_out_ready_trigger(io_out_ready_trigger)
    );

endmodule
