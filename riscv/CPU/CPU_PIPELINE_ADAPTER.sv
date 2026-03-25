// Адаптер для Von Neumann архитектуры: instruction fetch + data access
// через один порт MEMORY_CONTROLLER (time-multiplexed).
//
// Фазы:
//   FETCH_TRIG  → FETCH_WAIT → EXECUTE → [DATA_TRIG → DATA_WAIT → DATA_DONE] → FETCH_TRIG
//
// FETCH: читает 32-бит слово по instr_addr из памяти, выдаёт instr_data.
// EXECUTE: instr_stall=0, CPU исполняет инструкцию за 1 такт.
//   Если CPU делает load/store (mem_read_en | mem_write_en) → DATA фаза.
//   Иначе → сразу FETCH следующей инструкции.
// DATA: выполняет load/store через тот же порт памяти.
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
    output logic [27:0] mc_address,
    output logic        mc_read_trigger,
    output logic        mc_write_trigger,
    output logic [31:0] mc_write_value,
    output logic [3:0]  mc_mask,
    input  wire  [31:0] mc_read_value,
    input  wire         mc_controller_ready,

    // Flush: сбросить pipeline (при dbg_set_pc)
    input  wire         flush
);
    typedef enum logic [2:0] {
        S_FETCH_TRIG,
        S_FETCH_WAIT,
        S_EXECUTE,
        S_DATA_TRIG,
        S_DATA_WAIT,
        S_DATA_DONE
    } PIPELINE_STATE;

    PIPELINE_STATE state;
    logic [31:0] instr_reg;
    logic [31:0] data_reg;

    // ---------------------------------------------------------------
    // Outputs to CPU
    // ---------------------------------------------------------------
    assign instr_data  = instr_reg;
    assign mem_read_data = data_reg;

    // instr_stall: CPU stalled unless we're in EXECUTE (or DATA phases where CPU already executed)
    assign instr_stall = (state != S_EXECUTE) &&
                         (state != S_DATA_TRIG) &&
                         (state != S_DATA_WAIT) &&
                         (state != S_DATA_DONE);

    // mem_stall: CPU stalled during data access
    assign mem_stall = (state == S_DATA_TRIG) ||
                       (state == S_DATA_WAIT) ||
                       (state == S_EXECUTE && (mem_read_en || mem_write_en));

    // ---------------------------------------------------------------
    // MC port mux (combinational)
    // ---------------------------------------------------------------
    always_comb begin
        mc_address       = 28'b0;
        mc_read_trigger  = 1'b0;
        mc_write_trigger = 1'b0;
        mc_write_value   = 32'b0;
        mc_mask          = 4'b1111;

        case (state)
            S_FETCH_TRIG: begin
                mc_address      = instr_addr[27:0];
                mc_read_trigger = mc_controller_ready;
                mc_mask         = 4'b1111;
            end

            S_DATA_TRIG: begin
                mc_address       = mem_addr[27:0];
                mc_read_trigger  = mem_read_en & mc_controller_ready;
                mc_write_trigger = mem_write_en & mc_controller_ready;
                mc_write_value   = mem_write_data;
                mc_mask          = mem_byte_mask;
            end

            default: ;
        endcase
    end

    // ---------------------------------------------------------------
    // FSM
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset || flush) begin
            state     <= S_FETCH_TRIG;
            instr_reg <= 32'h0000_0013; // NOP
            data_reg  <= 32'b0;
        end else begin
            case (state)
                S_FETCH_TRIG: begin
                    // trigger выставлен комбинационно, но только если MC ready
                    if (mc_controller_ready)
                        state <= S_FETCH_WAIT;
                    // иначе остаёмся — trigger будет повторяться
                end

                S_FETCH_WAIT: begin
                    if (mc_controller_ready) begin
                        instr_reg <= mc_read_value;
                        state     <= S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    // CPU исполняет инструкцию (instr_stall=0 на этот такт)
                    if (mem_read_en || mem_write_en) begin
                        // Data access needed
                        state <= S_DATA_TRIG;
                    end else begin
                        // No data access, fetch next
                        state <= S_FETCH_TRIG;
                    end
                end

                S_DATA_TRIG: begin
                    // trigger выставлен комбинационно, но только если MC ready
                    if (mc_controller_ready)
                        state <= S_DATA_WAIT;
                end

                S_DATA_WAIT: begin
                    if (mc_controller_ready) begin
                        data_reg <= mc_read_value;
                        state    <= S_DATA_DONE;
                    end
                end

                S_DATA_DONE: begin
                    // mem_stall=0, CPU получает результат load
                    state <= S_FETCH_TRIG;
                end
            endcase
        end
    end

endmodule
