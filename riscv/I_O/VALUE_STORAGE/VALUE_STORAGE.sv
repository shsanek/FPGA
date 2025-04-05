typedef enum logic [1:0] {
    WATING_BUTTON_INPUT,
    WATING_BUTTON_UP,

    OUTPUT,
    WATING_OUTPUT
} VALUE_STORAGE_STATE;
        
module VALUE_STORAGE (
    input wire clk,

    input wire[3:0] buttons,

    input wire io_input_trigger,
    input wire[7:0] io_input_value,

    input wire io_output_ready_trigger, 

    output wire[7:0] io_output_value,
    output wire io_output_trigger,

    output wire[3:0] leds
);
    logic[7:0] internal_value;
    logic internal_io_output_trigger;
    VALUE_STORAGE_STATE state;

    assign io_output_value = internal_value;
    assign leds = internal_value[3:0];
    assign io_output_trigger = internal_io_output_trigger;

    always_ff @(posedge clk) begin
        if (io_input_trigger) begin 
            internal_value <= io_input_value;
        end else begin
            case(state)
                (WATING_BUTTON_INPUT): begin
                    if (buttons[0]) begin
                        internal_value <= (internal_value << 1) + 1;
                        state <= WATING_BUTTON_UP;
                    end else if (buttons[1]) begin
                        internal_value <= (internal_value << 1);
                        state <= WATING_BUTTON_UP;
                    end else if (buttons[2]) begin
                        internal_value <= 0;
                        state <= WATING_BUTTON_UP;
                    end else if (buttons[3]) begin
                        internal_io_output_trigger <= 1;
                        state <= OUTPUT;
                    end
                end
                (WATING_BUTTON_UP): begin
                    if (!(buttons[0] || buttons[1] || buttons[2] || buttons[3])) begin
                        state <= WATING_BUTTON_INPUT;
                    end
                end
                (OUTPUT): begin
                    internal_io_output_trigger <= 0;
                    state <= WATING_OUTPUT;
                end
                (WATING_OUTPUT): begin
                    if (io_output_ready_trigger) begin
                        state <= WATING_BUTTON_UP;
                    end;
                end
            endcase
        end
    end;

    initial begin
        internal_value = 8'd0;
        internal_io_output_trigger = 1'b0;
        state = WATING_BUTTON_INPUT;
    end;

endmodule