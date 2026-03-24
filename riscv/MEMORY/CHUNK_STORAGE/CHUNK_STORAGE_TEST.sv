module CHUNK_STORAGE_TEST;

  localparam CHUNK_PART   = 128;
  localparam DATA_SIZE    = 32;
  localparam MASK_SIZE    = DATA_SIZE/8;
  localparam ADDRESS_SIZE = 28;

  // Clock: 100 MHz
  reg clk;
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
  wire [15:0]             order_index;

  reg  [CHUNK_PART-1:0]   new_data;
  reg  [ADDRESS_SIZE-1:0] new_address;
  reg                     new_data_save;
  reg                     order_tick;

  int                     errors;
  logic [CHUNK_PART-1:0]  expected_data;

  CHUNK_STORAGE #(
    .CHUNK_PART   (CHUNK_PART),
    .DATA_SIZE    (DATA_SIZE),
    .MASK_SIZE    (MASK_SIZE),
    .ADDRESS_SIZE (ADDRESS_SIZE)
  ) dut (
    .clk                     (clk),
    .address                 (address),
    .mask                    (mask),
    .write_trigger           (write_trigger),
    .write_value             (write_value),
    .read_trigger            (read_trigger),
    .read_value              (read_value),
    .contains_address        (contains_address),
    .save_address            (save_address),
    .save_data               (save_data),
    .save_need_flag          (save_need_flag),
    .order_index             (order_index),
    .order_tick              (order_tick),
    .new_data                (new_data),
    .new_address             (new_address),
    .new_data_save           (new_data_save)
  );

  // Convenience: wait for posedge then drive signals #1 after,
  // so the DUT's always_ff samples the PREVIOUS cycle's values
  // before we change anything. Signals set here are sampled at
  // the NEXT posedge.
  task clk_step;
    begin
      @(posedge clk); #1;
    end
  endtask

  task chk;
    input string name;
    input logic  cond;
    begin
      if (!cond) begin
        $display("  FAIL: %s", name);
        errors = errors + 1;
      end
    end
  endtask

  // Two chunk-aligned addresses (bits [3:0] = 0)
  localparam [ADDRESS_SIZE-1:0] ADDR_A = 28'h0A5_0000;
  localparam [ADDRESS_SIZE-1:0] ADDR_B = 28'h1B0_0000;

  // 128-bit payloads: layout new_data[31:0]=d0 … [127:96]=d3
  localparam [CHUNK_PART-1:0] DATA_A =
    {32'hDEAD_BEEF, 32'hCAFE_BABE, 32'h1234_5678, 32'h8765_4321};
  localparam [CHUNK_PART-1:0] DATA_B =
    {32'hFFFF_0000, 32'h0000_FFFF, 32'hABCD_EF01, 32'h1234_5678};

  initial begin
    $dumpfile("CHUNK_STORAGE_TEST.vcd");
    $dumpvars(0, CHUNK_STORAGE_TEST);

    // Drive defaults at time 0 — before any posedge
    address         = ADDR_A;
    mask            = {MASK_SIZE{1'b1}};
    write_trigger   = 0;
    write_value     = 0;
    read_trigger    = 0;
    new_data        = 0;
    new_address     = 0;
    new_data_save   = 0;
    order_tick      = 0;
    errors          = 0;

    // ----------------------------------------------------------------
    // T1: Before any load — chunk invalid, everything is a miss
    // ----------------------------------------------------------------
    $display("T1: miss before any load");
    clk_step;  // posedge 1 — DUT sees new_data_save=0, chunk_valid=0
    // combinational outputs settle after DUT FF
    address         = ADDR_A;
    chk("T1 contains_address=0",         !contains_address);
    chk("T1 read_value=0",                read_value === 32'd0);

    // ----------------------------------------------------------------
    // T2: Load chunk A
    // ----------------------------------------------------------------
    $display("T2: load chunk A");
    // Set signals AFTER posedge 1 (#1 already elapsed in clk_step)
    new_address   = ADDR_A;
    new_data      = DATA_A;
    new_data_save = 1;          // will be sampled at posedge 2
    clk_step;                   // posedge 2 — DUT loads chunk A
    new_data_save = 0;
    clk_step;                   // posedge 3 — settle, order_index ticks
    address = ADDR_A;           // combinational check point
    chk("T2 contains_address=1",  contains_address);
    chk("T2 save_need_flag=0",   !save_need_flag);
    chk("T2 save_address",        save_address === {ADDR_A[ADDRESS_SIZE-1:4], 4'b0});
    chk("T2 save_data=DATA_A",    save_data    === DATA_A);

    // ----------------------------------------------------------------
    // T3: Read all 4 words (combinational)
    // Note: #0 is needed after each address change so iverilog
    //       propagates continuous assignments before reading wires.
    // ----------------------------------------------------------------
    $display("T3: read all 4 words");
    address = ADDR_A | 28'h0; #0; chk("T3 word0", read_value === DATA_A[31:0]);
    address = ADDR_A | 28'h4; #0; chk("T3 word1", read_value === DATA_A[63:32]);
    address = ADDR_A | 28'h8; #0; chk("T3 word2", read_value === DATA_A[95:64]);
    address = ADDR_A | 28'hC; #0; chk("T3 word3", read_value === DATA_A[127:96]);

    // ----------------------------------------------------------------
    // T4: Address miss — different chunk (combinational)
    // ----------------------------------------------------------------
    $display("T4: miss — different chunk address");
    address         = ADDR_B; #0;
    chk("T4 contains_address=0",         !contains_address);
    chk("T4 read_value=0",                read_value    === 32'd0);

    // ----------------------------------------------------------------
    // T5: Write miss — write to unloaded address must be ignored
    // ----------------------------------------------------------------
    $display("T5: write miss ignored");
    address       = ADDR_B;
    mask          = 4'b1111;
    write_value   = 32'hDEAD_DEAD;
    write_trigger = 1;
    clk_step;             // posedge — DUT: internal_contains_address=0 → ignored
    write_trigger = 0;
    clk_step;             // settle
    address = ADDR_A;
    chk("T5 data unchanged", save_data === DATA_A);
    chk("T5 save_need_flag still 0", !save_need_flag);

    // ----------------------------------------------------------------
    // T6: LRU order_index — resets on hit, increments only on order_tick
    // ----------------------------------------------------------------
    $display("T6: order_index behavior");
    address      = ADDR_A;
    read_trigger = 1;
    clk_step;                          // posedge — hit → order_index <= 0
    read_trigger = 0;
    chk("T6 order_index=0 after hit", order_index === 16'd0);

    // 3 idle posedges WITHOUT order_tick — counter must NOT change
    clk_step; clk_step; clk_step;
    chk("T6 order_index=0 without tick", order_index === 16'd0);

    // 3 posedges WITH order_tick=1 — counter increments each cycle
    order_tick = 1;
    clk_step; clk_step; clk_step;
    order_tick = 0;
    chk("T6 order_index=3 after 3 ticks", order_index === 16'd3);

    // ----------------------------------------------------------------
    // T7: Masked write — only selected bytes change
    // ----------------------------------------------------------------
    $display("T7: masked write to word1 (mask=0101)");
    address       = ADDR_A | 28'h4;   // word1
    mask          = 4'b0101;           // bytes 2 and 0
    write_value   = 32'hA1B2_C3D4;
    write_trigger = 1;
    clk_step;
    write_trigger = 0;
    clk_step;

    // word1 was DATA_A[63:32]=0x1234_5678
    // mask[3]=0→keep 0x12, mask[2]=1→take 0xB2, mask[1]=0→keep 0x56, mask[0]=1→take 0xD4
    expected_data = {DATA_A[127:64], 32'h12B2_56D4, DATA_A[31:0]};
    chk("T7 save_need_flag=1",   save_need_flag);
    chk("T7 save_data correct",  save_data === expected_data);

    // ----------------------------------------------------------------
    // T8: Full-mask write to word3 — all bytes replaced
    // ----------------------------------------------------------------
    $display("T8: full-mask write to word3");
    address       = ADDR_A | 28'hC;   // word3
    mask          = 4'b1111;
    write_value   = 32'hBEEF_CAFE;
    write_trigger = 1;
    clk_step;
    write_trigger = 0;
    clk_step;

    expected_data = {32'hBEEF_CAFE, DATA_A[95:64], 32'h12B2_56D4, DATA_A[31:0]};
    chk("T8 save_data word3 replaced", save_data === expected_data);

    // ----------------------------------------------------------------
    // T9: new_data_save overwrites — chunk B loaded, chunk A evicted
    // ----------------------------------------------------------------
    $display("T9: load chunk B (evicts chunk A)");
    new_address   = ADDR_B;
    new_data      = DATA_B;
    new_data_save = 1;
    clk_step;
    new_data_save = 0;
    clk_step;

    address = ADDR_B; #0;
    chk("T9 chunk B hit",       contains_address);
    chk("T9 save_need_flag=0", !save_need_flag);
    chk("T9 save_data=DATA_B",  save_data === DATA_B);
    chk("T9 word0 of B",        read_value === DATA_B[31:0]);

    address = ADDR_A; #0;
    chk("T9 chunk A now miss", !contains_address);

    // ----------------------------------------------------------------
    // Summary
    // ----------------------------------------------------------------
    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $display("FAILED: %0d error(s)", errors);

    $finish;
  end

endmodule
