// ALU_COMPUTE — R-type and I-type ALU operations. 1 cycle.
//
// R-type: add, sub, sll, slt, sltu, xor, srl, sra, or, and
// I-type: addi, slti, sltiu, xori, ori, andi, slli, srli, srai

module ALU_COMPUTE (
    input wire clk,
    input wire reset,

    // === From REGISTER_DISPATCHER ===
    input  wire [31:0] prev_instruction,
    input  wire [31:0] prev_rs1_value,
    input  wire [31:0] prev_rs2_value,
    input  wire        prev_stage_valid,
    output wire        prev_stage_ready,

    // === To writeback ===
    output reg  [4:0]  out_rd_index,
    output reg  [31:0] out_rd_value,
    output reg         next_stage_valid,
    input  wire        next_stage_ready
);

    wire blocked = next_stage_valid && !next_stage_ready;
    assign prev_stage_ready = !blocked;

    // Decode
    wire [6:0] opcode = prev_instruction[6:0];
    wire [2:0] funct3 = prev_instruction[14:12];
    wire [6:0] funct7 = prev_instruction[31:25];
    wire [4:0] rd     = prev_instruction[11:7];
    wire [4:0] shamt  = prev_instruction[24:20];

    // I-type immediate (sign-extended)
    wire [31:0] imm_i = {{20{prev_instruction[31]}}, prev_instruction[31:20]};

    // Select operand B: rs2 for R-type, imm for I-type
    wire is_r_type = (opcode == 7'b0110011);
    wire [31:0] op_b = is_r_type ? prev_rs2_value : imm_i;
    wire [31:0] op_a = prev_rs1_value;

    // ALU operation
    reg [31:0] result;
    always_comb begin
        result = 32'b0;
        case (funct3)
            3'b000: result = (is_r_type && funct7[5]) ? (op_a - op_b) : (op_a + op_b);
            3'b001: result = op_a << op_b[4:0];
            3'b010: result = {31'b0, $signed(op_a) < $signed(op_b)};
            3'b011: result = {31'b0, op_a < op_b};
            3'b100: result = op_a ^ op_b;
            3'b101: begin
                if (funct7[5])
                    result = $unsigned($signed(op_a) >>> op_b[4:0]);
                else
                    result = op_a >> op_b[4:0];
            end
            3'b110: result = op_a | op_b;
            3'b111: result = op_a & op_b;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            next_stage_valid <= 0;
            out_rd_index     <= 5'd0;
            out_rd_value     <= 32'b0;
        end else begin
            if (next_stage_valid && next_stage_ready)
                next_stage_valid <= 0;

            if (!blocked && prev_stage_valid) begin
                out_rd_index     <= rd;
                out_rd_value     <= result;
                next_stage_valid <= 1;
            end
        end
    end

endmodule
