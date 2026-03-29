// MEMORY_CONTROLLER_V2 — unified cache controller on standard bus.
//
// Bus slave (upstream): 128-bit data, 16-bit mask, 32-bit address.
// Bus master (external, downstream to DDR): same standard bus interface.
//
// WAYS=1: direct-mapped. WAYS=2: 2-way set-associative with LRU.
// READ_ONLY=0 (D-cache): write-back, dirty eviction.
// READ_ONLY=1 (I-cache): read-only, no dirty/evict, write ignored.
//
// Stream: bus_address[29]=1 → don't save to cache (bypass).
//         READ_ONLY=1 ignores stream (always caches).
//
// Miss flow: read DDR → MISS_SAVE (save + return data + fire evict if dirty).

module MEMORY_CONTROLLER_V2 #(
    parameter DEPTH      = 256,
    parameter WAYS       = 1,
    parameter READ_ONLY  = 0,
    parameter DATA_WIDTH = 128,
    parameter MASK_WIDTH = DATA_WIDTH / 8,
    parameter ADDR_WIDTH = 32
)(
    input wire clk,
    input wire reset,

    // === Cache invalidate (e.g. flush I_CACHE line on write to code region) ===
    output reg                    invalidate_ready,
    input  wire [ADDR_WIDTH-1:0]  invalidate_address,
    input  wire                   invalidate_trigger,

    // === Bus slave (upstream) ===
    input  wire [ADDR_WIDTH-1:0]  bus_address,
    input  wire                   bus_read,
    input  wire                   bus_write,
    input  wire [DATA_WIDTH-1:0]  bus_write_data,
    input  wire [MASK_WIDTH-1:0]  bus_write_mask,
    output reg                    bus_ready,
    output wire [DATA_WIDTH-1:0]  bus_read_data,
    output reg                    bus_read_valid,

    // === Bus master (downstream, to DDR) ===
    output reg  [ADDR_WIDTH-1:0]  external_address,
    output reg                    external_read,
    output reg                    external_write,
    output reg  [DATA_WIDTH-1:0]  external_write_data,
    output reg  [MASK_WIDTH-1:0]  external_write_mask,
    input  wire                   external_ready,
    input  wire [DATA_WIDTH-1:0]  external_read_data,
    input  wire                   external_read_valid
);

    // =========================================================
    // Cache geometry (uses lower 28 bits of address)
    // =========================================================
    localparam CACHE_ADDR_W = 28;
    localparam SETS    = DEPTH / WAYS;
    localparam INDEX_W = $clog2(SETS);
    localparam TAG_W   = CACHE_ADDR_W - INDEX_W - 4;

    // =========================================================
    // Cache storage: 2 ways (way1 unused when WAYS=1)
    // =========================================================
    reg [TAG_W-1:0]      tags_0  [0:SETS-1];
    reg                  valid_0 [0:SETS-1];
    reg                  dirty_0 [0:SETS-1];
    reg [DATA_WIDTH-1:0] lines_0 [0:SETS-1];

    reg [TAG_W-1:0]      tags_1  [0:SETS-1];
    reg                  valid_1 [0:SETS-1];
    reg                  dirty_1 [0:SETS-1];
    reg [DATA_WIDTH-1:0] lines_1 [0:SETS-1];

    reg lru [0:SETS-1];

    // =========================================================
    // Output buffer (1-entry line buffer)
    // =========================================================
    reg                        output_valid;
    reg [CACHE_ADDR_W-1:0]     output_address;
    reg [DATA_WIDTH-1:0]       output_value;

    assign bus_read_data = output_value;

    // =========================================================
    // Latched command state
    // =========================================================
    reg                    current_is_write;
    reg                    current_stream;
    reg [CACHE_ADDR_W-1:0] current_address;
    reg [MASK_WIDTH-1:0]   current_mask;
    reg [DATA_WIDTH-1:0]   current_data;
    reg [DATA_WIDTH-1:0]   miss_read_data;

    // =========================================================
    // Address decomposition (from current_address, lower 28 bits)
    // =========================================================
    wire [INDEX_W-1:0] idx = current_address[INDEX_W+3 : 4];
    wire [TAG_W-1:0]   tag = current_address[CACHE_ADDR_W-1 : INDEX_W+4];

    // =========================================================
    // Hit check (both ways)
    // =========================================================
    wire hit_0 = valid_0[idx] && (tags_0[idx] == tag);
    wire hit_1 = (WAYS > 1) && valid_1[idx] && (tags_1[idx] == tag);
    wire hit   = hit_0 || hit_1;
    wire hit_way = hit_1;
    wire [DATA_WIDTH-1:0] hit_line = hit_1 ? lines_1[idx] : lines_0[idx];

    // =========================================================
    // Allocation / eviction (on miss)
    // =========================================================
    wire alloc_way = (WAYS == 1)   ? 1'b0 :
                     !valid_0[idx] ? 1'b0 :
                     !valid_1[idx] ? 1'b1 :
                     lru[idx];

    wire alloc_valid = alloc_way ? valid_1[idx] : valid_0[idx];
    wire alloc_dirty = alloc_way ? dirty_1[idx] : dirty_0[idx];
    wire need_evict  = !READ_ONLY && alloc_valid && alloc_dirty;

    wire [TAG_W-1:0]      evict_tag  = alloc_way ? tags_1[idx]  : tags_0[idx];
    wire [DATA_WIDTH-1:0] evict_line = alloc_way ? lines_1[idx] : lines_0[idx];

    // =========================================================
    // Output buffer hit (uses bus_address input, lower 28 bits)
    // =========================================================
    wire output_hit = output_valid &&
                      (bus_address[CACHE_ADDR_W-1:4] == output_address[CACHE_ADDR_W-1:4]);

    // =========================================================
    // Stream flag: bus_address[29]=1 → don't cache (READ_ONLY ignores)
    // =========================================================
    wire addr_stream = bus_address[29];

    // Invalidate: TODO — implement cache line invalidation
    // For now just report ready when in WAIT_REQUEST

    // =========================================================
    // FSM states
    // =========================================================
    typedef enum logic [2:0] {
        WAIT_REQUEST,
        READ_CACHE,
        WRITE_CACHE,
        MISS_READ_REQ,
        MISS_READ_WAIT,
        MISS_SAVE
    } state_t;

    state_t state;

    // =========================================================
    // FSM
    // =========================================================
    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            state              <= WAIT_REQUEST;
            bus_ready          <= 1;
            bus_read_valid     <= 0;
            external_read      <= 0;
            external_write     <= 0;
            output_valid       <= 0;
            current_is_write   <= 0;
            current_stream     <= 0;
            invalidate_ready <= 1;
            for (i = 0; i < SETS; i = i + 1) begin
                valid_0[i] <= 0;
                dirty_0[i] <= 0;
                valid_1[i] <= 0;
                dirty_1[i] <= 0;
                lru[i]     <= 0;
            end
        end else begin
            // Clear single-cycle pulses
            bus_read_valid <= 0;
            external_read  <= 0;
            external_write <= 0;

            // Invalidate: TODO
            invalidate_ready <= (state == WAIT_REQUEST);

            case (state)

                // -------------------------------------------------
                WAIT_REQUEST: begin
                    if (bus_read) begin
                        current_is_write <= 0;
                        current_stream   <= READ_ONLY ? 1'b0 : addr_stream;
                        current_address  <= bus_address[CACHE_ADDR_W-1:0];

                        if (output_hit) begin
                            bus_read_valid <= 1;
                        end else begin
                            bus_ready <= 0;
                            state <= READ_CACHE;
                        end

                    end else if (!READ_ONLY && bus_write) begin
                        bus_ready        <= 0;
                        current_is_write <= 1;
                        current_stream   <= 0;
                        current_address  <= bus_address[CACHE_ADDR_W-1:0];
                        current_mask     <= bus_write_mask;
                        current_data     <= bus_write_data;

                        if (output_hit)
                            output_valid <= 0;

                        state <= WRITE_CACHE;
                    end else begin
                        bus_ready <= 1;
                    end
                end

                // -------------------------------------------------
                READ_CACHE: begin
                    if (hit) begin
                        output_valid   <= 1;
                        output_address <= current_address;
                        output_value   <= hit_line;
                        bus_read_valid <= 1;
                        bus_ready      <= 1;
                        if (WAYS > 1) lru[idx] <= !hit_way;
                        state <= WAIT_REQUEST;
                    end else begin
                        state <= MISS_READ_REQ;
                    end
                end

                // -------------------------------------------------
                WRITE_CACHE: begin
                    if (hit) begin
                        if (hit_1) begin
                            for (i = 0; i < MASK_WIDTH; i = i + 1)
                                if (current_mask[i])
                                    lines_1[idx][i*8 +: 8] <= current_data[i*8 +: 8];
                            dirty_1[idx] <= 1;
                        end else begin
                            for (i = 0; i < MASK_WIDTH; i = i + 1)
                                if (current_mask[i])
                                    lines_0[idx][i*8 +: 8] <= current_data[i*8 +: 8];
                            dirty_0[idx] <= 1;
                        end
                        if (WAYS > 1) lru[idx] <= !hit_way;
                        bus_ready <= 1;
                        state <= WAIT_REQUEST;
                    end else begin
                        if (READ_ONLY) begin
                            bus_ready <= 1;
                            state <= WAIT_REQUEST;
                        end else begin
                            state <= MISS_READ_REQ;
                        end
                    end
                end

                // -------------------------------------------------
                MISS_READ_REQ: begin
                    if (external_ready) begin
                        external_read    <= 1;
                        external_address <= {{(ADDR_WIDTH-CACHE_ADDR_W){1'b0}},
                                             current_address[CACHE_ADDR_W-1:4], 4'b0000};
                        state <= MISS_READ_WAIT;
                    end
                end

                // -------------------------------------------------
                MISS_READ_WAIT: begin
                    if (external_read_valid) begin
                        miss_read_data <= external_read_data;
                        state <= MISS_SAVE;
                    end
                end

                // -------------------------------------------------
                // MISS_SAVE: save + return read data + fire evict
                // NBA: RHS reads OLD tags/lines, LHS writes NEW.
                // -------------------------------------------------
                MISS_SAVE: begin
                    // For READ: return data immediately
                    if (!current_is_write) begin
                        output_valid   <= 1;
                        output_address <= current_address;
                        output_value   <= miss_read_data;
                        bus_read_valid <= 1;
                    end

                    if (current_stream) begin
                        bus_ready <= 1;
                        state <= WAIT_REQUEST;
                    end else begin
                        // Save new line to alloc_way
                        if (alloc_way) begin
                            tags_1[idx]  <= tag;
                            valid_1[idx] <= 1;
                            dirty_1[idx] <= 0;
                            lines_1[idx] <= miss_read_data;
                        end else begin
                            tags_0[idx]  <= tag;
                            valid_0[idx] <= 1;
                            dirty_0[idx] <= 0;
                            lines_0[idx] <= miss_read_data;
                        end

                        if (WAYS > 1) lru[idx] <= !alloc_way;

                        // Evict old dirty line (fire-and-forget, full mask)
                        if (need_evict) begin
                            external_write      <= 1;
                            external_address    <= {{(ADDR_WIDTH-CACHE_ADDR_W){1'b0}},
                                                    evict_tag, idx, 4'b0000};
                            external_write_data <= evict_line;
                            external_write_mask <= {MASK_WIDTH{1'b1}};
                        end

                        if (!current_is_write) begin
                            bus_ready <= 1;
                            state <= WAIT_REQUEST;
                        end else begin
                            state <= WRITE_CACHE;
                        end
                    end
                end

                default: state <= WAIT_REQUEST;

            endcase
        end
    end

endmodule
