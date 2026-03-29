// INSTRUCTION_PROVIDER — instruction fetch stage with internal PC and 128-bit line buffer.
//
// Holds PC internally. On set_pc: loads new_pc.
// Fetches 128-bit line from bus, selects word via BUS_32_TO_128 adapter (pc as cpu_address).
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
    output wire [ADDR_WIDTH-1:0] bus_address,
    output wire                  bus_read,
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
    // Word select via BUS_32_TO_128 adapter
    // cpu_address = pc → word select by pc[3:2] (combinational)
    // bus side reads from line_data (stored 128-bit line)
    // =========================================================
    reg         internal_bus_read;
    reg [31:0]  internal_bus_address;

    BUS_32_TO_128 word_select (
        // 32-bit side: pc for word select, instruction out
        .cpu_address    (pc),
        .cpu_read       (internal_bus_read),
        .cpu_write      (1'b0),
        .cpu_write_data (32'b0),
        .cpu_write_mask (4'b0),
        .cpu_read_data  (instruction),
        .cpu_ready      (),             // not used here
        .cpu_read_valid (),             // not used here
        // 128-bit side: to I_CACHE bus
        .bus_address    (bus_address),
        .bus_read       (bus_read),
        .bus_write      (),
        .bus_write_data (),
        .bus_write_mask (),
        .bus_ready      (bus_ready),
        .bus_read_data  (line_hit ? line_data : bus_read_data),
        .bus_read_valid (bus_read_valid)
    );

    // =========================================================
    // FSM
    // =========================================================
    typedef enum logic [1:0] {
        S_FETCH_REQ,     // need to fetch line for current PC
        S_FETCH_WAIT,    // waiting for bus response
        S_READY          // instruction valid, waiting for ready_save_data
    } state_t;

    state_t state;

    assign valid = line_hit && (state == S_READY);

    always_ff @(posedge clk) begin
        if (reset) begin
            pc               <= 32'b0;
            line_valid       <= 0;
            line_tag         <= {(ADDR_WIDTH-4){1'b1}};
            state            <= S_FETCH_REQ;
            internal_bus_read <= 0;
        end else if (set_pc) begin
            pc               <= new_pc;
            line_valid       <= 0;
            state            <= S_FETCH_REQ;
            internal_bus_read <= 0;
        end else begin
            internal_bus_read <= 0;

            case (state)
                // Load instruction for current PC
                S_FETCH_REQ: begin
                    if (line_hit) begin
                        // Already have this line cached
                        state <= S_READY;
                    end else if (bus_ready) begin
                        // Fetch from bus
                        internal_bus_read <= 1;
                        state             <= S_FETCH_WAIT;
                    end
                end

                // Waiting for bus response
                S_FETCH_WAIT: begin
                    if (bus_read_valid) begin
                        line_data  <= bus_read_data;
                        line_tag   <= pc[31:4];
                        line_valid <= 1;
                        state      <= S_READY;
                    end
                end

                // Instruction ready — wait for next stage to accept
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
