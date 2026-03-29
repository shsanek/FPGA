// CPU_IF_ADAPTER — instruction fetch adapter between CPU and bus.
//
// CPU presents instr_addr continuously. This adapter:
// - Detects when a new fetch is needed (addr changed or first fetch)
// - Sends bus_read pulse (1 cycle)
// - Holds instr_stall=1 until bus_read_valid
// - Latches bus_read_data, outputs instr_data, clears stall
//
// After data delivered, waits for next addr change.

module CPU_IF_ADAPTER (
    input  wire        clk,
    input  wire        reset,

    // CPU side
    input  wire [31:0] instr_addr,
    output wire [31:0] instr_data,
    output wire        instr_stall,

    // Bus side (32-bit, before BUS_32_TO_128)
    output reg  [31:0] bus_address,
    output reg         bus_read,
    input  wire [31:0] bus_read_data,
    input  wire        bus_ready,
    input  wire        bus_read_valid,

    // Flush (on set_pc — re-fetch)
    input  wire        flush
);

    typedef enum logic [1:0] {
        S_IDLE,       // have valid instruction, waiting for addr change
        S_READ_REQ,   // need to send bus_read pulse
        S_READ_WAIT   // waiting for bus_read_valid
    } state_t;

    state_t state;
    reg [31:0] fetched_data;
    reg [31:0] fetched_addr;   // addr of currently fetched instruction
    reg        has_data;       // fetched_data is valid

    assign instr_data  = fetched_data;
    assign instr_stall = (state != S_IDLE);

    // Need new fetch when addr doesn't match what we have
    wire addr_changed = (instr_addr != fetched_addr) || !has_data;

    always_ff @(posedge clk) begin
        if (reset || flush) begin
            state        <= S_READ_REQ;
            fetched_data <= 32'h0000_0013; // NOP
            fetched_addr <= 32'hFFFF_FFFF; // force mismatch
            has_data     <= 0;
            bus_read     <= 0;
        end else begin
            bus_read <= 0; // default: clear pulse

            case (state)
                S_IDLE: begin
                    if (addr_changed)
                        state <= S_READ_REQ;
                end

                S_READ_REQ: begin
                    if (bus_ready) begin
                        bus_address <= instr_addr;
                        bus_read    <= 1;
                        state       <= S_READ_WAIT;
                    end
                end

                S_READ_WAIT: begin
                    if (bus_read_valid) begin
                        fetched_data <= bus_read_data;
                        fetched_addr <= bus_address;
                        has_data     <= 1;
                        state        <= S_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
