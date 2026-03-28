module MEMORY_CONTROLLER#(
    parameter CHUNK_PART = 128,
    parameter DATA_SIZE = 32,
    parameter MASK_SIZE = DATA_SIZE / 8,
    parameter ADDRESS_SIZE = 28
)(
    input wire clk,
    input wire reset,

    // RAM
    input logic ram_controller_ready,

    output logic ram_write_trigger,
    output logic[CHUNK_PART - 1: 0] ram_write_value,
    output logic[ADDRESS_SIZE - 1:0] ram_write_address,

    output logic ram_read_trigger,
    input wire[CHUNK_PART - 1: 0] ram_read_value,
    output logic[ADDRESS_SIZE - 1:0] ram_read_address,
    input wire ram_read_value_ready,

    // USER INTERFACE
    output wire controller_ready,
    input wire[ADDRESS_SIZE - 1:0] address,
    input wire[MASK_SIZE - 1: 0] mask,

    input wire write_trigger,
    input wire[DATA_SIZE-1: 0] write_value,

    input wire read_trigger,
    output wire[DATA_SIZE-1: 0] read_value,
    output wire contains_address,

    // Stream bit: 1 = use stream line instead of cache
    input wire stream
);

    // =========================================================
    // Cache wires
    // =========================================================
    wire[ADDRESS_SIZE - 1:0] cache_save_address;
    wire[CHUNK_PART - 1: 0]  cache_save_data;
    wire                     cache_save_need_flag;
    wire                     cache_contains_address;
    wire[DATA_SIZE - 1:0]    cache_read_value;

    // =========================================================
    // Stream wires
    // =========================================================
    wire                     stream_contains_address;
    wire[DATA_SIZE - 1:0]    stream_read_value;

    // =========================================================
    // Mux: contains_address и read_value по stream биту
    // =========================================================
    wire internal_contains_address = stream ? stream_contains_address
                                            : cache_contains_address;

    assign contains_address = internal_contains_address;
    assign read_value       = stream ? stream_read_value
                                     : cache_read_value;

    // save_need_flag: stream read-only, never dirty
    wire save_need_flag = stream_latched ? 1'b0 : cache_save_need_flag;
    wire[ADDRESS_SIZE - 1:0] save_address = cache_save_address;
    wire[CHUNK_PART - 1: 0]  save_data    = cache_save_data;

    // =========================================================
    // Shared FSM state
    // =========================================================
    logic[CHUNK_PART - 1: 0]  new_data;
    logic[ADDRESS_SIZE - 1:0] new_address;
    logic                     new_data_save;

    logic internal_write_trigger;
    logic[ADDRESS_SIZE - 1:0] internal_address;
    logic[MASK_SIZE - 1:0]    internal_mask;
    logic[DATA_SIZE - 1:0]    internal_write_data;

    logic had_dirty_evict;
    logic stream_latched;  // stream bit, защёлкнутый при начале miss

    typedef enum logic [2:0] {
        MEMORY_CONTROLLER_STATE_NORMAL,
        MEMORY_CONTROLLER_STATE_WATING,
        MEMORY_CONTROLLER_STATE_SAVE_DATA,
        MEMORY_CONTROLLER_STATE_WRITE_DATA,
        MEMORY_CONTROLLER_STATE_WAIT_DIRTY
    } MEMORY_CONTROLLER_STATE;

    MEMORY_CONTROLLER_STATE internal_state;

    // =========================================================
    // Output mux (WRITE_DATA state uses latched values)
    // =========================================================
    wire output_write_trigger;
    wire[ADDRESS_SIZE - 1:0] output_address;
    wire[MASK_SIZE - 1:0] output_mask;
    wire[DATA_SIZE - 1:0] output_write_value;

    assign output_write_trigger = (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) ? internal_write_trigger : write_trigger;
    assign output_address       = (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) ? internal_address       : address;
    assign output_mask          = (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) ? internal_mask          : mask;
    assign output_write_value   = (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) ? internal_write_data    : write_value;

    assign controller_ready = (internal_state == MEMORY_CONTROLLER_STATE_NORMAL) && ram_controller_ready;

    wire order_tick = (internal_state != MEMORY_CONTROLLER_STATE_NORMAL);

    // =========================================================
    // FSM
    // =========================================================
    always_ff @(posedge clk) begin
        if (reset) begin
            internal_write_trigger <= 0;
            internal_state         <= MEMORY_CONTROLLER_STATE_NORMAL;
            new_data_save          <= 0;
            ram_write_trigger      <= 0;
            ram_read_trigger       <= 0;
            had_dirty_evict        <= 0;
            stream_latched         <= 0;
        end else begin

            if (internal_state == MEMORY_CONTROLLER_STATE_SAVE_DATA) begin
                new_data_save     <= 0;
                ram_write_trigger <= 0;
                if (had_dirty_evict)
                    internal_state <= MEMORY_CONTROLLER_STATE_WAIT_DIRTY;
                else if (internal_write_trigger)
                    internal_state <= MEMORY_CONTROLLER_STATE_WRITE_DATA;
                else
                    internal_state <= MEMORY_CONTROLLER_STATE_NORMAL;

            end else if (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) begin
                internal_write_trigger <= 0;
                internal_state <= MEMORY_CONTROLLER_STATE_NORMAL;

            end else if (internal_state == MEMORY_CONTROLLER_STATE_WAIT_DIRTY) begin
                if (ram_controller_ready) begin
                    had_dirty_evict <= 0;
                    if (internal_write_trigger)
                        internal_state <= MEMORY_CONTROLLER_STATE_WRITE_DATA;
                    else
                        internal_state <= MEMORY_CONTROLLER_STATE_NORMAL;
                end

            end else if (internal_state == MEMORY_CONTROLLER_STATE_NORMAL && ram_controller_ready) begin
                if ((!internal_contains_address) && (read_trigger || write_trigger)) begin
                    internal_write_trigger <= write_trigger;
                    internal_address       <= address;
                    internal_mask          <= mask;
                    internal_write_data    <= write_value;
                    stream_latched         <= stream;

                    ram_read_trigger  <= 1;
                    ram_read_address  <= { address[ADDRESS_SIZE-1:4], 4'b0000 };
                    internal_state    <= MEMORY_CONTROLLER_STATE_WATING;
                end

            end else if (internal_state == MEMORY_CONTROLLER_STATE_WATING) begin
                ram_read_trigger <= 0;
                if (ram_read_value_ready) begin
                    if (save_need_flag) begin
                        ram_write_trigger <= 1;
                        ram_write_value   <= save_data;
                        ram_write_address <= save_address;
                        had_dirty_evict   <= 1;
                    end
                    new_address   <= ram_read_address;
                    new_data      <= ram_read_value;
                    new_data_save <= 1;
                    internal_state <= MEMORY_CONTROLLER_STATE_SAVE_DATA;
                end
            end
        end
    end

    // =========================================================
    // CHUNK_STORAGE_4_POOL (main cache)
    // =========================================================
    CHUNK_STORAGE_4_POOL #(
        .CHUNK_PART(CHUNK_PART),
        .DATA_SIZE(DATA_SIZE),
        .MASK_SIZE(MASK_SIZE),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) storage_pool (
        .clk                   (clk),
        .reset                 (reset),
        .address               (output_address),
        .mask                  (output_mask),
        .write_trigger         (output_write_trigger),
        .write_value           (output_write_value),
        .read_trigger          (read_trigger),
        .read_value            (cache_read_value),
        .contains_address      (cache_contains_address),
        .save_address          (cache_save_address),
        .save_data             (cache_save_data),
        .save_need_flag        (cache_save_need_flag),
        .order_tick            (order_tick),
        .new_data              (new_data),
        .new_address           (new_address),
        .new_data_save         (new_data_save && !stream_latched)
    );

    // =========================================================
    // STREAM_CACHE (1-entry read-only)
    // =========================================================
    STREAM_CACHE #(
        .CHUNK_PART(CHUNK_PART),
        .DATA_SIZE(DATA_SIZE),
        .MASK_SIZE(MASK_SIZE),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) stream_cache (
        .clk                   (clk),
        .reset                 (reset),
        .address               (output_address),
        .mask                  (output_mask),
        .write_trigger         (1'b0),
        .write_value           ('0),
        .read_trigger          (read_trigger),
        .read_value            (stream_read_value),
        .contains_address      (stream_contains_address),
        .save_address          (),
        .save_data             (),
        .save_need_flag        (),
        .order_tick            (order_tick),
        .new_data              (new_data),
        .new_address           (new_address),
        .new_data_save         (new_data_save && stream_latched)
    );

endmodule
