// ALU_UPPER — LUI and AUIPC. 1 cycle.
//
// LUI:   rd = imm_u
// AUIPC: rd = pc + imm_u

module ALU_UPPER (
    input wire clk,
    input wire reset,

    // === From REGISTER_DISPATCHER ===
    input  wire [31:0] prev_pc,
    input  wire [31:0] prev_instruction,
    input  wire        prev_stage_valid,
    output wire        prev_stage_ready,

    // === To writeback ===
    output reg  [4:0]  out_rd_index,
    output reg  [31:0] out_rd_value,
    output reg         next_stage_valid,
    input  wire        next_stage_ready,

    // === Pipeline flush ===
    input  wire        flush
);

    wire blocked = next_stage_valid && !next_stage_ready;
    assign prev_stage_ready = !blocked;

    wire [6:0] opcode = prev_instruction[6:0];
    wire [4:0] rd     = prev_instruction[11:7];

    wire is_lui = (opcode == 7'b0110111);

    // U-type immediate
    wire [31:0] imm_u = {prev_instruction[31:12], 12'b0};

    wire [31:0] result = is_lui ? imm_u : (prev_pc + imm_u);

    always_ff @(posedge clk) begin
        if (reset || flush) begin
            next_stage_valid <= 0;
            out_rd_index     <= 5'd0;
            out_rd_value     <= 32'b0;
        end else begin
            if (next_stage_valid && next_stage_ready)
                next_stage_valid <= 0;

            if (!blocked && prev_stage_valid) begin
                out_rd_index     <= rd;
                out_rd_value     <= result;
                next_stage_valid <= 1;
            end
        end
    end

endmodule
