module MEMORY_CONTROLLER#(
    parameter CHUNK_PART = 128,
    parameter DATA_SIZE = 32,
    parameter MASK_SIZE = DATA_SIZE / 8,
    parameter ADDRESS_SIZE = 28
)(
    input wire clk,

    // RAM 

    // COMMON
    input logic ram_controller_ready,

    // WRITE
    output logic ram_write_trigger,
    output logic[CHUNK_PART - 1: 0] ram_write_value,
    output logic[ADDRESS_SIZE - 1:0] ram_write_address,

    // READ
    output logic ram_read_trigger,
    input wire[CHUNK_PART - 1: 0] ram_read_value,
    output logic[ADDRESS_SIZE - 1:0] ram_read_address,
    input wire ram_read_value_ready,

    // INTERFACE
    // COMMON
    output wire controller_ready,
    input wire[ADDRESS_SIZE - 1:0] address,
    input wire[MASK_SIZE - 1: 0] mask,

    // WRITE
    input wire write_trigger,
    input wire[DATA_SIZE-1: 0] write_value,

    // READ FOR COMMAND 
    input wire[ADDRESS_SIZE - 1:0] command_address,
    output wire[DATA_SIZE-1:0] read_command,
    output wire contains_command_address,

    // READ
    input wire read_trigger,
    output wire[DATA_SIZE-1: 0] read_value,
    output wire contains_address
);
    wire[ADDRESS_SIZE - 1:0] save_address;
    wire[CHUNK_PART - 1: 0] save_data;
    wire save_need_flag;

    logic[CHUNK_PART - 1: 0] new_data;
    logic[ADDRESS_SIZE - 1:0] new_address;
    logic new_data_save;

    wire internal_contains_address;
    wire internal_contains_command_address;

    logic internal_write_trigger;
    logic[ADDRESS_SIZE - 1:0] internal_address;
    logic[MASK_SIZE - 1:0] internal_mask;
    logic[DATA_SIZE - 1:0] internal_write_data;

    wire output_write_trigger;
    wire[ADDRESS_SIZE - 1:0] output_address;
    wire[MASK_SIZE - 1:0] output_mask;
    wire[DATA_SIZE - 1:0] output_write_value;
    
    assign output_write_trigger = (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) ? internal_write_trigger : write_trigger;
    assign output_address = (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) ? internal_address : address;
    assign output_mask = (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) ? internal_mask : mask;
    assign output_write_value = (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) ? internal_write_data : write_data;

    assign contains_address = internal_contains_address;
    assign contains_command_address = internal_contains_command_address;
    assign controller_ready = ((internal_state == MEMORY_CONTROLLER_STATE_NORMA) && ram_controller_ready); 
    typedef enum logic [1:0] {
        MEMORY_CONTROLLER_STATE_NORMAL,
        MEMORY_CONTROLLER_STATE_WATING,
        MEMORY_CONTROLLER_STATE_SAVE_DATA,
        MEMORY_CONTROLLER_STATE_WRITE_DATA
    } MEMORY_CONTROLLER_STATE;

    MEMORY_CONTROLLER_STATE internal_state;

    initial begin
        internal_write_trigger <= 0;
        internal_state = MEMORY_CONTROLLER_STATE_NORMAL;
        new_data_save = 0;
        ram_write_trigger = 0;
        ram_read_trigger = 0;
    end

    always_ff @(posedge clk) begin
        if (internal_state == MEMORY_CONTROLLER_STATE_SAVE_DATA) begin
            new_data_save <= 0;
            internal_state <= internal_write_trigger ? MEMORY_CONTROLLER_STATE_WRITE_DATA : MEMORY_CONTROLLER_STATE_NORMAL;
        end else if (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) begin
            internal_write_trigger <= 0;
            internal_state <= MEMORY_CONTROLLER_STATE_WATING;
        end else if (internal_state == MEMORY_CONTROLLER_STATE_NORMAL && ram_controller_ready) begin
            if ((!internal_contains_address) && (read_trigger || write_trigger)) begin
                if (save_need_flag) begin
                    ram_write_trigger <= 1;
                    ram_write_value <= save_data;
                    ram_write_address <= save_address;
                end
                internal_write_trigger <= write_trigger;
                internal_address <= address;
                internal_mask <= mask;
                internal_write_value <= write_value;

                ram_read_trigger <= 1;
                ram_read_address <= { address[27:4], 4'b0000 };
                internal_state <= MEMORY_CONTROLLER_STATE_WATING;
            end else if (!internal_contains_command_address) begin
                if (save_need_flag) begin
                    ram_write_trigger <= 1;
                    ram_write_value <= save_data;
                    ram_write_address <= save_address;
                end
                ram_read_trigger <= 1;
                ram_read_address <= { command_address[27:4], 4'b0000 };
                internal_state <= MEMORY_CONTROLLER_STATE_WATING;
            end
        end else if (internal_state == MEMORY_CONTROLLER_STATE_WATING) begin
            ram_read_trigger <= 0;
            ram_write_trigger <= 0;
            if (ram_read_value_ready) begin
                new_address <= ram_read_address;
                new_data <= ram_read_value;
                new_data_save <= 1;
                internal_state <= MEMORY_CONTROLLER_STATE_SAVE_DATA;
            end
        end
    end

    CHUNK_STORAGE_4_POOL #(
        .CHUNK_PART(CHUNK_PART),
        .DATA_SIZE(DATA_SIZE),
        .MASK_SIZE(MASK_SIZE),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) storage_pool (
        .clk                   (clk),
        .address               (output_address),
        .mask                  (output_mask),

        // WRITE
        .write_trigger         (output_write_trigger),
        .write_value           (output_write_value),

        // READ FOR COMMAND
        .command_address       (command_address),
        .read_command          (read_command),
        .contains_command_address(internal_contains_command_address),

        // READ
        .read_trigger          (read_trigger),
        .read_value            (read_value),
        .contains_address      (internal_contains_address),

        // SAVE
        .save_address          (save_address),
        .save_data             (save_data),
        .save_need_flag        (save_need_flag),

        // NEW DATA
        .new_data              (new_data),
        .new_address           (new_address),
        .new_data_save         (new_data_save)
    );

endmodule