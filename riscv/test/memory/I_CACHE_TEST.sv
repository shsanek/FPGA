module I_CACHE_TEST;

  localparam DEPTH        = 256;
  localparam CHUNK_PART   = 128;
  localparam DATA_SIZE    = 32;
  localparam MASK_SIZE    = DATA_SIZE/8;
  localparam ADDRESS_SIZE = 28;

  reg clk;
  reg reset;
  initial begin clk = 0; forever #5 clk = ~clk; end

  // DUT ports
  reg  [ADDRESS_SIZE-1:0] address;
  reg  [MASK_SIZE-1:0]    mask;
  reg                     write_trigger;
  reg  [DATA_SIZE-1:0]    write_value;
  reg                     read_trigger;
  wire                    contains_address;
  wire [DATA_SIZE-1:0]    read_value;

  wire [ADDRESS_SIZE-1:0] save_address;
  wire [CHUNK_PART-1:0]   save_data;
  wire                    save_need_flag;

  reg  [CHUNK_PART-1:0]   new_data;
  reg  [ADDRESS_SIZE-1:0] new_address;
  reg                     new_data_save;
  reg                     order_tick;

  int                     errors;

  I_CACHE #(
    .DEPTH        (DEPTH),
    .CHUNK_PART   (CHUNK_PART),
    .DATA_SIZE    (DATA_SIZE),
    .MASK_SIZE    (MASK_SIZE),
    .ADDRESS_SIZE (ADDRESS_SIZE)
  ) dut (
    .clk              (clk),
    .reset            (reset),
    .address          (address),
    .mask             (mask),
    .write_trigger    (write_trigger),
    .write_value      (write_value),
    .read_trigger     (read_trigger),
    .read_value       (read_value),
    .contains_address (contains_address),
    .save_address     (save_address),
    .save_data        (save_data),
    .save_need_flag   (save_need_flag),
    .order_tick       (order_tick),
    .new_data         (new_data),
    .new_address      (new_address),
    .new_data_save    (new_data_save)
  );

  task automatic fill_line(
    input [ADDRESS_SIZE-1:0] addr,
    input [CHUNK_PART-1:0]   data
  );
    @(posedge clk);
    #1;
    new_address   = addr;
    new_data      = data;
    new_data_save = 1;
    @(posedge clk);
    #1;
    new_data_save = 0;
  endtask

  task automatic check_hit(
    input [ADDRESS_SIZE-1:0] addr,
    input [DATA_SIZE-1:0]    expected,
    input string             label
  );
    #1;
    address      = addr;
    read_trigger = 1;
    #1;
    assert(contains_address == 1) else begin
      $display("FAIL [%s]: expected hit at %h, got miss", label, addr);
      errors++;
    end
    assert(read_value == expected) else begin
      $display("FAIL [%s]: addr=%h expected=%h got=%h", label, addr, expected, read_value);
      errors++;
    end
    read_trigger = 0;
  endtask

  task automatic check_miss(
    input [ADDRESS_SIZE-1:0] addr,
    input string             label
  );
    #1;
    address      = addr;
    read_trigger = 1;
    #1;
    assert(contains_address == 0) else begin
      $display("FAIL [%s]: expected miss at %h, got hit", label, addr);
      errors++;
    end
    read_trigger = 0;
  endtask

  initial begin
    $dumpfile("I_CACHE_TEST.vcd");
    $dumpvars(0, I_CACHE_TEST);

    errors        = 0;
    address       = 0;
    mask          = 4'hF;
    write_trigger = 0;
    write_value   = 0;
    read_trigger  = 0;
    new_data      = 0;
    new_address   = 0;
    new_data_save = 0;
    order_tick    = 0;

    // Reset
    reset = 1;
    @(posedge clk); @(posedge clk);
    #1; reset = 0;
    @(posedge clk);

    // =========================================================
    // T1: Empty cache — all misses
    // =========================================================
    $display("T1: Empty cache miss");
    check_miss(28'h0000000, "T1-addr0");
    check_miss(28'h0001000, "T1-addr1");

    // =========================================================
    // T2: Fill one line and read back all 4 words
    // =========================================================
    $display("T2: Fill + read 4 words");
    // Address 0x0000_0010 → tag=0x0000, index=0x01, offset=0x0
    // Data: word0=AAAA_1111, word1=BBBB_2222, word2=CCCC_3333, word3=DDDD_4444
    fill_line(28'h0000010, {32'hDDDD_4444, 32'hCCCC_3333, 32'hBBBB_2222, 32'hAAAA_1111});
    check_hit(28'h0000010, 32'hAAAA_1111, "T2-word0");
    check_hit(28'h0000014, 32'hBBBB_2222, "T2-word1");
    check_hit(28'h0000018, 32'hCCCC_3333, "T2-word2");
    check_hit(28'h000001C, 32'hDDDD_4444, "T2-word3");

    // =========================================================
    // T3: Different index — no conflict
    // =========================================================
    $display("T3: Different index");
    // Address 0x0000_0020 → tag=0x0000, index=0x02
    fill_line(28'h0000020, {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111});
    check_hit(28'h0000020, 32'h11111111, "T3-idx2-word0");
    // Old line at index 0x01 still valid
    check_hit(28'h0000010, 32'hAAAA_1111, "T3-idx1-still-valid");

    // =========================================================
    // T4: Same index, different tag — eviction (direct-mapped)
    // =========================================================
    $display("T4: Eviction (same index, different tag)");
    // Address 0x0001_0010 → tag=0x0001, index=0x01 (same index as T2)
    fill_line(28'h0001010, {32'hFFFF_FFFF, 32'hEEEE_EEEE, 32'hDDDD_DDDD, 32'hCCCC_CCCC});
    check_hit(28'h0001010, 32'hCCCC_CCCC, "T4-new-word0");
    check_hit(28'h0001014, 32'hDDDD_DDDD, "T4-new-word1");
    // Old tag at same index is gone
    check_miss(28'h0000010, "T4-old-evicted");

    // =========================================================
    // T5: save_need_flag is always 0 (read-only)
    // =========================================================
    $display("T5: Read-only — save_need_flag=0");
    assert(save_need_flag == 0) else begin
      $display("FAIL [T5]: save_need_flag should be 0");
      errors++;
    end

    // =========================================================
    // T6: Write is ignored
    // =========================================================
    $display("T6: Write ignored");
    // Try writing to line at index 0x02 (filled in T3)
    @(posedge clk);
    #1;
    address       = 28'h0000020;
    mask          = 4'hF;
    write_trigger = 1;
    write_value   = 32'hDEADBEEF;
    @(posedge clk);
    #1;
    write_trigger = 0;
    @(posedge clk);
    // Value should be unchanged
    check_hit(28'h0000020, 32'h11111111, "T6-write-ignored");

    // =========================================================
    // T7: Reset clears all valid bits
    // =========================================================
    $display("T7: Reset clears valid");
    reset = 1;
    @(posedge clk); @(posedge clk);
    #1; reset = 0;
    @(posedge clk);
    check_miss(28'h0001010, "T7-after-reset-1");
    check_miss(28'h0000020, "T7-after-reset-2");

    // =========================================================
    // T8: Multiple lines fill (stress)
    // =========================================================
    $display("T8: Fill 16 lines");
    begin
      int i;
      for (i = 0; i < 16; i++) begin
        fill_line(i * 16, {32'(i*4+3), 32'(i*4+2), 32'(i*4+1), 32'(i*4+0)});
      end
      // Verify all 16
      for (i = 0; i < 16; i++) begin
        check_hit(i * 16, 32'(i*4+0), $sformatf("T8-line%0d", i));
      end
    end

    // =========================================================
    // T9: High address tag bits
    // =========================================================
    $display("T9: High address tags");
    fill_line(28'hFFF0000, {32'h9999_9999, 32'h8888_8888, 32'h7777_7777, 32'h6666_6666});
    check_hit(28'hFFF0000, 32'h6666_6666, "T9-high-tag-w0");
    check_hit(28'hFFF000C, 32'h9999_9999, "T9-high-tag-w3");

    // =========================================================
    // Summary
    // =========================================================
    @(posedge clk);
    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $display("FAILED: %0d errors", errors);

    $finish;
  end

endmodule
