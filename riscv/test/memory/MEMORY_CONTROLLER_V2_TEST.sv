module MEMORY_CONTROLLER_V2_TEST;

    localparam DEPTH      = 16;
    localparam DATA_WIDTH = 128;
    localparam MASK_WIDTH = DATA_WIDTH / 8;
    localparam ADDR_WIDTH = 32;

    reg clk;
    initial begin clk = 0; forever #5 clk = ~clk; end

    reg reset;
    int errors;

    // =========================================================
    // DUT: READ_ONLY=0, WAYS=1 (D-cache)
    // =========================================================
    reg  [ADDR_WIDTH-1:0]  bus_address;
    reg                    bus_read, bus_write;
    reg  [DATA_WIDTH-1:0]  bus_write_data;
    reg  [MASK_WIDTH-1:0]  bus_write_mask;
    wire                   bus_ready;
    wire [DATA_WIDTH-1:0]  bus_read_data;
    wire                   bus_read_valid;

    wire [ADDR_WIDTH-1:0]  ext_address;
    wire                   ext_read, ext_write;
    wire [DATA_WIDTH-1:0]  ext_write_data;
    wire [MASK_WIDTH-1:0]  ext_write_mask;
    reg                    ext_ready;
    reg  [DATA_WIDTH-1:0]  ext_read_data;
    reg                    ext_read_valid;

    // DDR mock
    reg [DATA_WIDTH-1:0] ddr_mem [0:255];
    reg [3:0] ddr_delay;
    reg ddr_pending_read;
    reg [DATA_WIDTH-1:0] ddr_pending_data;

    always_ff @(posedge clk) begin
        ext_read_valid <= 0;
        if (reset) begin
            ext_ready <= 1;
            ddr_pending_read <= 0;
        end else begin
            if (ext_write) begin
                ddr_mem[ext_address[11:4]] <= ext_write_data;
                ext_ready <= 0;
            end
            if (ext_read) begin
                ddr_pending_data <= ddr_mem[ext_address[11:4]];
                ddr_pending_read <= 1;
                ddr_delay <= 2;
                ext_ready <= 0;
            end else if (ddr_pending_read) begin
                if (ddr_delay == 0) begin
                    ext_read_data <= ddr_pending_data;
                    ext_read_valid <= 1;
                    ddr_pending_read <= 0;
                    ext_ready <= 1;
                end else
                    ddr_delay <= ddr_delay - 1;
            end else if (!ext_ready)
                ext_ready <= 1;
        end
    end

    MEMORY_CONTROLLER_V2 #(
        .DEPTH(DEPTH), .WAYS(1), .READ_ONLY(0),
        .DATA_WIDTH(DATA_WIDTH), .MASK_WIDTH(MASK_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk), .reset(reset),
        .bus_address(bus_address), .bus_read(bus_read), .bus_write(bus_write),
        .bus_write_data(bus_write_data), .bus_write_mask(bus_write_mask),
        .bus_ready(bus_ready), .bus_read_data(bus_read_data), .bus_read_valid(bus_read_valid),
        .external_address(ext_address), .external_read(ext_read), .external_write(ext_write),
        .external_write_data(ext_write_data), .external_write_mask(ext_write_mask),
        .external_ready(ext_ready), .external_read_data(ext_read_data), .external_read_valid(ext_read_valid)
    );

    // =========================================================
    // DUT_RO: READ_ONLY=1 (I-cache)
    // =========================================================
    reg  [ADDR_WIDTH-1:0]  ro_bus_address;
    reg                    ro_bus_read, ro_bus_write;
    reg  [DATA_WIDTH-1:0]  ro_bus_write_data;
    reg  [MASK_WIDTH-1:0]  ro_bus_write_mask;
    wire                   ro_bus_ready;
    wire [DATA_WIDTH-1:0]  ro_bus_read_data;
    wire                   ro_bus_read_valid;

    wire [ADDR_WIDTH-1:0]  ro_ext_address;
    wire                   ro_ext_read, ro_ext_write;
    wire [DATA_WIDTH-1:0]  ro_ext_write_data;
    wire [MASK_WIDTH-1:0]  ro_ext_write_mask;
    reg                    ro_ext_ready;
    reg  [DATA_WIDTH-1:0]  ro_ext_read_data;
    reg                    ro_ext_read_valid;

    reg [DATA_WIDTH-1:0] ro_ddr_mem [0:255];
    reg [3:0] ro_ddr_delay;
    reg ro_ddr_pending_read;
    reg [DATA_WIDTH-1:0] ro_ddr_pending_data;

    always_ff @(posedge clk) begin
        ro_ext_read_valid <= 0;
        if (reset) begin
            ro_ext_ready <= 1;
            ro_ddr_pending_read <= 0;
        end else begin
            if (ro_ext_write) begin
                ro_ddr_mem[ro_ext_address[11:4]] <= ro_ext_write_data;
                ro_ext_ready <= 0;
            end
            if (ro_ext_read) begin
                ro_ddr_pending_data <= ro_ddr_mem[ro_ext_address[11:4]];
                ro_ddr_pending_read <= 1;
                ro_ddr_delay <= 2;
                ro_ext_ready <= 0;
            end else if (ro_ddr_pending_read) begin
                if (ro_ddr_delay == 0) begin
                    ro_ext_read_data <= ro_ddr_pending_data;
                    ro_ext_read_valid <= 1;
                    ro_ddr_pending_read <= 0;
                    ro_ext_ready <= 1;
                end else
                    ro_ddr_delay <= ro_ddr_delay - 1;
            end else if (!ro_ext_ready)
                ro_ext_ready <= 1;
        end
    end

    MEMORY_CONTROLLER_V2 #(
        .DEPTH(DEPTH), .WAYS(1), .READ_ONLY(1),
        .DATA_WIDTH(DATA_WIDTH), .MASK_WIDTH(MASK_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)
    ) dut_ro (
        .clk(clk), .reset(reset),
        .bus_address(ro_bus_address), .bus_read(ro_bus_read), .bus_write(ro_bus_write),
        .bus_write_data(ro_bus_write_data), .bus_write_mask(ro_bus_write_mask),
        .bus_ready(ro_bus_ready), .bus_read_data(ro_bus_read_data), .bus_read_valid(ro_bus_read_valid),
        .external_address(ro_ext_address), .external_read(ro_ext_read), .external_write(ro_ext_write),
        .external_write_data(ro_ext_write_data), .external_write_mask(ro_ext_write_mask),
        .external_ready(ro_ext_ready), .external_read_data(ro_ext_read_data), .external_read_valid(ro_ext_read_valid)
    );

    // =========================================================
    // DUT_2W: WAYS=2 (2-way set-associative)
    // =========================================================
    reg  [ADDR_WIDTH-1:0]  w2_bus_address;
    reg                    w2_bus_read, w2_bus_write;
    reg  [DATA_WIDTH-1:0]  w2_bus_write_data;
    reg  [MASK_WIDTH-1:0]  w2_bus_write_mask;
    wire                   w2_bus_ready;
    wire [DATA_WIDTH-1:0]  w2_bus_read_data;
    wire                   w2_bus_read_valid;

    wire [ADDR_WIDTH-1:0]  w2_ext_address;
    wire                   w2_ext_read, w2_ext_write;
    wire [DATA_WIDTH-1:0]  w2_ext_write_data;
    wire [MASK_WIDTH-1:0]  w2_ext_write_mask;
    reg                    w2_ext_ready;
    reg  [DATA_WIDTH-1:0]  w2_ext_read_data;
    reg                    w2_ext_read_valid;

    reg [DATA_WIDTH-1:0] w2_ddr_mem [0:255];
    reg [3:0] w2_ddr_delay;
    reg w2_ddr_pending_read;
    reg [DATA_WIDTH-1:0] w2_ddr_pending_data;

    always_ff @(posedge clk) begin
        w2_ext_read_valid <= 0;
        if (reset) begin
            w2_ext_ready <= 1;
            w2_ddr_pending_read <= 0;
        end else begin
            if (w2_ext_write) begin
                w2_ddr_mem[w2_ext_address[11:4]] <= w2_ext_write_data;
                w2_ext_ready <= 0;
            end
            if (w2_ext_read) begin
                w2_ddr_pending_data <= w2_ddr_mem[w2_ext_address[11:4]];
                w2_ddr_pending_read <= 1;
                w2_ddr_delay <= 2;
                w2_ext_ready <= 0;
            end else if (w2_ddr_pending_read) begin
                if (w2_ddr_delay == 0) begin
                    w2_ext_read_data <= w2_ddr_pending_data;
                    w2_ext_read_valid <= 1;
                    w2_ddr_pending_read <= 0;
                    w2_ext_ready <= 1;
                end else
                    w2_ddr_delay <= w2_ddr_delay - 1;
            end else if (!w2_ext_ready)
                w2_ext_ready <= 1;
        end
    end

    MEMORY_CONTROLLER_V2 #(
        .DEPTH(DEPTH), .WAYS(2), .READ_ONLY(0),
        .DATA_WIDTH(DATA_WIDTH), .MASK_WIDTH(MASK_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)
    ) dut_2w (
        .clk(clk), .reset(reset),
        .bus_address(w2_bus_address), .bus_read(w2_bus_read), .bus_write(w2_bus_write),
        .bus_write_data(w2_bus_write_data), .bus_write_mask(w2_bus_write_mask),
        .bus_ready(w2_bus_ready), .bus_read_data(w2_bus_read_data), .bus_read_valid(w2_bus_read_valid),
        .external_address(w2_ext_address), .external_read(w2_ext_read), .external_write(w2_ext_write),
        .external_write_data(w2_ext_write_data), .external_write_mask(w2_ext_write_mask),
        .external_ready(w2_ext_ready), .external_read_data(w2_ext_read_data), .external_read_valid(w2_ext_read_valid)
    );

    // =========================================================
    // Helper tasks (D-cache)
    // =========================================================

    task automatic do_read(
        input [ADDR_WIDTH-1:0]  addr,
        input [DATA_WIDTH-1:0]  expected,
        input string            label
    );
        begin int cnt = 0;
            while (!bus_ready && cnt < 100) begin @(posedge clk); cnt++; end
            assert(cnt < 100) else begin $display("TIMEOUT [%s] ready", label); errors++; end
        end
        @(posedge clk); #1;
        bus_address = addr; bus_read = 1;
        @(posedge clk); #1;
        bus_read = 0;
        begin int cnt = 0;
            while (!bus_read_valid && cnt < 100) begin @(posedge clk); cnt++; end
            assert(cnt < 100) else begin $display("TIMEOUT [%s] valid", label); errors++; end
        end
        assert(bus_read_data == expected) else begin
            $display("FAIL [%s]: addr=%h expected=%h got=%h", label, addr, expected, bus_read_data);
            errors++;
        end
    endtask

    task automatic do_write(
        input [ADDR_WIDTH-1:0]  addr,
        input [MASK_WIDTH-1:0]  mask_val,
        input [DATA_WIDTH-1:0]  data,
        input string            label
    );
        begin int cnt = 0;
            while (!bus_ready && cnt < 100) begin @(posedge clk); cnt++; end
            assert(cnt < 100) else begin $display("TIMEOUT [%s] ready", label); errors++; end
        end
        @(posedge clk); #1;
        bus_address = addr; bus_write = 1;
        bus_write_mask = mask_val; bus_write_data = data;
        @(posedge clk); #1;
        bus_write = 0;
        begin int cnt = 0;
            while (!bus_ready && cnt < 100) begin @(posedge clk); cnt++; end
            assert(cnt < 100) else begin $display("TIMEOUT [%s] done", label); errors++; end
        end
    endtask

    // RO helpers
    task automatic ro_do_read(
        input [ADDR_WIDTH-1:0]  addr,
        input [DATA_WIDTH-1:0]  expected,
        input string            label
    );
        begin int cnt = 0;
            while (!ro_bus_ready && cnt < 100) begin @(posedge clk); cnt++; end
        end
        @(posedge clk); #1;
        ro_bus_address = addr; ro_bus_read = 1;
        @(posedge clk); #1;
        ro_bus_read = 0;
        begin int cnt = 0;
            while (!ro_bus_read_valid && cnt < 100) begin @(posedge clk); cnt++; end
            assert(cnt < 100) else begin $display("TIMEOUT [%s]", label); errors++; end
        end
        assert(ro_bus_read_data == expected) else begin
            $display("FAIL [%s]: expected=%h got=%h", label, expected, ro_bus_read_data);
            errors++;
        end
    endtask

    // 2-way helpers
    task automatic w2_do_read(
        input [ADDR_WIDTH-1:0]  addr,
        input [DATA_WIDTH-1:0]  expected,
        input string            label
    );
        begin int cnt = 0;
            while (!w2_bus_ready && cnt < 100) begin @(posedge clk); cnt++; end
        end
        @(posedge clk); #1;
        w2_bus_address = addr; w2_bus_read = 1;
        @(posedge clk); #1;
        w2_bus_read = 0;
        begin int cnt = 0;
            while (!w2_bus_read_valid && cnt < 100) begin @(posedge clk); cnt++; end
            assert(cnt < 100) else begin $display("TIMEOUT [%s]", label); errors++; end
        end
        assert(w2_bus_read_data == expected) else begin
            $display("FAIL [%s]: expected=%h got=%h", label, expected, w2_bus_read_data);
            errors++;
        end
    endtask

    task automatic w2_do_write(
        input [ADDR_WIDTH-1:0]  addr,
        input [MASK_WIDTH-1:0]  mask_val,
        input [DATA_WIDTH-1:0]  data,
        input string            label
    );
        begin int cnt = 0;
            while (!w2_bus_ready && cnt < 100) begin @(posedge clk); cnt++; end
        end
        @(posedge clk); #1;
        w2_bus_address = addr; w2_bus_write = 1;
        w2_bus_write_mask = mask_val; w2_bus_write_data = data;
        @(posedge clk); #1;
        w2_bus_write = 0;
        begin int cnt = 0;
            while (!w2_bus_ready && cnt < 100) begin @(posedge clk); cnt++; end
        end
    endtask

    // =========================================================
    // Tests
    // =========================================================
    initial begin
        $dumpfile("MEMORY_CONTROLLER_V2_TEST.vcd");
        $dumpvars(0, MEMORY_CONTROLLER_V2_TEST);

        errors = 0;
        bus_address = 0; bus_read = 0; bus_write = 0;
        bus_write_data = 0; bus_write_mask = 0;
        ro_bus_address = 0; ro_bus_read = 0; ro_bus_write = 0;
        ro_bus_write_data = 0; ro_bus_write_mask = 0;
        w2_bus_address = 0; w2_bus_read = 0; w2_bus_write = 0;
        w2_bus_write_data = 0; w2_bus_write_mask = 0;

        // Pre-fill DDR (all three)
        ddr_mem[0]  = {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA};
        ddr_mem[1]  = {32'h44444444,  32'h33333333,  32'h22222222,  32'h11111111};
        ddr_mem[2]  = {32'h88888888,  32'h77777777,  32'h66666666,  32'h55555555};

        ro_ddr_mem[0] = {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA};
        ro_ddr_mem[1] = {32'h44444444,  32'h33333333,  32'h22222222,  32'h11111111};
        ro_ddr_mem[4] = {32'hF4F4F4F4,  32'hF3F3F3F3,  32'hF2F2F2F2,  32'hF1F1F1F1};

        w2_ddr_mem[0]  = {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA};
        w2_ddr_mem[8]  = {32'h44444444,  32'h33333333,  32'h22222222,  32'h11111111};
        w2_ddr_mem[16] = {32'hF4F4F4F4,  32'hF3F3F3F3,  32'hF2F2F2F2,  32'hF1F1F1F1};
        w2_ddr_mem[1]  = {32'h88888888,  32'h77777777,  32'h66666666,  32'h55555555};
        w2_ddr_mem[9]  = {32'hEEEEEEEE, 32'hDDDDDDDD, 32'hCCCCCCCC, 32'hBBBBBBBB};
        w2_ddr_mem[17] = {32'h12121212, 32'h34343434, 32'h56565656, 32'h78787878};

        reset = 1;
        @(posedge clk); @(posedge clk);
        #1; reset = 0;
        @(posedge clk);

        // === D-cache WAYS=1 ===
        $display("T1: Read miss");
        do_read(32'h0000_0000, {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T1");

        $display("T2: Output buffer hit");
        do_read(32'h0000_0000, {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T2");

        $display("T3: Second line");
        do_read(32'h0000_0010, {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111}, "T3");

        $display("T4: Cache hit");
        do_read(32'h0000_0000, {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T4");

        $display("T5: Write hit");
        do_write(32'h0000_0000, 16'h000F, {96'b0, 32'hDEADBEEF}, "T5");
        do_read(32'h0000_0000, {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hDEADBEEF}, "T5-rb");

        $display("T6: Partial mask");
        do_write(32'h0000_0000, 16'h0002, {96'b0, 32'h0000FF00}, "T6");
        do_read(32'h0000_0000, {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hDEADFFEF}, "T6-rb");

        $display("T7: Stream read (addr bit 29)");
        do_read(32'h2000_0020, {32'h88888888, 32'h77777777, 32'h66666666, 32'h55555555}, "T7");

        $display("T8: Dirty eviction");
        ddr_mem[16] = {32'hF4F4F4F4, 32'hF3F3F3F3, 32'hF2F2F2F2, 32'hF1F1F1F1};
        do_read(32'h0000_0100, {32'hF4F4F4F4, 32'hF3F3F3F3, 32'hF2F2F2F2, 32'hF1F1F1F1}, "T8");
        begin int cnt = 0;
            while (!bus_ready && cnt < 100) begin @(posedge clk); cnt++; end
        end
        @(posedge clk); @(posedge clk); @(posedge clk);
        assert(ddr_mem[0] == {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hDEADFFEF}) else begin
            $display("FAIL [T8-wb]: writeback mismatch, got %h", ddr_mem[0]);
            errors++;
        end

        $display("T9: Write miss");
        ddr_mem[3] = {32'hA4A4A4A4, 32'hA3A3A3A3, 32'hA2A2A2A2, 32'hA1A1A1A1};
        do_write(32'h0000_0030, 16'h000F, {96'b0, 32'hCAFECAFE}, "T9");
        do_read(32'h0000_0030, {32'hA4A4A4A4, 32'hA3A3A3A3, 32'hA2A2A2A2, 32'hCAFECAFE}, "T9-rb");

        $display("T10: Output buffer invalidation");
        do_read(32'h0000_0010, {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111}, "T10-pre");
        do_write(32'h0000_0010, 16'h000F, {96'b0, 32'hBEEFBEEF}, "T10-wr");
        do_read(32'h0000_0010, {32'h44444444, 32'h33333333, 32'h22222222, 32'hBEEFBEEF}, "T10-rb");

        $display("T11: Stream no pollution");
        do_read(32'h2000_0020, {32'h88888888, 32'h77777777, 32'h66666666, 32'h55555555}, "T11-str");
        do_read(32'h0000_0020, {32'h88888888, 32'h77777777, 32'h66666666, 32'h55555555}, "T11-norm");

        // === I-cache READ_ONLY=1 ===
        $display("T12: RO — read miss");
        ro_do_read(32'h0000_0000, {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T12");

        $display("T13: RO — output buffer hit");
        ro_do_read(32'h0000_0000, {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T13");

        $display("T14: RO — cache hit");
        ro_do_read(32'h0000_0010, {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111}, "T14-miss");
        ro_do_read(32'h0000_0000, {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T14-hit");

        $display("T15: RO — write ignored");
        @(posedge clk); #1;
        ro_bus_address = 32'h0000_0000; ro_bus_write = 1;
        ro_bus_write_mask = 16'h000F; ro_bus_write_data = {96'b0, 32'hDEADDEAD};
        @(posedge clk); #1;
        ro_bus_write = 0;
        @(posedge clk); @(posedge clk);
        ro_do_read(32'h0000_0000, {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T15-rb");

        $display("T16: RO — stream ignored (always caches)");
        ro_do_read(32'h2000_0040,  // bit 29 = 1 (stream), but READ_ONLY ignores
                   {32'hF4F4F4F4, 32'hF3F3F3F3, 32'hF2F2F2F2, 32'hF1F1F1F1}, "T16-str");
        ro_do_read(32'h0000_0040,  // same addr without stream — should be cached
                   {32'hF4F4F4F4, 32'hF3F3F3F3, 32'hF2F2F2F2, 32'hF1F1F1F1}, "T16-hit");

        $display("T17: RO — no dirty eviction");
        ro_do_read(32'h0000_0000, {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T17-fill");
        ro_ddr_mem[16] = {32'hBBBBBBBB, 32'hAAAAAAAA, 32'h99999999, 32'h88888888};
        ro_do_read(32'h0000_0100, {32'hBBBBBBBB, 32'hAAAAAAAA, 32'h99999999, 32'h88888888}, "T17-conf");
        assert(ro_ddr_mem[0] == {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}) else begin
            $display("FAIL [T17]: RO should never write to DDR");
            errors++;
        end

        // === 2-way set-associative ===
        $display("T18: 2W — two lines same set");
        w2_do_read(32'h0000_0000, {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T18-A");
        w2_do_read(32'h0000_0080, {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111}, "T18-B");
        w2_do_read(32'h0000_0000, {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T18-A-hit");

        $display("T19: 2W — third evicts LRU");
        w2_do_read(32'h0000_0100, {32'hF4F4F4F4, 32'hF3F3F3F3, 32'hF2F2F2F2, 32'hF1F1F1F1}, "T19-C");
        w2_do_read(32'h0000_0000, {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T19-A");
        w2_do_read(32'h0000_0080, {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111}, "T19-B-evicted");

        $display("T20: 2W — write hit");
        w2_do_read(32'h0000_0010, {32'h88888888, 32'h77777777, 32'h66666666, 32'h55555555}, "T20-fill");
        w2_do_write(32'h0000_0010, 16'h000F, {96'b0, 32'hCAFE0000}, "T20-wr");
        w2_do_read(32'h0000_0010, {32'h88888888, 32'h77777777, 32'h66666666, 32'hCAFE0000}, "T20-rb");

        $display("T21: 2W — dirty eviction");
        w2_do_read(32'h0000_0090, {32'hEEEEEEEE, 32'hDDDDDDDD, 32'hCCCCCCCC, 32'hBBBBBBBB}, "T21-fill");
        w2_do_read(32'h0000_0110, {32'h12121212, 32'h34343434, 32'h56565656, 32'h78787878}, "T21-evict");
        begin int cnt = 0;
            while (!w2_bus_ready && cnt < 100) begin @(posedge clk); cnt++; end
        end
        @(posedge clk); @(posedge clk); @(posedge clk);
        assert(w2_ddr_mem[1] == {32'h88888888, 32'h77777777, 32'h66666666, 32'hCAFE0000}) else begin
            $display("FAIL [T21-wb]: writeback mismatch, got %h", w2_ddr_mem[1]);
            errors++;
        end

        $display("T22: 2W — output buffer");
        w2_do_read(32'h0000_0010, {32'h88888888, 32'h77777777, 32'h66666666, 32'hCAFE0000}, "T22-fill");
        w2_do_read(32'h0000_0010, {32'h88888888, 32'h77777777, 32'h66666666, 32'hCAFE0000}, "T22-ob");

        // === Summary ===
        @(posedge clk); @(posedge clk);
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("FAILED: %0d errors", errors);
        $finish;
    end

endmodule
