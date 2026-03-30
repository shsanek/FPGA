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
    reg [5:0]  bit_count;
    reg        op_is_div;      // 1=div/rem, 0=mul
    reg        sign_a, sign_b; // original signs for signed ops
    reg        is_rem;         // 1=remainder, 0=quotient/product
    reg        is_signed;      // signed operation

    assign prev_stage_ready = (state == S_IDLE) && !blocked;

    // Unsigned absolute values
    wire [31:0] abs_rs1 = (prev_rs1_value[31] && (funct3[1:0] != 2'b11)) ? -prev_rs1_value : prev_rs1_value;
    wire [31:0] abs_rs2 = (prev_rs2_value[31] && (funct3[1:0] == 2'b00 || funct3[1:0] == 2'b01)) ? -prev_rs2_value : prev_rs2_value;

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
                        lat_rd     <= rd;
                        lat_funct3 <= funct3;
                        sign_a     <= prev_rs1_value[31];
                        sign_b     <= prev_rs2_value[31];
                        bit_count  <= 0;

                        case (funct3)
                            3'b000, 3'b001, 3'b010, 3'b011: begin // MUL variants
                                op_is_div   <= 0;
                                is_rem      <= 0;
                                is_signed   <= (funct3 != 3'b011);
                                accumulator <= 64'b0;
                                operand_a   <= abs_rs1;
                                operand_b   <= abs_rs2;
                            end
                            3'b100, 3'b101: begin // DIV, DIVU
                                op_is_div   <= 1;
                                is_rem      <= 0;
                                is_signed   <= (funct3 == 3'b100);
                                accumulator <= {32'b0, abs_rs1};
                                operand_b   <= abs_rs2;
                            end
                            3'b110, 3'b111: begin // REM, REMU
                                op_is_div   <= 1;
                                is_rem      <= 1;
                                is_signed   <= (funct3 == 3'b110);
                                accumulator <= {32'b0, abs_rs1};
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
                        // Done — compute final result
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    out_rd_index <= lat_rd;

                    if (op_is_div) begin
                        if (operand_b == 0) begin
                            // Division by zero
                            out_rd_value <= is_rem ? operand_a : 32'hFFFFFFFF;
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
                            default: begin // MULH, MULHSU, MULHU (upper 32)
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
