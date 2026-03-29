// INSTRUCTION_PROVIDER — pipeline stage 1: instruction fetch.
//
// Holds PC internally. On flush: loads new_pc.
// Stores 128-bit line, word select by pc[3:2] (combinational).
// Advances PC only when next stage accepts (next_stage_ready=1).

module INSTRUCTION_PROVIDER #(
    parameter ADDR_WIDTH = 32
)(
    input wire clk,
    input wire reset,

    // === To next stage (INSTRUCTION_DECODE) ===
    output reg  [31:0] out_pc,
    output reg  [31:0] out_instruction,
    output reg        next_stage_valid,
    input  wire        next_stage_ready,

    // === Pipeline flush (branch/jump changed PC) ===
    input wire [31:0]  new_pc,
    input wire         flush,

    // === 128-bit bus master (to I_CACHE) ===
    output reg  [ADDR_WIDTH-1:0] bus_address,
    output reg                   bus_read,
    input  wire [127:0]          bus_read_data,
    input  wire                  bus_ready,
    input  wire                  bus_read_valid
);

    // =========================================================
    // Internal PC
    // =========================================================
    reg [31:0] pc;

    // =========================================================
    // Line buffer: 128-bit (4 words)
    // =========================================================
    reg [127:0]          line_data;
    reg [ADDR_WIDTH-5:0] line_tag;
    reg                  line_valid;

    wire line_hit = line_valid && (pc[31:4] == line_tag);

    // =========================================================
    // Word select helper (combinational, used in FSM for latching)
    // =========================================================
    wire [127:0] active_line = bus_read_valid ? bus_read_data : line_data;
    wire [31:0]  word_from_line = pc[3:2] == 2'd3 ? active_line[127:96] :
                                  pc[3:2] == 2'd2 ? active_line[95:64]  :
                                  pc[3:2] == 2'd1 ? active_line[63:32]  :
                                                     active_line[31:0];

    // =========================================================
    // FSM
    // =========================================================
    typedef enum logic [1:0] {
        S_FETCH_REQ,
        S_FETCH_WAIT,
        S_READY
    } state_t;

    state_t state;

    always_ff @(posedge clk) begin
        if (reset) begin
            pc              <= 32'b0;
            line_valid      <= 0;
            line_tag        <= {(ADDR_WIDTH-4){1'b1}};
            state           <= S_FETCH_REQ;
            bus_read        <= 0;
            out_pc          <= 32'b0;
            out_instruction <= 32'h0000_0013;
        end else if (flush) begin
            pc         <= new_pc;
            line_valid <= 0;
            state      <= S_FETCH_REQ;
            bus_read   <= 0;
        end else begin
            bus_read <= 0;
            next_stage_valid <= 0;

            case (state)
                S_FETCH_REQ: begin
                    if (line_hit) begin
                        state       <= S_FETCH_WAIT;
                    end else if (bus_ready) begin
                        bus_address <= {pc[31:4], 4'b0000};
                        bus_read    <= 1;
                        state       <= S_FETCH_WAIT;
                    end
                end

                S_FETCH_WAIT: begin
                    // Save line from bus (only when fetch completes)
                    if (bus_read_valid) begin
                        line_data  <= bus_read_data;
                        line_tag   <= pc[31:4];
                        line_valid <= 1;
                        // Latch output from fresh bus data
                        out_pc          <= pc;
                        out_instruction <= word_from_line;
                        next_stage_valid <= 1;
                        if (next_stage_ready) begin
                            pc    <= pc + 4;
                            state <= S_FETCH_REQ;
                        end
                    end else if (line_hit) begin
                        // Latch output from cached line
                        out_pc          <= pc;
                        out_instruction <= word_from_line;
                        next_stage_valid <= 1;
                        if (next_stage_ready) begin
                            pc    <= pc + 4;
                            state <= S_FETCH_REQ;
                        end
                    end
                end
            endcase
        end
    end

endmodule
