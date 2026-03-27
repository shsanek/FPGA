// Многотактовый RV32M блок (MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU)
//
// MUL:  3 такта (registered inputs → DSP48 multiply → result ready)
// DIV:  34 такта (1 бит за итерацию, shift-subtract)
//
// Протокол:
//   start=1 — запуск операции (игнорируется если busy=1 или done=1)
//   busy=1  — пока считает
//   done=1  — результат готов в result, удерживается пока start не упадёт
//   result  — регистровый, держится до следующей операции
module MULDIV_UNIT (
    input  wire        clk,
    input  wire        reset,

    input  wire        start,      // запуск операции
    input  wire [2:0]  funct3,     // тип операции (0-7)
    input  wire [31:0] a,          // rs1
    input  wire [31:0] b,          // rs2

    output logic [31:0] result,
    output wire         busy,
    output logic        done
);

    // FSM
    typedef enum logic [2:0] {
        S_IDLE,
        S_MUL_1,        // DSP48 pipeline stage 1
        S_MUL_2,        // DSP48 pipeline stage 2 — результат готов
        S_DIV_INIT,     // подготовка делителя
        S_DIV_ITER,     // итерация (32 шага)
        S_DIV_DONE      // результат деления готов
    } state_t;

    state_t state;

    assign busy = (state != S_IDLE);

    // Registered inputs
    logic [2:0]  op_r;
    logic [31:0] a_r, b_r;

    // MUL: registered multiply для DSP48 inference
    (* use_dsp = "yes" *)
    logic signed [63:0] mul_result_r;

    // DIV: shift-subtract
    logic [63:0] dividend_r;   // [63:32] = remainder, [31:0] = quotient
    logic [31:0] divisor_r;
    logic [5:0]  iter_cnt;     // 0..31
    logic        div_neg_result;
    logic        rem_neg_result;

    // Абсолютные значения для signed div (от зарегистрированных входов)
    wire [31:0] abs_a_r = (a_r[31] ? (~a_r + 1) : a_r);
    wire [31:0] abs_b_r = (b_r[31] ? (~b_r + 1) : b_r);

    // DIV iter: комбинационный сдвиг (вне always_ff для совместимости с iverilog)
    wire [63:0] shifted = {dividend_r[62:0], 1'b0};
    wire        sub_ok  = (shifted[63:32] >= divisor_r);

    always_ff @(posedge clk) begin
        if (reset) begin
            state        <= S_IDLE;
            result       <= 32'd0;
            done         <= 1'b0;
            mul_result_r <= 64'd0;
            op_r         <= 3'd0;
            a_r          <= 32'd0;
            b_r          <= 32'd0;
            dividend_r   <= 64'd0;
            divisor_r    <= 32'd0;
            iter_cnt     <= 6'd0;
            div_neg_result <= 1'b0;
            rem_neg_result <= 1'b0;
        end else begin

            case (state)
                // --------------------------------------------------------
                S_IDLE: begin
                    if (done) begin
                        // Удерживаем done пока start не упадёт
                        if (!start)
                            done <= 1'b0;
                    end else if (start) begin
                        op_r <= funct3;
                        a_r  <= a;
                        b_r  <= b;

                        if (funct3 <= 3'd3)
                            state <= S_MUL_1;
                        else
                            state <= S_DIV_INIT;
                    end
                end

                // --------------------------------------------------------
                // MUL pipeline stage 1 — compute (DSP48 inference)
                // --------------------------------------------------------
                S_MUL_1: begin
                    case (op_r)
                        3'd0: mul_result_r <= $signed(a_r) * $signed(b_r);                        // MUL
                        3'd1: mul_result_r <= $signed(a_r) * $signed(b_r);                        // MULH
                        3'd2: mul_result_r <= $signed(a_r) * $signed({1'b0, b_r});                // MULHSU
                        3'd3: mul_result_r <= $signed({1'b0, a_r}) * $signed({1'b0, b_r});       // MULHU
                        default: mul_result_r <= 64'd0;
                    endcase
                    state <= S_MUL_2;
                end

                // MUL pipeline stage 2 — select result
                S_MUL_2: begin
                    case (op_r)
                        3'd0:    result <= mul_result_r[31:0];   // MUL  — lower 32
                        default: result <= mul_result_r[63:32];  // MULH/MULHSU/MULHU — upper 32
                    endcase
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                // --------------------------------------------------------
                // DIV init — edge cases + setup
                // --------------------------------------------------------
                S_DIV_INIT: begin
                    if (b_r == 32'd0) begin
                        // Division by zero
                        case (op_r)
                            3'd4:    result <= 32'hFFFF_FFFF;  // DIV  → -1
                            3'd5:    result <= 32'hFFFF_FFFF;  // DIVU → MAX
                            3'd6:    result <= a_r;            // REM  → dividend
                            3'd7:    result <= a_r;            // REMU → dividend
                            default: result <= 32'd0;
                        endcase
                        done  <= 1'b1;
                        state <= S_IDLE;

                    end else if ((op_r == 3'd4 || op_r == 3'd6) &&
                                 a_r == 32'h8000_0000 && b_r == 32'hFFFF_FFFF) begin
                        // Signed overflow: INT_MIN / -1
                        if (op_r == 3'd4)
                            result <= 32'h8000_0000;  // DIV → INT_MIN
                        else
                            result <= 32'd0;           // REM → 0
                        done  <= 1'b1;
                        state <= S_IDLE;

                    end else begin
                        // Normal division
                        if (op_r == 3'd4 || op_r == 3'd6) begin
                            // Signed: абсолютные значения
                            dividend_r     <= {32'd0, abs_a_r};
                            divisor_r      <= abs_b_r;
                            div_neg_result <= a_r[31] ^ b_r[31];
                            rem_neg_result <= a_r[31];
                        end else begin
                            // Unsigned
                            dividend_r     <= {32'd0, a_r};
                            divisor_r      <= b_r;
                            div_neg_result <= 1'b0;
                            rem_neg_result <= 1'b0;
                        end
                        iter_cnt <= 6'd0;
                        state    <= S_DIV_ITER;
                    end
                end

                // --------------------------------------------------------
                // DIV iteration — 32 шагов shift-subtract
                // --------------------------------------------------------
                S_DIV_ITER: begin
                    if (sub_ok)
                        dividend_r <= {shifted[63:32] - divisor_r, shifted[31:1], 1'b1};
                    else
                        dividend_r <= shifted;

                    if (iter_cnt == 6'd31)
                        state <= S_DIV_DONE;

                    iter_cnt <= iter_cnt + 1;
                end

                // --------------------------------------------------------
                // DIV done — финальный результат
                // --------------------------------------------------------
                S_DIV_DONE: begin
                    case (op_r)
                        3'd4: result <= div_neg_result ? (~dividend_r[31:0] + 1)  : dividend_r[31:0];
                        3'd5: result <= dividend_r[31:0];
                        3'd6: result <= rem_neg_result ? (~dividend_r[63:32] + 1) : dividend_r[63:32];
                        3'd7: result <= dividend_r[63:32];
                        default: result <= 32'd0;
                    endcase
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
