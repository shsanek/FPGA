module I_O_OUTPUT_CONTROLLER_TEST();
  logic clk;
  logic [7:0] io_output_value;
  logic io_output_trigger;
  wire  io_output_ready_trigger;
  wire  RXD;
  int   error = 0;

  // BIT_PERIOD=4: each bit takes 4 clock cycles (active fires every 4 clk)
  I_O_OUTPUT_CONTROLLER #(.BIT_PERIOD(4)) dut (
    .clk(clk),
    .io_output_value(io_output_value),
    .io_output_trigger(io_output_trigger),
    .io_output_ready_trigger(io_output_ready_trigger),
    .RXD(RXD)
  );

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin
    $dumpfile("I_O_OUTPUT_CONTROLLER.vcd");
    $dumpvars(0, I_O_OUTPUT_CONTROLLER_TEST);
    io_output_value   = 8'd0;
    io_output_trigger = 1'b0;
    #20;
    assert(io_output_ready_trigger === 1 && RXD === 1) else error = error + 1;

    // Send 0xAA = 8'b1010_1010, LSB first → 0,1,0,1,0,1,0,1
    io_output_value   = 8'hAA;
    io_output_trigger = 1'b1;
    #10;
    io_output_trigger = 1'b0;

    // Start bit (0)
    #40; assert(RXD === 0 && io_output_ready_trigger === 0) else error = error + 1;
    // bit0=0
    #40; assert(RXD === 0 && io_output_ready_trigger === 0) else error = error + 1;
    // bit1=1
    #40; assert(RXD === 1 && io_output_ready_trigger === 0) else error = error + 1;
    // bit2=0
    #40; assert(RXD === 0 && io_output_ready_trigger === 0) else error = error + 1;
    // bit3=1
    #40; assert(RXD === 1 && io_output_ready_trigger === 0) else error = error + 1;
    // bit4=0
    #40; assert(RXD === 0 && io_output_ready_trigger === 0) else error = error + 1;
    // bit5=1
    #40; assert(RXD === 1 && io_output_ready_trigger === 0) else error = error + 1;
    // bit6=0
    #40; assert(RXD === 0 && io_output_ready_trigger === 0) else error = error + 1;
    // bit7=1
    #40; assert(RXD === 1 && io_output_ready_trigger === 0) else error = error + 1;
    // Stop bit (1) + ready
    #40; assert(RXD === 1 && io_output_ready_trigger === 1) else error = error + 1;

    #10;
    if (error == 0)
      $display("ALL TESTS PASSED");
    else
      $display("TEST FAILED with %0d errors", error);
    $finish;
  end
endmodule
