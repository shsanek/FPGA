// I_CACHE — direct-mapped cache with optional write support.
//
// DEPTH lines x 16 bytes. Same external interface as CHUNK_STORAGE_4_POOL.
// READ_ONLY=1 (default): save_need_flag=0 always, writes ignored (I-cache mode).
// READ_ONLY=0: byte-masked writes, dirty tracking, write-back eviction (D-cache mode).
//
// Address decomposition (28-bit):
//   [tag | index (clog2(DEPTH)) | offset (4 bit)]
//
// Hit check is combinational (tags/valid in distributed RAM).
// Data stored as 128-bit lines, word selected by address[3:2].
module I_CACHE #(
    parameter DEPTH = 256,
    parameter READ_ONLY = 1,
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

    // Dirty bit per line (only meaningful when READ_ONLY=0)
    reg dirty [0:DEPTH-1];

    // Data storage: one 128-bit line per entry (single write port)
    reg [CHUNK_PART-1:0] lines [0:DEPTH-1];

    // --- Address decomposition ---
    wire [INDEX_W-1:0] idx      = address[INDEX_W+3 : 4];
    wire [TAG_W-1:0]   addr_tag = address[ADDRESS_SIZE-1 : INDEX_W+4];
    wire [1:0]         word_sel = address[3:2];

    // --- Hit check (combinational) ---
    wire hit = valid[idx] && (tags[idx] == addr_tag);
    assign contains_address = hit;

    // --- Read value: select word from 128-bit line ---
    wire [CHUNK_PART-1:0] line_data = lines[idx];
    reg [DATA_SIZE-1:0] selected_word;
    always_comb begin
        case (word_sel)
            2'd0: selected_word = line_data[31:0];
            2'd1: selected_word = line_data[63:32];
            2'd2: selected_word = line_data[95:64];
            2'd3: selected_word = line_data[127:96];
        endcase
    end
    assign read_value = hit ? selected_word : {DATA_SIZE{1'b0}};

    // --- Eviction / dirty outputs ---
    generate
        if (READ_ONLY) begin : gen_ro
            assign save_address   = {ADDRESS_SIZE{1'b0}};
            assign save_data      = {CHUNK_PART{1'b0}};
            assign save_need_flag = 1'b0;
        end else begin : gen_rw
            assign save_need_flag = dirty[idx] && valid[idx];
            assign save_address   = {tags[idx], idx, 4'b0000};
            assign save_data      = lines[idx];
        end
    endgenerate

    // --- Fill logic ---
    wire [INDEX_W-1:0] new_idx = new_address[INDEX_W+3 : 4];
    wire [TAG_W-1:0]   new_tag = new_address[ADDRESS_SIZE-1 : INDEX_W+4];

    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                valid[i] <= 1'b0;
                dirty[i] <= 1'b0;
            end
        end else if (new_data_save) begin
            tags[new_idx]  <= new_tag;
            valid[new_idx] <= 1'b1;
            dirty[new_idx] <= 1'b0;
            lines[new_idx] <= new_data;
        end else if (!READ_ONLY && write_trigger && hit) begin
            // Byte-masked write into the hit line
            begin
                reg [CHUNK_PART-1:0] updated_line;
                updated_line = lines[idx];
                case (word_sel)
                    2'd0: begin
                        if (mask[0]) updated_line[ 7: 0] = write_value[ 7: 0];
                        if (mask[1]) updated_line[15: 8] = write_value[15: 8];
                        if (mask[2]) updated_line[23:16] = write_value[23:16];
                        if (mask[3]) updated_line[31:24] = write_value[31:24];
                    end
                    2'd1: begin
                        if (mask[0]) updated_line[39:32] = write_value[ 7: 0];
                        if (mask[1]) updated_line[47:40] = write_value[15: 8];
                        if (mask[2]) updated_line[55:48] = write_value[23:16];
                        if (mask[3]) updated_line[63:56] = write_value[31:24];
                    end
                    2'd2: begin
                        if (mask[0]) updated_line[71:64] = write_value[ 7: 0];
                        if (mask[1]) updated_line[79:72] = write_value[15: 8];
                        if (mask[2]) updated_line[87:80] = write_value[23:16];
                        if (mask[3]) updated_line[95:88] = write_value[31:24];
                    end
                    2'd3: begin
                        if (mask[0]) updated_line[103: 96] = write_value[ 7: 0];
                        if (mask[1]) updated_line[111:104] = write_value[15: 8];
                        if (mask[2]) updated_line[119:112] = write_value[23:16];
                        if (mask[3]) updated_line[127:120] = write_value[31:24];
                    end
                endcase
                lines[idx] <= updated_line;
            end
            dirty[idx] <= 1'b1;
        end
    end

endmodule
