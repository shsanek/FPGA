module I_CACHE_TEST;

  localparam DEPTH        = 256;
  localparam CHUNK_PART   = 128;
  localparam DATA_SIZE    = 32;
  localparam MASK_SIZE    = DATA_SIZE/8;
  localparam ADDRESS_SIZE = 28;

  reg clk;
  reg reset;
  initial begin clk = 0; forever #5 clk = ~clk; end

  // =========================================================
  // DUT: READ_ONLY=0 (writable D-cache mode)
  // =========================================================
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
    .READ_ONLY    (0),
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

  // =========================================================
  // DUT2: READ_ONLY=1 (for T14)
  // =========================================================
  reg  [ADDRESS_SIZE-1:0] ro_address;
  reg  [MASK_SIZE-1:0]    ro_mask;
  reg                     ro_write_trigger;
  reg  [DATA_SIZE-1:0]    ro_write_value;
  reg                     ro_read_trigger;
  wire                    ro_contains_address;
  wire [DATA_SIZE-1:0]    ro_read_value;
  wire [ADDRESS_SIZE-1:0] ro_save_address;
  wire [CHUNK_PART-1:0]   ro_save_data;
  wire                    ro_save_need_flag;
  reg  [CHUNK_PART-1:0]   ro_new_data;
  reg  [ADDRESS_SIZE-1:0] ro_new_address;
  reg                     ro_new_data_save;

  I_CACHE #(
    .DEPTH        (DEPTH),
    .READ_ONLY    (1),
    .CHUNK_PART   (CHUNK_PART),
    .DATA_SIZE    (DATA_SIZE),
    .MASK_SIZE    (MASK_SIZE),
    .ADDRESS_SIZE (ADDRESS_SIZE)
  ) dut_ro (
    .clk              (clk),
    .reset            (reset),
    .address          (ro_address),
    .mask             (ro_mask),
    .write_trigger    (ro_write_trigger),
    .write_value      (ro_write_value),
    .read_trigger     (ro_read_trigger),
    .read_value       (ro_read_value),
    .contains_address (ro_contains_address),
    .save_address     (ro_save_address),
    .save_data        (ro_save_data),
    .save_need_flag   (ro_save_need_flag),
    .order_tick       (1'b0),
    .new_data         (ro_new_data),
    .new_address      (ro_new_address),
    .new_data_save    (ro_new_data_save)
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

  task automatic write_word(
    input [ADDRESS_SIZE-1:0] addr,
    input [MASK_SIZE-1:0]    wr_mask,
    input [DATA_SIZE-1:0]    data
  );
    @(posedge clk);
    #1;
    address       = addr;
    mask          = wr_mask;
    write_trigger = 1;
    write_value   = data;
    @(posedge clk);
    #1;
    write_trigger = 0;
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
    // T5: Clean line — save_need_flag=0 (just filled, not written)
    // =========================================================
    $display("T5: Clean line — save_need_flag=0");
    // Point address at index 0x02 (filled in T3, never written)
    #1; address = 28'h0000020;
    #1;
    assert(save_need_flag == 0) else begin
      $display("FAIL [T5]: save_need_flag should be 0 for clean line");
      errors++;
    end

    // =========================================================
    // T6: Write hit — word is updated (READ_ONLY=0)
    // =========================================================
    $display("T6: Write hit");
    // Write to line at index 0x02, word0
    write_word(28'h0000020, 4'hF, 32'hDEADBEEF);
    check_hit(28'h0000020, 32'hDEADBEEF, "T6-write-hit-word0");
    // Other words unchanged
    check_hit(28'h0000024, 32'h22222222, "T6-other-words-ok");

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
    // T10: Write hit — write to word2, read back
    // =========================================================
    $display("T10: Write hit — word2");
    // Reset and fill a fresh line at index 0x05
    reset = 1; @(posedge clk); @(posedge clk); #1; reset = 0; @(posedge clk);
    fill_line(28'h0000050, {32'hAAAAAAAA, 32'hBBBBBBBB, 32'hCCCCCCCC, 32'hDDDDDDDD});
    // Write to word2 (offset 0x8)
    write_word(28'h0000058, 4'hF, 32'h12345678);
    check_hit(28'h0000058, 32'h12345678, "T10-word2-written");
    // Other words intact
    check_hit(28'h0000050, 32'hDDDDDDDD, "T10-word0-intact");
    check_hit(28'h0000054, 32'hCCCCCCCC, "T10-word1-intact");
    check_hit(28'h000005C, 32'hAAAAAAAA, "T10-word3-intact");

    // =========================================================
    // T11: Byte mask — partial write
    // =========================================================
    $display("T11: Byte mask");
    // Fill line at index 0x06 with known data
    fill_line(28'h0000060, {32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hAABBCCDD});
    // Write only byte0 (mask=0001)
    write_word(28'h0000060, 4'b0001, 32'h00000011);
    check_hit(28'h0000060, 32'hAABBCC11, "T11-byte0-only");
    // Write only byte2 (mask=0100)
    write_word(28'h0000060, 4'b0100, 32'h00990000);
    check_hit(28'h0000060, 32'hAA99CC11, "T11-byte2-only");

    // =========================================================
    // T12: Dirty eviction — save_need_flag + save_data
    // =========================================================
    $display("T12: Dirty eviction");
    reset = 1; @(posedge clk); @(posedge clk); #1; reset = 0; @(posedge clk);
    // Fill line at index 0x00, tag=0x0000
    fill_line(28'h0000000, {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111});
    // Write to make it dirty
    write_word(28'h0000000, 4'hF, 32'hBEEFBEEF);
    // Point address at same index — should see dirty flag
    #1; address = 28'h0000000;
    #1;
    assert(save_need_flag == 1) else begin
      $display("FAIL [T12]: save_need_flag should be 1 for dirty line");
      errors++;
    end
    assert(save_address == 28'h0000000) else begin
      $display("FAIL [T12]: save_address expected 0, got %h", save_address);
      errors++;
    end
    // Check save_data has written word (word0=BEEFBEEF, rest unchanged)
    assert(save_data[31:0] == 32'hBEEFBEEF) else begin
      $display("FAIL [T12]: save_data word0 expected BEEFBEEF, got %h", save_data[31:0]);
      errors++;
    end
    assert(save_data[63:32] == 32'h22222222) else begin
      $display("FAIL [T12]: save_data word1 expected 22222222, got %h", save_data[63:32]);
      errors++;
    end

    // Now fill same index with different tag — evicts dirty line
    // (save_need_flag was checked above; after fill, dirty clears)
    fill_line(28'h0001000, {32'hAAAAAAAA, 32'hBBBBBBBB, 32'hCCCCCCCC, 32'hDDDDDDDD});
    #1; address = 28'h0001000;
    #1;
    assert(save_need_flag == 0) else begin
      $display("FAIL [T12]: save_need_flag should be 0 after clean fill");
      errors++;
    end

    // =========================================================
    // T13: Fill clears dirty
    // =========================================================
    $display("T13: Fill clears dirty");
    reset = 1; @(posedge clk); @(posedge clk); #1; reset = 0; @(posedge clk);
    // Fill, write (dirty), then re-fill same index
    fill_line(28'h0000010, {32'h0, 32'h0, 32'h0, 32'h0});
    write_word(28'h0000010, 4'hF, 32'hCAFECAFE);
    #1; address = 28'h0000010;
    #1;
    assert(save_need_flag == 1) else begin
      $display("FAIL [T13]: expected dirty after write");
      errors++;
    end
    // Re-fill same index — dirty should clear
    fill_line(28'h0000010, {32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF});
    #1; address = 28'h0000010;
    #1;
    assert(save_need_flag == 0) else begin
      $display("FAIL [T13]: expected clean after re-fill");
      errors++;
    end
    check_hit(28'h0000010, 32'hFFFFFFFF, "T13-refill-data");

    // =========================================================
    // T14: READ_ONLY=1 — writes ignored, save_need_flag=0
    // =========================================================
    $display("T14: READ_ONLY=1");
    // Use dut_ro instance
    ro_address       = 0;
    ro_mask          = 4'hF;
    ro_write_trigger = 0;
    ro_write_value   = 0;
    ro_read_trigger  = 0;
    ro_new_data      = 0;
    ro_new_address   = 0;
    ro_new_data_save = 0;
    @(posedge clk);
    // Fill a line
    @(posedge clk); #1;
    ro_new_address   = 28'h0000020;
    ro_new_data      = {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111};
    ro_new_data_save = 1;
    @(posedge clk); #1;
    ro_new_data_save = 0;
    // Attempt write
    @(posedge clk); #1;
    ro_address       = 28'h0000020;
    ro_mask          = 4'hF;
    ro_write_trigger = 1;
    ro_write_value   = 32'hDEADDEAD;
    @(posedge clk); #1;
    ro_write_trigger = 0;
    @(posedge clk);
    // Read back — should be original
    #1;
    ro_address    = 28'h0000020;
    ro_read_trigger = 1;
    #1;
    assert(ro_read_value == 32'h11111111) else begin
      $display("FAIL [T14]: READ_ONLY write should be ignored, got %h", ro_read_value);
      errors++;
    end
    assert(ro_save_need_flag == 0) else begin
      $display("FAIL [T14]: READ_ONLY save_need_flag should be 0");
      errors++;
    end
    ro_read_trigger = 0;

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
