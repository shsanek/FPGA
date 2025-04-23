module MEMORY_CONTROLLER_TEST;

  localparam CHUNK_PART    = 128;
  localparam DATA_SIZE     = 32;
  localparam MASK_SIZE     = DATA_SIZE/8;
  localparam ADDRESS_SIZE  = 28;

  reg                         clk;
  always #5 clk = ~clk;
  initial clk = 0;

  reg                         ram_controller_ready;
  wire                        ram_write_trigger;
  wire [CHUNK_PART-1:0]       ram_write_value;
  wire [ADDRESS_SIZE-1:0]     ram_write_address;
  wire                        ram_read_trigger;
  reg  [CHUNK_PART-1:0]       ram_read_value;
  wire [ADDRESS_SIZE-1:0]     ram_read_address;
  reg                         ram_read_value_ready;

  reg  [ADDRESS_SIZE-1:0]     address;
  reg  [MASK_SIZE-1:0]        mask;
  reg                         write_trigger;
  reg  [DATA_SIZE-1:0]        write_value;
  reg                         read_trigger;
  reg  [ADDRESS_SIZE-1:0]     command_address;

  wire                        contains_address;
  wire [DATA_SIZE-1:0]        read_value;
  wire                        contains_command_address;
  wire [DATA_SIZE-1:0]        read_command;

  int error = 0;

  MEMORY_CONTROLLER #(
    .CHUNK_PART   (CHUNK_PART),
    .DATA_SIZE    (DATA_SIZE),
    .MASK_SIZE    (MASK_SIZE),
    .ADDRESS_SIZE (ADDRESS_SIZE)
  ) dut (
    .clk                       (clk),
    .ram_controller_ready      (ram_controller_ready),
    .ram_write_trigger         (ram_write_trigger),
    .ram_write_value           (ram_write_value),
    .ram_write_address         (ram_write_address),
    .ram_read_trigger          (ram_read_trigger),
    .ram_read_value            (ram_read_value),
    .ram_read_address          (ram_read_address),
    .ram_read_value_ready      (ram_read_value_ready),
    .address                   (address),
    .mask                      (mask),
    .write_trigger             (write_trigger),
    .write_value               (write_value),
    .command_address           (command_address),
    .read_trigger              (read_trigger),
    .read_value                (read_value),
    .contains_address          (contains_address),
    .contains_command_address  (contains_command_address),
    .read_command              (read_command)
  );

  // test vectors
  localparam [CHUNK_PART-1:0] CHUNK0 = {
    32'hDEAD_BEEF,  
    32'hCAFE_BABE,
    32'h1234_5678,
    32'h8765_4321
  };
  localparam [CHUNK_PART-1:0] CHUNK1 = {
    32'h1111_1111,
    32'h2222_2222,
    32'h3333_3333,
    32'h4444_4444
  };
  localparam [CHUNK_PART-1:0] CHUNK2 = {
    32'hAAAA_AAAA,
    32'hBBBB_BBBB,
    32'hCCCC_CCCC,
    32'hDDDD_DDDD
  };
  localparam [CHUNK_PART-1:0] CHUNK3 = {
    32'hFACE_FACE,
    32'hBEEF_BEEF,
    32'hFEED_FEED,
    32'hC0DE_C0DE
  };

  initial begin
    $dumpfile("MEMORY_CONTROLLER_TEST.vcd");
    $dumpvars(0, MEMORY_CONTROLLER_TEST);

    clk = 0;
    ram_controller_ready = 1;
    ram_read_value_ready = 0;
    mask    = {MASK_SIZE{1'b1}};
    write_trigger = 0;
    write_value   = 0;
    read_trigger  = 0;
    ram_read_value = '0;
    address       = '0;
    command_address = '0;
    #5;

    // fill block 0
    address     = 32'h0000_0000; 
    read_trigger = 1; 
    #10; 
    read_trigger = 0;
    if (ram_read_trigger !== 1)         error = error + 1;
    if (ram_read_address  !== 32'h0000_0000) error = error + 2;
    #10;
    ram_read_value        = CHUNK0;
    ram_read_value_ready  = 1;
    #10;
    ram_read_value_ready  = 0;
    #30;
    if (contains_address   !== 1)         error = error + 3;
    if (read_value         !== 32'h8765_4321) error = error + 4;

    // fill block 1
    address     = 32'h0000_0010;
    read_trigger = 1;
    #20;
    read_trigger = 0;
    if (ram_read_trigger !== 1)         error = error + 5;
    if (ram_read_address  !== 32'h0000_0010) error = error + 6;
    #10;
    ram_read_value        = CHUNK1;
    ram_read_value_ready  = 1;
    #10;
    ram_read_value_ready  = 0;
    #30;
    if (contains_address   !== 1)         error = error + 7;
    if (read_value         !== 32'h4444_4444) error = error + 8;

    // fill block 2
    address     = 32'h0000_0020;
    read_trigger = 1;
    #20;
    read_trigger = 0;
    if (ram_read_trigger !== 1)         error = error + 9;
    if (ram_read_address !== 32'h0000_0020) error = error + 10;
    #10;
    ram_read_value        = CHUNK2;
    ram_read_value_ready  = 1;
    #10;
    ram_read_value_ready  = 0;
    #40;
    if (contains_address   !== 1)         error = error + 11;
    if (read_value         !== 32'hDDDD_DDDD) error = error + 12;

    // fill block 3
    address     = 32'h0000_0030;
    read_trigger = 1;
    #20;
    read_trigger = 0;
    if (ram_read_trigger !== 1)         error = error + 13;
    if (ram_read_address  !== 32'h0000_0030) error = error + 14;
    #10;
    ram_read_value        = CHUNK3;
    ram_read_value_ready  = 1;
    #10;
    ram_read_value_ready  = 0;
    #30;
    if (contains_address   !== 1)         error = error + 15;
    if (read_value         !== 32'hC0DE_C0DE) error = error + 16;

    // hit on block 1
    address     = 32'h0000_0010;
    read_trigger = 1;
    #10;
    read_trigger = 0;
    #10;
    if (ram_read_trigger !== 0)         error = error + 17;
    if (read_value         !== 32'h4444_4444) error = error + 18;

    // masked write to block 2 (offset 2)
    address      = 32'h0000_0028; // bits [4] selects word1 inside chunk2
    mask         = 4'b0011;      
    write_value  = 32'h1234_5678;
    write_trigger = 1;
    #10;
    write_trigger = 0;
    #30;
    if (ram_write_trigger !== 0)       error = error + 19;

    // miss on block 4 => flush dirty block 2 then read block 4
    address      = 32'h0000_0040;
    read_trigger = 1;
    #20;
    read_trigger = 0;
    #10;
    if (ram_write_trigger !== 1)       error = error + 20;
    if (ram_write_address  !== 32'h0000_0020) error = error + 21;
    // build expected save_data for chunk2 after masked write:
    if (ram_write_value !== {
         32'hAAAA_AAAA,
         32'hBBBB_BBBB,
         32'h1234_5678,  // bottom half of word0 masked
         32'hDDDD_DDDD
       })                               error = error + 22;
    #10;
    // now read new block 4
    ram_read_value        = {32'h0101_0101,32'h0202_0202,32'h0303_0303,32'h0404_0404};
    ram_read_value_ready  = 1;
    #10;
    ram_read_value_ready  = 0;
    #30;
    if (contains_address   !== 1)       error = error + 23;
    if (read_value         !== 32'h0404_0404) error = error + 24;

    if (error == 0)
      $display("ALL TESTS PASSED");
    else
      $display("TEST FAILED with %0d errors", error);

    $finish;
  end

endmodule
