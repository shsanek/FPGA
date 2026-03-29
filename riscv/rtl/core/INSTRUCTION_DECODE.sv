// INSTRUCTION_DECODE — pipeline stage: decode instruction indices.
//
// Receives PC + instruction from INSTRUCTION_PROVIDER.
// Decodes rs1/rs2/rd indices (values read later by Execute stage).
// Passes to next stage (Execute) via valid/ready handshake.
//
// FSM: WAITING_INSTRUCTION → WAITING_SEND
//   WAITING_INSTRUCTION: wait for prev_stage_valid, latch + decode
//   WAITING_SEND: wait for next_stage_ready, then back to WAITING_INSTRUCTION
//
// Index = 5'b10000 (32) means register not used by this instruction.

module INSTRUCTION_DECODE (
    input wire clk,
    input wire reset,

    // === From INSTRUCTION_PROVIDER ===
    input  wire [31:0] prev_pc,
    input  wire [31:0] prev_instruction,
    input  wire        prev_stage_valid,     // previous stage ready to send
    output wire        prev_stage_ready,     // we are ready to accept

    // === To next stage (Execute) ===
    output reg  [31:0] out_pc,
    output reg  [31:0] out_instruction,
    output reg  [4:0]  out_rs1_index,        // 5'b10000 = not used
    output reg  [4:0]  out_rs2_index,        // 5'b10000 = not used
    output reg  [4:0]  out_rd_index,         // 5'b10000 = not used
    output wire        next_stage_valid,     // we are ready to send
    input  wire        next_stage_ready,     // next stage ready to accept

    // === Pipeline flush (branch/jump changed PC) ===
    input  wire        flush
);

    // =========================================================
    // Opcodes that use rs1, rs2, rd
    // =========================================================
    localparam [6:0] OP_R      = 7'b0110011;  // R-type: rs1, rs2, rd
    localparam [6:0] OP_I_ALU  = 7'b0010011;  // I-type ALU: rs1, rd
    localparam [6:0] OP_LOAD   = 7'b0000011;  // Load: rs1, rd
    localparam [6:0] OP_STORE  = 7'b0100011;  // Store: rs1, rs2
    localparam [6:0] OP_BRANCH = 7'b1100011;  // Branch: rs1, rs2
    localparam [6:0] OP_JAL    = 7'b1101111;  // JAL: rd
    localparam [6:0] OP_JALR   = 7'b1100111;  // JALR: rs1, rd
    localparam [6:0] OP_LUI    = 7'b0110111;  // LUI: rd
    localparam [6:0] OP_AUIPC  = 7'b0010111;  // AUIPC: rd

    localparam [4:0] NO_REG = 5'b10000;       // index 32 = not used

    // =========================================================
    // Decode fields from prev_instruction (combinational)
    // =========================================================
    wire [6:0] opcode = prev_instruction[6:0];
    wire [4:0] rs1    = prev_instruction[19:15];
    wire [4:0] rs2    = prev_instruction[24:20];
    wire [4:0] rd     = prev_instruction[11:7];

    // Which registers does this instruction use?
    wire uses_rs1 = (opcode == OP_R) || (opcode == OP_I_ALU) || (opcode == OP_LOAD) ||
                    (opcode == OP_STORE) || (opcode == OP_BRANCH) || (opcode == OP_JALR);
    wire uses_rs2 = (opcode == OP_R) || (opcode == OP_STORE) || (opcode == OP_BRANCH);
    wire uses_rd  = (opcode == OP_R) || (opcode == OP_I_ALU) || (opcode == OP_LOAD) ||
                    (opcode == OP_JAL) || (opcode == OP_JALR) || (opcode == OP_LUI) ||
                    (opcode == OP_AUIPC);

    // =========================================================
    // FSM
    // =========================================================
    typedef enum logic [0:0] {
        WAITING_INSTRUCTION,
        WAITING_SEND
    } state_t;

    state_t state;

    assign prev_stage_ready = (state == WAITING_INSTRUCTION);
    assign next_stage_valid = (state == WAITING_SEND);

    always_ff @(posedge clk) begin
        if (reset || flush) begin
            state           <= WAITING_INSTRUCTION;
            out_pc          <= 32'b0;
            out_instruction <= 32'h0000_0013;  // NOP
            out_rs1_index   <= NO_REG;
            out_rs2_index   <= NO_REG;
            out_rd_index    <= NO_REG;
        end else begin
            case (state)
                WAITING_INSTRUCTION: begin
                    if (prev_stage_valid) begin
                        // Latch decoded values
                        out_pc          <= prev_pc;
                        out_instruction <= prev_instruction;
                        out_rs1_index   <= uses_rs1 ? rs1 : NO_REG;
                        out_rs2_index   <= uses_rs2 ? rs2 : NO_REG;
                        out_rd_index    <= uses_rd  ? rd  : NO_REG;
                        state           <= WAITING_SEND;
                    end
                end

                WAITING_SEND: begin
                    if (next_stage_ready) begin
                        state <= WAITING_INSTRUCTION;
                    end
                end
            endcase
        end
    end

endmodule
