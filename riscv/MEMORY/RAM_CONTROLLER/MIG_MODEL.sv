// Simulation model of the Xilinx MIG7 DDR interface.
// Stores written data and returns it on reads (1-cycle latency).
// mig_app_rdy and mig_app_wdf_rdy are always 1 (no back-pressure).
module MIG_MODEL #(
    parameter CHUNK_PART   = 128,
    parameter ADDRESS_SIZE = 28,
    parameter MEM_DEPTH    = 16       // indexed by addr[7:4]
)(
    input  wire                     mig_ui_clk,

    output logic                    mig_init_calib_complete,
    output logic                    mig_app_rdy,

    // Command
    input  wire                     mig_app_en,
    input  wire [2:0]               mig_app_cmd,
    input  wire [ADDRESS_SIZE-1:0]  mig_app_addr,

    // Write data
    input  wire [CHUNK_PART-1:0]    mig_app_wdf_data,
    input  wire                     mig_app_wdf_wren,
    input  wire                     mig_app_wdf_end,
    output logic                    mig_app_wdf_rdy,

    // Read data
    output logic [CHUNK_PART-1:0]   mig_app_rd_data,
    output logic                    mig_app_rd_data_valid,
    output logic                    mig_app_rd_data_end
);
    localparam CMD_WRITE = 3'b000;
    localparam CMD_READ  = 3'b001;

    logic [CHUNK_PART-1:0]   mem [0:MEM_DEPTH-1];
    logic                    read_pending;
    logic [ADDRESS_SIZE-1:0] read_addr_latch;
    integer                  i;

    initial begin
        mig_init_calib_complete = 1;
        mig_app_rdy             = 1;
        mig_app_wdf_rdy         = 1;
        mig_app_rd_data_valid   = 0;
        mig_app_rd_data_end     = 0;
        mig_app_rd_data         = 0;
        read_pending            = 0;
        read_addr_latch         = 0;
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            mem[i] = 0;
    end

    always @(posedge mig_ui_clk) begin
        // Default: deassert read valid
        mig_app_rd_data_valid <= 0;
        mig_app_rd_data_end   <= 0;

        // Return read data 1 cycle after command
        if (read_pending) begin
            mig_app_rd_data       <= mem[read_addr_latch[7:4]];
            mig_app_rd_data_valid <= 1;
            mig_app_rd_data_end   <= 1;
            read_pending          <= 0;
        end

        // Store write data when wdf_wren is asserted
        if (mig_app_wdf_wren)
            mem[mig_app_addr[7:4]] <= mig_app_wdf_data;

        // Latch read address, respond next cycle
        if (mig_app_en && mig_app_cmd == CMD_READ) begin
            read_addr_latch <= mig_app_addr;
            read_pending    <= 1;
        end
    end
endmodule
