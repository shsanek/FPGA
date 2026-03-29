// INSTRUCTION_PROVIDER — instruction fetch stage with internal PC and 128-bit line buffer.
//
// Holds PC internally. On set_pc: loads new_pc.
// Stores 128-bit line, word select by pc[3:2] (combinational).
// Advances PC only when next stage accepts data (ready_save_data=1).

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

    input wire         ready_save_data,  // next stage accepted data, can advance PC

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
    reg [127:0]          line_data;
    reg [ADDR_WIDTH-5:0] line_tag;     // pc[31:4] of cached line
    reg                  line_valid;

    wire line_hit = line_valid && (pc[31:4] == line_tag);

    // =========================================================
    // Word select by pc[3:2] (combinational)
    // =========================================================
    assign instruction = pc[3:2] == 2'd3 ? line_data[127:96] :
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

    assign valid = line_hit && (state == S_READY);

    // =========================================================
    // Bus address: always line-aligned from current PC
    // =========================================================

    always_ff @(posedge clk) begin
        if (reset) begin
            pc         <= 32'b0;
            line_valid <= 0;
            line_tag   <= {(ADDR_WIDTH-4){1'b1}};
            state      <= S_FETCH_REQ;
            bus_read   <= 0;
        end else if (set_pc) begin
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
                        if (ready_save_data) begin
                            pc    <= pc + 4;
                            state <= S_FETCH_REQ;
                        end else begin
                            state <= S_READY;
                        end;
                    end
                end

                S_READY: begin
                    if (ready_save_data) begin
                        pc    <= pc + 4;
                        state <= S_FETCH_REQ;
                    end
                end
            endcase
        end
    end

endmodule
