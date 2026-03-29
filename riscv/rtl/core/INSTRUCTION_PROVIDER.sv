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
    output wire [31:0] out_pc,
    output wire [31:0] out_instruction,
    output wire        next_stage_valid,
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
    assign out_pc = pc;

    // =========================================================
    // Line buffer: 128-bit (4 words)
    // =========================================================
    reg [127:0]          line_data;
    reg [ADDR_WIDTH-5:0] line_tag;
    reg                  line_valid;

    wire line_hit = line_valid && (pc[31:4] == line_tag);

    // =========================================================
    // Word select by pc[3:2] (combinational)
    // =========================================================
    assign out_instruction = pc[3:2] == 2'd3 ? line_data[127:96] :
                             pc[3:2] == 2'd2 ? line_data[95:64]  :
                             pc[3:2] == 2'd1 ? line_data[63:32]  :
                                               line_data[31:0];

    // =========================================================
    // FSM
    // =========================================================
    typedef enum logic [1:0] {
        S_FETCH_REQ,
        S_FETCH_WAIT,
        S_READY
    } state_t;

    state_t state;

    assign next_stage_valid = line_hit && (state != S_FETCH_REQ);

    always_ff @(posedge clk) begin
        if (reset) begin
            pc         <= 32'b0;
            line_valid <= 0;
            line_tag   <= {(ADDR_WIDTH-4){1'b1}};
            state      <= S_FETCH_REQ;
            bus_read   <= 0;
        end else if (flush) begin
            pc         <= new_pc;
            line_valid <= 0;
            state      <= S_FETCH_REQ;
            bus_read   <= 0;
        end else begin
            bus_read <= 0;

            case (state)
                S_FETCH_REQ: begin
                    if (line_hit) begin
                        state <= S_READY;
                    end else if (bus_ready) begin
                        bus_address <= {pc[31:4], 4'b0000};
                        bus_read    <= 1;
                        state       <= S_FETCH_WAIT;
                    end
                end

                S_FETCH_WAIT: begin
                    if (bus_read_valid) begin
                        line_data  <= bus_read_data;
                        line_tag   <= pc[31:4];
                        line_valid <= 1;
                        if (next_stage_ready) begin
                            pc    <= pc + 4;
                            state <= S_FETCH_REQ;
                        end else begin
                            state <= S_READY;
                        end
                    end
                end

                S_READY: begin
                    if (next_stage_ready) begin
                        pc    <= pc + 4;
                        state <= S_FETCH_REQ;
                    end
                end
            endcase
        end
    end

endmodule
