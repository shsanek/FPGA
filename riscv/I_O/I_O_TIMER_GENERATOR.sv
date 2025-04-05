module I_O_TIMER_GENERATOR #(
  parameter CLOCK_FREQ = 100000000,
  parameter BAUD_RATE  = 115200,
  parameter BIT_PERIOD = CLOCK_FREQ / BAUD_RATE
) (
  input  wire clk,
  output wire active
);
  logic[16:0] counter;
  logic internal_active;

  assign active = internal_active;

  always_ff @(posedge clk) begin
    if (counter == BIT_PERIOD - 1) begin
          counter <= 0;
          internal_active <= 1;
    end else begin
      counter <= counter + 1;
      internal_active <= 0;
    end
  end

  initial begin
    counter = 0;
    internal_active = 0;
  end;

endmodule