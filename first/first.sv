module bf_register (
    input logic clk,
    input logic reset_trigger,
    input logic write_trigger,
    input logic [7:0] value,
    output logic [7:0] current_value 
);

    logic [7:0] current_value_internal;

    always_ff @(posedge clk or posedge reset_trigger) begin
        if (reset_trigger) begin
            current_value_internal <= 8'b0;
        end else if (write_trigger) begin
            current_value_internal <= value;
        end
    end

    assign current_value = current_value_internal;

endmodule

module NAND(
    input logic a, 
    input logic b,

    output logic y
);
    assign y = ~(a & b);

endmodule

typedef enum logic [1:0] {
    RUN_COMMAND,
    READ_COMMAND,
    READ_VALUE,
    WRITE_VALUE
} global_state;


typedef enum logic [1:0] {
    DEFAULT,
    SEARCH_NEXT,
    SEARCH_BACK
} state_t;

module bf_command_runner(
    input wire clk,

    input wire run_trigger,

    input wire [2:0] current_command,
    input wire [7:0] current_value,

    output reg [15: 0] command_addr,
    output reg [15: 0] cell_addr,

    output reg [7: 0] new_value,
    output reg write_trigger
);
    reg [15: 0] command_addr_internal;
    reg [15: 0] cell_addr_internal;
    reg [7: 0] stack;
    reg write_trigger_internal;
    reg [7: 0] new_value_internal;

    state_t state = DEFAULT;

    initial begin
        command_addr_internal = 0;
        cell_addr_internal = 0;
        stack = 0;
        write_trigger_internal = 0;
        new_value_internal = 0;
    end

    always @(posedge clk) begin
        write_trigger_internal = 0;
        if (run_trigger) begin
        case(state)
        DEFAULT: begin 
            command_addr_internal = command_addr_internal + 1;
            case(current_command)
            3'b000: begin
                new_value_internal = current_value + 1;
                write_trigger_internal = 1;
            end
            3'b001: begin
                new_value_internal = current_value - 1;
                write_trigger_internal = 1;
            end
            3'b010: begin
                if (current_value == 8'b0) begin
                    stack = 0;
                    state = SEARCH_NEXT;
                end
            end
            3'b011: begin
                if (current_value != 8'b0) begin
                    stack = 0;
                    command_addr_internal = command_addr_internal - 2;
                    state = SEARCH_BACK;
                end
            end
            3'b100: begin
                cell_addr_internal = cell_addr_internal + 1;
            end
            3'b101: begin
                cell_addr_internal = cell_addr_internal - 1;
            end
            endcase
        end
        SEARCH_NEXT: begin 
            command_addr_internal = command_addr_internal + 1;
            if (current_command == 3'b011) begin
                if (stack == 0) begin
                    state = DEFAULT;
                end else begin
                    stack = stack - 1;
                end
            end else if (current_command == 3'b010) begin
                stack = stack + 1;
            end
        end
        SEARCH_BACK: begin 
            command_addr_internal = command_addr_internal - 1;
            if (current_command == 3'b010) begin
                if (stack == 0) begin
                    state = DEFAULT;
                    command_addr_internal = command_addr_internal + 2;
                end else begin
                    stack = stack - 1;
                end
            end else if (current_command == 3'b011) begin
                stack = stack + 1;
            end
        end
        endcase 
        end
    end

    assign cell_addr = cell_addr_internal;
    assign command_addr = command_addr_internal;
    assign new_value = new_value_internal;
    assign write_trigger = write_trigger_internal;


endmodule

module memory_model #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 16
)(
    input  wire                   clk,
    input  wire                   we,       // сигнал записи
    input  wire [ADDR_WIDTH-1:0]  addr,
    input  wire [DATA_WIDTH-1:0]  data_in,
    output reg  [DATA_WIDTH-1:0]  data_out
);

    reg [DATA_WIDTH-1:0] mem [(2**ADDR_WIDTH)-1:0];

    initial begin
        integer i;
        for (i = 0; i < (2**ADDR_WIDTH); i = i + 1)
            mem[i] = 0;
    end

    always @(posedge clk) begin
        if (we)
            mem[addr] <= data_in;
        data_out <= mem[addr];
    end

endmodule