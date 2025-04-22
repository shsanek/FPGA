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
    logic [ADDRESS_SIZE-5:0] chunk_addr;
    logic                    chunk_valid;
    logic [DATA_SIZE-1:0]    chunk_data0;
    logic [DATA_SIZE-1:0]    chunk_data1;
    logic [DATA_SIZE-1:0]    chunk_data2;
    logic [DATA_SIZE-1:0]    chunk_data3;
    logic                    chunk_need_save;

    logic [15:0] internal_order_index;
    assign order_index = internal_order_index;

    // FOR COMMAND
    wire internal_contains_command_address = (chunk_valid && (chunk_addr[23:0] == command_address[27:4]));
    wire[1:0] internal_address_command_index = command_address[3:2];
    assign contains_command_address = internal_contains_command_address;
    assign read_command = internal_contains_command_address ? (
        internal_address_command_index == 0 ? chunk_data0 : (
            internal_address_command_index == 1 ? chunk_data1 : (
                internal_address_command_index == 2 ? chunk_data2 : chunk_data3
            )
        )
    ) : 32'd0;

    // FOR READ
    wire internal_contains_address = (chunk_valid && (chunk_addr[23:0] == address[27:4]));
    wire[1:0] internal_address_index = address[3:2];
    assign contains_address = internal_contains_address;
    assign read_value = internal_contains_address ? (
        internal_address_index == 0 ? chunk_data0 : (
            internal_address_index == 1 ? chunk_data1 : (
                internal_address_index == 2 ? chunk_data2 : chunk_data3
            )
        )
    ) : 32'd0;

    // FOR SAVE
    assign save_address = { chunk_addr, 4'b0000 };
    assign save_need_flag = chunk_need_save;
    assign save_data = { chunk_data3, chunk_data2, chunk_data1, chunk_data0 };
    wire internal_write_trigger = internal_contains_address && write_trigger;

    initial begin 
        chunk_valid = 0;
        chunk_need_save = 0;
    end

    always_ff @(posedge clk) begin
        if ((internal_contains_address && (read_trigger || write_trigger)) || internal_contains_command_address || new_data_save) begin
            internal_order_index <= 0;
        end else if (!chunk_valid) begin
            internal_order_index <= 16'hFFFF;
        end else begin
            if (internal_order_index != 16'hFFFF) begin 
                internal_order_index <= internal_order_index + 1;
            end
        end

        if (new_data_save) begin
            chunk_addr <= new_address[27:4];
            chunk_data0 <= new_data[31:0];
            chunk_data1 <= new_data[63:32];
            chunk_data2 <= new_data[95:64];
            chunk_data3 <= new_data[127:96];
            chunk_need_save <= 0;
            chunk_valid <= 1;
        end else if (internal_write_trigger) begin 
                case(internal_address_index)
                2'b00: chunk_data0 <= { 
                    mask[3] ? write_value[31:24] : chunk_data0[31:24],
                    mask[2] ? write_value[23:16] : chunk_data0[23:16],
                    mask[1] ? write_value[15:8] : chunk_data0[15:8],
                    mask[0] ? write_value[7:0] : chunk_data0[7:0]
                };
                2'b01: chunk_data1 <= { 
                    mask[3] ? write_value[31:24] : chunk_data1[31:24],
                    mask[2] ? write_value[23:16] : chunk_data1[23:16],
                    mask[1] ? write_value[15:8] : chunk_data1[15:8],
                    mask[0] ? write_value[7:0] : chunk_data1[7:0]
                };
                2'b10: chunk_data2 <= { 
                    mask[3] ? write_value[31:24] : chunk_data2[31:24],
                    mask[2] ? write_value[23:16] : chunk_data2[23:16],
                    mask[1] ? write_value[15:8] : chunk_data2[15:8],
                    mask[0] ? write_value[7:0] : chunk_data2[7:0]
                };
                2'b11: chunk_data3 <= { 
                    mask[3] ? write_value[31:24] : chunk_data3[31:24],
                    mask[2] ? write_value[23:16] : chunk_data3[23:16],
                    mask[1] ? write_value[15:8] : chunk_data3[15:8],
                    mask[0] ? write_value[7:0] : chunk_data3[7:0]
                };
                endcase;
                chunk_need_save <= 1;
        end
    end
endmodule