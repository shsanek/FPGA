module I_O_INPUT_CONTROLLER_TEST();
  logic clk;
  logic TXD;
  wire io_input_trigger;
  wire [7:0] io_input_value;
  int error = 0;
  int out_count = 0;
  int out_value = 0;

  I_O_INPUT_CONTROLLER #(.BIT_PERIOD(6)) dut (
    .clk(clk),
    .TXD(TXD),
    .io_input_trigger(io_input_trigger),
    .io_input_value(io_input_value)
  );

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  always @(posedge io_input_trigger) begin
    out_count = out_count + 1;
    out_value = io_input_value;
  end;

  initial begin
    $dumpfile("I_O_INPUT_CONTROLLER.vcd");
    $dumpvars(0, I_O_INPUT_CONTROLLER_TEST);
    TXD = 1;
    #80;
    TXD = 1;
    #60;
    TXD = 0;
    #60;
    TXD = 1;
    #60;
    TXD = 0;
    #60;
    TXD = 1;
    #60;
    TXD = 0;
    #60;
    TXD = 1;
    #60;
    TXD = 0;
    #60;
    TXD = 1;
    #60;
    TXD = 0;
    #60;
    TXD = 1;
    #60;
    assert(io_input_trigger === 0) else error = error + 1;
    assert(io_input_value === 8'hAA) else error = error + 1;
    assert(out_count === 1) else error = error + 1;
    assert(out_value === 8'hAA) else error = error + 1;

    #10;
    if(error == 0)
      $display("ALL TESTS PASSED");
    else
      $display("TEST FAILED with %0d errors", error);
    $finish;
  end
endmodule
