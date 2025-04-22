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
    output logic[2:0] led0,

    // MIG INTERFACE

    // --- MIG INTERFACE --- (подключается к блоку MIG DDR3)
    // Управляющие сигналы (выходы от вашего контроллера, входы в MIG)
    output wire [ADDRESS_SIZE-1:0] mig_app_addr,  // Адрес для операции (28 бит)
    output logic [2:0]              mig_app_cmd,   // Команда: например, 3'b001 для чтения, 3'b010 для записи
    output logic                    mig_app_en,    // Валидность команды и адреса

    // Сигналы для записи (подаются в Write Data FIFO MIG)
    output logic [CHUNK_PART - 1:0]          mig_app_wdf_data, // 128-битные данные для записи
    output logic                  mig_app_wdf_end,  // Сигнал завершения передачи burst данных
    output wire [(CHUNK_PART / 8 - 1):0]           mig_app_wdf_mask, // Маска для 128-битных данных (если нужна)
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
        RAM_CONTROLLER_STATE_WRITE,
        RAM_CONTROLLER_STATE_INIT
    } RAM_CONTROLLER_STATE; 

    SYNC_CONTROLLER_STATE controll_clk_state;
    SYNC_CONTROLLER_STATE _controll_clk_state;
    
    SYNC_CONTROLLER_STATE _controll_ui_clk_state;
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
        controll_ui_clk_state = SYNC_CONTROLLER_ACTIVE_CONTROLL;
        controll_clk_state = SYNC_CONTROLLER_NOT_CONTOLL;
        
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
        led0[1] <= mig_init_calib_complete;
        led0[0] <= !mig_init_calib_complete;
        led0[2] <= !controll_clk_state == SYNC_CONTROLLER_ACTIVE_CONTROLL;
        _controll_ui_clk_state <= controll_ui_clk_state;
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
            _controll_ui_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL
        ) begin
            controll_clk_state <= SYNC_CONTROLLER_NOT_CONTOLL;
        end else if (
            _controll_ui_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL &&
            controll_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin
            controll_clk_state <= SYNC_CONTROLLER_WILL_START_CONTROLL;
        end else if (
            controll_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL &&
            _controll_ui_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin 
            controll_clk_state <= SYNC_CONTROLLER_ACTIVE_CONTROLL;
        end
    end

    initial begin 
        ram_state = RAM_CONTROLLER_STATE_INIT;
        internal_mask = ~0;
        internal_chunk_part_index = 0;
    end

    // эти сигналы постоянны
    assign mig_app_addr = internal_address;
    assign mig_app_wdf_mask = 16'b0000000000000000;
 
    always_ff @(posedge mig_ui_clk) begin
        _controll_clk_state <= controll_clk_state;

        // код синхронизации
        if (controll_ui_clk_state == SYNC_CONTROLLER_ACTIVE_CONTROLL) begin
            if (ram_state == RAM_CONTROLLER_STATE_INIT) begin
                if (mig_init_calib_complete) begin
                    ram_state <= RAM_CONTROLLER_STATE_WATING;
                    controll_ui_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
                end
            end else if (ram_state == RAM_CONTROLLER_STATE_WATING) begin 
                if (mig_app_rdy && mig_init_calib_complete) begin

                    if (internal_read_trigger) begin
                        mig_app_en <= 1;
                        mig_app_cmd <= 1;
                        
                        ram_state <= RAM_CONTROLLER_STATE_READ;
                    end else if (internal_write_trigger) begin
                        mig_app_en <= 1;
                        mig_app_cmd <= 3'b000;

                        mig_app_wdf_data[31:0] <= internal_write_value;
                       
                        ram_state <= RAM_CONTROLLER_STATE_WRITE;
                    end else begin 
                        internal_error <= 1;
                        controll_ui_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
                    end
                end
            end else if (ram_state == RAM_CONTROLLER_STATE_READ) begin
                if (mig_app_rdy) begin
                    mig_app_en <= 0;
                end
                if (mig_app_rd_data_valid) begin
                    internal_output_value <= mig_app_rd_data[31:0];

                    ram_state <= RAM_CONTROLLER_STATE_WATING;
                    controll_ui_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
                end
            end else if (ram_state == RAM_CONTROLLER_STATE_WRITE) begin
                if (mig_app_rdy) begin
                    mig_app_en <= 0;
                end
                if (!mig_app_en && !mig_app_wdf_wren && mig_app_wdf_rdy) begin
                    mig_app_wdf_wren <= 1;
                    mig_app_wdf_end <= 1;
                end else if (mig_app_wdf_wren) begin
                    mig_app_wdf_wren <= 0;
                    mig_app_wdf_end <= 0;
                    ram_state <= RAM_CONTROLLER_STATE_WATING;
                    controll_ui_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
                end
            end
        end else if (
            controll_ui_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL && 
            _controll_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL
        ) begin
            mig_app_en <= 0;
            controll_ui_clk_state <= SYNC_CONTROLLER_NOT_CONTOLL;
        end else if (
            _controll_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL &&
            controll_ui_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin
            controll_ui_clk_state <= SYNC_CONTROLLER_WILL_START_CONTROLL;
        end else if (
            controll_ui_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL &&
            _controll_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin 
            controll_ui_clk_state <= SYNC_CONTROLLER_ACTIVE_CONTROLL;
        end
    end

endmodule



// module CHUNK_STORAGE_POOL#(
//     parameter CHUNK_PART = 128,
//     parameter DATA_SIZE = 32,
//     parameter MASK_SIZE = DATA_SIZE / 8,
//     parameter ADDRESS_SIZE = 28
// )(
//     input wire clk,

//     // COMMON
//     input wire[ADDRESS_SIZE - 1:0] address,
//     input wire[MASK_SIZE - 1: 0] mask,

//     // WRITE
//     input wire write_trigger,
//     input wire[DATA_SIZE-1: 0] write_value,

//     // READ FOR COMMAND 
//     input wire[ADDRESS_SIZE - 1:0] command_address,
//     output wire[DATA_SIZE-1:0] read_command,
//     output wire contains_command_address,

//     // READ
//     input wire read_trigger,
//     output wire[DATA_SIZE-1: 0] read_value,
//     output wire contains_address,

//     output wire[ADDRESS_SIZE - 1:0] save_address,
//     output wire[CHUNK_PART - 1: 0] save_data,
//     output wire save_need_flag,

//     output wire[15:0] order_index,

//     input wire[CHUNK_PART - 1: 0] new_data,
//     input wire[ADDRESS_SIZE - 1:0] new_address,
//     input wire new_data_save
// );
//     assign contains_command_address = _contains_command_address[0] || _contains_command_address[1] || _contains_command_address[2] || _contains_command_address[3];
//     assign contains_address = _contains_address[0] || _contains_address[1] || _contains_address[2] || _contains_address[3];

//     localparam COUNT = 4;

//     assign read_command = _read_command[0] | _read_command[1] | _read_command[2] | _read_command[3];
//     assign read_value = _read_value[0] | _read_value[1] | _read_value[2] | _read_value[3];

//     wire _out_index_0_i = !((_order_index[0] < _order_index[1]) || (_order_index[0] < _order_index[2]) || (_order_index[0] < _order_index[3]));
//     wire _out_index_1_i = !((_order_index[1] < _order_index[0]) || (_order_index[1] < _order_index[2]) || (_order_index[1] < _order_index[3]));
//     wire _out_index_2_i = !((_order_index[2] < _order_index[1]) || (_order_index[2] < _order_index[0]) || (_order_index[2] < _order_index[3]));
//     wire _out_index_3_i = !((_order_index[3] < _order_index[1]) || (_order_index[3] < _order_index[2]) || (_order_index[3] < _order_index[0]));

//     wire _out_index[COUNT];

//     assign _out_index[0] = _out_index_0_i;
//     assign _out_index[1] = _out_index_1_i && !_out_index[0];
//     assign _out_index[2] = _out_index_2_i && !_out_index[1];
//     assign _out_index[3] = _out_index_3_i && !_out_index[2];

//     assign order_index =
//         (_out_index[0] & _order_index[0]) |
//         (_out_index[1] & _order_index[1]) |
//         (_out_index[2] & _order_index[2]) |
//         (_out_index[3] & _order_index[3]);

//     assign save_address = 
//         (_out_index[0] & _save_address[0]) |
//         (_out_index[1] & _save_address[1]) |
//         (_out_index[2] & _save_address[2]) |
//         (_out_index[3] & _save_address[3]);

//     assign save_data = 
//         (_out_index[0] & _save_data[0]) |
//         (_out_index[1] & _save_data[1]) |
//         (_out_index[2] & _save_data[2]) |
//         (_out_index[3] & _save_data[3]);

//     assign save_need_flag = 
//         (_out_index[0] & _save_need_flag[0]) |
//         (_out_index[1] & _save_need_flag[1]) |
//         (_out_index[2] & _save_need_flag[2]) |
//         (_out_index[3] & _save_need_flag[3]);

//     wire[DATA_SIZE-1:0] _read_command[COUNT];
//     wire[COUNT] _contains_command_address;

//     // READ
//     wire[DATA_SIZE-1: 0] _read_value[COUNT];
//     wire[COUNT] _contains_address;

//     wire[ADDRESS_SIZE - 1:0] _save_address[COUNT];
//     wire[CHUNK_PART - 1: 0] _save_data[COUNT];
//     wire _save_need_flag[COUNT];

//     wire[15:0] _order_index[COUNT];
    
//     genvar i;
//     generate
//         for (i = 0; i < COUNT; i = i + 1) begin : gen_storage
//             CHUNK_STORAGE #(
//                 .CHUNK_PART(CHUNK_PART),
//                 .DATA_SIZE(DATA_SIZE),
//                 .MASK_SIZE(MASK_SIZE),
//                 .ADDRESS_SIZE(ADDRESS_SIZE)
//             ) storage_inst (
//                 .clk                   (clk),
//                 .address               (address),
//                 .mask                  (mask),

//                 // WRITE
//                 .write_trigger         (write_trigger),
//                 .write_value           (write_value),

//                 // READ FOR COMMAND
//                 .command_address       (command_address),
//                 .read_command          (_read_command[i]),
//                 .contains_command_address(_contains_command_address[i]),

//                 // READ
//                 .read_trigger          (read_trigger),
//                 .read_value            (_read_value[i]),
//                 .contains_address      (_contains_address[i]),

//                 // SAVE
//                 .save_address          (_save_address[i]),
//                 .save_data             (_save_data[i]),
//                 .save_need_flag        (_save_need_flag[i]),

//                 .order_index           (_order_index[i]),

//                 // NEW DATA
//                 .new_data              (new_data),
//                 .new_address           (new_address),
//                 .new_data_save         (_out_index[i] && new_data_save)
//             );
//         end
//     endgenerate
// endmodule