// MEMORY_MUX — 2-port arbiter between D-path (port0) and I-path (port1).
//
// Port0 (PERIPHERAL_BUS / D-path): priority, read/write.
// Port1 (I_CACHE miss / I-path): lower priority, read-only (stream).
//
// On simultaneous send: port0 wins, port1 is queued (1-entry).
// On port0 write: snoop signal sent to I_CACHE for coherency.

module MEMORY_MUX #(
    parameter CHUNK_PART   = 128,
    parameter MASK_SIZE    = CHUNK_PART / 8,
    parameter ADDRESS_SIZE = 28
)(
    input wire clk,
    input wire reset,

    // === Port 0: D-path (priority) ===
    input  wire [ADDRESS_SIZE-1:0] p0_address,
    input  wire [1:0]              p0_command,       // 00=nop, 01=read, 10=write
    input  wire                    p0_read_stream,
    input  wire [MASK_SIZE-1:0]    p0_write_mask,
    input  wire [CHUNK_PART-1:0]   p0_write_value,
    output wire                    p0_ready,
    output wire [CHUNK_PART-1:0]   p0_read_value,
    output reg                     p0_read_value_ready,

    // === Port 1: I-path ===
    input  wire [ADDRESS_SIZE-1:0] p1_address,
    input  wire [1:0]              p1_command,
    input  wire                    p1_read_stream,
    input  wire [MASK_SIZE-1:0]    p1_write_mask,
    input  wire [CHUNK_PART-1:0]   p1_write_value,
    output wire                    p1_ready,
    output wire [CHUNK_PART-1:0]   p1_read_value,
    output reg                     p1_read_value_ready,

    // === Downstream: to MEMORY_CONTROLLER ===
    output reg  [ADDRESS_SIZE-1:0] mem_address,
    output reg  [1:0]              mem_command,
    output reg                     mem_read_stream,
    output reg  [MASK_SIZE-1:0]    mem_write_mask,
    output reg  [CHUNK_PART-1:0]   mem_write_value,
    input  wire                    mem_ready,
    input  wire [CHUNK_PART-1:0]   mem_read_value,
    input  wire                    mem_read_value_ready,

    // === Snoop: to I_CACHE (on port0 write) ===
    output reg                     snoop_valid,
    output reg  [ADDRESS_SIZE-1:0] snoop_address,
    output reg  [MASK_SIZE-1:0]    snoop_mask,
    output reg  [CHUNK_PART-1:0]   snoop_value
);

    // Read value shared — only active port gets read_value_ready
    assign p0_read_value = mem_read_value;
    assign p1_read_value = mem_read_value;

    // =========================================================
    // FSM
    // =========================================================
    typedef enum logic [1:0] {
        IDLE,
        BUSY_P0,
        BUSY_P1
    } state_t;

    state_t state;

    // Skip first cycle in BUSY (mem_ready still high from previous cycle)
    reg first_busy_cycle;

    // Port1 queue (1-entry, for simultaneous send race)
    reg                    p1_queued;
    reg [ADDRESS_SIZE-1:0] p1_q_address;
    reg [1:0]              p1_q_command;
    reg                    p1_q_read_stream;
    reg [MASK_SIZE-1:0]    p1_q_write_mask;
    reg [CHUNK_PART-1:0]   p1_q_write_value;

    // Ready: both ports can send in IDLE when no queued command
    assign p0_ready = (state == IDLE) && mem_ready && !p1_queued;
    assign p1_ready = (state == IDLE) && mem_ready && !p1_queued;

    // =========================================================
    always_ff @(posedge clk) begin
        if (reset) begin
            state               <= IDLE;
            mem_command          <= 2'b00;
            p0_read_value_ready  <= 0;
            p1_read_value_ready  <= 0;
            snoop_valid          <= 0;
            p1_queued            <= 0;
            first_busy_cycle     <= 0;
        end else begin
            // Clear pulses
            p0_read_value_ready <= 0;
            p1_read_value_ready <= 0;
            snoop_valid         <= 0;
            mem_command         <= 2'b00;

            case (state)

                // -------------------------------------------------
                // IDLE: arbitrate and forward
                // -------------------------------------------------
                IDLE: begin
                    if (p1_queued && mem_ready) begin
                        // Serve queued port1 command first
                        mem_address     <= p1_q_address;
                        mem_command     <= p1_q_command;
                        mem_read_stream <= p1_q_read_stream;
                        mem_write_mask  <= p1_q_write_mask;
                        mem_write_value <= p1_q_write_value;
                        p1_queued        <= 0;
                        first_busy_cycle <= 1;
                        state            <= BUSY_P1;

                    end else if (p0_command != 2'b00) begin
                        // Port0 wins (priority)
                        mem_address     <= p0_address;
                        mem_command     <= p0_command;
                        mem_read_stream <= p0_read_stream;
                        mem_write_mask  <= p0_write_mask;
                        mem_write_value <= p0_write_value;
                        first_busy_cycle <= 1;
                        state            <= BUSY_P0;

                        // Snoop I_CACHE on port0 write
                        if (p0_command == 2'b10) begin
                            snoop_valid   <= 1;
                            snoop_address <= p0_address;
                            snoop_mask    <= p0_write_mask;
                            snoop_value   <= p0_write_value;
                        end

                        // Queue port1 if it also sent (race)
                        if (p1_command != 2'b00) begin
                            p1_queued        <= 1;
                            p1_q_address     <= p1_address;
                            p1_q_command     <= p1_command;
                            p1_q_read_stream <= p1_read_stream;
                            p1_q_write_mask  <= p1_write_mask;
                            p1_q_write_value <= p1_write_value;
                        end

                    end else if (p1_command != 2'b00) begin
                        // Port1 only
                        mem_address     <= p1_address;
                        mem_command     <= p1_command;
                        mem_read_stream <= p1_read_stream;
                        mem_write_mask  <= p1_write_mask;
                        mem_write_value <= p1_write_value;
                        first_busy_cycle <= 1;
                        state            <= BUSY_P1;
                    end
                end

                // -------------------------------------------------
                // BUSY_P0: wait for MEMORY_CONTROLLER response
                // -------------------------------------------------
                BUSY_P0: begin
                    first_busy_cycle <= 0;
                    if (mem_read_value_ready)
                        p0_read_value_ready <= 1;
                    if (mem_ready && !first_busy_cycle)
                        state <= IDLE;
                end

                // -------------------------------------------------
                // BUSY_P1: wait for MEMORY_CONTROLLER response
                // -------------------------------------------------
                BUSY_P1: begin
                    first_busy_cycle <= 0;
                    if (mem_read_value_ready)
                        p1_read_value_ready <= 1;
                    if (mem_ready && !first_busy_cycle)
                        state <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
