module RAM_CONTROLLER_TEST();

  localparam CHUNK_PART   = 128;
  localparam ADDRESS_SIZE = 28;

  // Clocks: clk=100MHz (T=10ns), mig_ui_clk=125MHz (T=8ns)
  reg clk;
  reg mig_ui_clk;
  reg reset;
  initial begin clk = 0;       forever #5 clk       = ~clk;       end
  initial begin mig_ui_clk = 0; forever #4 mig_ui_clk = ~mig_ui_clk; end

  // DUT interface
  wire                    controller_ready;
  wire [3:0]              error;
  wire [2:0]              led0;

  reg                     write_trigger;
  reg  [CHUNK_PART-1:0]   write_value;
  reg  [ADDRESS_SIZE-1:0] write_address;

  reg                     read_trigger;
  reg  [ADDRESS_SIZE-1:0] read_address;
  wire [CHUNK_PART-1:0]   read_value;
  wire                    read_value_ready;

  // MIG bus (wires between DUT and MIG_MODEL)
  wire [ADDRESS_SIZE-1:0]   mig_app_addr;
  wire [2:0]                mig_app_cmd;
  wire                      mig_app_en;
  wire [CHUNK_PART-1:0]     mig_app_wdf_data;
  wire                      mig_app_wdf_end;
  wire [(CHUNK_PART/8)-1:0] mig_app_wdf_mask;
  wire                      mig_app_wdf_wren;
  wire                      mig_app_wdf_rdy;
  wire [CHUNK_PART-1:0]     mig_app_rd_data;
  wire                      mig_app_rd_data_valid;
  wire                      mig_app_rd_data_end;
  wire                      mig_app_rdy;
  wire                      mig_init_calib_complete;

  // Test bookkeeping
  integer             errors;
  integer             write_count;
  reg [CHUNK_PART-1:0] write_captured;
  reg [CHUNK_PART-1:0] read_captured;

  // DUT
  RAM_CONTROLLER #(
    .CHUNK_PART(CHUNK_PART),
    .ADDRESS_SIZE(ADDRESS_SIZE)
  ) dut (
    .clk                   (clk),
    .reset                 (reset),
    .controller_ready      (controller_ready),
    .error                 (error),
    .write_trigger         (write_trigger),
    .write_value           (write_value),
    .write_address         (write_address),
    .read_trigger          (read_trigger),
    .read_value            (read_value),
    .read_address          (read_address),
    .read_value_ready      (read_value_ready),
    .led0                  (led0),
    .mig_app_addr          (mig_app_addr),
    .mig_app_cmd           (mig_app_cmd),
    .mig_app_en            (mig_app_en),
    .mig_app_wdf_data      (mig_app_wdf_data),
    .mig_app_wdf_end       (mig_app_wdf_end),
    .mig_app_wdf_mask      (mig_app_wdf_mask),
    .mig_app_wdf_wren      (mig_app_wdf_wren),
    .mig_app_wdf_rdy       (mig_app_wdf_rdy),
    .mig_app_rd_data       (mig_app_rd_data),
    .mig_app_rd_data_end   (mig_app_rd_data_end),
    .mig_app_rd_data_valid (mig_app_rd_data_valid),
    .mig_app_rdy           (mig_app_rdy),
    .mig_ui_clk            (mig_ui_clk),
    .mig_init_calib_complete(mig_init_calib_complete)
  );

  // MIG model
  MIG_MODEL #(
    .CHUNK_PART(CHUNK_PART),
    .ADDRESS_SIZE(ADDRESS_SIZE)
  ) mig (
    .mig_ui_clk            (mig_ui_clk),
    .mig_init_calib_complete(mig_init_calib_complete),
    .mig_app_rdy           (mig_app_rdy),
    .mig_app_en            (mig_app_en),
    .mig_app_cmd           (mig_app_cmd),
    .mig_app_addr          (mig_app_addr),
    .mig_app_wdf_data      (mig_app_wdf_data),
    .mig_app_wdf_wren      (mig_app_wdf_wren),
    .mig_app_wdf_end       (mig_app_wdf_end),
    .mig_app_wdf_rdy       (mig_app_wdf_rdy),
    .mig_app_rd_data       (mig_app_rd_data),
    .mig_app_rd_data_valid (mig_app_rd_data_valid),
    .mig_app_rd_data_end   (mig_app_rd_data_end)
  );

  // Monitor: capture last read result
  always @(posedge clk) begin
    if (read_value_ready)
      read_captured <= read_value;
  end

  // Monitor: count writes reaching MIG
  always @(posedge mig_ui_clk) begin
    if (mig_app_wdf_wren && mig_app_wdf_end) begin
      write_count   <= write_count + 1;
      write_captured <= mig_app_wdf_data;
    end
  end

  // ----------------------------------------------------------------
  // Tasks
  // ----------------------------------------------------------------

  // Wait for controller_ready to return high after an operation.
  // Includes an extra cycle so all NBAs have settled before caller checks results.
  task wait_done;
    integer n;
    begin
      repeat(4) @(posedge clk);     // give controller time to go not-ready
      n = 0;
      while (!controller_ready && n < 1000) begin
        @(posedge clk);
        n = n + 1;
      end
      @(posedge clk);               // one extra cycle for NBA settle
      if (!controller_ready) begin
        $display("  TIMEOUT: controller_ready never returned");
        errors = errors + 1;
      end
    end
  endtask

  task do_write;
    input [ADDRESS_SIZE-1:0] addr;
    input [CHUNK_PART-1:0]   data;
    begin
      @(posedge clk);
      write_address = addr;
      write_value   = data;
      write_trigger = 1;
      @(posedge clk);
      write_trigger = 0;
      wait_done;
    end
  endtask

  task do_read;
    input [ADDRESS_SIZE-1:0] addr;
    begin
      @(posedge clk);
      read_address = addr;
      read_trigger = 1;
      @(posedge clk);
      read_trigger = 0;
      wait_done;
    end
  endtask

  // ----------------------------------------------------------------
  // Main test
  // ----------------------------------------------------------------
  initial begin
    $dumpfile("RAM_CONTROLLER_TEST.vcd");
    $dumpvars(0, RAM_CONTROLLER_TEST);

    write_trigger  = 0;
    write_value    = 0;
    write_address  = 0;
    read_trigger   = 0;
    read_address   = 0;
    errors         = 0;
    write_count    = 0;
    write_captured = 0;
    read_captured  = 0;

    // Reset
    reset = 1;
    #50;
    reset = 0;

    // Wait for MIG calibration handshake to complete
    #100;

    // ---- T1: basic write ----------------------------------------
    $display("T1: basic write to addr 0x00");
    do_write(28'h00, 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0);
    if (write_count !== 1)
      begin $display("  FAIL write_count=%0d expected 1", write_count); errors=errors+1; end
    if (write_captured !== 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0)
      begin $display("  FAIL write_captured=%h", write_captured); errors=errors+1; end

    // ---- T2: basic read (read back T1 data) ---------------------
    $display("T2: basic read from addr 0x00");
    do_read(28'h00);
    if (read_captured !== 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0)
      begin $display("  FAIL read_captured=%h", read_captured); errors=errors+1; end

    // ---- T3: multiple addresses ---------------------------------
    $display("T3: write/read 3 different addresses");
    do_write(28'h10, 128'hAAAA_AAAA_BBBB_BBBB_CCCC_CCCC_DDDD_DDDD);
    do_write(28'h20, 128'h1111_2222_3333_4444_5555_6666_7777_8888);
    do_write(28'h30, 128'hFACE_CAFE_FEED_BEEF_C0DE_1234_ABCD_EF01);

    do_read(28'h10);
    if (read_captured !== 128'hAAAA_AAAA_BBBB_BBBB_CCCC_CCCC_DDDD_DDDD)
      begin $display("  FAIL addr 0x10: %h", read_captured); errors=errors+1; end
    do_read(28'h20);
    if (read_captured !== 128'h1111_2222_3333_4444_5555_6666_7777_8888)
      begin $display("  FAIL addr 0x20: %h", read_captured); errors=errors+1; end
    do_read(28'h30);
    if (read_captured !== 128'hFACE_CAFE_FEED_BEEF_C0DE_1234_ABCD_EF01)
      begin $display("  FAIL addr 0x30: %h", read_captured); errors=errors+1; end

    // ---- T4: simultaneous write+read (skip_write path) ----------
    // Pre-load 0x50 so the simultaneous read has known data
    $display("T4: simultaneous write+read (skip_write path)");
    do_write(28'h50, 128'h5A5A_5A5A_A5A5_A5A5_5A5A_5A5A_A5A5_A5A5);

    // Issue both triggers in the same cycle
    @(posedge clk);
    write_address = 28'h40;
    write_value   = 128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111;
    read_address  = 28'h50;
    write_trigger = 1;
    read_trigger  = 1;
    @(posedge clk);
    write_trigger = 0;
    read_trigger  = 0;
    wait_done;

    // read_captured now holds result of the simultaneous READ (addr 0x50)
    if (read_captured !== 128'h5A5A_5A5A_A5A5_A5A5_5A5A_5A5A_A5A5_A5A5)
      begin $display("  FAIL T4 read(0x50): %h", read_captured); errors=errors+1; end

    // Verify the simultaneous WRITE actually reached addr 0x40
    do_read(28'h40);
    if (read_captured !== 128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111)
      begin $display("  FAIL T4 write(0x40) verify: %h", read_captured); errors=errors+1; end

    // ---- error flag check --------------------------------------
    if (error !== 4'h0)
      begin $display("FAIL DUT error flag set: %h", error); errors=errors+1; end

    // ---- summary -----------------------------------------------
    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $display("FAILED: %0d error(s)", errors);

    $finish;
  end

endmodule
