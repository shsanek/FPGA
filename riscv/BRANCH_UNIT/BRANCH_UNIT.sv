// B-type branch instructions (opcode 1100011)
// BEQ / BNE / BLT / BGE / BLTU / BGEU
//
// branch_taken — условие выполнено
// target_pc    — pc + imm (адрес перехода)
module BRANCH_UNIT (
    input  wire [2:0]  funct3,
    input  wire [31:0] rs1,
    input  wire [31:0] rs2,
    input  wire [31:0] pc,
    input  wire [31:0] imm,       // знаковорасширенный B-immediate из IMMEDIATE_GENERATOR

    output logic        branch_taken,
    output logic [31:0] target_pc
);
    always_comb begin
        target_pc = pc + imm;

        case (funct3)
            3'b000: branch_taken = (rs1 == rs2);                          // BEQ
            3'b001: branch_taken = (rs1 != rs2);                          // BNE
            3'b100: branch_taken = ($signed(rs1) <  $signed(rs2));        // BLT
            3'b101: branch_taken = ($signed(rs1) >= $signed(rs2));        // BGE
            3'b110: branch_taken = (rs1 <  rs2);                          // BLTU
            3'b111: branch_taken = (rs1 >= rs2);                          // BGEU
            default: branch_taken = 1'b0;
        endcase
    end
endmodule
