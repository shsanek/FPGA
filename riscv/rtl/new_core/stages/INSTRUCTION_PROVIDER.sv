// INSTRUCTION_PROVIDER — pipeline stage 1: instruction fetch.
//
// Pipelined: advances PC every cycle when line_hit and downstream accepts.
// Stalls only on line miss (bus fetch) or backpressure (next stage busy).

module INSTRUCTION_PROVIDER #(
    parameter ADDR_WIDTH = 32
)(
    input wire clk,
    input wire reset,

    // === To next stage (INSTRUCTION_DECODE) ===
    output reg  [31:0] out_pc,
    output reg  [31:0] out_instruction,
    output reg         next_stage_valid,
    input  wire        next_stage_ready,

    // === Pipeline flush ===
    input wire [31:0]  new_pc,
    input wire         flush,

    // === 128-bit bus master (to I_CACHE) ===
    output reg  [ADDR_WIDTH-1:0] bus_address,
    output reg                   bus_read,
    input  wire [127:0]          bus_read_data,
    input  wire                  bus_ready,
    input  wire                  bus_read_valid
);

    reg [31:0] pc;
    reg [127:0]          line_data;
    reg [ADDR_WIDTH-5:0] line_tag;
    reg                  line_valid;

    wire line_hit = line_valid && (pc[31:4] == line_tag);

    // Word select from active source (fresh bus data or cached line)
    wire [127:0] active_line = bus_read_valid ? bus_read_data : line_data;
    wire [31:0]  word_from_line = pc[3:2] == 2'd3 ? active_line[127:96] :
                                  pc[3:2] == 2'd2 ? active_line[95:64]  :
                                  pc[3:2] == 2'd1 ? active_line[63:32]  :
                                                     active_line[31:0];

    // Can we accept/produce this cycle?
    // Blocked = we have valid output but next stage hasn't taken it yet
    wire blocked = next_stage_valid && !next_stage_ready;

    typedef enum logic [0:0] {
        S_READY,        // have line or waiting for line_hit
        S_FETCH_WAIT    // bus_read sent, waiting for bus_read_valid
    } state_t;

    state_t state;

    always_ff @(posedge clk) begin
        if (reset) begin
            pc               <= 32'b0;
            line_valid       <= 0;
            line_tag         <= {(ADDR_WIDTH-4){1'b1}};
            state            <= S_READY;
            bus_read         <= 0;
            next_stage_valid <= 0;
            out_pc           <= 32'b0;
            out_instruction  <= 32'h0000_0013;
        end else if (flush) begin
            pc               <= new_pc;
            line_valid       <= 0;
            state            <= S_READY;
            bus_read         <= 0;
            next_stage_valid <= 0;
        end else begin
            bus_read <= 0;

            // Clear valid when next stage accepts
            if (next_stage_valid && next_stage_ready)
                next_stage_valid <= 0;

            case (state)
                S_READY: begin
                    if (!blocked) begin
                        if (line_hit) begin
                            // Hit: output instruction, advance PC
                            out_pc           <= pc;
                            out_instruction  <= word_from_line;
                            next_stage_valid <= 1;
                            pc               <= pc + 4;
                        end else if (bus_ready) begin
                            // Miss: fetch from bus
                            bus_address <= {pc[31:4], 4'b0000};
                            bus_read    <= 1;
                            state       <= S_FETCH_WAIT;
                        end
                    end
                end

                S_FETCH_WAIT: begin
                    if (bus_read_valid) begin
                        line_data  <= bus_read_data;
                        line_tag   <= pc[31:4];
                        line_valid <= 1;

                        if (!blocked) begin
                            out_pc           <= pc;
                            out_instruction  <= word_from_line;
                            next_stage_valid <= 1;
                            pc               <= pc + 4;
                        end
                        state <= S_READY;
                    end
                end
            endcase
        end
    end

endmodule
