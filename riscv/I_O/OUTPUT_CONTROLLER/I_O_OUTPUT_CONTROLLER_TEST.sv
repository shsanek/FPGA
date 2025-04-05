module I_O_OUTPUT_CONTROLLER_TEST();
  logic clk;
  logic [7:0] io_output_value;
  logic io_output_trigger;
  logic active;
  logic io_output_ready_trigger;
  logic RXD;
  int error = 0;

  I_O_OUTPUT_CONTROLLER dut (
    .clk(clk),
    .io_output_value(io_output_value),
    .io_output_trigger(io_output_trigger),
    .active(active),
    .io_output_ready_trigger(io_output_ready_trigger),
    .RXD(RXD)
  );

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  logic [1:0] active_counter;
  initial active_counter = 0;
  always_ff @(posedge clk) begin
    if (active_counter == 3)
      active_counter <= 0;
    else
      active_counter <= active_counter + 1;
  end
  assign active = (active_counter == 0);

  initial begin
    $dumpfile("I_O_OUTPUT_CONTROLLER.vcd");
    $dumpvars(0, I_O_OUTPUT_CONTROLLER_TEST);
    io_output_value = 8'd0;
    io_output_trigger = 1'b0;
    #20;
    assert(io_output_ready_trigger === 1 && RXD === 1) else error = error + 1;
    io_output_value = 8'hAA;
    io_output_trigger = 1'b1;
    #10;
    io_output_trigger = 1'b0;
    #40;
    assert(RXD === 0 && io_output_ready_trigger === 0) else error = error + 1;
    #40;
    assert(RXD === 0 && io_output_ready_trigger === 0) else error = error + 1;
    #40;
    assert(RXD === 1 && io_output_ready_trigger === 0) else error = error + 1;
    #40;
    assert(RXD === 0 && io_output_ready_trigger === 0) else error = error + 1;
    #40;
    assert(RXD === 1 && io_output_ready_trigger === 0) else error = error + 1;
    #40;
    assert(RXD === 0 && io_output_ready_trigger === 0) else error = error + 1;
    #40;
    assert(RXD === 1 && io_output_ready_trigger === 0) else error = error + 1;
    #40;
    assert(RXD === 0 && io_output_ready_trigger === 0) else error = error + 1;
    #40;
    assert(RXD === 1 && io_output_ready_trigger === 0) else error = error + 1;
    #40;
    assert(RXD === 1 && io_output_ready_trigger === 1) else error = error + 1;
    #10;
    if(error == 0)
      $display("ALL TESTS PASSED");
    else
      $display("TEST FAILED with %0d errors", error);
    $finish;
  end
endmodule
