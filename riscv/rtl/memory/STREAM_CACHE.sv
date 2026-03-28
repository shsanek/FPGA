// STREAM_CACHE — 1-entry read-only cache line.
//
// Тот же внешний интерфейс что у CHUNK_STORAGE_4_POOL.
// Один слот 128 бит, без dirty/save (read-only, never evicts to DDR).
// save_need_flag = 0 всегда.
module STREAM_CACHE #(
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

    // WRITE (not used — read-only cache, but interface must match)
    input wire write_trigger,
    input wire[DATA_SIZE-1: 0] write_value,

    // READ
    input wire read_trigger,
    output wire[DATA_SIZE-1: 0] read_value,
    output wire contains_address,

    output wire[ADDRESS_SIZE - 1:0] save_address,
    output wire[CHUNK_PART - 1: 0] save_data,
    output wire save_need_flag,

    output wire[15:0] order_index,

    input wire order_tick,

    input wire[CHUNK_PART - 1: 0] new_data,
    input wire[ADDRESS_SIZE - 1:0] new_address,
    input wire new_data_save
);

    logic [ADDRESS_SIZE-5:0] chunk_addr;
    logic                    chunk_valid;
    logic [DATA_SIZE-1:0]    chunk_data0;
    logic [DATA_SIZE-1:0]    chunk_data1;
    logic [DATA_SIZE-1:0]    chunk_data2;
    logic [DATA_SIZE-1:0]    chunk_data3;

    // Tag compare
    wire internal_contains = chunk_valid &&
                             (chunk_addr == address[ADDRESS_SIZE-1:4]);
    wire [1:0] word_sel = address[3:2];

    assign contains_address = internal_contains;

    // Read: select word from 128-bit chunk
    assign read_value = internal_contains ? (
        word_sel == 2'd0 ? chunk_data0 :
        word_sel == 2'd1 ? chunk_data1 :
        word_sel == 2'd2 ? chunk_data2 : chunk_data3
    ) : 32'd0;

    // Read-only: never needs save
    assign save_address   = '0;
    assign save_data      = '0;
    assign save_need_flag = 1'b0;

    // Order: always max (lowest priority for eviction — but only 1 slot)
    assign order_index = 16'hFFFF;

    always_ff @(posedge clk) begin
        if (reset) begin
            chunk_valid <= 1'b0;
        end else begin
            if (new_data_save) begin
                chunk_addr  <= new_address[ADDRESS_SIZE-1:4];
                chunk_data0 <= new_data[31:0];
                chunk_data1 <= new_data[63:32];
                chunk_data2 <= new_data[95:64];
                chunk_data3 <= new_data[127:96];
                chunk_valid <= 1'b1;
            end
        end
    end

endmodule
