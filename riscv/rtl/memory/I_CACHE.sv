// I_CACHE — direct-mapped read-only instruction cache.
//
// 256 lines x 16 bytes = 4 KB. Same external interface as CHUNK_STORAGE_4_POOL.
// Read-only: save_need_flag = 0 always, writes ignored.
//
// Address decomposition (28-bit):
//   [27:12] tag (16 bit)  |  [11:4] index (8 bit)  |  [3:0] offset (4 bit)
//
// Hit check is combinational (tags/valid in distributed RAM).
// Data storage also distributed RAM for combinational read.
module I_CACHE #(
    parameter DEPTH = 256,
    parameter CHUNK_PART = 128,
    parameter DATA_SIZE = 32,
    parameter MASK_SIZE = DATA_SIZE / 8,
    parameter ADDRESS_SIZE = 28
)(
    input wire clk,
    input wire reset,

    // COMMON
    input wire[ADDRESS_SIZE - 1:0] address,
    input wire[MASK_SIZE - 1: 0] mask,

    // WRITE (ignored — read-only cache, interface must match)
    input wire write_trigger,
    input wire[DATA_SIZE-1: 0] write_value,

    // READ
    input wire read_trigger,
    output wire[DATA_SIZE-1: 0] read_value,
    output wire contains_address,

    output wire[ADDRESS_SIZE - 1:0] save_address,
    output wire[CHUNK_PART - 1: 0] save_data,
    output wire save_need_flag,

    input wire order_tick,

    input wire[CHUNK_PART - 1: 0] new_data,
    input wire[ADDRESS_SIZE - 1:0] new_address,
    input wire new_data_save
);
    localparam INDEX_W = $clog2(DEPTH);                    // 8
    localparam TAG_W   = ADDRESS_SIZE - INDEX_W - 4;       // 16

    // Tag & valid storage (distributed RAM — async read)
    reg [TAG_W-1:0] tags  [0:DEPTH-1];
    reg             valid [0:DEPTH-1];

    // Data storage (distributed RAM — async read, 4 words per line)
    reg [DATA_SIZE-1:0] data [0:DEPTH*4-1];

    // --- Address decomposition ---
    wire [INDEX_W-1:0] idx      = address[INDEX_W+3 : 4];
    wire [TAG_W-1:0]   addr_tag = address[ADDRESS_SIZE-1 : INDEX_W+4];
    wire [1:0]         word_sel = address[3:2];

    // --- Hit check (combinational) ---
    wire hit = valid[idx] && (tags[idx] == addr_tag);
    assign contains_address = hit;

    // --- Read value (combinational) ---
    wire [INDEX_W+1:0] data_idx = {idx, word_sel};
    assign read_value = hit ? data[data_idx] : {DATA_SIZE{1'b0}};

    // --- Read-only: never dirty ---
    assign save_address   = '0;
    assign save_data      = '0;
    assign save_need_flag = 1'b0;

    // --- Fill logic ---
    wire [INDEX_W-1:0] new_idx = new_address[INDEX_W+3 : 4];
    wire [TAG_W-1:0]   new_tag = new_address[ADDRESS_SIZE-1 : INDEX_W+4];

    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < DEPTH; i = i + 1)
                valid[i] <= 1'b0;
        end else if (new_data_save) begin
            tags[new_idx]              <= new_tag;
            valid[new_idx]             <= 1'b1;
            data[{new_idx, 2'd0}]     <= new_data[31:0];
            data[{new_idx, 2'd1}]     <= new_data[63:32];
            data[{new_idx, 2'd2}]     <= new_data[95:64];
            data[{new_idx, 2'd3}]     <= new_data[127:96];
        end
    end

endmodule
