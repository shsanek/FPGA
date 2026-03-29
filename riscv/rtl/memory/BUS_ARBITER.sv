// BUS_ARBITER — 2-port priority arbiter with standard bus interface.
//
// Port 0 has priority. Incoming commands latched into registers,
// then forwarded to bus. States encode exactly what's happening:
//
//   IDLE → WAIT_P0 / WAIT_P1 / WAIT_P0_QUEUE_P1
//   WAIT_P0 → IDLE (done) / WAIT_P0_QUEUE_P1 (p1 arrives)
//   WAIT_P1 → IDLE (done) / QUEUE_P0_WAIT_P1 (p0 arrives)
//   WAIT_P0_QUEUE_P1 → WAIT_P1 (p0 done, forward p1)
//   QUEUE_P0_WAIT_P1 → WAIT_P0 (p1 done, forward p0)

module BUS_ARBITER #(
    parameter DATA_WIDTH = 128,
    parameter MASK_WIDTH = DATA_WIDTH / 8,
    parameter ADDR_WIDTH = 32
)(
    input wire clk,
    input wire reset,

    // === Port 0 (higher priority) ===
    input  wire [ADDR_WIDTH-1:0]  p0_address,
    input  wire                   p0_read,
    input  wire                   p0_write,
    input  wire [DATA_WIDTH-1:0]  p0_write_data,
    input  wire [MASK_WIDTH-1:0]  p0_write_mask,
    output wire                   p0_ready,
    output wire [DATA_WIDTH-1:0]  p0_read_data,
    output reg                    p0_read_valid,

    // === Port 1 (lower priority) ===
    input  wire [ADDR_WIDTH-1:0]  p1_address,
    input  wire                   p1_read,
    input  wire                   p1_write,
    input  wire [DATA_WIDTH-1:0]  p1_write_data,
    input  wire [MASK_WIDTH-1:0]  p1_write_mask,
    output wire                   p1_ready,
    output wire [DATA_WIDTH-1:0]  p1_read_data,
    output reg                    p1_read_valid,

    // === Downstream ===
    output reg  [ADDR_WIDTH-1:0]  bus_address,
    output reg                    bus_read,
    output reg                    bus_write,
    output reg  [DATA_WIDTH-1:0]  bus_write_data,
    output reg  [MASK_WIDTH-1:0]  bus_write_mask,
    input  wire                   bus_ready,
    input  wire [DATA_WIDTH-1:0]  bus_read_data,
    input  wire                   bus_read_valid
);

    assign p0_read_data = bus_read_data;
    assign p1_read_data = bus_read_data;

    // =========================================================
    // Port registers (latched on send)
    // =========================================================
    reg [ADDR_WIDTH-1:0]  p0_reg_address;
    reg                   p0_reg_is_read;
    reg [DATA_WIDTH-1:0]  p0_reg_write_data;
    reg [MASK_WIDTH-1:0]  p0_reg_write_mask;

    reg [ADDR_WIDTH-1:0]  p1_reg_address;
    reg                   p1_reg_is_read;
    reg [DATA_WIDTH-1:0]  p1_reg_write_data;
    reg [MASK_WIDTH-1:0]  p1_reg_write_mask;

    // =========================================================
    // FSM
    // =========================================================
    typedef enum logic [2:0] {
        IDLE,
        WAIT_P0,
        WAIT_P1,
        WAIT_P0_QUEUE_P1,
        QUEUE_P0_WAIT_P1
    } state_t;

    state_t state;
    reg first_cycle;  // NBA timing guard

    wire p0_request = p0_read || p0_write;
    wire p1_request = p1_read || p1_write;

    // Port ready: can send when IDLE, or when OTHER port is being served (queue slot free)
    assign p0_ready = (state == IDLE) || (state == WAIT_P1);
    assign p1_ready = (state == IDLE) || (state == WAIT_P0);

    // Bus done = downstream ready AND not first cycle (NBA guard)
    wire bus_done = bus_ready && !first_cycle;

    // =========================================================
    always_ff @(posedge clk) begin
        if (reset) begin
            state         <= IDLE;
            bus_read      <= 0;
            bus_write     <= 0;
            p0_read_valid <= 0;
            p1_read_valid <= 0;
            first_cycle   <= 0;
        end else begin
            bus_read      <= 0;
            bus_write     <= 0;
            p0_read_valid <= 0;
            p1_read_valid <= 0;

            case (state)

                IDLE: begin
                    if (p0_request) begin
                        // Latch p0
                        p0_reg_address    <= p0_address;
                        p0_reg_is_read    <= p0_read;
                        p0_reg_write_data <= p0_write_data;
                        p0_reg_write_mask <= p0_write_mask;
                        // Forward p0 to bus
                        bus_address    <= p0_address;
                        bus_read       <= p0_read;
                        bus_write      <= p0_write;
                        bus_write_data <= p0_write_data;
                        bus_write_mask <= p0_write_mask;
                        first_cycle    <= 1;

                        if (p1_request) begin
                            // Latch p1 too (simultaneous)
                            p1_reg_address    <= p1_address;
                            p1_reg_is_read    <= p1_read;
                            p1_reg_write_data <= p1_write_data;
                            p1_reg_write_mask <= p1_write_mask;
                            state <= WAIT_P0_QUEUE_P1;
                        end else begin
                            state <= WAIT_P0;
                        end

                    end else if (p1_request) begin
                        // Latch p1
                        p1_reg_address    <= p1_address;
                        p1_reg_is_read    <= p1_read;
                        p1_reg_write_data <= p1_write_data;
                        p1_reg_write_mask <= p1_write_mask;
                        // Forward p1 to bus
                        bus_address    <= p1_address;
                        bus_read       <= p1_read;
                        bus_write      <= p1_write;
                        bus_write_data <= p1_write_data;
                        bus_write_mask <= p1_write_mask;
                        first_cycle    <= 1;
                        state <= WAIT_P1;
                    end
                end

                WAIT_P0: begin
                    first_cycle <= 0;
                    // p1 can arrive while we wait
                    if (p1_request) begin
                        p1_reg_address    <= p1_address;
                        p1_reg_is_read    <= p1_read;
                        p1_reg_write_data <= p1_write_data;
                        p1_reg_write_mask <= p1_write_mask;
                        state <= WAIT_P0_QUEUE_P1;
                    end
                    // Bus done → response to p0
                    if (bus_done) begin
                        if (bus_read_valid) p0_read_valid <= 1;
                        if (!p1_request)
                            state <= IDLE;
                        else
                            state <= WAIT_P0_QUEUE_P1;
                    end
                end

                WAIT_P1: begin
                    first_cycle <= 0;
                    // p0 can arrive while we wait
                    if (p0_request) begin
                        p0_reg_address    <= p0_address;
                        p0_reg_is_read    <= p0_read;
                        p0_reg_write_data <= p0_write_data;
                        p0_reg_write_mask <= p0_write_mask;
                        state <= QUEUE_P0_WAIT_P1;
                    end
                    // Bus done → response to p1
                    if (bus_done) begin
                        if (bus_read_valid) p1_read_valid <= 1;
                        if (!p0_request)
                            state <= IDLE;
                        else
                            state <= QUEUE_P0_WAIT_P1;
                    end
                end

                WAIT_P0_QUEUE_P1: begin
                    first_cycle <= 0;
                    // Bus done → response to p0, forward p1 from latch
                    if (bus_done) begin
                        if (bus_read_valid) p0_read_valid <= 1;
                        // Forward queued p1
                        bus_address    <= p1_reg_address;
                        bus_read       <= p1_reg_is_read;
                        bus_write      <= !p1_reg_is_read;
                        bus_write_data <= p1_reg_write_data;
                        bus_write_mask <= p1_reg_write_mask;
                        first_cycle    <= 1;
                        state <= WAIT_P1;
                    end
                end

                QUEUE_P0_WAIT_P1: begin
                    first_cycle <= 0;
                    // Bus done → response to p1, forward p0 from latch
                    if (bus_done) begin
                        if (bus_read_valid) p1_read_valid <= 1;
                        // Forward queued p0
                        bus_address    <= p0_reg_address;
                        bus_read       <= p0_reg_is_read;
                        bus_write      <= !p0_reg_is_read;
                        bus_write_data <= p0_reg_write_data;
                        bus_write_mask <= p0_reg_write_mask;
                        first_cycle    <= 1;
                        state <= WAIT_P0;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
