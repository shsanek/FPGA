// REGISTER_DISPATCHER — pipeline stage 3: hazard check + register read.
//
// Waits for decoded instruction from INSTRUCTION_DECODE.
// Checks busy[rs1]/busy[rs2] — if register is being written by in-flight
// instruction, stalls until writeback clears it.
// When clear: reads register values, marks busy[rd], sends to Execute.
// If next_stage_ready — goes straight back to WAITING_INSTRUCTION.
//
// FSM: WAITING_INSTRUCTION → WAITING_HAZARD (→ back when next_stage_ready)

module REGISTER_DISPATCHER (
    input wire clk,
    input wire reset,

    // === From INSTRUCTION_DECODE ===
    input  wire [31:0] prev_pc,
    input  wire [31:0] prev_instruction,
    input  wire [4:0]  prev_rs1_index,       // 5'b10000 = not used
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

    // === Writeback notification (from last stage) ===
    input  wire [4:0]  wb_rd_index,          // which register was written
    input  wire        wb_valid,             // write happened

    // === Pipeline flush ===
    input  wire        flush
);

    // =========================================================
    // Busy table: 1 bit per register (0..31)
    // busy[i]=1 means an in-flight instruction will write to register i
    // Register 0 is always free (hardwired zero)
    // =========================================================
    reg busy [0:31];

    // =========================================================
    // Latched instruction from decode stage
    // =========================================================
    reg [31:0] lat_pc;
    reg [31:0] lat_instruction;
    reg [4:0]  lat_rs1_index;
    reg [4:0]  lat_rs2_index;
    reg [4:0]  lat_rd_index;

    // =========================================================
    // Hazard check: are source registers busy?
    // Index 5'b10000 (32) = not used → no hazard
    // Register 0 = never busy
    // =========================================================
    wire rs1_busy = (lat_rs1_index < 5'd32) && (lat_rs1_index != 5'd0) && busy[lat_rs1_index];
    wire rs2_busy = (lat_rs2_index < 5'd32) && (lat_rs2_index != 5'd0) && busy[lat_rs2_index];
    wire has_hazard = rs1_busy || rs2_busy;

    // =========================================================
    // Register file read addresses (from latched indices)
    // =========================================================
    assign rf_rs1_addr = lat_rs1_index[4] ? 5'd0 : lat_rs1_index;
    assign rf_rs2_addr = lat_rs2_index[4] ? 5'd0 : lat_rs2_index;

    // =========================================================
    // FSM
    // =========================================================
    typedef enum logic [0:0] {
        WAITING_INSTRUCTION,
        WAITING_HAZARD
    } state_t;

    state_t state;

    assign prev_stage_ready = (state == WAITING_INSTRUCTION);

    integer i;
    always_ff @(posedge clk) begin
        // Writeback: clear busy bit (always, independent of state)
        if (wb_valid && wb_rd_index < 5'd32 && wb_rd_index != 5'd0)
            busy[wb_rd_index] <= 0;

        next_stage_valid <= 0;

        if (reset || flush) begin
            state <= WAITING_INSTRUCTION;
            for (i = 0; i < 32; i = i + 1)
                busy[i] <= 0;
            out_pc          <= 32'b0;
            out_instruction <= 32'h0000_0013;
            out_rs1_value   <= 32'b0;
            out_rs2_value   <= 32'b0;
            next_stage_valid <= 1'b0;
        end else begin
            case (state)
                WAITING_INSTRUCTION: begin
                    if (prev_stage_valid) begin
                        lat_pc          <= prev_pc;
                        lat_instruction <= prev_instruction;
                        lat_rs1_index   <= prev_rs1_index;
                        lat_rs2_index   <= prev_rs2_index;
                        lat_rd_index    <= prev_rd_index;
                        state           <= WAITING_HAZARD;
                    end
                end

                WAITING_HAZARD: begin
                    if (!has_hazard) begin
                        out_pc          <= lat_pc;
                        out_instruction <= lat_instruction;
                        out_rs1_value   <= rf_rs1_data;
                        out_rs2_value   <= rf_rs2_data;
                        next_stage_valid <= 1;
                        // Mark destination register as busy
                        if (lat_rd_index < 5'd32 && lat_rd_index != 5'd0)
                            busy[lat_rd_index] <= 1;

                        if (next_stage_ready)
                            state <= WAITING_INSTRUCTION;
                    end
                end
            endcase
        end
    end

endmodule
