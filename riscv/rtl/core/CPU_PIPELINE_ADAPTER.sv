// Адаптер для Von Neumann архитектуры: instruction fetch + data access
// через один порт MEMORY_CONTROLLER (time-multiplexed).
//
// Фазы:
//   FETCH_TRIG → FETCH_WAIT → EXECUTE → [DATA_TRIG → DATA_WAIT → DATA_DONE] → FETCH_TRIG
//
// Debug pause:
//   Когда pause=1, pipeline завершает текущую фазу и переходит в S_PAUSED.
//   В S_PAUSED: bus свободен (triggers=0), CPU stalled.
//   Debug использует bus пока paused=1. Когда pause=0 → S_FETCH_TRIG.
module CPU_PIPELINE_ADAPTER (
    input  wire        clk,
    input  wire        reset,

    // Интерфейс с CPU — instruction fetch
    input  wire [31:0] instr_addr,
    output wire [31:0] instr_data,
    output wire        instr_stall,

    // Интерфейс с CPU — data access
    input  wire        mem_read_en,
    input  wire        mem_write_en,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_write_data,
    input  wire [3:0]  mem_byte_mask,
    output wire [31:0] mem_read_data,
    output wire        mem_stall,

    // Интерфейс с PERIPHERAL_BUS / MEMORY_CONTROLLER
    output logic [29:0] mc_address,
    output logic        mc_read_trigger,
    output logic        mc_write_trigger,
    output logic [31:0] mc_write_value,
    output logic [3:0]  mc_mask,
    input  wire  [31:0] mc_read_value,
    input  wire         mc_controller_ready,

    // Flush: сбросить pipeline (при dbg_set_pc)
    input  wire         flush,

    // Debug pause: debug запрашивает bus
    input  wire         pause,
    output wire         paused,

    // Debug step: выполнить 1 инструкцию из S_PAUSED и вернуться
    input  wire         step
);
    typedef enum logic [2:0] {
        S_FETCH_TRIG,
        S_FETCH_WAIT,
        S_EXECUTE,
        S_DATA_TRIG,
        S_DATA_WAIT,
        S_DATA_DONE,
        S_PAUSED
    } PIPELINE_STATE;

    PIPELINE_STATE state;
    logic [31:0] instr_reg;
    logic [31:0] data_reg;
    logic [29:0] addr_reg;    // latched address for WAIT states

    // Stepping: выполняем 1 инструкцию, игнорируем pause
    logic stepping;

    // Защёлкнутые CPU data-выходы (разрыв критического пути ALU → cache)
    logic [29:0] data_addr_reg;
    logic [31:0] data_wr_data_reg;
    logic [3:0]  data_mask_reg;
    logic        data_rd_en_reg;
    logic        data_wr_en_reg;

    // ---------------------------------------------------------------
    // Outputs to CPU
    // ---------------------------------------------------------------
    assign instr_data    = instr_reg;
    assign mem_read_data = data_reg;
    assign paused        = (state == S_PAUSED);

    // instr_stall: CPU stalled unless in EXECUTE or DATA phases
    assign instr_stall = (state != S_EXECUTE) &&
                         (state != S_DATA_TRIG) &&
                         (state != S_DATA_WAIT) &&
                         (state != S_DATA_DONE);

    // mem_stall: CPU stalled during data access
    assign mem_stall = (state == S_DATA_TRIG) ||
                       (state == S_DATA_WAIT) ||
                       (state == S_EXECUTE && (mem_read_en || mem_write_en));

    // ---------------------------------------------------------------
    // MC port (combinational) — off when paused
    // ---------------------------------------------------------------
    always_comb begin
        mc_read_trigger  = 1'b0;
        mc_write_trigger = 1'b0;
        mc_write_value   = 32'b0;
        mc_mask          = 4'b1111;
        mc_address       = addr_reg;   // hold latched address by default

        case (state)
            S_FETCH_TRIG: begin
                mc_address      = instr_addr[29:0];
                mc_read_trigger = mc_controller_ready;
            end

            S_DATA_TRIG: begin
                mc_address       = data_addr_reg;
                mc_read_trigger  = data_rd_en_reg & mc_controller_ready;
                mc_write_trigger = data_wr_en_reg & mc_controller_ready;
                mc_write_value   = data_wr_data_reg;
                mc_mask          = data_mask_reg;
            end

            S_PAUSED: begin
                mc_address = 30'b0;  // don't care when paused
            end

            default: ;  // hold addr_reg
        endcase
    end

    // ---------------------------------------------------------------
    // FSM
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset || flush) begin
            state            <= S_FETCH_TRIG;
            instr_reg        <= 32'h0000_0013; // NOP
            data_reg         <= 32'b0;
            addr_reg         <= 28'b0;
            data_addr_reg    <= 28'b0;
            data_wr_data_reg <= 32'b0;
            data_mask_reg    <= 4'b0;
            data_rd_en_reg   <= 1'b0;
            data_wr_en_reg   <= 1'b0;
            stepping         <= 1'b0;
        end else begin
            case (state)
                S_FETCH_TRIG: begin
                    if (pause && !stepping)
                        state <= S_PAUSED;
                    else if (mc_controller_ready) begin
                        addr_reg <= instr_addr[29:0];
                        state    <= S_FETCH_WAIT;
                    end
                end

                S_FETCH_WAIT: begin
                    if (mc_controller_ready) begin
                        instr_reg <= mc_read_value;
                        if (pause && !stepping)
                            state <= S_PAUSED;
                        else
                            state <= S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    if (mem_read_en || mem_write_en) begin
                        data_addr_reg    <= mem_addr[29:0];
                        data_wr_data_reg <= mem_write_data;
                        data_mask_reg    <= mem_byte_mask;
                        data_rd_en_reg   <= mem_read_en;
                        data_wr_en_reg   <= mem_write_en;
                        state <= S_DATA_TRIG;
                    end else begin
                        stepping <= 0;
                        if (pause)
                            state <= S_PAUSED;
                        else
                            state <= S_FETCH_TRIG;
                    end
                end

                S_DATA_TRIG: begin
                    if (mc_controller_ready) begin
                        addr_reg <= data_addr_reg;
                        state    <= S_DATA_WAIT;
                    end
                end

                S_DATA_WAIT: begin
                    if (mc_controller_ready) begin
                        data_reg <= mc_read_value;
                        state    <= S_DATA_DONE;
                    end
                end

                S_DATA_DONE: begin
                    stepping <= 0;
                    if (pause)
                        state <= S_PAUSED;
                    else
                        state <= S_FETCH_TRIG;
                end

                S_PAUSED: begin
                    if (step) begin
                        stepping <= 1;
                        state    <= S_FETCH_TRIG;
                    end else if (!pause)
                        state <= S_FETCH_TRIG;
                end
            endcase
        end
    end

endmodule
