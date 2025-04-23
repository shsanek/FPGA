module CHUNK_STORAGE_4_POOL#(
    parameter CHUNK_PART = 128,
    parameter DATA_SIZE = 32,
    parameter MASK_SIZE = DATA_SIZE / 8,
    parameter ADDRESS_SIZE = 28
)(
    input wire clk,

    // COMMON
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
    output wire contains_address,

    output wire[ADDRESS_SIZE - 1:0] save_address,
    output wire[CHUNK_PART - 1: 0] save_data,
    output wire save_need_flag,

    output wire[15:0] order_index,

    input wire[CHUNK_PART - 1: 0] new_data,
    input wire[ADDRESS_SIZE - 1:0] new_address,
    input wire new_data_save
);
    assign contains_command_address = _contains_command_address[0] || _contains_command_address[1] || _contains_command_address[2] || _contains_command_address[3];
    assign contains_address = _contains_address[0] || _contains_address[1] || _contains_address[2] || _contains_address[3];

    localparam COUNT = 4;

    assign read_command = _read_command[0] | _read_command[1] | _read_command[2] | _read_command[3];
    assign read_value = _read_value[0] | _read_value[1] | _read_value[2] | _read_value[3];

    wire _out_index_0_i = !((_order_index[0] < _order_index[1]) || (_order_index[0] < _order_index[2]) || (_order_index[0] < _order_index[3]));
    wire _out_index_1_i = !((_order_index[1] < _order_index[0]) || (_order_index[1] < _order_index[2]) || (_order_index[1] < _order_index[3]));
    wire _out_index_2_i = !((_order_index[2] < _order_index[1]) || (_order_index[2] < _order_index[0]) || (_order_index[2] < _order_index[3]));
    wire _out_index_3_i = !((_order_index[3] < _order_index[1]) || (_order_index[3] < _order_index[2]) || (_order_index[3] < _order_index[0]));

    wire internal_out_index[COUNT-1:0];

    assign internal_out_index[0] = _out_index_0_i;
    assign internal_out_index[1] = _out_index_1_i && !(_out_index_0_i);
    assign internal_out_index[2] = _out_index_2_i && !(_out_index_0_i || _out_index_1_i);
    assign internal_out_index[3] = !(_out_index_0_i || _out_index_1_i || _out_index_2_i);

    assign order_index =
        (internal_out_index[0] ? _order_index[0] : 0) |
        (internal_out_index[1] ? _order_index[1] : 0) |
        (internal_out_index[2] ? _order_index[2] : 0) |
        (internal_out_index[3] ? _order_index[3] : 0);

    assign save_address = 
        (internal_out_index[0] ? _save_address[0] : 0) |
        (internal_out_index[1] ? _save_address[1] : 0) |
        (internal_out_index[2] ? _save_address[2] : 0) |
        (internal_out_index[3] ? _save_address[3] : 0);

    assign save_data = 
        (internal_out_index[0] ? _save_data[0] : 0) |
        (internal_out_index[1] ? _save_data[1] : 0) |
        (internal_out_index[2] ? _save_data[2] : 0) |
        (internal_out_index[3] ? _save_data[3] : 0);

    assign save_need_flag = 
        (internal_out_index[0] ? _save_need_flag[0] : 0) |
        (internal_out_index[1] ? _save_need_flag[1] : 0) |
        (internal_out_index[2] ? _save_need_flag[2] : 0) |
        (internal_out_index[3] ? _save_need_flag[3] : 0);

    wire[DATA_SIZE-1:0] _read_command[COUNT];
    wire[COUNT-1:0] _contains_command_address;

    // READ
    wire[DATA_SIZE-1: 0] _read_value[COUNT];
    wire[COUNT-1:0] _contains_address;

    wire[ADDRESS_SIZE - 1:0] _save_address[COUNT];
    wire[CHUNK_PART - 1: 0] _save_data[COUNT];
    wire[COUNT - 1: 0] _save_need_flag;

    wire[15:0] _order_index[COUNT];
    wire[COUNT:0] _new_data_save;

    assign _new_data_save[0] = new_data_save & internal_out_index[0];
    assign _new_data_save[1] = new_data_save & internal_out_index[1];
    assign _new_data_save[2] = new_data_save & internal_out_index[2];
    assign _new_data_save[3] = new_data_save & internal_out_index[3];
    
    genvar i;
    generate
        for (i = 0; i < COUNT; i = i + 1) begin : gen_storage
            CHUNK_STORAGE #(
                .CHUNK_PART(CHUNK_PART),
                .DATA_SIZE(DATA_SIZE),
                .MASK_SIZE(MASK_SIZE),
                .ADDRESS_SIZE(ADDRESS_SIZE)
            ) storage_inst (
                .clk                   (clk),
                .address               (address),
                .mask                  (mask),

                // WRITE
                .write_trigger         (write_trigger),
                .write_value           (write_value),

                // READ FOR COMMAND
                .command_address       (command_address),
                .read_command          (_read_command[i]),
                .contains_command_address(_contains_command_address[i]),

                // READ
                .read_trigger          (read_trigger),
                .read_value            (_read_value[i]),
                .contains_address      (_contains_address[i]),

                // SAVE
                .save_address          (_save_address[i]),
                .save_data             (_save_data[i]),
                .save_need_flag        (_save_need_flag[i]),

                .order_index           (_order_index[i]),

                // NEW DATA
                .new_data              (new_data),
                .new_address           (new_address),
                .new_data_save         (_new_data_save[i])
            );
        end
    endgenerate
endmodule