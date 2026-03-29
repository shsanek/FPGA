// BUS_ARBITER — 2-port priority arbiter with standard bus interface.
//
// Each port has a 1-entry command latch. When arbiter is IDLE and
// downstream is ready, commands are forwarded directly (0-cycle).
// When arbiter is BUSY, incoming commands are latched and served later.
//
// Port 0 has priority over Port 1.
// Simultaneous sends: p0 forwarded, p1 latched.

module BUS_ARBITER #(
    parameter DATA_WIDTH = 128,
    parameter MASK_WIDTH = DATA_WIDTH / 8,
    parameter ADDR_WIDTH = 32
)(
    input wire clk,
    input wire reset,

    // === Port 0 (higher priority) — bus slave interface ===
    input  wire [ADDR_WIDTH-1:0]  p0_address,
    input  wire                   p0_read,
    input  wire                   p0_write,
    input  wire [DATA_WIDTH-1:0]  p0_write_data,
    input  wire [MASK_WIDTH-1:0]  p0_write_mask,
    output wire                   p0_ready,
    output wire [DATA_WIDTH-1:0]  p0_read_data,
    output reg                    p0_read_valid,

    // === Port 1 (lower priority) — bus slave interface ===
    input  wire [ADDR_WIDTH-1:0]  p1_address,
    input  wire                   p1_read,
    input  wire                   p1_write,
    input  wire [DATA_WIDTH-1:0]  p1_write_data,
    input  wire [MASK_WIDTH-1:0]  p1_write_mask,
    output wire                   p1_ready,
    output wire [DATA_WIDTH-1:0]  p1_read_data,
    output reg                    p1_read_valid,

    // === Downstream — bus master interface ===
    output reg  [ADDR_WIDTH-1:0]  bus_address,
    output reg                    bus_read,
    output reg                    bus_write,
    output reg  [DATA_WIDTH-1:0]  bus_write_data,
    output reg  [MASK_WIDTH-1:0]  bus_write_mask,
    input  wire                   bus_ready,
    input  wire [DATA_WIDTH-1:0]  bus_read_data,
    input  wire                   bus_read_valid
);

    // Read data shared — only active port gets read_valid
    assign p0_read_data = bus_read_data;
    assign p1_read_data = bus_read_data;

    // =========================================================
    // Per-port command latch (1-entry buffer)
    // =========================================================
    reg                    p0_lat_valid;
    reg                    p0_lat_is_read;
    reg [ADDR_WIDTH-1:0]  p0_lat_address;
    reg [DATA_WIDTH-1:0]  p0_lat_write_data;
    reg [MASK_WIDTH-1:0]  p0_lat_write_mask;

    reg                    p1_lat_valid;
    reg                    p1_lat_is_read;
    reg [ADDR_WIDTH-1:0]  p1_lat_address;
    reg [DATA_WIDTH-1:0]  p1_lat_write_data;
    reg [MASK_WIDTH-1:0]  p1_lat_write_mask;

    // =========================================================
    // FSM
    // =========================================================
    typedef enum logic [0:0] {
        IDLE,
        BUSY
    } state_t;

    state_t state;
    reg active_port;    // 0 or 1
    reg first_busy;     // skip first BUSY cycle (NBA timing guard)

    wire port0_reuest = p0_read || p0_write;
    wire port1_reuest = p1_read || p1_write;

    // Port ready = latch empty AND not being served right now
    wire p0_busy = (state == BUSY) && (active_port == 0);
    wire p1_busy = (state == BUSY) && (active_port == 1);

    assign p0_ready = !p0_lat_valid && !p0_busy;
    assign p1_ready = !p1_lat_valid && !p1_busy;

    // =========================================================
    always_ff @(posedge clk) begin
        if (reset) begin
            state          <= IDLE;
            bus_read       <= 0;
            bus_write      <= 0;
            p0_read_valid  <= 0;
            p1_read_valid  <= 0;
            p0_lat_valid   <= 0;
            p1_lat_valid   <= 0;
            first_busy     <= 0;
            active_port    <= 0;
        end else begin
            // Clear pulses
            bus_read      <= 0;
            bus_write     <= 0;
            p0_read_valid <= 0;
            p1_read_valid <= 0;

            case (state)

                // -------------------------------------------------
                // IDLE: forward by priority (direct or from latch)
                // -------------------------------------------------
                IDLE: begin
                    if (bus_ready) begin

                        // === Direct forward from port inputs (0-cycle) ===
                        if (port0_reuest) begin
                            bus_address    <= p0_address;
                            bus_read       <= p0_read;
                            bus_write      <= p0_write;
                            bus_write_data <= p0_write_data;
                            bus_write_mask <= p0_write_mask;
                            active_port    <= 0;
                            first_busy     <= 1;
                            state          <= BUSY;

                            // p1 sent simultaneously → latch it
                            // (p1_lat_valid guaranteed 0 — port won't send when latch full)
                            if (port1_reuest) begin
                                p1_lat_valid      <= 1;
                                p1_lat_is_read    <= p1_read;
                                p1_lat_address    <= p1_address;
                                p1_lat_write_data <= p1_write_data;
                                p1_lat_write_mask <= p1_write_mask;
                            end

                        end else if (port1_reuest) begin
                            bus_address    <= p1_address;
                            bus_read       <= p1_read;
                            bus_write      <= p1_write;
                            bus_write_data <= p1_write_data;
                            bus_write_mask <= p1_write_mask;
                            active_port    <= 1;
                            first_busy     <= 1;
                            state          <= BUSY;

                        // === Forward from latch (1-cycle, was latched while busy) ===
                        end else if (p0_lat_valid) begin
                            bus_address    <= p0_lat_address;
                            bus_read       <= p0_lat_is_read;
                            bus_write      <= !p0_lat_is_read;
                            bus_write_data <= p0_lat_write_data;
                            bus_write_mask <= p0_lat_write_mask;
                            p0_lat_valid   <= 0;
                            active_port    <= 0;
                            first_busy     <= 1;
                            state          <= BUSY;

                        end else if (p1_lat_valid) begin
                            bus_address    <= p1_lat_address;
                            bus_read       <= p1_lat_is_read;
                            bus_write      <= !p1_lat_is_read;
                            bus_write_data <= p1_lat_write_data;
                            bus_write_mask <= p1_lat_write_mask;
                            p1_lat_valid   <= 0;
                            active_port    <= 1;
                            first_busy     <= 1;
                            state          <= BUSY;
                        end

                    end // bus_ready
                end

                // -------------------------------------------------
                // BUSY: wait for downstream, latch incoming
                // -------------------------------------------------
                BUSY: begin
                    first_busy <= 0;

                    // Latch incoming commands while busy
                    // (port won't send when latch full — ready=0)
                    if (port0_reuest) begin
                        p0_lat_valid      <= 1;
                        p0_lat_is_read    <= p0_read;
                        p0_lat_address    <= p0_address;
                        p0_lat_write_data <= p0_write_data;
                        p0_lat_write_mask <= p0_write_mask;
                    end
                    if (port1_reuest) begin
                        p1_lat_valid      <= 1;
                        p1_lat_is_read    <= p1_read;
                        p1_lat_address    <= p1_address;
                        p1_lat_write_data <= p1_write_data;
                        p1_lat_write_mask <= p1_write_mask;
                    end

                    // Route read response to active port
                    if (bus_read_valid) begin
                        if (active_port == 0) p0_read_valid <= 1;
                        else                  p1_read_valid <= 1;
                    end

                    // Done when downstream ready (skip first cycle — NBA guard)
                    if (bus_ready && !first_busy)
                        state <= IDLE;
                end

            endcase
        end
    end

endmodule
