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
    reg reset;
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
        .reset                    (reset),
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
        .reset                  (reset),
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

    // ================================================================
    // Main test
    // ================================================================
    initial begin
        $dumpfile("MEMORY_CONTROLLER_INTEGRATION_TEST.vcd");
        $dumpvars(0, MEMORY_CONTROLLER_INTEGRATION_TEST);

        address         = '0;
        mask            = {MASK_SIZE{1'b1}};
        write_trigger   = 0;
        write_value     = 0;
        read_trigger    = 0;
        errors          = 0;
        reset           = 1;

        // Hold reset for a few cycles
        repeat(5) @(posedge clk);
        #1;
        reset = 0;

        // Wait for RAM_CONTROLLER INIT to complete and controller_ready to rise.
        begin : wait_init
            integer n;
            @(posedge clk); #1;
            n = 0;
            while (controller_ready !== 1'b1 && n < 4000) begin
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
        // T8: Clean eviction — ADDR_E causes LRU (ADDR_A, clean) eviction.
        //     Access order: A(T1 last hit), B(T4), C(T5), D(T6).
        //     A has been aging the longest without a hit → LRU victim.
        //     No dirty writeback expected.
        // ============================================================
        $display("T8: clean eviction (LRU = ADDR_A, no writeback)");
        do_read(ADDR_E);
        @(posedge clk); #1;
        address = ADDR_E; #1;
        chk("T8 ADDR_E loaded after eviction", contains_address);
        address = ADDR_A; #1;
        chk("T8 ADDR_A evicted (miss)",        !contains_address);

        // ============================================================
        // T9: Dirty eviction writeback — ADDR_B was last written in T4,
        //     making it the oldest dirty slot after T8.
        //     Loading ADDR_F evicts B (LRU dirty) → writeback to MIG.
        //     Loading ADDR_G evicts E or C (next in LRU order).
        //     Re-reading ADDR_B fetches the written-back value from MIG.
        // ============================================================
        $display("T9: dirty eviction writeback");
        // Cache after T8: {E(clean), B(dirty,0xCAFE_BABE), C(dirty), D(dirty)}
        // B is the LRU dirty slot (last accessed in T4).
        do_read(ADDR_F);   // evicts B (LRU, dirty) → writeback 0xCAFE_BABE to MIG
        do_read(ADDR_G);   // evicts next LRU slot

        // Re-read ADDR_B from RAM to verify dirty writeback preserved data.
        do_read(ADDR_B);
        @(posedge clk); #1;
        address = ADDR_B; #1;
        chk("T9 ADDR_B in cache after re-read",         contains_address);
        chk("T9 dirty writeback preserved 0xCAFE_BABE", read_value === 32'hCAFE_BABE);

        // ============================================================
        // T10: Dirty writeback for word offsets — ADDR_D was written with
        //      4 distinct words in T6 (1111,2222,3333,4444).
        //      Evict D and re-read to verify all 4 words survived.
        // ============================================================
        $display("T10: dirty writeback preserves all 4 words of a chunk");
        // Force D out of cache by loading two cold addresses, then re-read D.
        do_read(28'h000_0080);   // evicts LRU — forces D toward eviction
        do_read(28'h000_0090);   // one more to ensure D is evicted
        do_read(ADDR_D);
        @(posedge clk); #1;
        address = ADDR_D | 28'h0; #1; chk("T10 w0 after writeback", read_value === 32'h1111_1111);
        address = ADDR_D | 28'h4; #1; chk("T10 w1 after writeback", read_value === 32'h2222_2222);
        address = ADDR_D | 28'h8; #1; chk("T10 w2 after writeback", read_value === 32'h3333_3333);
        address = ADDR_D | 28'hC; #1; chk("T10 w3 after writeback", read_value === 32'h4444_4444);

        // ============================================================
        // T11: Masked partial write does not corrupt other words.
        //      Write-miss on ADDR_A (not in cache, RAM holds 0).
        //      Apply mask=0010 to w2 → only byte1 changes.
        // ============================================================
        $display("T11: masked partial write does not corrupt other words");
        do_write(ADDR_A | 28'h8, 4'b0010, 32'hFF_AA_BB_CC);
        @(posedge clk); #1;
        // w0 and w1 come from RAM (all zeros), w2 only byte1 written
        address = ADDR_A | 28'h0; #1; chk("T11 w0 unchanged (=0)", read_value === 32'h0000_0000);
        address = ADDR_A | 28'h4; #1; chk("T11 w1 unchanged (=0)", read_value === 32'h0000_0000);
        address = ADDR_A | 28'h8; #1; chk("T11 w2 byte1 written",  read_value === 32'h0000_BB00);

        // ============================================================
        // T12: Read-then-write at the same address — interleaved ops.
        //      ADDR_C was evicted in T9 with dirty data 0xAA00_CC00.
        //      Re-fetch it from RAM, then overwrite in cache.
        // ============================================================
        $display("T12: read-modify-write sequence");
        do_read(ADDR_C);
        @(posedge clk); #1;
        address = ADDR_C; #1;
        chk("T12 ADDR_C re-fetched from RAM", contains_address);
        chk("T12 ADDR_C RAM value correct",   read_value === 32'hAA00_CC00);
        do_write(ADDR_C, 4'b1111, 32'hDEAD_C0DE);
        @(posedge clk); #1;
        address = ADDR_C; #1;
        chk("T12 ADDR_C updated in cache",    read_value === 32'hDEAD_C0DE);

        // ============================================================
        // T13: controller_ready gating — while busy, controller_ready = 0
        // ============================================================
        $display("T13: controller_ready low while fetching");
        @(posedge clk); #1;
        // Start a read on a cold address.
        address      = 28'h000_00A0;   // not in cache
        read_trigger = 1;
        @(posedge clk); #1;
        read_trigger = 0;
        // Immediately after the trigger, the controller should be busy.
        chk("T13 controller_ready = 0 during fetch", !controller_ready);
        wait_ready;
        chk("T13 controller_ready = 1 after fetch", controller_ready);

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
