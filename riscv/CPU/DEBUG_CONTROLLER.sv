// Отладочный контроллер RISC-V CPU.
//
// Протокол (little-endian, фиксированные пакеты):
//   0x01  HALT      payload=—            ответ=0xFF
//   0x02  RESUME    payload=—            ответ=0xFF
//   0x03  STEP      payload=—            ответ=PC[31:0]+INSTR[31:0]  (8 байт)
//   0x04  READ_MEM  payload=ADDR[31:0]   ответ=DATA[31:0]            (4 байта)
//   0x05  WRITE_MEM payload=ADDR+DATA    ответ=0xFF
//
// Интерфейс с внешним миром — байтовый (не UART).
// Для подключения к физическому UART используй I_O_INPUT/OUTPUT_CONTROLLER снаружи.
//
// При DEBUG_ENABLE=0 модуль синтезируется в заглушку (нет логики).
module DEBUG_CONTROLLER #(
    parameter DEBUG_ENABLE  = 1,
    parameter ADDRESS_SIZE  = 28,
    parameter DATA_SIZE     = 32,
    parameter MASK_SIZE     = DATA_SIZE / 8
)(
    input  wire        clk,
    input  wire        reset,

    // Байтовый RX-интерфейс (от UART RX или теста)
    input  wire [7:0]  rx_byte,
    input  wire        rx_valid,   // 1-тактовый импульс: новый байт принят

    // Байтовый TX-интерфейс (к UART TX или тесту)
    output wire [7:0]  tx_byte,
    output wire        tx_valid,   // 1-тактовый импульс: отправить байт
    input  wire        tx_ready,   // TX свободен (можно слать следующий байт)

    // CPU debug-порты
    output wire        dbg_halt,
    output wire        dbg_step,
    output wire        dbg_set_pc,
    output wire [31:0] dbg_new_pc,
    input  wire        dbg_is_halted,
    input  wire [31:0] dbg_current_pc,
    input  wire [31:0] dbg_current_instr,

    // MEMORY_CONTROLLER debug-порты
    output wire [ADDRESS_SIZE-1:0] mc_dbg_address,
    output wire                    mc_dbg_read_trigger,
    output wire                    mc_dbg_write_trigger,
    output wire [DATA_SIZE-1:0]    mc_dbg_write_data,
    output wire [MASK_SIZE-1:0]    mc_dbg_mask,
    input  wire [DATA_SIZE-1:0]    mc_dbg_read_data,
    input  wire                    mc_dbg_ready,

    // CPU passthrough — байты которые НЕ являются дебаг-командами
    output wire [7:0]  cpu_rx_byte,    // байт пришедший с UART для CPU
    output wire        cpu_rx_valid,   // 1-тактовый импульс
    input  wire [7:0]  cpu_tx_byte,    // байт от CPU для отправки
    input  wire        cpu_tx_valid,   // UART_IO_DEVICE хочет отправить байт
    output wire        cpu_tx_ready    // DEBUG готов забрать байт (комбинационно)
);

    // ---------------------------------------------------------------
    // Команды
    // ---------------------------------------------------------------
    localparam CMD_HALT      = 8'h01;
    localparam CMD_RESUME    = 8'h02;
    localparam CMD_STEP      = 8'h03;
    localparam CMD_READ_MEM  = 8'h04;
    localparam CMD_WRITE_MEM = 8'h05;
    localparam CMD_RESET_PC  = 8'h06;

    typedef enum logic [2:0] {
        S_IDLE,
        S_RECV,
        S_EXEC,
        S_HALT_WAIT,
        S_SEND
    } DBG_STATE;

