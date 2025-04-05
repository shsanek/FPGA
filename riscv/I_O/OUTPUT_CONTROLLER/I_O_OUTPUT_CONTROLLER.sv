typedef enum logic [1:0] {
    OUT_WATING_VALUE,
    OUT_START_SIGNAL,
    OUT_VALUE,
    OUT_END_SIGNAL
} OUTPUT_CONTROLLER_STATE;

module I_O_OUTPUT_CONTROLLER(
  input wire clk,

  input wire[7:0] io_output_value,
  input wire io_output_trigger,

  output wire io_output_ready_trigger, 
  output wire RXD
);
  logic internal_output;
  logic internal_io_output_ready_trigger;
  logic[2:0] internal_output_counter;
  logic[7:0] internal_current_value;
  wire active;
  
  I_O_TIMER_GENERATOR timer_generator(
   .clk(CLK100MHZ),
   .active(active)
  );
    

  OUTPUT_CONTROLLER_STATE internal_state;

  assign RXD = internal_output;
  assign io_output_ready_trigger = internal_io_output_ready_trigger;

  always_ff @(posedge clk) begin
    if (OUT_WATING_VALUE == internal_state && io_output_trigger) begin
      internal_current_value <= io_output_value;
      internal_io_output_ready_trigger <= 0;
      internal_state <= OUT_START_SIGNAL;
      internal_output_counter <= 0;
    end else if (active) begin
      if (internal_state == OUT_START_SIGNAL) begin
        internal_output <= 0;
        internal_state <= OUT_VALUE;
      end else if (internal_state == OUT_VALUE) begin
        internal_output <= internal_current_value[0];
        internal_current_value <= internal_current_value >> 1;
        internal_output_counter <= internal_output_counter + 1;
        if (internal_output_counter == 7) begin
          internal_state <= OUT_END_SIGNAL;
        end
      end else begin
        internal_state <= OUT_WATING_VALUE;
        internal_io_output_ready_trigger <= 1;
        internal_output <= 1;
      end
    end
  end

  initial begin
    internal_output = 1;
    internal_output_counter = 0;
    internal_state = OUT_WATING_VALUE;
    internal_io_output_ready_trigger = 1;
  end;
endmodule