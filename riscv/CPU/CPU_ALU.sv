// Комбинационный ALU для CPU_SINGLE_CYCLE
// Используется вместо зарегистрированных OP_0110011/OP_0010011
// force_add=1 → всегда ADD (для адресной арифметики LOAD/STORE/JALR/AUIPC/JAL)
module CPU_ALU (
    input  wire [2:0]  funct3,
    input  wire        funct7_5,   // instr[30]: SUB/SRA/SRAI vs ADD/SRL/SRLI
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        force_add,

    output logic [31:0] result
);
    always_comb begin
        if (force_add) begin
            result = a + b;
        end else begin
            case (funct3)
                3'd0: result = funct7_5 ? a - b : a + b;
                3'd1: result = a << b[4:0];
                3'd2: result = ($signed(a) <  $signed(b)) ? 32'd1 : 32'd0;
                3'd3: result = (a < b) ? 32'd1 : 32'd0;
                3'd4: result = a ^ b;
                3'd5: result = funct7_5 ? 32'($signed(a) >>> b[4:0]) : a >> b[4:0];
                3'd6: result = a | b;
                3'd7: result = a & b;
                default: result = 32'd0;
            endcase
        end
    end
endmodule
