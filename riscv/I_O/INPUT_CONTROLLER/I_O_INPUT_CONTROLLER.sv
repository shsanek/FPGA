typedef enum logic [1:0] {
    IN_WATING_VALUE,
    IN_VALUE_OFF_RESET_TIMER,
    IN_VALUE,
    IN_WATING_STOP_SIGNAL
} INPUT_CONTROLLER_STATE;

module SIGNAL_ACCAMULATOR #(
  parameter int SIGNAL_SIZE = 8
) (
  input wire clk,
  input wire signal,
  output wire active_trigger
);
  logic[SIGNAL_SIZE+1: 0] counter;

  assign active_trigger = counter[SIGNAL_SIZE] || counter[SIGNAL_SIZE + 1];

  always_ff @(posedge clk) begin
    if (!signal) begin
      if (!counter[SIGNAL_SIZE + 1]) begin
        counter <= counter + 1;
      end;
    end else if (counter != 0) begin 
      counter <= counter - 1;
    end
  end;

  initial begin
    counter = 0;
  end;
endmodule;

module CLK_DELAY #(
  parameter CLK_COUNT = 100,
  parameter int SIZE = $clog2(CLK_COUNT + 1)
)(
  input wire clk,
  input wire reset_trigger,
  input wire[SIZE - 1: 0] reset_value,
  output logic active_trigger
);
  logic[SIZE - 1: 0] counter;

  always_ff @(posedge clk) begin
    if (reset_trigger) begin
      counter <= reset_value;
      active_trigger <= 0;
    end else if (counter == 0) begin
      active_trigger <= 1;
    end else begin 
      counter <= counter - 1;
    end
  end;

  initial begin
    counter = CLK_COUNT;
  end;
endmodule;

module I_O_INPUT_CONTROLLER #(
  parameter CLOCK_FREQ = 100000000,
  parameter BAUD_RATE  = 115200,
  parameter BIT_PERIOD = CLOCK_FREQ / BAUD_RATE,
  parameter int SIZE = $clog2(BIT_PERIOD + TIME_SHIFT + 1),
  parameter int TIME_SHIFT = BIT_PERIOD / 3
) (
  input wire clk,

  input wire TXD,

  output wire io_input_trigger,
  output wire[7:0] io_input_value
);
  logic internal_io_input_trigger;
  logic[2:0] internal_input_counter;
  logic[7:0] internal_current_value;

  INPUT_CONTROLLER_STATE internal_state;

  wire internal_current_invert_siggnal; 
  SIGNAL_ACCAMULATOR #(
    .SIGNAL_SIZE($clog2(TIME_SHIFT))
  ) signal_acc(
    .clk(clk),
    .signal(TXD),
    .active_trigger(internal_current_invert_siggnal)
  );

  logic internal_timer_reset;
  logic[SIZE - 1: 0] internal_timer_reset_value;
  wire internal_timmer_trigger; 
  CLK_DELAY #(
    .CLK_COUNT(BIT_PERIOD),
    .SIZE(SIZE)
  ) timer(
    .clk(clk),
    .reset_trigger(internal_timer_reset),
    .reset_value(internal_timer_reset_value),
    .active_trigger(internal_timmer_trigger)
  );

  assign io_input_value = internal_current_value;
  assign io_input_trigger = internal_io_input_trigger;

  always_ff @(posedge clk) begin
      if (internal_state == IN_WATING_STOP_SIGNAL) begin
        internal_timer_reset <= 0;
        internal_io_input_trigger <= 0;
        if (internal_timmer_trigger && !internal_current_invert_siggnal) begin
          internal_state <= IN_WATING_VALUE;
        end;
      end else if (internal_state == IN_WATING_VALUE) begin
        if (internal_current_invert_siggnal) begin
          internal_timer_reset <= 1;
          internal_timer_reset_value <= BIT_PERIOD + TIME_SHIFT - 3;
          internal_state <= IN_VALUE_OFF_RESET_TIMER;
        end
      end else if (internal_state == IN_VALUE_OFF_RESET_TIMER) begin
        internal_timer_reset <= 0;
        internal_state <= IN_VALUE;
      end else if (internal_state == IN_VALUE) begin
        if (internal_timmer_trigger) begin
          internal_current_value <= (internal_current_value << 1) + !internal_current_invert_siggnal;
          internal_input_counter <= internal_input_counter + 1;
        
          internal_timer_reset <= 1;
          internal_timer_reset_value <= BIT_PERIOD - 3;

          if (internal_input_counter == 7) begin
            internal_state <= IN_WATING_STOP_SIGNAL;
            internal_io_input_trigger <= 1;
          end else begin
            internal_state <= IN_VALUE_OFF_RESET_TIMER;
          end
        end
      end
  end

  initial begin
    internal_io_input_trigger = 0;
    internal_input_counter = 0;
    internal_current_value = 0;

    internal_state = IN_WATING_STOP_SIGNAL;
  end;
endmodule;