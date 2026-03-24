// Адаптер между CPU data-портом и MEMORY_CONTROLLER.
// Преобразует одиночные read/write запросы CPU в протокол MEMORY_CONTROLLER.
// Генерирует stall пока операция не завершена.
//
// FSM:
//   S_IDLE  → (data op) → S_TRIG → S_WAIT → S_DONE → S_IDLE
//
//   S_DONE: stall=0 на 1 такт — CPU читает результат и продвигает PC.
module CPU_DATA_ADAPTER (
    input  wire        clk,
    input  wire        reset,

    // Интерфейс с CPU
    input  wire        mem_read_en,
    input  wire        mem_write_en,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_write_data,
    input  wire [3:0]  mem_byte_mask,
    output wire [31:0] mem_read_data,
    output wire        stall,

    // Интерфейс с MEMORY_CONTROLLER
    output logic [27:0] mc_address,
    output logic        mc_read_trigger,
    output logic        mc_write_trigger,
    output logic [31:0] mc_write_value,
    output logic [3:0]  mc_mask,
    input  wire  [31:0] mc_read_value,
    input  wire         mc_controller_ready
);
    typedef enum logic [1:0] {
        S_IDLE,   // ожидание
        S_TRIG,   // выдаём trigger (1 такт)
        S_WAIT,   // ждём controller_ready
        S_DONE    // операция завершена, stall=0 на 1 такт
    } ADAPTER_STATE;

    ADAPTER_STATE state;
    logic [31:0] data_result;
    logic        is_read;

    // ---------------------------------------------------------------
    // Адрес и данные для MEMORY_CONTROLLER
    // ---------------------------------------------------------------
    always_comb begin
        mc_address     = mem_addr[27:0];
        mc_write_value = mem_write_data;
        mc_mask        = mem_byte_mask;
        mc_read_trigger  = (state == S_TRIG && is_read);
        mc_write_trigger = (state == S_TRIG && !is_read);
    end

    assign mem_read_data = data_result;

    // ---------------------------------------------------------------
    // Stall: 0 только в S_DONE (операция завершена) и S_IDLE без op
    // ---------------------------------------------------------------
    assign stall = (state == S_TRIG) ||
                   (state == S_WAIT) ||
                   (state == S_IDLE && (mem_read_en || mem_write_en));

    // ---------------------------------------------------------------
    // FSM
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            state       <= S_IDLE;
            data_result <= 32'b0;
            is_read     <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (mem_read_en || mem_write_en) begin
                        is_read <= mem_read_en;
                        state   <= S_TRIG;
                    end
                end

                S_TRIG: begin
                    // trigger выставлен комбинационно на этот такт
                    state <= S_WAIT;
                end

                S_WAIT: begin
                    if (mc_controller_ready) begin
                        if (is_read)
                            data_result <= mc_read_value;
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    // CPU получил stall=0, выполнил инструкцию, PC продвинулся
                    state <= S_IDLE;
                end
            endcase
        end
    end

    initial begin
        state       = S_IDLE;
        data_result = 32'b0;
        is_read     = 1'b0;
    end

endmodule
