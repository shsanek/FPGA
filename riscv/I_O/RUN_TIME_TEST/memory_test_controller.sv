
/*
    Module: byte_collector
    Собирает 4 байта из UART и выдаёт их вместе с сигналом valid
*/
module byte_collector(
    input  wire      clk,
    input  wire      io_in_trig,
    input  wire [7:0] io_in_val,
    output logic [1:0] byte_cnt,
    output logic [7:0] bytes [3:0],
    output logic       packet_valid
);
    always_ff @(posedge clk) begin
        packet_valid <= 1'b0;
        if (io_in_trig) begin
            bytes[byte_cnt] <= io_in_val;
            if (byte_cnt == 2'd3) begin
                packet_valid <= 1'b1;
                byte_cnt <= 2'd0;
            end else begin
                byte_cnt <= byte_cnt + 1;
            end
        end
    end
endmodule

/*
    Memory Test Controller: использует byte_collector для приёма 4-байтных пакетов
*/
module memory_test_controller #(
    parameter ADDRESS_SIZE = 28
)(
    input  wire                    clk,
    // UART input
    input  wire                    io_in_trig,
    input  wire [7:0]              io_in_val,
    // MEMORY_CONTROLLER готовность
    input  wire                    controller_ready,
    // Интерфейс к MEMORY_CONTROLLER
    input  wire [31: 0]            mem_value,
    output logic [ADDRESS_SIZE-1:0] mem_address,
    output logic                     mem_read_trigger,
    output logic                     mem_write_trigger,
    output logic [31:0]             mem_write_value,
    // UART output
    output logic [7:0]               io_out_val,
    output logic                     io_out_trig,
    input  wire                      io_out_ready_trigger
);

    // Компонент сбора 4 байт
    wire [1:0] bc_cnt;
    wire [7:0] bc_bytes [3:0];
    wire       bc_valid;
    byte_collector bc(
        .clk(clk), .io_in_trig(io_in_trig), .io_in_val(io_in_val),
        .byte_cnt(bc_cnt), .bytes(bc_bytes), .packet_valid(bc_valid)
    );

    // Определение команд
    typedef enum logic [1:0] {
        CMD_READ  = 2'b00,
        CMD_WRITE = 2'b01
    } cmd_t;
    cmd_t cmd;

    typedef enum logic [2:0] {
        S_IDLE,
        S_SEND_HASH,
        S_CMD,
        S_COUNT,
        S_SEND_STAT,
        S_SEND_HASH2
    } state_t;
    state_t state;

    logic [7:0]        hdr_hash;
    logic [ADDRESS_SIZE-1:0] addr;
    logic [31:0]       step_cnt, last_step;
    logic [2:0]        send_count;

    always_ff @(posedge clk) begin
        // сброс всех триггеров
        io_out_trig      <= 1'b0;
        mem_read_trigger <= 1'b0;
        mem_write_trigger<= 1'b0;

        case(state)
            S_IDLE: begin
                if (bc_valid) begin
                    hdr_hash <= bc_bytes[0] ^ bc_bytes[1] ^ bc_bytes[2] ^ bc_bytes[3];
                    cmd      <= cmd_t'(bc_bytes[0][7:6]);
                    addr     <= {bc_bytes[0][5:0], bc_bytes[1], bc_bytes[2], bc_bytes[3]};
                    state    <= S_SEND_HASH;
                end
            end

            S_SEND_HASH: begin
                if (io_out_ready_trigger) begin
                    io_out_val  <= hdr_hash;
                    io_out_trig <= 1;
                    state       <= S_CMD;
                end
            end

            S_CMD: begin
                // подготовка счётчиков и сброс триггеров
                step_cnt <= 0;
                last_step <= 0;
                send_count <= 4;
                unique case(cmd)
                    CMD_READ: begin
                        mem_address      <= addr;
                        mem_read_trigger <= 1;
                        state            <= S_COUNT;
                        hdr_hash <= 0;
                    end
                    CMD_WRITE: begin
                        if (bc_valid) begin
                            mem_write_value   <= {bc_bytes[0], bc_bytes[1], bc_bytes[2], bc_bytes[3]};
                            mem_write_trigger <= 1;
                            hdr_hash          <= bc_bytes[0] ^ bc_bytes[1] ^ bc_bytes[2] ^ bc_bytes[3];
                            state             <= S_COUNT;
                        end
                    end
                endcase
            end

            S_COUNT: begin
                // сброс триггеров перед подсчётом
                mem_read_trigger  <= 1'b0;
                mem_write_trigger <= 1'b0;
                step_cnt <= step_cnt + 1;
                if (controller_ready) begin
                    last_step <= step_cnt;
                    state     <= S_SEND_STAT;
                end
            end

            S_SEND_STAT: begin
                if (io_out_ready_trigger) begin
                    if (cmd == CMD_READ && send_count != 0) begin
                        io_out_val  <= mem_value[8*(send_count-1)+:8];
                        hdr_hash <= hdr_hash ^ mem_value[8*(send_count-1)+:8];
                        io_out_trig <= 1;
                        send_count  <= send_count - 1;
                    end else begin
                        io_out_val  <= last_step[31:24];
                        io_out_trig <= 1;
                        state       <= S_SEND_HASH2;
                    end
                end
            end

            S_SEND_HASH2: begin
                if (io_out_ready_trigger) begin
                    io_out_val  <= hdr_hash;
                    io_out_trig <= 1;
                    state       <= S_IDLE;
                end
            end
        endcase
    end
endmodule
