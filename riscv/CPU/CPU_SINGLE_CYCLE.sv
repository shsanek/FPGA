// RV32I однотактовый процессор
// Каждая инструкция выполняется за 1 такт (при условии комбинационной памяти)
//
// Параметр DEBUG_ENABLE=1 добавляет логику останова и пошагового выполнения.
// При DEBUG_ENABLE=0 debug-порты присутствуют, но логика не синтезируется.
module CPU_SINGLE_CYCLE #(
    parameter DEBUG_ENABLE = 1
)(
    input  wire        clk,
    input  wire        reset,

    // Инструкционная память (комбинационное чтение)
    output wire [31:0] instr_addr,
    input  wire [31:0] instr_data,

    // Память данных (комбинационное чтение, запись по фронту)
    output wire        mem_read_en,
    output wire        mem_write_en,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_write_data,
    output wire [3:0]  mem_byte_mask,
    input  wire [31:0] mem_read_data,

    // Stall от памяти (MEMORY_CONTROLLER не готов)
    input  wire        mem_stall,

    // Stall от instruction fetch (инструкция ещё не готова)
    input  wire        instr_stall,

    // Debug-интерфейс (управление через pipeline adapter)
    input  wire        dbg_set_pc,
    input  wire [31:0] dbg_new_pc,
    output wire        dbg_is_halted,
    output wire [31:0] dbg_current_pc,
    output wire [31:0] dbg_current_instr
);
    // Opcodes
    localparam OP_R      = 7'b0110011;
    localparam OP_I_ALU  = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_FENCE  = 7'b0001111;  // FENCE — NOP в однотактовом CPU
    localparam OP_SYSTEM = 7'b1110011;  // ECALL / EBREAK

    // -------------------------------------------------------------------------
    // EBREAK: CPU останавливается при встрече инструкции EBREAK.
    // Pipeline adapter видит dbg_is_halted=1 и переходит в S_PAUSED.
    // Всё остальное debug-управление — через pipeline adapter (instr_stall).
    // -------------------------------------------------------------------------
    logic ebreak_halted_r;

    wire is_ebreak = DEBUG_ENABLE &&
                     (instr_data[6:0]   == OP_SYSTEM) &&
                     (instr_data[14:12] == 3'b000)    &&
                     (instr_data[20]    == 1'b1);

    always_ff @(posedge clk) begin
        if (reset) begin
            ebreak_halted_r <= 1'b0;
        end else if (DEBUG_ENABLE) begin
            if (is_ebreak && !mem_stall && !instr_stall)
                ebreak_halted_r <= 1'b1;
            else if (ebreak_halted_r && dbg_set_pc)
                ebreak_halted_r <= 1'b0;  // RESET_PC снимает ebreak
        end else begin
            ebreak_halted_r <= 1'b0;
        end
    end

    wire cpu_stall = mem_stall || instr_stall || ebreak_halted_r;

    assign dbg_is_halted = ebreak_halted_r;

    // -------------------------------------------------------------------------
    // PC
    // -------------------------------------------------------------------------
    logic [31:0] pc;
    assign instr_addr = pc;

    // -------------------------------------------------------------------------
    // Декодирование инструкции
    // -------------------------------------------------------------------------
    wire [31:0] instr   = instr_data;
    wire [6:0]  opcode  = instr[6:0];
    wire [4:0]  rd      = instr[11:7];
    wire [2:0]  funct3  = instr[14:12];
    wire [4:0]  rs1_idx = instr[19:15];
    wire [4:0]  rs2_idx = instr[24:20];

    // Debug assigns, требующие pc и instr
    assign dbg_current_pc    = DEBUG_ENABLE ? pc    : 32'b0;
    assign dbg_current_instr = DEBUG_ENABLE ? instr : 32'b0;

    // -------------------------------------------------------------------------
    // Immediate
    // -------------------------------------------------------------------------
    wire [31:0] imm;
    IMMEDIATE_GENERATOR imm_gen (
        .instruction(instr),
        .imm(imm)
    );

    // -------------------------------------------------------------------------
    // Регистровый файл
    // -------------------------------------------------------------------------
    wire  [31:0] rs1_val, rs2_val;
    logic        wb_en;
    logic [31:0] wb_data;

    REGISTER_32_BLOCK_32 regfile (
        .clk          (clk),
        .reset_trigger(reset),
        .rs1          (rs1_idx),
        .rs2          (rs2_idx),
        .rd           (rd),
        .write_trigger(wb_en && !cpu_stall),
        .write_value  (wb_data),
        .rs1_value    (rs1_val),
        .rs2_value    (rs2_val)
    );

    // -------------------------------------------------------------------------
    // ALU
    // -------------------------------------------------------------------------
    wire [31:0] alu_a = ((opcode == OP_AUIPC) || (opcode == OP_JAL)) ? pc : rs1_val;
    wire [31:0] alu_b = (opcode != OP_R) ? imm : rs2_val;

    wire force_add = (opcode == OP_LOAD)  || (opcode == OP_STORE) ||
                     (opcode == OP_JALR)  || (opcode == OP_AUIPC) ||
                     (opcode == OP_JAL);

    // funct7[5]: для R-type всегда, для I-type только при сдвигах (funct3=101)
    wire funct7_5 = (opcode == OP_R)                             ? instr[30] :
                    (opcode == OP_I_ALU && funct3 == 3'b101)     ? instr[30] : 1'b0;

    wire [31:0] alu_result;
    CPU_ALU alu (
        .funct3    (funct3),
        .funct7_5  (funct7_5),
        .a         (alu_a),
        .b         (alu_b),
        .force_add (force_add),
        .result    (alu_result)
    );

    // -------------------------------------------------------------------------
    // Branch unit
    // -------------------------------------------------------------------------
    wire        branch_taken;
    wire [31:0] target_pc;
    BRANCH_UNIT branch_unit (
        .funct3      (funct3),
        .rs1         (rs1_val),
        .rs2         (rs2_val),
        .pc          (pc),
        .imm         (imm),
        .branch_taken(branch_taken),
        .target_pc   (target_pc)
    );

    // -------------------------------------------------------------------------
    // Load unit
    // -------------------------------------------------------------------------
    wire [31:0] load_result;
    LOAD_UNIT load_unit (
        .funct3     (funct3),
        .mem_data   (mem_read_data),
        .byte_offset(alu_result[1:0]),
        .result     (load_result)
    );

    // -------------------------------------------------------------------------
    // Store unit
    // -------------------------------------------------------------------------
    wire [31:0] store_data;
    wire [3:0]  store_mask;
    STORE_UNIT store_unit (
        .funct3     (funct3),
        .rs2        (rs2_val),
        .byte_offset(alu_result[1:0]),
        .write_data (store_data),
        .byte_mask  (store_mask)
    );

    // -------------------------------------------------------------------------
    // Интерфейс памяти данных
    // -------------------------------------------------------------------------
    assign mem_read_en    = (opcode == OP_LOAD);
    assign mem_write_en   = (opcode == OP_STORE);
    assign mem_addr       = alu_result;
    assign mem_write_data = store_data;
    assign mem_byte_mask  = store_mask;

    // -------------------------------------------------------------------------
    // Write-back
    // -------------------------------------------------------------------------
    always_comb begin
        case (opcode)
            OP_LOAD:                   begin wb_en = 1; wb_data = load_result; end
            OP_JAL, OP_JALR:           begin wb_en = 1; wb_data = pc + 32'd4; end
            OP_LUI:                    begin wb_en = 1; wb_data = imm;         end
            OP_R, OP_I_ALU, OP_AUIPC:  begin wb_en = 1; wb_data = alu_result; end
            OP_FENCE, OP_SYSTEM:       begin wb_en = 0; wb_data = 32'b0;       end
            default:                   begin wb_en = 0; wb_data = 32'b0;       end
        endcase
    end

    // -------------------------------------------------------------------------
    // Следующий PC
    // -------------------------------------------------------------------------
    wire [31:0] jalr_target = {alu_result[31:1], 1'b0};

    wire [31:0] next_pc =
        (opcode == OP_JALR)                   ? jalr_target :
        (opcode == OP_JAL)                    ? alu_result  :
        (opcode == OP_BRANCH && branch_taken) ? target_pc   :
        pc + 32'd4;

    // -------------------------------------------------------------------------
    // PC register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset)              pc <= 32'b0;
        else if (dbg_set_pc)    pc <= dbg_new_pc;
        else if (!cpu_stall)    pc <= next_pc;
    end

endmodule
