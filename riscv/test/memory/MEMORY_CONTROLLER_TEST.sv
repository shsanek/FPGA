module MEMORY_CONTROLLER_TEST;

  localparam CHUNK_PART    = 128;
  localparam DATA_SIZE     = 32;
  localparam MASK_SIZE     = DATA_SIZE/8;
  localparam ADDRESS_SIZE  = 28;

  reg                         clk;
  reg                         reset;
  initial clk = 0;
  always #5 clk = ~clk;

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

  wire                        contains_address;
  wire [DATA_SIZE-1:0]        read_value;

  int error = 0;

  // instance
  MEMORY_CONTROLLER #(
    .CHUNK_PART   (CHUNK_PART),
    .DATA_SIZE    (DATA_SIZE),
    .MASK_SIZE    (MASK_SIZE),
    .ADDRESS_SIZE (ADDRESS_SIZE)
  ) dut (
    .clk                       (clk),
    .reset                     (reset),
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
    .read_trigger              (read_trigger),
    .read_value                (read_value),
    .contains_address          (contains_address),
    .bus_type                  (2'b00)
  );

  // test chunks
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
    reset = 1; #20; reset = 0;
    #10;

    // init — hold ram_controller_ready=0 so NORMAL does not fire a
    // spurious command_address fetch before we assert our first read_trigger
    ram_controller_ready = 0;
    ram_read_value_ready = 0;
    mask    = {MASK_SIZE{1'b1}};
    write_trigger = 0;
    write_value   = 0;
    read_trigger  = 0;
    ram_read_value = '0;
    address       = '0;
    #10;

    // fill block 0 — enable controller together with the first read trigger
    address      = 32'h0000_0000; read_trigger = 1; ram_controller_ready = 1; #10;
    read_trigger = 0;
    if (ram_read_trigger !== 1)           error = error + 1;
    if (ram_read_address  !== 32'h0000_0000) error = error + 1;
    #20;
    ram_read_value       = CHUNK0;
    ram_read_value_ready = 1;
    #10;
    ram_read_value_ready = 0;
    #30;
    if (!contains_address)                error = error + 1;
    if (read_value        !== 32'h8765_4321) error = error + 1;

    // fill block 1
    address      = 32'h0000_0010; read_trigger = 1; #10;
    read_trigger = 0;
    if (ram_read_trigger !== 1)           error = error + 1;
    if (ram_read_address  !== 32'h0000_0010) error = error + 1;
    #10;
    ram_read_value       = CHUNK1;
    ram_read_value_ready = 1;
    #10;
    ram_read_value_ready = 0;
    #30;
    if (!contains_address)                error = error + 1;
    if (read_value        !== 32'h4444_4444) error = error + 1;

    // fill block 2
    address      = 32'h0000_0020; read_trigger = 1; #10;
    read_trigger = 0;
    if (ram_read_trigger !== 1)           error = error + 1;
    if (ram_read_address  !== 32'h0000_0020) error = error + 1;
    #10;
    ram_read_value       = CHUNK2;
    ram_read_value_ready = 1;
    #10;
    ram_read_value_ready = 0;
    #30;
    if (!contains_address)                error = error + 1;
    if (read_value        !== 32'hDDDD_DDDD) error = error + 1;

    // fill block 3
    address      = 32'h0000_0030; read_trigger = 1; #10;
    read_trigger = 0;
    if (ram_read_trigger !== 1)           error = error + 1;
    if (ram_read_address  !== 32'h0000_0030) error = error + 1;
    #10;
    ram_read_value       = CHUNK3;
    ram_read_value_ready = 1;
    #10;
    ram_read_value_ready = 0;
    #30;
    if (!contains_address)                error = error + 1;
    if (read_value        !== 32'hC0DE_C0DE) error = error + 1;

    // masked write to block 2 (in-cache)
    address       = 32'h0000_0028;
    mask          = 4'b0011;
    write_value   = 32'h1234_5678;
    write_trigger = 1;
    #10;
    write_trigger = 0;
    #30;
    if (ram_write_trigger !== 0)          error = error + 1;

    // miss on block 4 => evict oldest (block 0, clean — no writeback), fetch block 4
    address      = 32'h0000_0040; read_trigger = 1; #10;
    read_trigger = 0;
    // At this point NORMAL just fired: ram_read_trigger=1 (not yet cleared by WATING).
    // Block 0 is clean (save_need_flag=0) → no dirty writeback.
    if (ram_write_trigger !== 0)             error = error + 1;
    if (ram_read_trigger  !== 1)             error = error + 1;
    if (ram_read_address  !== 32'h0000_0040) error = error + 1;
    #20;
    ram_read_value       = {32'h5555_5555,32'h6666_6666,32'h7777_7777,32'h8888_8888};
    ram_read_value_ready = 1;
    #10;
    ram_read_value_ready = 0;
    #30;
    if (!contains_address)                   error = error + 1;
    if (read_value        !== 32'h8888_8888) error = error + 1;

    if (error == 0)
      $display("ALL TESTS PASSED");
    else
      $display("TEST FAILED with %0d errors", error);

    $finish;
  end

endmodule
