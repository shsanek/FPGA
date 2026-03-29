// INSTRUCTION_PROVIDER — instruction fetch stage with internal PC and 128-bit line buffer.
//
// Holds PC internally. On set_pc: loads new_pc. Otherwise increments PC on each valid cycle.
// Stores 128-bit cache line, word select by internal pc[3:2] (combinational).
// On line miss: stalls (valid=0), fetches via 128-bit bus.

module INSTRUCTION_PROVIDER #(
    parameter ADDR_WIDTH = 32
)(
    input wire clk,
    input wire reset,

    // === Output: instruction to CPU ===
    output wire [31:0] instruction,
    output wire        valid,            // 1 = instruction ready, CPU can execute
    output wire [31:0] current_pc,       // current PC value

    // === Control ===
    input wire [31:0]  new_pc,           // new PC value
    input wire         set_pc,           // 1 = load new_pc, invalidate line buffer
    input wire         stall,            // 1 = don't advance PC (CPU busy with MEM etc.)

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
    assign current_pc = pc;

    // =========================================================
    // Line buffer: 128-bit (4 words)
    // =========================================================
    reg [127:0]         line_data;
    reg [ADDR_WIDTH-5:0] line_tag;       // pc[31:4] of cached line
    reg                  line_valid;

    // =========================================================
    // Line hit: current pc within cached line
    // =========================================================
    wire line_hit = line_valid && (pc[31:4] == line_tag);

    // =========================================================
    // Word select by pc[3:2] (combinational)
    // =========================================================
    wire [1:0] word_sel = pc[3:2];
    reg [31:0] selected_word;
    always_comb begin
        case (word_sel)
            2'd0: selected_word = line_data[31:0];
            2'd1: selected_word = line_data[63:32];
            2'd2: selected_word = line_data[95:64];
            2'd3: selected_word = line_data[127:96];
        endcase
    end

    assign instruction = selected_word;
    assign valid       = line_hit && (state == S_IDLE);

    // =========================================================
    // FSM
    // =========================================================
    typedef enum logic [1:0] {
        S_IDLE,
        S_FETCH_REQ,
        S_FETCH_WAIT
    } state_t;

    state_t state;

    always_ff @(posedge clk) begin
        if (reset) begin
            pc         <= 32'b0;
            line_valid <= 0;
            line_tag   <= {(ADDR_WIDTH-4){1'b1}};
            state      <= S_IDLE;
            bus_read   <= 0;
        end else if (set_pc) begin
            pc         <= new_pc;
            line_valid <= 0;
            state      <= S_IDLE;
            bus_read   <= 0;
        end else begin
            bus_read <= 0;

            case (state)
                S_IDLE: begin
                    if (line_hit) begin
                        if (!stall)
                            pc <= pc + 4;
                    end else begin
                        if (bus_ready) begin
                            bus_address <= {pc[31:4], 4'b0000};
                            bus_read    <= 1;
                            state       <= S_FETCH_WAIT;
                        end else begin
                            state <= S_FETCH_REQ;
                        end
                    end
                end

                S_FETCH_REQ: begin
                    if (bus_ready) begin
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
                        state      <= S_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
