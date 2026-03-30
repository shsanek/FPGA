// INSTRUCTION_PROVIDER — pipeline stage 1: instruction fetch with prefetch.
//
// Two data sources: internal line buffer (line_hit) and I_CACHE peek (peek_hit).
// If peek_hit but not line_hit — copy peek to our buffer.
// Prefetches next line in background while serving current.
// No in-flight tracking needed — bus_ready gates duplicate requests.

module INSTRUCTION_PROVIDER #(
    parameter ADDR_WIDTH = 32
)(
    input wire clk,
    input wire reset,

    // === To next stage ===
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
    input  wire                  bus_ready,

    // === I_CACHE peek (combinational) ===
    input  wire [ADDR_WIDTH-1:0] peek_line_address,
    input  wire [127:0]          peek_line_data,
    input  wire                  peek_line_valid
);

    reg [31:0] pc;

    // Internal line buffer
    reg [127:0]          line_data;
    reg [ADDR_WIDTH-5:0] line_tag;
    reg                  line_valid;

    wire line_hit = line_valid && (pc[31:4] == line_tag);
    wire peek_hit = peek_line_valid && (pc[31:4] == peek_line_address[ADDR_WIDTH-1:4]);

    // Word select
    wire [1:0] word_sel = pc[3:2];
    wire [127:0] selected_line = line_hit ? line_data : peek_line_data;
    wire [31:0]  current_instruction = word_sel == 2'd3 ? selected_line[127:96] :
                                       word_sel == 2'd2 ? selected_line[95:64]  :
                                       word_sel == 2'd1 ? selected_line[63:32]  :
                                                          selected_line[31:0];

    // 4 key signals
    wire have_current       = line_hit || peek_hit;
    wire need_fetch_current = !have_current;
    wire need_prefetch_next = have_current;
    wire blocked            = next_stage_valid && !next_stage_ready;

    wire [31:0] current_line_addr = {pc[31:4], 4'b0000};
    wire [31:0] next_line_addr    = {pc[31:4] + 1'b1, 4'b0000};

    always_ff @(posedge clk) begin
        if (reset) begin
            pc               <= 32'b0;
            line_valid       <= 0;
            line_tag         <= {(ADDR_WIDTH-4){1'b1}};
            bus_read         <= 0;
            next_stage_valid <= 0;
            out_pc           <= 32'b0;
            out_instruction  <= 32'h0000_0013;
        end else if (flush) begin
            pc               <= new_pc;
            line_valid       <= 0;
            bus_read         <= 0;
            next_stage_valid <= 0;
        end else begin
            bus_read <= 0;

            if (next_stage_valid && next_stage_ready)
                next_stage_valid <= 0;

            // ---- Serve instruction ----
            if (!blocked && have_current) begin
                out_pc           <= pc;
                out_instruction  <= current_instruction;
                next_stage_valid <= 1;
                pc               <= pc + 4;

                // Copy peek to our buffer if needed
                if (!line_hit && peek_hit) begin
                    line_data  <= peek_line_data;
                    line_tag   <= pc[31:4];
                    line_valid <= 1;
                end
            end

            // ---- Bus requests: fetch_current > prefetch_next ----
            if (need_fetch_current && bus_ready) begin
                bus_address <= current_line_addr;
                bus_read    <= 1;
            end else if (need_prefetch_next && bus_ready) begin
                bus_address <= next_line_addr;
                bus_read    <= 1;
            end
        end
    end

endmodule
