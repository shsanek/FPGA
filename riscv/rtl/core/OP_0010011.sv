// I-type ALU instructions (opcode 0010011)
// ADDI / SLTI / SLTIU / XORI / ORI / ANDI / SLLI / SRLI / SRAI
module OP_0010011 (
    input wire [6:0] funct7,   // используется для SRAI vs SRLI (funct7[5])
    input wire [2:0] funct3,

    input wire [31:0] rs1,
    input wire [31:0] imm,     // знаковорасширенный 12-bit immediate

    input wire clk,

    output logic [31:0] output_value
);
    always_ff @(posedge clk) begin
        case (funct3)
            3'd0: output_value <= rs1 + imm;                              // ADDI

            3'd1: output_value <= rs1 << imm[4:0];                        // SLLI

            3'd2: begin                                                    // SLTI
                if ($signed(rs1) < $signed(imm))
                    output_value <= 32'd1;
                else
                    output_value <= 32'd0;
            end

            3'd3: begin                                                    // SLTIU
                if (rs1 < imm)
                    output_value <= 32'd1;
                else
                    output_value <= 32'd0;
            end

            3'd4: output_value <= rs1 ^ imm;                              // XORI

            3'd5: begin                                                    // SRLI / SRAI
                if (!funct7[5])
                    output_value <= rs1 >> imm[4:0];                      // SRLI
                else
                    output_value <= $signed(rs1) >>> imm[4:0];            // SRAI
            end

            3'd6: output_value <= rs1 | imm;                              // ORI

            3'd7: output_value <= rs1 & imm;                              // ANDI
        endcase
    end
endmodule
