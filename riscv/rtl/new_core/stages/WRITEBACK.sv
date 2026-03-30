// WRITEBACK — pipeline final stage: write result to register file.
//
// Registered stage (1 cycle): latches rd_index + rd_value, writes on next cycle.
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
    output reg  [4:0]  rf_wr_addr,
    output reg  [31:0] rf_wr_data,
    output reg         rf_wr_en,

    // === Notify REGISTER_DISPATCHER: register freed ===
    output reg  [4:0]  wb_done_index,
    output reg         wb_done_valid
);

    wire blocked = rf_wr_en && !1'b1;  // register file always accepts — never blocked
    // (if register file had backpressure, blocked = rf_wr_en && !rf_accepted)

    assign prev_stage_ready = !rf_wr_en;  // can accept when not holding data

    always_ff @(posedge clk) begin
        if (reset) begin
            rf_wr_en      <= 0;
            rf_wr_addr    <= 5'd0;
            rf_wr_data    <= 32'b0;
            wb_done_valid <= 0;
            wb_done_index <= 5'd0;
        end else begin
            // Default: clear write pulse
            rf_wr_en      <= 0;
            wb_done_valid <= 0;

            // If holding data from previous cycle — write it now
            // (rf_wr_en was set, register file captures on this posedge)

            // Accept new from arbiter when not holding
            if (!rf_wr_en && prev_stage_valid) begin
                rf_wr_addr    <= prev_rd_index;
                rf_wr_data    <= prev_rd_value;
                rf_wr_en      <= (prev_rd_index != 5'd0);
                wb_done_index <= prev_rd_index;
                wb_done_valid <= (prev_rd_index != 5'd0);
            end
        end
    end

endmodule
