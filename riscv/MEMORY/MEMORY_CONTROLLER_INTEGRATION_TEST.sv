// Integration test: MEMORY_CONTROLLER + CHUNK_STORAGE_4_POOL + RAM_CONTROLLER + MIG_MODEL
// Tests the full memory subsystem through the MEMORY_CONTROLLER user-facing interface.
module MEMORY_CONTROLLER_INTEGRATION_TEST;

    localparam CHUNK_PART   = 128;
    localparam DATA_SIZE    = 32;
    localparam MASK_SIZE    = DATA_SIZE / 8;
    localparam ADDRESS_SIZE = 28;

    // clk=100 MHz (T=10ns), mig_ui_clk=125 MHz (T=8ns)
    reg clk;
    reg mig_ui_clk;
    initial begin clk = 0;        forever #5 clk        = ~clk;        end
    initial begin mig_ui_clk = 0; forever #4 mig_ui_clk = ~mig_ui_clk; end

    // ----------------------------------------------------------------
    // MEMORY_CONTROLLER user interface
    // ----------------------------------------------------------------
    wire                    controller_ready;
    reg  [ADDRESS_SIZE-1:0] address;
    reg  [MASK_SIZE-1:0]    mask;
    reg                     write_trigger;
    reg  [DATA_SIZE-1:0]    write_value;
    reg  [ADDRESS_SIZE-1:0] command_address;
    wire [DATA_SIZE-1:0]    read_command;
    wire                    contains_command_address;
    reg                     read_trigger;
    wire [DATA_SIZE-1:0]    read_value;
    wire                    contains_address;

    // ----------------------------------------------------------------
    // MEMORY_CONTROLLER <-> RAM_CONTROLLER wires
    // ----------------------------------------------------------------
    wire                       ram_controller_ready;
    wire                       ram_write_trigger;
    wire [CHUNK_PART-1:0]      ram_write_value;
    wire [ADDRESS_SIZE-1:0]    ram_write_address;
    wire                       ram_read_trigger;
    wire [CHUNK_PART-1:0]      ram_read_value;
    wire [ADDRESS_SIZE-1:0]    ram_read_address;
    wire                       ram_read_value_ready;

    // ----------------------------------------------------------------
    // RAM_CONTROLLER <-> MIG_MODEL wires
    // ----------------------------------------------------------------
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

    integer errors;

    // ----------------------------------------------------------------
    // DUT: MEMORY_CONTROLLER
    // ----------------------------------------------------------------
    MEMORY_CONTROLLER #(
        .CHUNK_PART  (CHUNK_PART),
        .DATA_SIZE   (DATA_SIZE),
        .MASK_SIZE   (MASK_SIZE),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) dut (
        .clk                      (clk),
        .ram_controller_ready     (ram_controller_ready),
        .ram_write_trigger        (ram_write_trigger),
        .ram_write_value          (ram_write_value),
        .ram_write_address        (ram_write_address),
        .ram_read_trigger         (ram_read_trigger),
        .ram_read_value           (ram_read_value),
        .ram_read_address         (ram_read_address),
        .ram_read_value_ready     (ram_read_value_ready),
        .controller_ready         (controller_ready),
        .address                  (address),
        .mask                     (mask),
        .write_trigger            (write_trigger),
        .write_value              (write_value),
        .command_address          (command_address),
        .read_command             (read_command),
        .contains_command_address (contains_command_address),
        .read_trigger             (read_trigger),
        .read_value               (read_value),
        .contains_address         (contains_address)
    );

    // ----------------------------------------------------------------
    // RAM_CONTROLLER
    // ----------------------------------------------------------------
    RAM_CONTROLLER #(
        .CHUNK_PART  (CHUNK_PART),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) ram (
        .clk                    (clk),
        .controller_ready       (ram_controller_ready),
        .write_trigger          (ram_write_trigger),
        .write_value            (ram_write_value),
        .write_address          (ram_write_address),
        .read_trigger           (ram_read_trigger),
        .read_value             (ram_read_value),
        .read_address           (ram_read_address),
        .read_value_ready       (ram_read_value_ready),
        .mig_app_addr           (mig_app_addr),
        .mig_app_cmd            (mig_app_cmd),
        .mig_app_en             (mig_app_en),
        .mig_app_wdf_data       (mig_app_wdf_data),
        .mig_app_wdf_end        (mig_app_wdf_end),
        .mig_app_wdf_mask       (mig_app_wdf_mask),
        .mig_app_wdf_wren       (mig_app_wdf_wren),
        .mig_app_wdf_rdy        (mig_app_wdf_rdy),
        .mig_app_rd_data        (mig_app_rd_data),
        .mig_app_rd_data_end    (mig_app_rd_data_end),
        .mig_app_rd_data_valid  (mig_app_rd_data_valid),
        .mig_app_rdy            (mig_app_rdy),
        .mig_ui_clk             (mig_ui_clk),
        .mig_init_calib_complete(mig_init_calib_complete),
        .error                  (),
        .led0                   ()
    );

    // ----------------------------------------------------------------
    // MIG_MODEL
    // ----------------------------------------------------------------
    MIG_MODEL #(
        .CHUNK_PART  (CHUNK_PART),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) mig (
        .mig_ui_clk             (mig_ui_clk),
        .mig_init_calib_complete(mig_init_calib_complete),
        .mig_app_rdy            (mig_app_rdy),
        .mig_app_en             (mig_app_en),
        .mig_app_cmd            (mig_app_cmd),
        .mig_app_addr           (mig_app_addr),
        .mig_app_wdf_data       (mig_app_wdf_data),
        .mig_app_wdf_wren       (mig_app_wdf_wren),
        .mig_app_wdf_end        (mig_app_wdf_end),
        .mig_app_wdf_rdy        (mig_app_wdf_rdy),
        .mig_app_rd_data        (mig_app_rd_data),
        .mig_app_rd_data_valid  (mig_app_rd_data_valid),
        .mig_app_rd_data_end    (mig_app_rd_data_end)
    );

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    task wait_ready;
        integer n;
        begin
            // give controller time to go not-ready after a command
            repeat(6) @(posedge clk);
            n = 0;
            while (!controller_ready && n < 4000) begin
                @(posedge clk);
                n = n + 1;
            end
            @(posedge clk); #1;   // one extra settle cycle
            if (!controller_ready) begin
                $display("  TIMEOUT: controller_ready never returned");
                errors = errors + 1;
            end
        end
    endtask

    // Issue a 32-bit read and wait for completion.
    task do_read;
        input [ADDRESS_SIZE-1:0] addr;
        begin
            @(posedge clk); #1;
            address      = addr;
            read_trigger = 1;
            @(posedge clk); #1;
            read_trigger = 0;
            wait_ready;
        end
    endtask

    // Issue a 32-bit write and wait for completion.
    task do_write;
        input [ADDRESS_SIZE-1:0] addr;
        input [MASK_SIZE-1:0]    wr_mask;
        input [DATA_SIZE-1:0]    data;
        begin
            @(posedge clk); #1;
            address       = addr;
            mask          = wr_mask;
            write_value   = data;
            write_trigger = 1;
            @(posedge clk); #1;
            write_trigger = 0;
            wait_ready;
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

    // ----------------------------------------------------------------
    // Test addresses  (chunk = 16 B; MIG indexes by addr[7:4])
    // ADDR_X is the word-0 (byte offset 0) of each chunk.
    // Word offsets: +0x0 =w0, +0x4 =w1, +0x8 =w2, +0xC =w3.
    // ----------------------------------------------------------------
    localparam [ADDRESS_SIZE-1:0] ADDR_A = 28'h000_0000;  // MIG[0]
    localparam [ADDRESS_SIZE-1:0] ADDR_B = 28'h000_0010;  // MIG[1]
    localparam [ADDRESS_SIZE-1:0] ADDR_C = 28'h000_0020;  // MIG[2]
    localparam [ADDRESS_SIZE-1:0] ADDR_D = 28'h000_0030;  // MIG[3]
    localparam [ADDRESS_SIZE-1:0] ADDR_E = 28'h000_0040;  // MIG[4]  — 5th → triggers eviction
    localparam [ADDRESS_SIZE-1:0] ADDR_F = 28'h000_0050;  // MIG[5]
    localparam [ADDRESS_SIZE-1:0] ADDR_G = 28'h000_0060;  // MIG[6]
    localparam [ADDRESS_SIZE-1:0] ADDR_H = 28'h000_0070;  // MIG[7]

    // ================================================================
    // Main test
    // ================================================================
    initial begin
        $dumpfile("MEMORY_CONTROLLER_INTEGRATION_TEST.vcd");
        $dumpvars(0, MEMORY_CONTROLLER_INTEGRATION_TEST);

        // init — hold triggers low; command_address='0 (ADDR_A) so once
        // ADDR_A loads it stays hot in the command-fetch slot.
        address         = '0;
        command_address = ADDR_A;
        mask            = {MASK_SIZE{1'b1}};
        write_trigger   = 0;
        write_value     = 0;
        read_trigger    = 0;
        errors          = 0;

        // Wait for RAM_CONTROLLER INIT to complete and controller_ready to rise.
        // MIG_MODEL calibration completes instantly, but RAM_CONTROLLER needs
        // its INIT handshake cycle before it asserts controller_ready.
        begin : wait_init
            integer n;
            n = 0;
            while (!controller_ready && n < 4000) begin
                @(posedge clk); n = n + 1;
            end
            @(posedge clk); #1;
        end

        // ============================================================
        // T1: Read miss — fresh cache, address not present
        //     MIG_MODEL initialises all memory to 0 → read back 0
        // ============================================================
        $display("T1: read miss on empty cache");
        do_read(ADDR_A);
        @(posedge clk); #1;
        address = ADDR_A; #1;
        chk("T1 contains_address after miss+load", contains_address);
        chk("T1 read_value = 0 (RAM unwritten)",   read_value === 32'd0);

        // ============================================================
        // T2: Read hit — same address, no RAM transaction expected
        // ============================================================
        $display("T2: read hit (same address, cache warm)");
        do_read(ADDR_A);
        @(posedge clk); #1;
        address = ADDR_A; #1;
        chk("T2 contains_address still hit", contains_address);
        chk("T2 read_value still 0",         read_value === 32'd0);

        // ============================================================
        // T3: Write miss — ADDR_B not in cache
        //     Controller fetches chunk B from RAM (zeros), then writes.
        // ============================================================
        $display("T3: write miss — fetch then write");
        do_write(ADDR_B, 4'b1111, 32'hDEAD_BEEF);
        @(posedge clk); #1;
        address = ADDR_B; #1;
        chk("T3 ADDR_B in cache after write-miss", contains_address);
        chk("T3 word0 of ADDR_B = 0xDEAD_BEEF",   read_value === 32'hDEAD_BEEF);

        // ============================================================
        // T4: Write hit — ADDR_B is already cached; update in place
        // ============================================================
        $display("T4: write hit — in-cache update");
        do_write(ADDR_B, 4'b1111, 32'hCAFE_BABE);
        @(posedge clk); #1;
        address = ADDR_B; #1;
        chk("T4 ADDR_B still in cache", contains_address);
        chk("T4 word0 updated to 0xCAFE_BABE", read_value === 32'hCAFE_BABE);

        // ============================================================
        // T5: Masked write — only bytes 3 and 1 written
        //     ADDR_C not in cache; RAM holds 0.
        //     write_value = 0xAABBCCDD, mask = 1010
        //       byte3 (bits31:24): mask[3]=1 → 0xAA
        //       byte2 (bits23:16): mask[2]=0 → 0x00  (RAM value)
        //       byte1 (bits15:8):  mask[1]=1 → 0xCC
        //       byte0 (bits7:0):   mask[0]=0 → 0x00  (RAM value)
        //     Expected word0 = 0xAA00_CC00
        // ============================================================
        $display("T5: masked write (bytes 3,1 only)");
        do_write(ADDR_C, 4'b1010, 32'hAABBCCDD);
        @(posedge clk); #1;
        address = ADDR_C; #1;
        chk("T5 ADDR_C in cache",      contains_address);
        chk("T5 masked result correct", read_value === 32'hAA00_CC00);

        // ============================================================
        // T6: Word-offset reads — write all 4 words of a chunk, read back
        //     ADDR_D is a fresh chunk. First write (w0) → miss+load.
        //     Subsequent writes (w1, w2, w3) → hits on the same chunk.
        // ============================================================
        $display("T6: all 4 word offsets within one chunk");
        do_write(ADDR_D | 28'h0, 4'b1111, 32'h1111_1111);   // w0 — miss
        do_write(ADDR_D | 28'h4, 4'b1111, 32'h2222_2222);   // w1 — hit
        do_write(ADDR_D | 28'h8, 4'b1111, 32'h3333_3333);   // w2 — hit
        do_write(ADDR_D | 28'hC, 4'b1111, 32'h4444_4444);   // w3 — hit
        @(posedge clk); #1;
        address = ADDR_D | 28'h0; #1; chk("T6 w0", read_value === 32'h1111_1111);
        address = ADDR_D | 28'h4; #1; chk("T6 w1", read_value === 32'h2222_2222);
        address = ADDR_D | 28'h8; #1; chk("T6 w2", read_value === 32'h3333_3333);
        address = ADDR_D | 28'hC; #1; chk("T6 w3", read_value === 32'h4444_4444);

        // All 4 slots now occupied: A(clean), B(dirty), C(dirty), D(dirty)
        // Point command_address at ADDR_B so evicting A later won't re-fetch it.
        // Then refresh C and D via read hits so their order_indices reset to 0.
        // With all four slots at order_index=0, slot 0 (A, clean) becomes the
        // LRU victim (slot 0 wins the priority tie-break in the pool logic).
        @(posedge clk); #1;
        command_address = ADDR_B;
        wait_ready;   // let any pending command fetch settle
        do_read(ADDR_C);  // hit → C.order_index resets to 0
        do_read(ADDR_D);  // hit → D.order_index resets to 0
        // Now: A=0, B=0(cmd-pinned), C=0, D=0 → slot 0 (A) is the LRU victim.

        // ============================================================
        // T7: Cache full check — all 4 addresses simultaneously in cache
        // ============================================================
        $display("T7: all 4 cache slots occupied simultaneously");
        @(posedge clk); #1;
        address = ADDR_A; #1; chk("T7 ADDR_A cached", contains_address);
        address = ADDR_B; #1; chk("T7 ADDR_B cached", contains_address);
        address = ADDR_C; #1; chk("T7 ADDR_C cached", contains_address);
        address = ADDR_D; #1; chk("T7 ADDR_D cached", contains_address);

        // ============================================================
        // T8: Clean eviction — ADDR_E causes LRU (ADDR_A, clean) eviction
        //     ADDR_A was last accessed in T2; B/C/D touched more recently.
        //     No dirty writeback expected for the evicted clean line.
        // ============================================================
        $display("T8: clean eviction (LRU = ADDR_A, no writeback)");
        do_read(ADDR_E);
        @(posedge clk); #1;
        address = ADDR_E; #1;
        chk("T8 ADDR_E loaded after eviction", contains_address);
        address = ADDR_A; #1;
        chk("T8 ADDR_A evicted (miss)",        !contains_address);

        // ============================================================
        // T9: Dirty eviction writeback — write to ADDR_B (mark dirty),
        //     then evict it by loading 4 new unique chunks; finally
        //     re-read ADDR_B from RAM and verify dirty data survived.
        // ============================================================
        $display("T9: dirty eviction writeback");
        // Cache after T8: {E, B(dirty,0xCAFE_BABE), C(dirty), D(dirty)}
        // Overwrite ADDR_B with a distinct value to make the test unambiguous.
        do_write(ADDR_B, 4'b1111, 32'hBEEF_CAFE);
        @(posedge clk); #1;
        address = ADDR_B; #1;
        chk("T9 ADDR_B dirty in cache", contains_address);
        chk("T9 ADDR_B pre-evict value", read_value === 32'hBEEF_CAFE);

        // Load 4 new chunks → evicts all 4 current slots (including dirty ADDR_B).
        // command_address stays on ADDR_B; set it away to avoid auto-refetch.
        @(posedge clk); #1;
        command_address = ADDR_F;
        do_read(ADDR_E);  // already loaded but causes a command-miss resolution
        do_read(ADDR_F);
        do_read(ADDR_G);
        do_read(ADDR_H);
        // All 4 original dirty lines (B, C, D, E) must have been written back to MIG.

        // Now re-read ADDR_B from RAM through the empty cache.
        do_read(ADDR_B);
        @(posedge clk); #1;
        address = ADDR_B; #1;
        chk("T9 ADDR_B in cache after re-read", contains_address);
        chk("T9 dirty writeback preserved 0xBEEF_CAFE", read_value === 32'hBEEF_CAFE);

        // ============================================================
        // T10: Dirty writeback for word offsets — ADDR_D was written with
        //      4 distinct words; after eviction and re-read all 4 must
        //      match what was written in T6.
        // ============================================================
        $display("T10: dirty writeback preserves all 4 words of a chunk");
        // ADDR_D was evicted in T9's flush. Re-read it from RAM.
        do_read(ADDR_D);
        @(posedge clk); #1;
        address = ADDR_D | 28'h0; #1; chk("T10 w0 after writeback", read_value === 32'h1111_1111);
        address = ADDR_D | 28'h4; #1; chk("T10 w1 after writeback", read_value === 32'h2222_2222);
        address = ADDR_D | 28'h8; #1; chk("T10 w2 after writeback", read_value === 32'h3333_3333);
        address = ADDR_D | 28'hC; #1; chk("T10 w3 after writeback", read_value === 32'h4444_4444);

        // ============================================================
        // T11: Command-address port — write to an address via data port,
        //      confirm read_command reflects the written value.
        // ============================================================
        $display("T11: command port read_command matches written data");
        // Write to ADDR_A first (cache miss → fetch + write), THEN point
        // command_address at it.  Setting command_address before the write
        // would trigger a command-miss prefetch that consumes the miss slot and
        // causes the write_trigger pulse to be missed.
        do_write(ADDR_A, 4'b1111, 32'hFACE_FEED);
        // ADDR_A now in cache with w0=0xFACE_FEED. Set command_address.
        @(posedge clk); #1;
        command_address = ADDR_A;
        @(posedge clk); #1;
        address = ADDR_A; #1;
        chk("T11 contains_address for ADDR_A",         contains_address);
        chk("T11 contains_command_address for ADDR_A", contains_command_address);
        chk("T11 read_command = 0xFACE_FEED",          read_command === 32'hFACE_FEED);

        // ============================================================
        // T12: Masked write preserves other words in the same chunk
        //      Write w2 partially; w0 and w1 from the original chunk must be intact.
        // ============================================================
        $display("T12: masked partial write does not corrupt other words");
        // ADDR_A in cache with w0=0xFACE_FEED, w1=0, w2=0, w3=0.
        // Write only byte1 of w2 (offset +8): mask=0010, value=0x00XX00XX
        do_write(ADDR_A | 28'h8, 4'b0010, 32'hFF_AA_BB_CC);
        @(posedge clk); #1;
        // w0 and w1 unchanged
        address = ADDR_A | 28'h0; #1; chk("T12 w0 unchanged", read_value === 32'hFACE_FEED);
        address = ADDR_A | 28'h4; #1; chk("T12 w1 unchanged", read_value === 32'h0000_0000);
        // w2: only byte1 (bits15:8) changed to 0xBB
        address = ADDR_A | 28'h8; #1; chk("T12 w2 byte1 written", read_value === 32'h0000_BB00);

        // ============================================================
        // T13: Read-then-write at the same address — interleaved ops
        //      Simulate a read-modify-write sequence.
        // ============================================================
        $display("T13: read-modify-write sequence");
        do_read(ADDR_C);                            // C was evicted; re-fetch from RAM
        @(posedge clk); #1;
        address = ADDR_C; #1;
        // RAM holds the T5 masked result: 0xAA00_CC00
        chk("T13 ADDR_C re-fetched from RAM", contains_address);
        chk("T13 ADDR_C RAM value correct",   read_value === 32'hAA00_CC00);
        // Now modify it in-place.
        do_write(ADDR_C, 4'b1111, 32'hDEAD_C0DE);
        @(posedge clk); #1;
        address = ADDR_C; #1;
        chk("T13 ADDR_C updated in cache",    read_value === 32'hDEAD_C0DE);

        // ============================================================
        // T14: controller_ready gating — while busy, controller_ready = 0
        // ============================================================
        $display("T14: controller_ready low while fetching");
        @(posedge clk); #1;
        // Start a read on a cold address.
        address      = 28'h000_0090;   // MIG[9], not in cache
        read_trigger = 1;
        @(posedge clk); #1;
        read_trigger = 0;
        // Immediately after the trigger, the controller should be busy.
        chk("T14 controller_ready = 0 during fetch", !controller_ready);
        wait_ready;
        chk("T14 controller_ready = 1 after fetch", controller_ready);

        // ============================================================
        // Summary
        // ============================================================
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILED: %0d error(s)", errors);

        $finish;
    end

endmodule
