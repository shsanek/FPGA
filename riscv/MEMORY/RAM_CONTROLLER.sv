module RAM_CONTROLLER #(
    parameter CHUNK_PART = 128,
    parameter DATA_SIZE = 32,
    parameter MASK_SIZE = DATA_SIZE / 8,
    parameter ADDRESS_SIZE = 28,
    parameter CHUNK_COUNT = 4
)
(
    input wire clk,

    // COMMON
    input wire[ADDRESS_SIZE - 1:0] address,
    input wire[MASK_SIZE - 1: 0] mask,
    output logic controller_ready,
    output logic[3:0] error,

    // WRITE
    input wire write_trigger,
    input wire[DATA_SIZE-1: 0] write_value,

    // READ
    input wire read_trigger,
    output wire[DATA_SIZE-1: 0] read_value,
    output wire read_value_ready,


    // MIG INTERFACE

    // --- MIG INTERFACE --- (подключается к блоку MIG DDR3)
    // Управляющие сигналы (выходы от вашего контроллера, входы в MIG)
    output wire [ADDRESS_SIZE-1:0] mig_app_addr,  // Адрес для операции (28 бит)
    output logic [2:0]              mig_app_cmd,   // Команда: например, 3'b001 для чтения, 3'b010 для записи
    output logic                    mig_app_en,    // Валидность команды и адреса

    // Сигналы для записи (подаются в Write Data FIFO MIG)
    output logic [CHUNK_PART - 1:0]          mig_app_wdf_data, // 128-битные данные для записи
    output logic                  mig_app_wdf_end,  // Сигнал завершения передачи burst данных
    output logic [(CHUNK_PART / 8 - 1):0]           mig_app_wdf_mask, // Маска для 128-битных данных (если нужна)
    output logic                  mig_app_wdf_wren, // Разрешение записи в Write Data FIFO
    input  wire                  mig_app_wdf_rdy, // MIG готов принять данные для записи

    // Сигналы для чтения (выходы из MIG)
    input  wire [CHUNK_PART - 1:0]          mig_app_rd_data,  // 128-битные данные, считанные из памяти
    input  wire                  mig_app_rd_data_end,   // Сигнал, показывающий завершение burst чтения
    input  wire                  mig_app_rd_data_valid, // Валидность полученных данных

    // Сигналы готовности MIG
    input  wire                  mig_app_rdy,    // MIG готов принять новую команду

    // Тактовые и синхронные сигналы от MIG
    input  wire                  mig_ui_clk,         // ui_clk - тактовый сигнал пользовательского интерфейса MIG
    input  wire                  mig_init_calib_complete // Сигнал завершения инициализации и калибровки DDR3
);

    typedef enum logic [1:0] {
        SYNC_CONTROLLER_ACTIVE_CONTROLL,
        SYNC_CONTROLLER_WILL_START_CONTROLL,
        SYNC_CONTROLLER_WILL_STOP_CONTROLL,
        SYNC_CONTROLLER_NOT_CONTOLL
    } SYNC_CONTROLLER_STATE;

    typedef enum logic [1:0] {
        RAM_CONTROLLER_STATE_WATING,
        RAM_CONTROLLER_STATE_READ,
        RAM_CONTROLLER_STATE_WRITE
    } RAM_CONTROLLER_STATE; 

    SYNC_CONTROLLER_STATE controll_clk_state;
    SYNC_CONTROLLER_STATE controll_ui_clk_state;

    logic[ADDRESS_SIZE - 1:0] internal_address;
    logic[MASK_SIZE - 1: 0] internal_mask;
    logic[3:0] internal_error;
    logic[DATA_SIZE-1: 0] internal_write_value;
    logic internal_read_trigger;
    logic internal_write_trigger;
    logic[DATA_SIZE-1: 0] internal_read_value;
    logic internal_read_value_ready;

    RAM_CONTROLLER_STATE ram_state;

    logic[3: 0] internal_chunk_part_index;
    logic[CHUNK_PART-1: 0] internal_output_value;
    
    logic internal_read_value_ready2;
    assign read_value_ready = internal_read_value_ready2;
    assign read_value = internal_output_value[31:0];

    initial begin
        controll_ui_clk_state = SYNC_CONTROLLER_NOT_CONTOLL;
        controll_clk_state = SYNC_CONTROLLER_ACTIVE_CONTROLL;
        internal_address = 0;
        internal_mask = 0;
        controller_ready = 1;
        internal_error = 0;
        internal_write_trigger = 0;
        internal_write_value = 0;
        internal_read_trigger = 0;
        internal_read_value = 0;
        internal_read_value_ready2 = 0;
        internal_read_value_ready = 0;
    end

    always_ff @(posedge clk) begin
        if (controll_clk_state == SYNC_CONTROLLER_ACTIVE_CONTROLL) begin
            controller_ready <= !(write_trigger || read_trigger) && (internal_error == 0);
            
            internal_read_value_ready2 <= internal_read_value_ready;
            internal_read_value_ready <= read_trigger;

            internal_address <= address;
            internal_mask <= mask;

            internal_write_trigger <= write_trigger;
            internal_write_value <= write_value;
            internal_read_trigger <= read_trigger;

            error <= internal_error;
            
            if (write_trigger || read_trigger) begin
                controll_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
            end
        end else if (
            controll_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL && 
            controll_ui_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL
        ) begin
            controll_clk_state <= SYNC_CONTROLLER_NOT_CONTOLL;
        end else if (
            controll_ui_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL &&
            controll_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin
            controll_clk_state <= SYNC_CONTROLLER_WILL_START_CONTROLL;
        end else if (
            controll_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL &&
            controll_ui_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin 
            controll_clk_state <= SYNC_CONTROLLER_ACTIVE_CONTROLL;
        end
    end

    initial begin 
        ram_state = RAM_CONTROLLER_STATE_WATING;
        internal_mask = ~0;
        internal_chunk_part_index = 0;
    end

    // эти сигналы постоянны
    assign mig_app_wdf_wren = 1;
    assign mig_app_wdf_data = internal_write_value;
    assign mig_app_wdf_end = 1;
    assign mig_app_addr = internal_address;
    assign mig_app_wdf_mask = 1;
 
    always_ff @(posedge mig_ui_clk) begin
        // тут код не требующий синхронизации

        // код синхронизации
        if (controll_ui_clk_state == SYNC_CONTROLLER_ACTIVE_CONTROLL) begin
            if (ram_state == RAM_CONTROLLER_STATE_WATING) begin 
                if (mig_app_rdy && mig_init_calib_complete) begin

                    if (internal_read_trigger) begin
                        mig_app_en <= 1;
                        mig_app_cmd <= 1;
                        
                        ram_state <= RAM_CONTROLLER_STATE_READ;
                    end else if (internal_write_trigger) begin
                        mig_app_en <= 1;
                        mig_app_cmd <= 2;

                        // mig_app_wdf_wren <= 1;
                        // mig_app_wdf_data <= internal_write_value;
                        // mig_app_wdf_end <= 1;

                        ram_state <= RAM_CONTROLLER_STATE_WRITE;
                    end else begin 
                        internal_error <= 1;
                        controll_ui_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
                    end
                end
            end else if (ram_state == RAM_CONTROLLER_STATE_READ) begin
                mig_app_en <= 0;
                if (mig_app_rd_data_valid) begin
                    internal_output_value <= mig_app_rd_data;
                    // сохраняем сигнал и передаем управление
                    ram_state <= RAM_CONTROLLER_STATE_WATING;
                    controll_ui_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
                end
            end else if (ram_state == RAM_CONTROLLER_STATE_WRITE) begin
                mig_app_en <= 0;
                if (mig_app_wdf_rdy) begin
                    // сигналы уже выставлены и синхронизированные так что просто передаем управление другому домену
                    ram_state <= RAM_CONTROLLER_STATE_WATING;
                    controll_ui_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
                end
            end
        end else if (
            controll_ui_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL && 
            controll_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL
        ) begin
            controll_ui_clk_state <= SYNC_CONTROLLER_NOT_CONTOLL;
        end else if (
            controll_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL &&
            controll_ui_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin
            controll_ui_clk_state <= SYNC_CONTROLLER_WILL_START_CONTROLL;
        end else if (
            controll_ui_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL &&
            controll_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin 
            controll_ui_clk_state <= SYNC_CONTROLLER_ACTIVE_CONTROLL;
        end
    end

endmodule

module CHUNK_STORAGE#(
    parameter CHUNK_PART = 128,
    parameter DATA_SIZE = 32,
    parameter MASK_SIZE = DATA_SIZE / 8,
    parameter ADDRESS_SIZE = 28
)(
    input wire clk,

    // COMMON
    input wire[ADDRESS_SIZE - 1:0] address,
    input wire[MASK_SIZE - 1: 0] mask,
    output logic controller_ready,
    output logic[3:0] error,

    // WRITE
    input wire write_trigger,
    input wire[DATA_SIZE-1: 0] write_value,

    // READ
    input wire read_trigger,
    output wire[DATA_SIZE-1: 0] read_value,
    output wire read_value_ready,

    //
    output wire contains_address,
    output wire[ADDRESS_SIZE - 1:0] save_address,
    output wire[CHUNK_PART - 1: 0] save_data,
    output wire save_need_flag,

    input wire[CHUNK_PART - 1: 0] new_data,
    input wire new_data_save
);
    typedef struct packed {
        logic[ADDRESS_SIZE - 5:0] address;
        logic [DATA_SIZE - 1:0] data_0;
        logic [DATA_SIZE - 1:0] data_1;
        logic [DATA_SIZE - 1:0] data_2;
        logic [DATA_SIZE - 1:0] data_3;
        logic valid;
        logic need_save;
    } CHUNK;

    CHUNK chunks[3:0];
    
    wire address_0 = (chunks[0].valid && chunks[0].address[23:0] == address[27:4]); // 248
    wire address_1 = (chunks[1].valid && chunks[1].address[23:0] == address[27:4]);
    wire address_2 = (chunks[2].valid && chunks[2].address[23:0] == address[27:4]);
    wire address_3 = (chunks[3].valid && chunks[3].address[23:0] == address[27:4]);
    
    wire [DATA_SIZE - 1:0] data_0 = (address[3:2] == 2'd0) ? chunks[0].data_0 :
                                    (address[3:2] == 2'd1) ? chunks[0].data_1 :
                                    (address[3:2] == 2'd2) ? chunks[0].data_2 :
                                                            chunks[0].data_3;

    wire [DATA_SIZE - 1:0] data_1 = (address[3:2] == 2'd0) ? chunks[1].data_0 :
                                    (address[3:2] == 2'd1) ? chunks[1].data_1 :
                                    (address[3:2] == 2'd2) ? chunks[1].data_2 :
                                                            chunks[1].data_3;

    wire [DATA_SIZE - 1:0] data_2 = (address[3:2] == 2'd0) ? chunks[2].data_0 :
                                    (address[3:2] == 2'd1) ? chunks[2].data_1 :
                                    (address[3:2] == 2'd2) ? chunks[2].data_2 :
                                                            chunks[2].data_3;

    wire [DATA_SIZE - 1:0] data_3 = (address[3:2] == 2'd0) ? chunks[3].data_0 :
                                    (address[3:2] == 2'd1) ? chunks[3].data_1 :
                                    (address[3:2] == 2'd2) ? chunks[3].data_2 :
                                                            chunks[3].data_3;

    wire[DATA_SIZE - 1:0] read_data = address_0 ? data_0 : (address_1 ? data_1 : (address_2 ? data_2 : (address_3 ? data_3 : 0)));

    assign contains_address = address_0 || address_1 || address_2 || address_3;

    assign save_address = {chunks[chunks_list[3]].address, 4'b000};
    assign save_data = { chunks[chunks_list[3]].data_0, chunks[chunks_list[3]].data_1, chunks[chunks_list[3]].data_2, chunks[chunks_list[3]].data_3 };
    assign save_need_flag = chunks[chunks_list[3]].need_save;

    logic[1:0] chunks_list[3:0];

    always_ff @(posedge clk) begin
        if (new_data_save) begin
            chunks[chunks_list[3]].address <= address[27:4];
            chunks[chunks_list[3]].data_0 <= new_data[31:0];
            chunks[chunks_list[3]].data_1 <= new_data[63:32];
            chunks[chunks_list[3]].data_2 <= new_data[95:64];
            chunks[chunks_list[3]].data_3 <= new_data[127:96];
            chunks[chunks_list[3]].valid <= 1;
        end else begin 
            for (int i = 0; i < 4; i++) begin
                if (chunks[i].valid && chunks[i].address == address[27:4]) begin
                    if (write_trigger || read_trigger) begin
                        if (chunks_list[0] != i) begin
                            chunks_list[1] <= chunks_list[0];
                            if (chunks_list[1] != i) begin
                                chunks_list[2] <= chunks_list[1];
                                if (chunks_list[2] != i) begin
                                    chunks_list[3] <= chunks_list[2];
                                end
                            end
                        end
                        chunks_list[0] <= i;
                    end
                    if (write_trigger) begin
                        case(address[3:2])
                        2'b00: chunks[i].data_0 <= { 
                            mask[0] ? write_value[7:0] : chunks[i].data_0[7:0],
                            mask[1] ? write_value[15:8] : chunks[i].data_0[15:8],
                            mask[2] ? write_value[23:16] : chunks[i].data_0[23:16],
                            mask[3] ? write_value[31:24] : chunks[i].data_0[31:24]
                        };
                        2'b01: chunks[i].data_1 <= { 
                            mask[0] ? write_value[7:0] : chunks[i].data_1[7:0],
                            mask[1] ? write_value[15:8] : chunks[i].data_1[15:8],
                            mask[2] ? write_value[23:16] : chunks[i].data_1[23:16],
                            mask[3] ? write_value[31:24] : chunks[i].data_1[31:24]
                        };
                        2'b10: chunks[i].data_2 <= { 
                            mask[0] ? write_value[7:0] : chunks[i].data_2[7:0],
                            mask[1] ? write_value[15:8] : chunks[i].data_2[15:8],
                            mask[2] ? write_value[23:16] : chunks[i].data_2[23:16],
                            mask[3] ? write_value[31:24] : chunks[i].data_2[31:24]
                        };
                        2'b11: chunks[i].data_3 <= { 
                            mask[0] ? write_value[7:0] : chunks[i].data_3[7:0],
                            mask[1] ? write_value[15:8] : chunks[i].data_3[15:8],
                            mask[2] ? write_value[23:16] : chunks[i].data_3[23:16],
                            mask[3] ? write_value[31:24] : chunks[i].data_3[31:24]
                        };
                        endcase;
                        chunks[i].need_save <= 1;
                    end
                end
            end
        end
    end
endmodule