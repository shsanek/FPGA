// Отладочный контроллер RISC-V CPU.
//
// Pipeline:
//   S_IDLE → приняли команду от UART
//   S_RECV → (если команда составная) принимаем payload
//   S_PAUSE_WAIT → bus_request=1, ждём granted от pipeline
//   S_EXEC → выполняем команду
//   S_MEM_WAIT → (если память) ждём bus ready
//   S_SEND_ACK1 → отправляем первый байт ACK
//   S_SEND_ACK2 → отправляем второй байт ACK (такой же)
//   S_SEND_DATA → отправляем resp_len байт данных (если есть)
//   → если cmd != HALT: отпускаем CPU → S_IDLE
//
// ACK = два одинаковых байта (код команды).
// После ACK — данные ответа (0, 4 или 8 байт в зависимости от команды).
//
// При DEBUG_ENABLE=0 модуль синтезируется в заглушку.
module DEBUG_CONTROLLER #(
    parameter DEBUG_ENABLE  = 1,
    parameter ADDRESS_SIZE  = 28,
    parameter DATA_SIZE     = 32,
    parameter MASK_SIZE     = DATA_SIZE / 8
)(
    input  wire        clk,
    input  wire        reset,

    // Байтовый RX-интерфейс (от UART FIFO)
    input  wire [7:0]  rx_byte,
    input  wire        rx_valid,

    // Байтовый TX-интерфейс (к UART FIFO)
    output wire [7:0]  tx_byte,
    output wire        tx_valid,
    input  wire        tx_ready,

    // CPU debug-порты
    output wire        dbg_halt,
    output wire        dbg_step,
    output wire        dbg_set_pc,
    output wire [31:0] dbg_new_pc,
    input  wire        dbg_is_halted,
    input  wire [31:0] dbg_current_pc,
    input  wire [31:0] dbg_current_instr,

    // Bus debug-порты
    output wire                    dbg_bus_request,
    input  wire                    dbg_bus_granted,
    output wire [ADDRESS_SIZE-1:0] mc_dbg_address,
    output wire                    mc_dbg_read_trigger,
    output wire                    mc_dbg_write_trigger,
    output wire [DATA_SIZE-1:0]    mc_dbg_write_data,
    input  wire [DATA_SIZE-1:0]    mc_dbg_read_data,
    input  wire                    mc_dbg_ready,

    // CPU passthrough
    output wire [7:0]  cpu_rx_byte,
    output wire        cpu_rx_valid,
    input  wire [7:0]  cpu_tx_byte,
    input  wire        cpu_tx_valid,
    output wire        cpu_tx_ready
);

    // ---------------------------------------------------------------
    // Команды (однобайтовые, составные — позже)
    // ---------------------------------------------------------------
    localparam CMD_HALT      = 8'h01;
    localparam CMD_RESUME    = 8'h02;
    localparam CMD_STEP      = 8'h03;
    localparam CMD_READ_MEM  = 8'h04;
    localparam CMD_WRITE_MEM = 8'h05;
    localparam CMD_INPUT     = 8'h06;  // обёртка: доставить 1 байт в CPU
    localparam CMD_RESET_PC  = 8'h07;
    localparam CMD_SYNC_RESET = 8'hFD; // псевдо-команда: сброс FSM

    // Заголовки ответов (1 байт перед данными)
    localparam HDR_DEBUG    = 8'hAA;  // debug-ответ: ACK + [данные]
    localparam HDR_CPU_UART = 8'hBB;  // байт от CPU через UART

    typedef enum logic [3:0] {
        S_IDLE,
        S_RECV,          // приём payload (составные команды)
        S_PAUSE_WAIT,    // ждём granted от pipeline
        S_EXEC,          // выполняем команду
        S_MEM_WAIT,      // ждём bus ready (для READ/WRITE_MEM)
        S_SEND_HDR,      // отправляем заголовок 0xAA (debug response)
        S_SEND_ACK1,     // отправляем 1-й байт ACK
        S_SEND_ACK2,     // отправляем 2-й байт ACK
        S_SEND_DATA,     // отправляем данные ответа побайтно
        S_CPU_TX         // отправляем байт от CPU (после заголовка 0xBB)
    } state_t;