generate
if (DEBUG_ENABLE) begin : dbg

    DBG_STATE state;

    logic [7:0]  cmd;
    logic [31:0] payload_addr;
    logic [31:0] payload_data;
    logic [2:0]  byte_idx;     // счётчик принятых/отправленных байт

    // Регистры для ответа
    logic [7:0]  resp [0:7];   // до 8 байт ответа
    logic [3:0]  resp_len;     // сколько байт слать (0..8)
    logic [3:0]  resp_idx;     // уже отправлено

    // CPU halt/step control
    logic halt_r;
    logic step_r;

    // MC debug control
    logic [ADDRESS_SIZE-1:0] mc_addr_r;
    logic [DATA_SIZE-1:0]    mc_data_r;
    logic                    mc_read_r;
    logic                    mc_write_r;

    // TX буфер
    logic [7:0] tx_byte_r;
    logic       tx_valid_r;

    // CPU passthrough
    logic [7:0] cpu_rx_byte_r;
    logic       cpu_rx_valid_r;

    // PC reset control
    logic        set_pc_r;
    logic [31:0] new_pc_r;

    assign dbg_halt   = halt_r;
    assign dbg_step   = step_r;
    assign dbg_set_pc = set_pc_r;
    assign dbg_new_pc = new_pc_r;

    assign cpu_rx_byte  = cpu_rx_byte_r;
    assign cpu_rx_valid = cpu_rx_valid_r;
    // CPU TX ready: DEBUG в S_IDLE и физический TX свободен
    assign cpu_tx_ready = (state == S_IDLE) && tx_ready && !tx_valid_r;

    assign mc_dbg_address       = mc_addr_r;
    assign mc_dbg_write_data    = mc_data_r;
    assign mc_dbg_mask          = {MASK_SIZE{1'b1}};  // полное слово
    assign mc_dbg_read_trigger  = mc_read_r;
    assign mc_dbg_write_trigger = mc_write_r;

    assign tx_byte  = tx_byte_r;
    assign tx_valid = tx_valid_r;

    // ---------------------------------------------------------------
    // Вспомогательная функция: сколько байт принять для команды
    // ---------------------------------------------------------------
    function automatic [3:0] payload_bytes(input [7:0] c);
        case (c)
            CMD_HALT:      payload_bytes = 0;
            CMD_RESUME:    payload_bytes = 0;
            CMD_STEP:      payload_bytes = 0;
            CMD_READ_MEM:  payload_bytes = 4;
            CMD_WRITE_MEM: payload_bytes = 8;
            CMD_RESET_PC:  payload_bytes = 4;
            default:       payload_bytes = 0;
        endcase
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            state      <= S_IDLE;
            halt_r     <= 0;
            step_r     <= 0;
            set_pc_r   <= 0;
            new_pc_r   <= 0;
            mc_read_r  <= 0;
            mc_write_r <= 0;
            mc_addr_r  <= 0;
            mc_data_r  <= 0;
            tx_byte_r      <= 0;
            tx_valid_r     <= 0;
            cpu_rx_byte_r  <= 0;
            cpu_rx_valid_r <= 0;
            byte_idx       <= 0;
            resp_idx       <= 0;
            resp_len       <= 0;
            cmd            <= 0;
            payload_addr   <= 0;
            payload_data   <= 0;
            for (int i = 0; i < 8; i++) resp[i] <= 0;
        end else begin
            tx_valid_r     <= 0;   // по умолчанию не слать
            step_r         <= 0;   // step — 1 такт импульс
            set_pc_r       <= 0;   // set_pc — 1 такт импульс
            mc_read_r      <= 0;   // trigger — 1 такт импульс
            mc_write_r     <= 0;   // trigger — 1 такт импульс
            cpu_rx_valid_r <= 0;   // CPU RX — 1 такт импульс

            case (state)

                // -------------------------------------------------------
                S_IDLE: begin
                    if (rx_valid) begin
                        if (rx_byte >= CMD_HALT && rx_byte <= CMD_RESET_PC) begin
                            // Дебаг-команда
                            cmd <= rx_byte;
                            if (payload_bytes(rx_byte) == 0) begin
                                byte_idx <= 0;
                                state    <= S_EXEC;
                            end else begin
                                byte_idx <= 0;
                                state    <= S_RECV;
                            end
                        end else begin
                            // Не дебаг-команда → форвардим в CPU RX буфер
                            cpu_rx_byte_r  <= rx_byte;
                            cpu_rx_valid_r <= 1;
                        end
                    end else if (cpu_tx_valid && tx_ready) begin
                        // Форвардим CPU TX байт в физический UART
                        tx_byte_r  <= cpu_tx_byte;
                        tx_valid_r <= 1;
                    end
                end

                // -------------------------------------------------------
                // Получаем payload little-endian: ADDR[7:0] … ADDR[31:24]
                // затем DATA[7:0] … DATA[31:24]  (для WRITE_MEM)
                S_RECV: begin
                    if (rx_valid) begin
                        if (byte_idx < 4)
                            payload_addr[byte_idx*8 +: 8] <= rx_byte;
                        else
                            payload_data[(byte_idx-4)*8 +: 8] <= rx_byte;

                        if (byte_idx == payload_bytes(cmd) - 1) begin
                            byte_idx <= 0;
                            state    <= S_EXEC;
                        end else begin
                            byte_idx <= byte_idx + 1;
                        end
                    end
                end

                // -------------------------------------------------------
                S_EXEC: begin
                    case (cmd)
                        CMD_HALT: begin
                            halt_r      <= 1;
                            state       <= S_HALT_WAIT;
                        end

                        CMD_RESUME: begin
                            halt_r      <= 0;
                            resp[0]     <= 8'hFF;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                            state       <= S_SEND;
                        end

                        CMD_STEP: begin
                            // CPU должен быть уже halted; выдаём step
                            step_r      <= 1;
                            // Ждём 2 такта чтобы CPU обновил PC/INSTR, потом шлём
                            resp[0]     <= dbg_current_pc[7:0];
                            resp[1]     <= dbg_current_pc[15:8];
                            resp[2]     <= dbg_current_pc[23:16];
                            resp[3]     <= dbg_current_pc[31:24];
                            resp[4]     <= dbg_current_instr[7:0];
                            resp[5]     <= dbg_current_instr[15:8];
                            resp[6]     <= dbg_current_instr[23:16];
                            resp[7]     <= dbg_current_instr[31:24];
                            resp_len    <= 8;
                            resp_idx    <= 0;
                            state       <= S_SEND;
                        end

                        CMD_READ_MEM: begin
                            mc_addr_r   <= payload_addr[ADDRESS_SIZE-1:0];
                            mc_read_r   <= 1;
                            state       <= S_HALT_WAIT;   // ждём mc_dbg_ready
                        end

                        CMD_WRITE_MEM: begin
                            mc_addr_r   <= payload_addr[ADDRESS_SIZE-1:0];
                            mc_data_r   <= payload_data;
                            mc_write_r  <= 1;
                            state       <= S_HALT_WAIT;   // ждём mc_dbg_ready
                        end

                        CMD_RESET_PC: begin
                            set_pc_r    <= 1;
                            new_pc_r    <= payload_addr;
                            resp[0]     <= 8'hFF;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                            state       <= S_SEND;
                        end

                        default: begin
                            resp[0]  <= 8'hFF;
                            resp_len <= 1;
                            resp_idx <= 0;
                            state    <= S_SEND;
                        end
                    endcase
                end

                // -------------------------------------------------------
                // Ожидание завершения асинхронной операции
                S_HALT_WAIT: begin
                    case (cmd)
                        CMD_HALT: begin
                            if (dbg_is_halted) begin
                                resp[0]  <= 8'hFF;
                                resp_len <= 1;
                                resp_idx <= 0;
                                state    <= S_SEND;
                            end
                        end

                        CMD_READ_MEM: begin
                            if (mc_dbg_ready) begin
                                mc_read_r <= 0;
                                resp[0]   <= mc_dbg_read_data[7:0];
                                resp[1]   <= mc_dbg_read_data[15:8];
                                resp[2]   <= mc_dbg_read_data[23:16];
                                resp[3]   <= mc_dbg_read_data[31:24];
                                resp_len  <= 4;
                                resp_idx  <= 0;
                                state     <= S_SEND;
                            end
                        end

                        CMD_WRITE_MEM: begin
                            if (mc_dbg_ready) begin
                                mc_write_r <= 0;
                                resp[0]    <= 8'hFF;
                                resp_len   <= 1;
                                resp_idx   <= 0;
                                state      <= S_SEND;
                            end
                        end

                        default: state <= S_IDLE;
                    endcase
                end

                // -------------------------------------------------------
                S_SEND: begin
                    if (tx_ready && !tx_valid_r) begin
                        tx_byte_r  <= resp[resp_idx];
                        tx_valid_r <= 1;
                        if (resp_idx == resp_len - 1) begin
                            resp_idx <= 0;
                            state    <= S_IDLE;
                        end else begin
                            resp_idx <= resp_idx + 1;
                        end
                    end
                end

            endcase
        end
    end

end else begin : no_dbg
    // DEBUG_ENABLE=0 — заглушка
    assign dbg_halt             = 0;
    assign dbg_step             = 0;
    assign dbg_set_pc           = 0;
    assign dbg_new_pc           = 0;
    assign mc_dbg_address       = 0;
    assign mc_dbg_read_trigger  = 0;
    assign mc_dbg_write_trigger = 0;
    assign mc_dbg_write_data    = 0;
    assign mc_dbg_mask          = 0;
    assign tx_byte              = 0;
    assign tx_valid             = 0;
    assign cpu_rx_byte          = 0;
    assign cpu_rx_valid         = 0;
    assign cpu_tx_ready         = 1;  // всегда готов (нет дебага)
end
endgenerate

endmodule
