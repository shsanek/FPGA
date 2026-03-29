// CPU_DATA_ADAPTER_V2 — data-only bus adapter (no instruction fetch).
//
// CPU MEM stage (load/store) → 32-bit bus interface.
// IF goes to I_CACHE separately (not through this adapter).
//
// States:
//   IDLE → DATA_TRIG → DATA_WAIT → IDLE
//   IDLE → PAUSED (debug) → IDLE
//
// When no mem access needed: IDLE, CPU runs freely.
// When mem_read_en/mem_write_en: stall CPU, do bus transaction, unstall.

module CPU_DATA_ADAPTER_V2 (
    input  wire        clk,
    input  wire        reset,

    // CPU data access
    input  wire        mem_read_en,
    input  wire        mem_write_en,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_write_data,
    input  wire [3:0]  mem_byte_mask,
    output wire [31:0] mem_read_data,
    output wire        mem_stall,

    // 32-bit bus master
    output logic [31:0] bus_address,
    output logic        bus_read,
    output logic        bus_write,
    output logic [31:0] bus_write_data,
    output logic [3:0]  bus_write_mask,
    input  wire  [31:0] bus_read_data,
    input  wire         bus_ready,

    // Flush (on set_pc)
    input  wire         flush,

    // Debug pause
    input  wire         pause,
    output wire         paused,
    input  wire         step
);

    typedef enum logic [1:0] {
        S_IDLE,
        S_DATA_TRIG,
        S_DATA_WAIT,
        S_PAUSED
    } state_t;

    state_t state;
    logic [31:0] data_reg;
    logic stepping;

    // Latched CPU data outputs (break critical path ALU → bus)
    logic [31:0] lat_addr;
    logic [31:0] lat_wr_data;
    logic [3:0]  lat_mask;
    logic        lat_rd_en;
    logic        lat_wr_en;

    // ---------------------------------------------------------------
    // Outputs
    // ---------------------------------------------------------------
    assign mem_read_data = data_reg;
    assign paused        = (state == S_PAUSED);

    // mem_stall: CPU stalled during data access
    assign mem_stall = (state == S_DATA_TRIG) ||
                       (state == S_DATA_WAIT) ||
                       (state == S_IDLE && (mem_read_en || mem_write_en));

    // ---------------------------------------------------------------
    // Bus port (combinational)
    // ---------------------------------------------------------------
    always_comb begin
        bus_address    = lat_addr;
        bus_read       = 1'b0;
        bus_write      = 1'b0;
        bus_write_data = lat_wr_data;
        bus_write_mask = lat_mask;

        if (state == S_DATA_TRIG) begin
            bus_address    = lat_addr;
            bus_read       = lat_rd_en & bus_ready;
            bus_write      = lat_wr_en & bus_ready;
            bus_write_data = lat_wr_data;
            bus_write_mask = lat_mask;
        end
    end

    // ---------------------------------------------------------------
    // FSM
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset || flush) begin
            state       <= S_IDLE;
            data_reg    <= 32'b0;
            lat_addr    <= 32'b0;
            lat_wr_data <= 32'b0;
            lat_mask    <= 4'b0;
            lat_rd_en   <= 1'b0;
            lat_wr_en   <= 1'b0;
            stepping    <= 1'b0;
        end else begin
            case (state)

                S_IDLE: begin
                    if (pause && !stepping) begin
                        state <= S_PAUSED;
                    end else if (mem_read_en || mem_write_en) begin
                        lat_addr    <= mem_addr;
                        lat_wr_data <= mem_write_data;
                        lat_mask    <= mem_byte_mask;
                        lat_rd_en   <= mem_read_en;
                        lat_wr_en   <= mem_write_en;
                        state <= S_DATA_TRIG;
                    end
                end

                S_DATA_TRIG: begin
                    if (bus_ready) begin
                        state <= S_DATA_WAIT;
                    end
                end

                S_DATA_WAIT: begin
                    if (bus_ready) begin
                        data_reg <= bus_read_data;
                        stepping <= 0;
                        if (pause)
                            state <= S_PAUSED;
                        else
                            state <= S_IDLE;
                    end
                end

                S_PAUSED: begin
                    if (step) begin
                        stepping <= 1;
                        state    <= S_IDLE;
                    end else if (!pause)
                        state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
