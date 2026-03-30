// REGISTER_DISPATCHER — pipeline stage 3: hazard check + register read.
//
// Pipelined: accepts in 1 cycle when no hazard and not blocked.
// Stalls on data hazard (busy source register) until writeback clears it.

module REGISTER_DISPATCHER (
    input wire clk,
    input wire reset,

    // === From INSTRUCTION_DECODE ===
    input  wire [31:0] prev_pc,
    input  wire [31:0] prev_instruction,
    input  wire [4:0]  prev_rs1_index,
    input  wire [4:0]  prev_rs2_index,
    input  wire [4:0]  prev_rd_index,
    input  wire        prev_stage_valid,
    output wire        prev_stage_ready,

    // === To Execute ===
    output reg  [31:0] out_pc,
    output reg  [31:0] out_instruction,
    output reg  [31:0] out_rs1_value,
    output reg  [31:0] out_rs2_value,
    output reg         next_stage_valid,
    input  wire        next_stage_ready,

    // === Register file read (combinational) ===
    output wire [4:0]  rf_rs1_addr,
    output wire [4:0]  rf_rs2_addr,
    input  wire [31:0] rf_rs1_data,
    input  wire [31:0] rf_rs2_data,

    // === Writeback notification ===
    input  wire [4:0]  wb_rd_index,
    input  wire [31:0] wb_rd_value,     // for forwarding (bypass)
    input  wire        wb_valid,

    // === Pipeline flush ===
    input  wire        flush
);

    reg busy [0:31];

    // Latched from decode (need to hold during hazard stall)
    reg [31:0] lat_pc;
    reg [31:0] lat_instruction;
    reg [4:0]  lat_rs1_index;
    reg [4:0]  lat_rs2_index;
    reg [4:0]  lat_rd_index;
    reg        lat_valid;      // have latched instruction waiting

    // Hazard check on latched indices
    // x0 never busy (writes to x0 ignored), so index=0 → no hazard
    wire rs1_busy = (lat_rs1_index != 5'd0) && busy[lat_rs1_index];
    wire rs2_busy = (lat_rs2_index != 5'd0) && busy[lat_rs2_index];
    wire has_hazard = lat_valid && (rs1_busy || rs2_busy);

    // Register file addresses from latched indices
    assign rf_rs1_addr = lat_rs1_index;
    assign rf_rs2_addr = lat_rs2_index;

    // Blocked = have valid output but next stage hasn't taken it
    wire blocked = next_stage_valid && !next_stage_ready;

    // Can accept: no latched instruction waiting (or it's being dispatched this cycle)
    wire can_dispatch = lat_valid && !has_hazard && !blocked;
    assign prev_stage_ready = !lat_valid || can_dispatch;

    integer i;
    always_ff @(posedge clk) begin
        // Writeback: always clear busy (independent of everything)
        if (wb_valid && wb_rd_index != 5'd0)
            busy[wb_rd_index] <= 0;

        if (reset || flush) begin
            for (i = 0; i < 32; i = i + 1)
                busy[i] <= 0;
            lat_valid        <= 0;
            next_stage_valid <= 0;
            out_pc           <= 32'b0;
            out_instruction  <= 32'h0000_0013;
            out_rs1_value    <= 32'b0;
            out_rs2_value    <= 32'b0;
        end else begin
            // Clear valid when next stage accepts
            if (next_stage_valid && next_stage_ready)
                next_stage_valid <= 0;

            // Dispatch: no hazard, not blocked → send to execute
            // Forwarding: if writeback is writing to our source reg THIS cycle,
            // use writeback value (regfile NBA hasn't applied yet)
            if (can_dispatch) begin
                out_pc           <= lat_pc;
                out_instruction  <= lat_instruction;
                out_rs1_value    <= (wb_valid && wb_rd_index != 0 && wb_rd_index == lat_rs1_index)
                                    ? wb_rd_value : rf_rs1_data;
                out_rs2_value    <= (wb_valid && wb_rd_index != 0 && wb_rd_index == lat_rs2_index)
                                    ? wb_rd_value : rf_rs2_data;
                next_stage_valid <= 1;

                if (lat_rd_index != 5'd0)
                    busy[lat_rd_index] <= 1;

                lat_valid <= 0;
            end

            // Accept new from decode (when slot free)
            if (prev_stage_ready && prev_stage_valid) begin
                lat_pc          <= prev_pc;
                lat_instruction <= prev_instruction;
                lat_rs1_index   <= prev_rs1_index;
                lat_rs2_index   <= prev_rs2_index;
                lat_rd_index    <= prev_rd_index;
                lat_valid       <= 1;
            end
        end
    end

endmodule
