// Комбинационный ALU для CPU_SINGLE_CYCLE + многотактовый RV32M
// force_add=1 → всегда ADD (для адресной арифметики LOAD/STORE/JALR/AUIPC/JAL)
// is_muldiv=1 → RV32M расширение (MUL/DIV/REM), делегируется в MULDIV_UNIT
module CPU_ALU (
    input  wire        clk,
    input  wire        reset,

    input  wire [2:0]  funct3,
    input  wire        funct7_5,   // instr[30]: SUB/SRA/SRAI vs ADD/SRL/SRLI
    input  wire        is_muldiv,  // instr[25]: RV32M (funct7=0000001)
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        force_add,
    input  wire        cpu_stall,  // stall от памяти/instr — не запускать MULDIV повторно

    output wire [31:0] result,
    output wire        alu_stall   // 1 = MUL/DIV в процессе, CPU должен ждать
);

    // -----------------------------------------------------------------
    // Базовый комбинационный ALU (RV32I)
    // -----------------------------------------------------------------
    logic [31:0] base_result;

    always_comb begin
        if (force_add) begin
            base_result = a + b;
        end else begin
            case (funct3)
                3'd0: base_result = funct7_5 ? a - b : a + b;
                3'd1: base_result = a << b[4:0];
                3'd2: base_result = ($signed(a) <  $signed(b)) ? 32'd1 : 32'd0;
                3'd3: base_result = (a < b) ? 32'd1 : 32'd0;
                3'd4: base_result = a ^ b;
                3'd5: base_result = funct7_5 ? 32'($signed(a) >>> b[4:0]) : a >> b[4:0];
                3'd6: base_result = a | b;
                3'd7: base_result = a & b;
                default: base_result = 32'd0;
            endcase
        end
    end

    // -----------------------------------------------------------------
    // MULDIV_UNIT (многотактовый RV32M)
    // -----------------------------------------------------------------
    wire [31:0] muldiv_result;
    wire        muldiv_busy;
    wire        muldiv_done;

    // Запуск: is_muldiv=1 И MULDIV не занят И не done (удерживается) И нет stall
    wire muldiv_start = is_muldiv && !muldiv_busy && !muldiv_done && !cpu_stall;

    // Подтверждение: CPU забирает результат (done=1 и pipeline в EXECUTE)
    wire muldiv_ack = muldiv_done && !cpu_stall;

    MULDIV_UNIT muldiv (
        .clk    (clk),
        .reset  (reset),
        .start  (muldiv_start),
        .ack    (muldiv_ack),
        .funct3 (funct3),
        .a      (a),
        .b      (b),
        .result (muldiv_result),
        .busy   (muldiv_busy),
        .done   (muldiv_done)
    );

    // -----------------------------------------------------------------
    // Stall: пока MULDIV работает или только что запущен
    // -----------------------------------------------------------------
    assign alu_stall = is_muldiv && !muldiv_done;

    // -----------------------------------------------------------------
    // Выбор результата
    // -----------------------------------------------------------------
    assign result = muldiv_done ? muldiv_result : base_result;

endmodule
