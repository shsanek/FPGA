// ALU_JUMP — JAL and JALR. 1 cycle.
//
// JAL:  rd = pc+4, flush, new_pc = pc + imm_j
// JALR: rd = pc+4, flush, new_pc = (rs1 + imm_i) & ~1

module ALU_JUMP (
    input wire clk,
    input wire reset,

    // === From REGISTER_DISPATCHER ===
    input  wire [31:0] prev_pc,
    input  wire [31:0] prev_instruction,
    input  wire [31:0] prev_rs1_value,
    input  wire        prev_stage_valid,
    output wire        prev_stage_ready,

    // === To writeback ===
    output reg  [4:0]  out_rd_index,
    output reg  [31:0] out_rd_value,
    output reg         next_stage_valid,
    input  wire        next_stage_ready,

    // === Jump result ===
    output reg         out_flush,
    output reg  [31:0] out_new_pc,

    // === Pipeline flush ===
    input  wire        flush
);

    wire blocked = next_stage_valid && !next_stage_ready;
    assign prev_stage_ready = !blocked;

    wire [6:0] opcode = prev_instruction[6:0];
    wire [4:0] rd     = prev_instruction[11:7];

    wire is_jal  = (opcode == 7'b1101111);
    wire is_jalr = (opcode == 7'b1100111);

    // J-type immediate (JAL)
    wire [31:0] imm_j = {{12{prev_instruction[31]}},
                          prev_instruction[19:12],
                          prev_instruction[20],
                          prev_instruction[30:21],
                          1'b0};

    // I-type immediate (JALR)
    wire [31:0] imm_i = {{20{prev_instruction[31]}}, prev_instruction[31:20]};

    wire [31:0] target = is_jal ? (prev_pc + imm_j)
                                : ((prev_rs1_value + imm_i) & 32'hFFFFFFFE);

    always_ff @(posedge clk) begin
        if (reset || flush) begin
            next_stage_valid <= 0;
            out_rd_index     <= 5'b10000;
            out_rd_value     <= 32'b0;
            out_flush        <= 0;
            out_new_pc       <= 32'b0;
        end else begin
            if (next_stage_valid && next_stage_ready) begin
                next_stage_valid <= 0;
                out_flush        <= 0;
            end

            if (!blocked && prev_stage_valid) begin
                out_rd_index     <= rd;
                out_rd_value     <= prev_pc + 4;  // return address
                next_stage_valid <= 1;
                out_flush        <= 1;
                out_new_pc       <= target;
            end
        end
    end

endmodule
