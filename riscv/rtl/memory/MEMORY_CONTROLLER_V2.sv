// MEMORY_CONTROLLER_V2 — unified cache controller.
//
// Direct-mapped cache (DEPTH lines × 16 bytes).
// READ_ONLY=0 (D-cache): write-back, dirty eviction, read_stream support.
// READ_ONLY=1 (I-cache): read-only, no dirty/evict, write/stream ignored.
//
// Miss flow: read DDR → MISS_SAVE (save + return data + fire evict if dirty).

module MEMORY_CONTROLLER_V2 #(
    parameter DEPTH        = 256,
    parameter READ_ONLY    = 0,
    parameter CHUNK_PART   = 128,
    parameter MASK_SIZE    = CHUNK_PART / 8,   // 16
    parameter ADDRESS_SIZE = 28
)(
    input wire clk,
    input wire reset,

    // === Upstream (D-cache: from MEMORY_MUX, I-cache: Core instruction) ===
    input wire [ADDRESS_SIZE-1:0]  address,
    input wire [1:0]               command,       // 00=nop, 01=read, 10=write
    input wire                     read_stream,   // 1 = don't save to D_CACHE
    input wire [MASK_SIZE-1:0]     write_mask,    // 16-byte mask // not use in I-cache
    input wire [CHUNK_PART-1:0]    write_value, // not use in I-cache

    output reg                     controller_ready,
    output wire [CHUNK_PART-1:0]   read_value,    // 128-bit line
    output reg                     read_value_ready,
    output reg                     write_done, // not use in I-cache

    // === Downstream (D-cache: to RAM_CONTROLLER, I-cache to MEMORY_MUX) ===
    input  wire                    ram_controller_ready,

    output reg  [ADDRESS_SIZE-1:0] ram_address,
    output reg                     ram_read_trigger,
    input  wire [CHUNK_PART-1:0]   ram_read_value,
    input  wire                    ram_read_value_ready,

    output reg                     ram_write_trigger,
    output reg  [CHUNK_PART-1:0]   ram_write_value
);

    // =========================================================
    // Cache geometry
    // =========================================================
    localparam INDEX_W = $clog2(DEPTH);
    localparam TAG_W   = ADDRESS_SIZE - INDEX_W - 4;

    // =========================================================
    // D-Cache storage (direct-mapped, write-back)
    // =========================================================
    reg [TAG_W-1:0]      tags  [0:DEPTH-1];
    reg                  valid [0:DEPTH-1];
    reg                  dirty [0:DEPTH-1];
    reg [CHUNK_PART-1:0] lines [0:DEPTH-1];

    // =========================================================
    // Output buffer (1-entry line buffer — fast path)
    // =========================================================
    reg                    output_valid;
    reg [ADDRESS_SIZE-1:0] output_address;
    reg [CHUNK_PART-1:0]   output_value;

    assign read_value = output_value;

    // =========================================================
    // Latched command state
    // =========================================================
    reg [1:0]              current_command;
    reg                    current_stream;
    reg [ADDRESS_SIZE-1:0] current_address;
    reg [MASK_SIZE-1:0]    current_mask;
    reg [CHUNK_PART-1:0]   current_data;
    reg [CHUNK_PART-1:0]   miss_read_data;

    // =========================================================
    // Address decomposition (from current_address)
    // =========================================================
    wire [INDEX_W-1:0] idx = current_address[INDEX_W+3 : 4];
    wire [TAG_W-1:0]   tag = current_address[ADDRESS_SIZE-1 : INDEX_W+4];

    // =========================================================
    // Cache lookup (combinational)
    // =========================================================
    wire hit        = valid[idx] && (tags[idx] == tag);
    wire need_evict = !READ_ONLY && valid[idx] && dirty[idx];

    // =========================================================
    // Output buffer hit (uses `address` input, not latched)
    // =========================================================
    wire output_hit = output_valid &&
                      (address[ADDRESS_SIZE-1:4] == output_address[ADDRESS_SIZE-1:4]);

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
            state            <= WAIT_REQUEST;
            controller_ready <= 1;
            read_value_ready <= 0;
            write_done       <= 0;
            ram_read_trigger <= 0;
            ram_write_trigger<= 0;
            output_valid     <= 0;
            current_command  <= 0;
            current_stream   <= 0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                valid[i] <= 0;
                dirty[i] <= 0;
            end
        end else begin
            // Clear single-cycle pulses
            read_value_ready  <= 0;
            write_done        <= 0;
            ram_read_trigger  <= 0;
            ram_write_trigger <= 0;

            case (state)

                // -------------------------------------------------
                // WAIT_REQUEST
                // -------------------------------------------------
                WAIT_REQUEST: begin
                    if (command == 2'b01) begin
                        // === READ ===
                        current_command <= command;
                        current_stream  <= READ_ONLY ? 1'b0 : read_stream;
                        current_address <= address;

                        if (output_hit) begin
                            // Output buffer hit — respond, stay ready
                            read_value_ready <= 1;
                        end else begin
                            controller_ready <= 0;
                            state <= READ_CACHE;
                        end

                    end else if (!READ_ONLY && command == 2'b10) begin
                        // === WRITE (D-cache only) ===
                        controller_ready <= 0;
                        current_command <= command;
                        current_stream  <= 0;
                        current_address <= address;
                        current_mask    <= write_mask;
                        current_data    <= write_value;

                        if (output_hit)
                            output_valid <= 0;

                        state <= WRITE_CACHE;
                    end else begin
                        controller_ready <= 1;
                    end
                end

                // -------------------------------------------------
                // READ_CACHE
                // -------------------------------------------------
                READ_CACHE: begin
                    if (hit) begin
                        output_valid     <= 1;
                        output_address   <= {current_address[ADDRESS_SIZE-1:4], 4'b0000};
                        output_value     <= lines[idx];
                        read_value_ready <= 1;
                        controller_ready <= 1;
                        state <= WAIT_REQUEST;
                    end else begin
                        state <= MISS_READ_REQ;
                    end
                end

                // -------------------------------------------------
                // WRITE_CACHE
                // -------------------------------------------------
                WRITE_CACHE: begin
                    if (hit) begin
                        for (i = 0; i < MASK_SIZE; i = i + 1) begin
                            if (current_mask[i])
                                lines[idx][i*8 +: 8] <= current_data[i*8 +: 8];
                        end
                        dirty[idx] <= 1;
                        write_done <= 1;
                        controller_ready <= 1;
                        state <= WAIT_REQUEST;
                    end else begin
                        // Write miss: allocate via DDR (D-cache) or ignore (I-cache)
                        if (READ_ONLY) begin
                            write_done <= 1;
                            controller_ready <= 1;
                            state <= WAIT_REQUEST;
                        end else begin
                            state <= MISS_READ_REQ;
                        end
                    end
                end

                // -------------------------------------------------
                // MISS_READ_REQ: request line from DDR
                // -------------------------------------------------
                MISS_READ_REQ: begin
                    if (ram_controller_ready) begin
                        ram_read_trigger <= 1;
                        ram_address      <= {current_address[ADDRESS_SIZE-1:4], 4'b0000};
                        state <= MISS_READ_WAIT;
                    end
                end

                // -------------------------------------------------
                // MISS_READ_WAIT: wait for DDR data
                // -------------------------------------------------
                MISS_READ_WAIT: begin
                    if (ram_read_value_ready) begin
                        miss_read_data <= ram_read_value;
                        state <= MISS_SAVE;
                    end
                end

                // -------------------------------------------------
                // MISS_SAVE: save + return read data + fire evict
                //
                // NBA: RHS reads OLD tags/lines, LHS writes NEW.
                // -------------------------------------------------
                MISS_SAVE: begin
                    // For READ: return data immediately (no retry needed)
                    if (current_command == 2'b01) begin
                        output_valid     <= 1;
                        output_address   <= {current_address[ADDRESS_SIZE-1:4], 4'b0000};
                        output_value     <= miss_read_data;
                        read_value_ready <= 1;
                    end

                    if (current_stream) begin
                        // Stream: don't save to cache, done
                        controller_ready <= 1;
                        state <= WAIT_REQUEST;
                    end else begin
                        // Save new line to D_CACHE
                        tags[idx]  <= tag;
                        valid[idx] <= 1;
                        dirty[idx] <= 0;
                        lines[idx] <= miss_read_data;

                        // Evict old dirty line (fire-and-forget)
                        // DDR write runs in background; next miss waits in MISS_READ_REQ
                        if (need_evict) begin
                            ram_write_trigger <= 1;
                            ram_address       <= {tags[idx], idx, 4'b0000};
                            ram_write_value   <= lines[idx];
                        end

                        if (current_command == 2'b01) begin
                            // Read: data already returned above
                            controller_ready <= 1;
                            state <= WAIT_REQUEST;
                        end else begin
                            // Write: byte-masked write (guaranteed hit next cycle)
                            state <= WRITE_CACHE;
                        end
                    end
                end

                default: state <= WAIT_REQUEST;

            endcase
        end
    end

endmodule
