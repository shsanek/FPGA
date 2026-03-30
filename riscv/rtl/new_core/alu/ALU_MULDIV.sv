// ALU_MULDIV — MUL/DIV/REM operations. Multi-cycle.
//
// M-extension (RV32M): MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
// Uses iterative shift-add for MUL (~32 cycles) and shift-subtract for DIV (~32 cycles).

module ALU_MULDIV (
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

    wire [2:0] funct3 = prev_instruction[14:12];
    wire [4:0] rd     = prev_instruction[11:7];

    // =========================================================
    // FSM
    // =========================================================
    typedef enum logic [1:0] {
        S_IDLE,
        S_COMPUTE,
        S_DONE
    } state_t;

    state_t state;
    reg [4:0]  lat_rd;
    reg [2:0]  lat_funct3;

    // Iterative computation state
    reg [63:0] accumulator;
    reg [31:0] operand_a;
    reg [31:0] operand_b;
    reg [31:0] orig_rs1;     // original rs1 for REM/REMU by zero
    reg [5:0]  bit_count;
    reg        op_is_div;
    reg        sign_a, sign_b;
    reg        is_rem;
    reg        is_signed;
    reg        rs2_is_signed; // rs2 signedness (false for MULHSU)

    assign prev_stage_ready = (state == S_IDLE) && !blocked;

    // Per-operation signedness (explicit, not funct3[1:0] hack)
    //   rs1 signed: MUL(000) MULH(001) MULHSU(010) DIV(100) REM(110)
    //   rs1 unsigned: MULHU(011) DIVU(101) REMU(111)
    //   rs2 signed: MUL(000) MULH(001) DIV(100) REM(110)
    //   rs2 unsigned: MULHSU(010) MULHU(011) DIVU(101) REMU(111)
    wire rs1_is_unsigned = (funct3 == 3'b011) || (funct3 == 3'b101) || (funct3 == 3'b111);
    wire rs2_is_unsigned = (funct3 == 3'b010) || (funct3 == 3'b011) ||
                           (funct3 == 3'b101) || (funct3 == 3'b111);

    wire [31:0] abs_rs1 = (prev_rs1_value[31] && !rs1_is_unsigned) ? -prev_rs1_value : prev_rs1_value;
    wire [31:0] abs_rs2 = (prev_rs2_value[31] && !rs2_is_unsigned) ? -prev_rs2_value : prev_rs2_value;

    always_ff @(posedge clk) begin
        if (reset) begin
            state            <= S_IDLE;
            next_stage_valid <= 0;
            out_rd_index     <= 5'd0;
            out_rd_value     <= 32'b0;
        end else begin
            if (next_stage_valid && next_stage_ready)
                next_stage_valid <= 0;

            case (state)
                S_IDLE: begin
                    if (!blocked && prev_stage_valid) begin
                        lat_rd        <= rd;
                        lat_funct3    <= funct3;
                        sign_a        <= prev_rs1_value[31];
                        sign_b        <= prev_rs2_value[31];
                        orig_rs1      <= prev_rs1_value;
                        rs2_is_signed <= !rs2_is_unsigned;
                        bit_count     <= 0;

                        case (funct3)
                            3'b000, 3'b001, 3'b010, 3'b011: begin // MUL variants
                                op_is_div   <= 0;
                                is_rem      <= 0;
                                is_signed   <= !rs1_is_unsigned;
                                accumulator <= 64'b0;
                                operand_a   <= abs_rs1;
                                operand_b   <= abs_rs2;
                            end
                            3'b100, 3'b101: begin // DIV, DIVU
                                op_is_div   <= 1;
                                is_rem      <= 0;
                                is_signed   <= !rs1_is_unsigned;
                                accumulator <= {32'b0, abs_rs1};
                                operand_a   <= abs_rs1;
                                operand_b   <= abs_rs2;
                            end
                            3'b110, 3'b111: begin // REM, REMU
                                op_is_div   <= 1;
                                is_rem      <= 1;
                                is_signed   <= !rs1_is_unsigned;
                                accumulator <= {32'b0, abs_rs1};
                                operand_a   <= abs_rs1;
                                operand_b   <= abs_rs2;
                            end
                        endcase
                        state <= S_COMPUTE;
                    end
                end

                S_COMPUTE: begin
                    if (bit_count < 32) begin
                        if (op_is_div) begin
                            // Shift-subtract division
                            reg [63:0] shifted;
                            shifted = {accumulator[62:0], 1'b0};
                            if (shifted[63:32] >= operand_b) begin
                                shifted[63:32] = shifted[63:32] - operand_b;
                                shifted[0] = 1;
                            end
                            accumulator <= shifted;
                        end else begin
                            // Shift-add multiplication
                            if (operand_a[bit_count])
                                accumulator <= accumulator + ({32'b0, operand_b} << bit_count);
                        end
                        bit_count <= bit_count + 1;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    out_rd_index <= lat_rd;

                    if (op_is_div) begin
                        if (operand_b == 0) begin
                            // Division by zero (RISC-V spec):
                            //   DIV/DIVU → 0xFFFFFFFF (-1)
                            //   REM/REMU → original dividend (rs1)
                            out_rd_value <= is_rem ? orig_rs1 : 32'hFFFFFFFF;
                        end else if (is_rem) begin
                            out_rd_value <= (is_signed && sign_a) ? -accumulator[63:32] : accumulator[63:32];
                        end else begin
                            out_rd_value <= (is_signed && (sign_a ^ sign_b)) ? -accumulator[31:0] : accumulator[31:0];
                        end
                    end else begin
                        // MUL result
                        case (lat_funct3)
                            3'b000: begin // MUL (lower 32)
                                reg [31:0] prod_lo;
                                prod_lo = accumulator[31:0];
                                out_rd_value <= (is_signed && (sign_a ^ sign_b)) ? -prod_lo : prod_lo;
                            end
                            3'b010: begin // MULHSU (upper 32, rs1 signed × rs2 unsigned)
                                reg [31:0] prod_hi;
                                prod_hi = accumulator[63:32];
                                // Only rs1 sign matters (rs2 is unsigned)
                                out_rd_value <= sign_a ?
                                    (~prod_hi + (accumulator[31:0] == 0 ? 1 : 0)) : prod_hi;
                            end
                            default: begin // MULH, MULHU (upper 32)
                                reg [31:0] prod_hi;
                                prod_hi = accumulator[63:32];
                                out_rd_value <= (is_signed && (sign_a ^ sign_b)) ?
                                    (~prod_hi + (accumulator[31:0] == 0 ? 1 : 0)) : prod_hi;
                            end
                        endcase
                    end

                    next_stage_valid <= 1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
