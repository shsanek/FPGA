// ALU_BRANCH — branch comparison. 1 cycle.
//
// BEQ, BNE, BLT, BGE, BLTU, BGEU
// Outputs flush + new_pc if branch taken. No register write (rd=5'd0).

module ALU_BRANCH (
    input wire clk,
    input wire reset,

    // === From REGISTER_DISPATCHER ===
    input  wire [31:0] prev_pc,
    input  wire [31:0] prev_instruction,
    input  wire [31:0] prev_rs1_value,
    input  wire [31:0] prev_rs2_value,
    input  wire        prev_stage_valid,
    output wire        prev_stage_ready,

    // === To writeback (rd=5'd0 always) ===
    output reg  [4:0]  out_rd_index,
    output reg  [31:0] out_rd_value,
    output reg         next_stage_valid,
    input  wire        next_stage_ready,

    // === Branch result ===
    output reg         out_flush,
    output reg  [31:0] out_new_pc,

    // === Pipeline flush ===
    input  wire        flush
);

    wire blocked = next_stage_valid && !next_stage_ready;
    assign prev_stage_ready = !blocked;

    wire [2:0] funct3 = prev_instruction[14:12];

    // B-type immediate
    wire [31:0] imm_b = {{20{prev_instruction[31]}},
                          prev_instruction[7],
                          prev_instruction[30:25],
                          prev_instruction[11:8],
                          1'b0};

    // Branch condition
    wire [31:0] a = prev_rs1_value;
    wire [31:0] b = prev_rs2_value;

    reg take;
    always_comb begin
        case (funct3)
            3'b000:  take = (a == b);                          // BEQ
            3'b001:  take = (a != b);                          // BNE
            3'b100:  take = ($signed(a) < $signed(b));         // BLT
            3'b101:  take = ($signed(a) >= $signed(b));        // BGE
            3'b110:  take = (a < b);                           // BLTU
            3'b111:  take = (a >= b);                          // BGEU
            default: take = 0;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset || flush) begin
            next_stage_valid <= 0;
            out_rd_index     <= 5'd0;
            out_rd_value     <= 32'b0;
            out_flush        <= 0;
            out_new_pc       <= 32'b0;
        end else begin
            if (next_stage_valid && next_stage_ready) begin
                next_stage_valid <= 0;
                out_flush        <= 0;
            end

            if (!blocked && prev_stage_valid) begin
                out_rd_index     <= 5'd0;  // branches don't write registers
                out_rd_value     <= 32'b0;
                next_stage_valid <= 1;
                out_flush        <= take;
                out_new_pc       <= take ? (prev_pc + imm_b) : 32'b0;
            end
        end
    end

endmodule