generate
if (DEBUG_ENABLE) begin : dbg

    state_t state;

    logic [7:0]  cmd;
    logic [31:0] payload_addr;
    logic [31:0] payload_data;
    logic [2:0]  byte_idx;

    // CPU control
    logic halt_r;
    logic step_r;
    logic set_pc_r;
    logic [31:0] new_pc_r;

    // Bus control
    logic bus_request_r;
    logic [ADDRESS_SIZE-1:0] mc_addr_r;
    logic [DATA_SIZE-1:0]    mc_data_r;
    logic mc_read_r;
    logic mc_write_r;

    // TX
    logic [7:0] tx_byte_r;
    logic       tx_valid_r;

    // Буфер ответа (до 8 байт данных после ACK)
    logic [7:0] resp [0:7];
    logic [3:0] resp_len;      // сколько байт отправить (0 = нет данных)
    logic [3:0] resp_idx;      // текущий индекс отправки

    // CPU passthrough
    logic [7:0] cpu_rx_byte_r;
    logic       cpu_rx_valid_r;
    logic [7:0] cpu_tx_saved;    // сохранённый CPU TX байт (для S_CPU_TX)

    // Assigns
    assign dbg_halt        = halt_r;
    assign dbg_step        = step_r;
    assign dbg_set_pc      = set_pc_r;
    assign dbg_new_pc      = new_pc_r;
    assign dbg_bus_request = bus_request_r;

    assign mc_dbg_address       = mc_addr_r;
    assign mc_dbg_write_data    = mc_data_r;
    assign mc_dbg_read_trigger  = mc_read_r;
    assign mc_dbg_write_trigger = mc_write_r;

    assign tx_byte  = tx_byte_r;
    assign tx_valid = tx_valid_r;

    assign cpu_rx_byte  = cpu_rx_byte_r;
    assign cpu_rx_valid = cpu_rx_valid_r;
    assign cpu_tx_ready = (state == S_IDLE) && tx_ready && !tx_valid_r;

    // Сколько байт payload для команды
    function automatic [3:0] payload_bytes(input [7:0] c);
        case (c)
            CMD_READ_MEM:  payload_bytes = 4;   // ADDR[31:0]
            CMD_WRITE_MEM: payload_bytes = 8;   // ADDR[31:0] + DATA[31:0]
            CMD_INPUT:     payload_bytes = 1;   // DATA[7:0]
            CMD_RESET_PC:  payload_bytes = 4;   // ADDR[31:0]
            default:       payload_bytes = 0;
        endcase
    endfunction

    // Является ли байт debug-командой
    function automatic logic is_debug_cmd(input [7:0] b);
        is_debug_cmd = (b >= CMD_HALT && b <= CMD_RESET_PC);
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            state          <= S_IDLE;
            cmd            <= 0;
            halt_r         <= 0;
            step_r         <= 0;
            set_pc_r       <= 0;
            new_pc_r       <= 0;
            bus_request_r  <= 0;
            mc_addr_r      <= 0;
            mc_data_r      <= 0;
            mc_read_r      <= 0;
            mc_write_r     <= 0;
            tx_byte_r      <= 0;
            tx_valid_r     <= 0;
            cpu_rx_byte_r  <= 0;
            cpu_rx_valid_r <= 0;
            byte_idx       <= 0;
            payload_addr   <= 0;
            payload_data   <= 0;
            resp_len       <= 0;
            resp_idx       <= 0;
        end else begin
            // Auto-clear импульсы
            tx_valid_r     <= 0;
            step_r         <= 0;
            set_pc_r       <= 0;
            cpu_rx_valid_r <= 0;

            // Псевдо-команда 0xFD: сброс FSM из любого состояния кроме S_RECV
            // (в S_RECV ждём payload — 0xFD может быть частью данных)
            if (rx_valid && rx_byte == CMD_SYNC_RESET && state != S_RECV) begin
                state         <= S_IDLE;
                bus_request_r <= 0;
                halt_r        <= 0;
                mc_read_r     <= 0;
                mc_write_r    <= 0;
                resp_len      <= 0;
                resp_idx      <= 0;
            end else case (state)

                // ---------------------------------------------------------
                // Ждём байт от UART
                // ---------------------------------------------------------
                S_IDLE: begin
                    if (rx_valid) begin
                        if (is_debug_cmd(rx_byte)) begin
                            cmd <= rx_byte;
                            if (payload_bytes(rx_byte) == 0) begin
                                // Однобайтовая команда → сразу pause
                                bus_request_r <= 1;
                                state         <= S_PAUSE_WAIT;
                            end else begin
                                // Составная → принимаем payload
                                byte_idx <= 0;
                                state    <= S_RECV;
                            end
                        end else begin
                            // Passthrough в CPU
                            cpu_rx_byte_r  <= rx_byte;
                            cpu_rx_valid_r <= 1;
                        end
                    end else if (cpu_tx_valid && tx_ready && !tx_valid_r) begin
                        // CPU хочет отправить → сначала заголовок 0xBB
                        cpu_tx_saved <= cpu_tx_byte;
                        tx_byte_r    <= HDR_CPU_UART;
                        tx_valid_r   <= 1;
                        state        <= S_CPU_TX;
                    end
                end

                // ---------------------------------------------------------
                // Приём payload (составные команды)
                // ---------------------------------------------------------
                S_RECV: begin
                    if (rx_valid) begin
                        if (byte_idx < 4)
                            payload_addr[byte_idx*8 +: 8] <= rx_byte;
                        else
                            payload_data[(byte_idx-4)*8 +: 8] <= rx_byte;

                        if (byte_idx == payload_bytes(cmd) - 1) begin
                            bus_request_r <= 1;
                            state         <= S_PAUSE_WAIT;
                        end else begin
                            byte_idx <= byte_idx + 1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // Ждём остановки pipeline
                // ---------------------------------------------------------
                S_PAUSE_WAIT: begin
                    if (dbg_bus_granted)
                        state <= S_EXEC;
                end

                // ---------------------------------------------------------
                // Выполняем команду
                // ---------------------------------------------------------
                S_EXEC: begin
                    resp_len <= 0;  // по умолчанию нет данных
                    resp_idx <= 0;

                    case (cmd)
                        CMD_HALT: begin
                            halt_r <= 1;
                        end

                        CMD_RESUME: begin
                            halt_r <= 0;
                        end

                        CMD_STEP: begin
                            step_r <= 1;
                            // Данные: PC[31:0] + INSTR[31:0] = 8 байт
                            resp[0] <= dbg_current_pc[7:0];
                            resp[1] <= dbg_current_pc[15:8];
                            resp[2] <= dbg_current_pc[23:16];
                            resp[3] <= dbg_current_pc[31:24];
                            resp[4] <= dbg_current_instr[7:0];
                            resp[5] <= dbg_current_instr[15:8];
                            resp[6] <= dbg_current_instr[23:16];
                            resp[7] <= dbg_current_instr[31:24];
                            resp_len <= 8;
                        end

                        CMD_READ_MEM: begin
                            mc_addr_r <= payload_addr[ADDRESS_SIZE-1:0];
                            mc_read_r <= 1;
                            state     <= S_MEM_WAIT;
                        end

                        CMD_WRITE_MEM: begin
                            mc_addr_r  <= payload_addr[ADDRESS_SIZE-1:0];
                            mc_data_r  <= payload_data;
                            mc_write_r <= 1;
                            state      <= S_MEM_WAIT;
                        end

                        CMD_INPUT: begin
                            // Доставить payload_addr[7:0] в CPU
                            cpu_rx_byte_r  <= payload_addr[7:0];
                            cpu_rx_valid_r <= 1;
                        end

                        CMD_RESET_PC: begin
                            set_pc_r <= 1;
                            new_pc_r <= payload_addr;
                        end

                        default: ;
                    endcase

                    if (cmd != CMD_READ_MEM && cmd != CMD_WRITE_MEM)
                        state <= S_SEND_HDR;
                end

                // ---------------------------------------------------------
                // Ждём завершения операции с памятью
                // ---------------------------------------------------------
                S_MEM_WAIT: begin
                    if (mc_dbg_ready) begin
                        mc_read_r  <= 0;
                        mc_write_r <= 0;
                        // READ_MEM → 4 байта данных, WRITE_MEM → 0
                        if (cmd == CMD_READ_MEM) begin
                            resp[0]  <= mc_dbg_read_data[7:0];
                            resp[1]  <= mc_dbg_read_data[15:8];
                            resp[2]  <= mc_dbg_read_data[23:16];
                            resp[3]  <= mc_dbg_read_data[31:24];
                            resp_len <= 4;
                        end
                        resp_idx <= 0;
                        state    <= S_SEND_HDR;
                    end
                end

                // ---------------------------------------------------------
                // Заголовок debug-ответа (0xAA)
                // ---------------------------------------------------------
                S_SEND_HDR: begin
                    if (tx_ready && !tx_valid_r) begin
                        tx_byte_r  <= HDR_DEBUG;
                        tx_valid_r <= 1;
                        state      <= S_SEND_ACK1;
                    end
                end

                // ---------------------------------------------------------
                // Отправляем 1-й байт ACK (= код команды)
                // ---------------------------------------------------------
                S_SEND_ACK1: begin
                    if (tx_ready && !tx_valid_r) begin
                        tx_byte_r  <= cmd;
                        tx_valid_r <= 1;
                        state      <= S_SEND_ACK2;
                    end
                end

                // ---------------------------------------------------------
                // Отправляем 2-й байт ACK (= код команды, такой же)
                // ---------------------------------------------------------
                S_SEND_ACK2: begin
                    if (tx_ready && !tx_valid_r) begin
                        tx_byte_r  <= cmd;
                        tx_valid_r <= 1;

                        if (resp_len != 0) begin
                            // Есть данные → отправляем
                            state <= S_SEND_DATA;
                        end else begin
                            // Нет данных → завершаем
                            if (cmd != CMD_HALT)
                                bus_request_r <= 0;
                            state <= S_IDLE;
                        end
                    end
                end

                // ---------------------------------------------------------
                // Отправляем данные ответа побайтно
                // ---------------------------------------------------------
                S_SEND_DATA: begin
                    if (tx_ready && !tx_valid_r) begin
                        tx_byte_r  <= resp[resp_idx];
                        tx_valid_r <= 1;

                        if (resp_idx == resp_len - 1) begin
                            if (cmd != CMD_HALT)
                                bus_request_r <= 0;
                            state <= S_IDLE;
                        end else begin
                            resp_idx <= resp_idx + 1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // Отправляем байт от CPU (после заголовка 0xBB)
                // ---------------------------------------------------------
                S_CPU_TX: begin
                    if (tx_ready && !tx_valid_r) begin
                        tx_byte_r  <= cpu_tx_saved;
                        tx_valid_r <= 1;
                        state      <= S_IDLE;
                    end
                end

            endcase
        end
    end

end else begin : no_dbg
    assign dbg_halt             = 0;
    assign dbg_step             = 0;
    assign dbg_set_pc           = 0;
    assign dbg_new_pc           = 0;
    assign dbg_bus_request      = 0;
    assign mc_dbg_address       = 0;
    assign mc_dbg_read_trigger  = 0;
    assign mc_dbg_write_trigger = 0;
    assign mc_dbg_write_data    = 0;
    assign tx_byte              = 0;
    assign tx_valid             = 0;
    assign cpu_rx_byte          = 0;
    assign cpu_rx_valid         = 0;
    assign cpu_tx_ready         = 1;
end
endgenerate

endmodule
