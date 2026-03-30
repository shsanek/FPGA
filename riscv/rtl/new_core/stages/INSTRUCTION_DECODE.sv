// INSTRUCTION_DECODE — pipeline stage 2: decode instruction indices.
//
// Pipelined: accepts + decodes in 1 cycle when not blocked by backpressure.
// Purely combinational decode, registered output.

module INSTRUCTION_DECODE (
    input wire clk,
    input wire reset,

    // === From INSTRUCTION_PROVIDER ===
    input  wire [31:0] prev_pc,
    input  wire [31:0] prev_instruction,
    input  wire        prev_stage_valid,
    output wire        prev_stage_ready,

    // === To next stage (REGISTER_DISPATCHER) ===
    output reg  [31:0] out_pc,
    output reg  [31:0] out_instruction,
    output reg  [4:0]  out_rs1_index,        // 5'd0 = not used
    output reg  [4:0]  out_rs2_index,        // 5'd0 = not used
    output reg  [4:0]  out_rd_index,         // 5'd0 = not used
    output reg         next_stage_valid,
    input  wire        next_stage_ready,

    // === Pipeline flush ===
    input  wire        flush
);

    localparam [6:0] OP_R      = 7'b0110011;
    localparam [6:0] OP_I_ALU  = 7'b0010011;
    localparam [6:0] OP_LOAD   = 7'b0000011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [6:0] OP_AUIPC  = 7'b0010111;
    // rd/rs1/rs2 = 0 means x0 (zero register, write ignored)

    // Combinational decode from prev_instruction
    wire [6:0] opcode = prev_instruction[6:0];
    wire [4:0] rs1    = prev_instruction[19:15];
    wire [4:0] rs2    = prev_instruction[24:20];
    wire [4:0] rd     = prev_instruction[11:7];

    wire uses_rs1 = (opcode == OP_R) || (opcode == OP_I_ALU) || (opcode == OP_LOAD) ||
                    (opcode == OP_STORE) || (opcode == OP_BRANCH) || (opcode == OP_JALR);
    wire uses_rs2 = (opcode == OP_R) || (opcode == OP_STORE) || (opcode == OP_BRANCH);
    wire uses_rd  = (opcode == OP_R) || (opcode == OP_I_ALU) || (opcode == OP_LOAD) ||
                    (opcode == OP_JAL) || (opcode == OP_JALR) || (opcode == OP_LUI) ||
                    (opcode == OP_AUIPC);

    // Blocked = have valid output but next stage hasn't taken it
    wire blocked = next_stage_valid && !next_stage_ready;

    // Can accept when not blocked
    assign prev_stage_ready = !blocked;

    always_ff @(posedge clk) begin
        if (reset || flush) begin
            next_stage_valid <= 0;
            out_pc           <= 32'b0;
            out_instruction  <= 32'h0000_0013;
            out_rs1_index    <= 5'd0;
            out_rs2_index    <= 5'd0;
            out_rd_index     <= 5'd0;
        end else begin
            // Clear valid when next stage accepts
            if (next_stage_valid && next_stage_ready)
                next_stage_valid <= 0;

            // Accept new instruction when not blocked
            if (!blocked && prev_stage_valid) begin
                out_pc          <= prev_pc;
                out_instruction <= prev_instruction;
                out_rs1_index   <= uses_rs1 ? rs1 : 5'd0;
                out_rs2_index   <= uses_rs2 ? rs2 : 5'd0;
                out_rd_index    <= uses_rd  ? rd  : 5'd0;
                next_stage_valid <= 1;
            end
        end
    end

endmodule
