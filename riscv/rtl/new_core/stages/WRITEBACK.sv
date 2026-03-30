// WRITEBACK — pipeline final stage: write result to register file.
//
// Receives rd_index + rd_value from WRITEBACK_ARBITER.
// Writes to register file (if rd != 0).
// Notifies REGISTER_DISPATCHER that register is free (wb_done_index/wb_done_valid).

module WRITEBACK (
    input wire clk,
    input wire reset,

    // === From WRITEBACK_ARBITER ===
    input  wire [4:0]  prev_rd_index,
    input  wire [31:0] prev_rd_value,
    input  wire        prev_stage_valid,
    output wire        prev_stage_ready,

    // === Register file write port ===
    output wire [4:0]  rf_wr_addr,
    output wire [31:0] rf_wr_data,
    output wire        rf_wr_en,

    // === Notify REGISTER_DISPATCHER: register freed ===
    output wire [4:0]  wb_done_index,
    output wire        wb_done_valid
);

    // Always ready — single cycle, no stall
    assign prev_stage_ready = 1'b1;

    // Write to register file (skip x0)
    assign rf_wr_en   = prev_stage_valid && (prev_rd_index != 5'd0);
    assign rf_wr_addr = prev_rd_index;
    assign rf_wr_data = prev_rd_value;

    // Notify dispatcher: this register is now free
    assign wb_done_index = prev_rd_index;
    assign wb_done_valid = prev_stage_valid && (prev_rd_index != 5'd0);

endmodule
