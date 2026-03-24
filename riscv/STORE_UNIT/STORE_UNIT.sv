// Store instructions (opcode 0100011)
// SB / SH / SW
//
// rs2         — значение для записи
// byte_offset — addr[1:0]: позиция внутри 32-bit слова
// write_data  — данные, позиционированные в 32-bit слово
// byte_mask   — маска активных байт (1 = записать)
module STORE_UNIT (
    input  wire [2:0]  funct3,
    input  wire [31:0] rs2,
    input  wire [1:0]  byte_offset,

    output logic [31:0] write_data,
    output logic [3:0]  byte_mask
);
    always_comb begin
        case (funct3)
            3'b000: begin  // SB
                case (byte_offset)
                    2'd0: begin write_data = {24'b0, rs2[7:0]};               byte_mask = 4'b0001; end
                    2'd1: begin write_data = {16'b0, rs2[7:0], 8'b0};         byte_mask = 4'b0010; end
                    2'd2: begin write_data = {8'b0,  rs2[7:0], 16'b0};        byte_mask = 4'b0100; end
                    2'd3: begin write_data = {rs2[7:0], 24'b0};               byte_mask = 4'b1000; end
                    default: begin write_data = 32'b0; byte_mask = 4'b0000; end
                endcase
            end
            3'b001: begin  // SH
                case (byte_offset[1])
                    1'b0: begin write_data = {16'b0, rs2[15:0]};              byte_mask = 4'b0011; end
                    1'b1: begin write_data = {rs2[15:0], 16'b0};              byte_mask = 4'b1100; end
                    default: begin write_data = 32'b0; byte_mask = 4'b0000; end
                endcase
            end
            3'b010: begin  // SW
                write_data = rs2;
                byte_mask  = 4'b1111;
            end
            default: begin
                write_data = 32'b0;
                byte_mask  = 4'b0000;
            end
        endcase
    end
endmodule
