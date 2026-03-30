// ALU_SYSTEM — handles FENCE, ECALL, EBREAK and unknown opcodes.
// 1 cycle. No register write. Prevents pipeline stall on unhandled opcodes.

module ALU_SYSTEM (
    input wire clk,
    input wire reset,

    input  wire [31:0] prev_instruction,
    input  wire        prev_stage_valid,
    output wire        prev_stage_ready,

    output reg  [4:0]  out_rd_index,
    output reg  [31:0] out_rd_value,
    output reg         next_stage_valid,
    input  wire        next_stage_ready
);

    wire blocked = next_stage_valid && !next_stage_ready;
    assign prev_stage_ready = !blocked;

    always_ff @(posedge clk) begin
        if (reset) begin
            next_stage_valid <= 0;
            out_rd_index     <= 5'd0;
            out_rd_value     <= 32'b0;
        end else begin
            if (next_stage_valid && next_stage_ready)
                next_stage_valid <= 0;
            if (!blocked && prev_stage_valid) begin
                out_rd_index     <= 5'd0;  // no register write
                out_rd_value     <= 32'b0;
                next_stage_valid <= 1;
            end
        end
    end

endmodule
