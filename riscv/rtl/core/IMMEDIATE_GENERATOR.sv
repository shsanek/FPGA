// Декодирует immediate из 32-битной инструкции RV32I
// Формат определяется по opcode (instruction[6:0])
//
// I-type: ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI / LOAD / JALR
// S-type: STORE
// B-type: BRANCH
// U-type: LUI / AUIPC
// J-type: JAL
module IMMEDIATE_GENERATOR (
    input  wire [31:0] instruction,
    output logic [31:0] imm
);
    wire [6:0] opcode = instruction[6:0];

    always_comb begin
        case (opcode)
            // I-type
            7'b0010011, // ALU immediate
            7'b0000011, // LOAD
            7'b1100111: // JALR
                imm = {{20{instruction[31]}}, instruction[31:20]};

            // S-type
            7'b0100011:
                imm = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};

            // B-type
            7'b1100011:
                imm = {{19{instruction[31]}}, instruction[31], instruction[7],
                       instruction[30:25], instruction[11:8], 1'b0};

            // U-type
            7'b0110111, // LUI
            7'b0010111: // AUIPC
                imm = {instruction[31:12], 12'b0};

            // J-type
            7'b1101111: // JAL
                imm = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                       instruction[20], instruction[30:21], 1'b0};

            default: imm = 32'b0;
        endcase
    end
endmodule
