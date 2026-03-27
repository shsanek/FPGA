// Load instructions (opcode 0000011)
// LB / LH / LW / LBU / LHU
//
// mem_data    — 32-bit слово из памяти (выровненное по адресу word)
// byte_offset — addr[1:0]: позиция внутри слова
// result      — знаково или беззнаково расширенное значение
module LOAD_UNIT (
    input  wire [2:0]  funct3,
    input  wire [31:0] mem_data,
    input  wire [1:0]  byte_offset,

    output logic [31:0] result
);
    logic [7:0]  byte_val;
    logic [15:0] half_val;

    always_comb begin
        // выбираем нужный байт/полуслово по offset
        case (byte_offset)
            2'd0: byte_val = mem_data[7:0];
            2'd1: byte_val = mem_data[15:8];
            2'd2: byte_val = mem_data[23:16];
            2'd3: byte_val = mem_data[31:24];
            default: byte_val = 8'b0;
        endcase

        case (byte_offset[1])
            1'b0: half_val = mem_data[15:0];
            1'b1: half_val = mem_data[31:16];
            default: half_val = 16'b0;
        endcase

        case (funct3)
            3'b000: result = {{24{byte_val[7]}},  byte_val};        // LB
            3'b001: result = {{16{half_val[15]}}, half_val};        // LH
            3'b010: result = mem_data;                               // LW
            3'b100: result = {24'b0, byte_val};                     // LBU
            3'b101: result = {16'b0, half_val};                     // LHU
            default: result = 32'b0;
        endcase
    end
endmodule
