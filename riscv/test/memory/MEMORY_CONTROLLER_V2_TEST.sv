module MEMORY_CONTROLLER_V2_TEST;

    localparam DEPTH        = 16;
    localparam CHUNK_PART   = 128;
    localparam MASK_SIZE    = CHUNK_PART / 8;
    localparam ADDRESS_SIZE = 28;

    reg clk;
    initial begin clk = 0; forever #5 clk = ~clk; end

    // =========================================================
    // DUT: READ_ONLY=0 (D-cache)
    // =========================================================
    reg  [ADDRESS_SIZE-1:0] address;
    reg  [1:0]              command;
    reg                     read_stream;
    reg  [MASK_SIZE-1:0]    write_mask;
    reg  [CHUNK_PART-1:0]   write_value;
    wire                    controller_ready;
    wire [CHUNK_PART-1:0]   read_value;
    wire                    read_value_ready;
    wire                    write_done;

    wire [ADDRESS_SIZE-1:0] ram_address;
    wire                    ram_read_trigger;
    wire                    ram_write_trigger;
    wire [CHUNK_PART-1:0]   ram_write_value;

    reg                     ram_controller_ready;
    reg  [CHUNK_PART-1:0]   ram_read_value;
    reg                     ram_read_value_ready;

    // DDR mock
    reg [CHUNK_PART-1:0] ddr_mem [0:255];
    reg [3:0] ddr_delay;
    reg ddr_pending_read;
    reg [CHUNK_PART-1:0] ddr_pending_data;

    always_ff @(posedge clk) begin
        ram_read_value_ready <= 0;
        if (ram_write_trigger) begin
            ddr_mem[ram_address[11:4]] <= ram_write_value;
            ram_controller_ready <= 0;
        end
        if (ram_read_trigger) begin
            ddr_pending_data <= ddr_mem[ram_address[11:4]];
            ddr_pending_read <= 1;
            ddr_delay <= 2;
            ram_controller_ready <= 0;
        end else if (ddr_pending_read) begin
            if (ddr_delay == 0) begin
                ram_read_value <= ddr_pending_data;
                ram_read_value_ready <= 1;
                ddr_pending_read <= 0;
                ram_controller_ready <= 1;
            end else begin
                ddr_delay <= ddr_delay - 1;
            end
        end else if (!ram_controller_ready) begin
            ram_controller_ready <= 1;
        end
    end

    reg reset;
    int errors;

    MEMORY_CONTROLLER_V2 #(
        .DEPTH        (DEPTH),
        .READ_ONLY    (0),
        .CHUNK_PART   (CHUNK_PART),
        .MASK_SIZE    (MASK_SIZE),
        .ADDRESS_SIZE (ADDRESS_SIZE)
    ) dut (
        .clk                  (clk),
        .reset                (reset),
        .address              (address),
        .command              (command),
        .read_stream          (read_stream),
        .write_mask           (write_mask),
        .write_value          (write_value),
        .controller_ready     (controller_ready),
        .read_value           (read_value),
        .read_value_ready     (read_value_ready),
        .write_done           (write_done),
        .ram_controller_ready (ram_controller_ready),
        .ram_address          (ram_address),
        .ram_read_trigger     (ram_read_trigger),
        .ram_read_value       (ram_read_value),
        .ram_read_value_ready (ram_read_value_ready),
        .ram_write_trigger    (ram_write_trigger),
        .ram_write_value      (ram_write_value)
    );

    // =========================================================
    // DUT_RO: READ_ONLY=1 (I-cache)
    // =========================================================
    reg  [ADDRESS_SIZE-1:0] ro_address;
    reg  [1:0]              ro_command;
    reg                     ro_read_stream;
    reg  [MASK_SIZE-1:0]    ro_write_mask;
    reg  [CHUNK_PART-1:0]   ro_write_value;
    wire                    ro_controller_ready;
    wire [CHUNK_PART-1:0]   ro_read_value;
    wire                    ro_read_value_ready;
    wire                    ro_write_done;

    wire [ADDRESS_SIZE-1:0] ro_ram_address;
    wire                    ro_ram_read_trigger;
    wire                    ro_ram_write_trigger;
    wire [CHUNK_PART-1:0]   ro_ram_write_value;

    reg                     ro_ram_controller_ready;
    reg  [CHUNK_PART-1:0]   ro_ram_read_value;
    reg                     ro_ram_read_value_ready;

    // DDR mock for RO
    reg [CHUNK_PART-1:0] ro_ddr_mem [0:255];
    reg [3:0] ro_ddr_delay;
    reg ro_ddr_pending_read;
    reg [CHUNK_PART-1:0] ro_ddr_pending_data;

    always_ff @(posedge clk) begin
        ro_ram_read_value_ready <= 0;
        if (ro_ram_write_trigger) begin
            ro_ddr_mem[ro_ram_address[11:4]] <= ro_ram_write_value;
            ro_ram_controller_ready <= 0;
        end
        if (ro_ram_read_trigger) begin
            ro_ddr_pending_data <= ro_ddr_mem[ro_ram_address[11:4]];
            ro_ddr_pending_read <= 1;
            ro_ddr_delay <= 2;
            ro_ram_controller_ready <= 0;
        end else if (ro_ddr_pending_read) begin
            if (ro_ddr_delay == 0) begin
                ro_ram_read_value <= ro_ddr_pending_data;
                ro_ram_read_value_ready <= 1;
                ro_ddr_pending_read <= 0;
                ro_ram_controller_ready <= 1;
            end else begin
                ro_ddr_delay <= ro_ddr_delay - 1;
            end
        end else if (!ro_ram_controller_ready) begin
            ro_ram_controller_ready <= 1;
        end
    end

    MEMORY_CONTROLLER_V2 #(
        .DEPTH        (DEPTH),
        .READ_ONLY    (1),
        .CHUNK_PART   (CHUNK_PART),
        .MASK_SIZE    (MASK_SIZE),
        .ADDRESS_SIZE (ADDRESS_SIZE)
    ) dut_ro (
        .clk                  (clk),
        .reset                (reset),
        .address              (ro_address),
        .command              (ro_command),
        .read_stream          (ro_read_stream),
        .write_mask           (ro_write_mask),
        .write_value          (ro_write_value),
        .controller_ready     (ro_controller_ready),
        .read_value           (ro_read_value),
        .read_value_ready     (ro_read_value_ready),
        .write_done           (ro_write_done),
        .ram_controller_ready (ro_ram_controller_ready),
        .ram_address          (ro_ram_address),
        .ram_read_trigger     (ro_ram_read_trigger),
        .ram_read_value       (ro_ram_read_value),
        .ram_read_value_ready (ro_ram_read_value_ready),
        .ram_write_trigger    (ro_ram_write_trigger),
        .ram_write_value      (ro_ram_write_value)
    );

    // =========================================================
    // Helper tasks (D-cache DUT)
    // =========================================================

    task automatic wait_ready(input int timeout);
        int cnt;
        cnt = 0;
        while (!controller_ready && cnt < timeout) begin
            @(posedge clk);
            cnt++;
        end
        assert(cnt < timeout) else begin
            $display("TIMEOUT waiting for controller_ready");
            errors++;
        end
    endtask

    task automatic wait_read_done(input int timeout);
        int cnt;
        cnt = 0;
        while (!read_value_ready && cnt < timeout) begin
            @(posedge clk);
            cnt++;
        end
        assert(cnt < timeout) else begin
            $display("TIMEOUT waiting for read_value_ready");
            errors++;
        end
    endtask

    task automatic wait_write_done_sig(input int timeout);
        int cnt;
        cnt = 0;
        while (!write_done && cnt < timeout) begin
            @(posedge clk);
            cnt++;
        end
        assert(cnt < timeout) else begin
            $display("TIMEOUT waiting for write_done");
            errors++;
        end
    endtask

    task automatic do_read(
        input [ADDRESS_SIZE-1:0] addr,
        input                    stream,
        input [CHUNK_PART-1:0]   expected,
        input string             label
    );
        wait_ready(100);
        @(posedge clk); #1;
        address     = addr;
        command     = 2'b01;
        read_stream = stream;
        @(posedge clk); #1;
        command = 2'b00;
        wait_read_done(100);
        assert(read_value == expected) else begin
            $display("FAIL [%s]: addr=%h expected=%h got=%h", label, addr, expected, read_value);
            errors++;
        end
    endtask

    task automatic do_write(
        input [ADDRESS_SIZE-1:0] addr,
        input [MASK_SIZE-1:0]    mask_val,
        input [CHUNK_PART-1:0]   data,
        input string             label
    );
        wait_ready(100);
        @(posedge clk); #1;
        address     = addr;
        command     = 2'b10;
        read_stream = 0;
        write_mask  = mask_val;
        write_value = data;
        @(posedge clk); #1;
        command = 2'b00;
        wait_write_done_sig(100);
    endtask

    // =========================================================
    // Helper tasks (I-cache DUT_RO)
    // =========================================================

    task automatic ro_wait_ready(input int timeout);
        int cnt;
        cnt = 0;
        while (!ro_controller_ready && cnt < timeout) begin
            @(posedge clk);
            cnt++;
        end
        assert(cnt < timeout) else begin
            $display("TIMEOUT waiting for ro_controller_ready");
            errors++;
        end
    endtask

    task automatic ro_do_read(
        input [ADDRESS_SIZE-1:0] addr,
        input [CHUNK_PART-1:0]   expected,
        input string             label
    );
        ro_wait_ready(100);
        @(posedge clk); #1;
        ro_address     = addr;
        ro_command     = 2'b01;
        ro_read_stream = 0;
        @(posedge clk); #1;
        ro_command = 2'b00;
        begin
            int cnt;
            cnt = 0;
            while (!ro_read_value_ready && cnt < 100) begin
                @(posedge clk);
                cnt++;
            end
            assert(cnt < 100) else begin
                $display("TIMEOUT [%s] waiting for ro_read_value_ready", label);
                errors++;
            end
        end
        assert(ro_read_value == expected) else begin
            $display("FAIL [%s]: addr=%h expected=%h got=%h", label, addr, expected, ro_read_value);
            errors++;
        end
    endtask

    // =========================================================
    // Tests
    // =========================================================
    initial begin
        $dumpfile("MEMORY_CONTROLLER_V2_TEST.vcd");
        $dumpvars(0, MEMORY_CONTROLLER_V2_TEST);

        errors = 0;
        address = 0; command = 0; read_stream = 0;
        write_mask = 0; write_value = 0;
        ram_controller_ready = 1; ram_read_value = 0;
        ram_read_value_ready = 0; ddr_pending_read = 0;

        ro_address = 0; ro_command = 0; ro_read_stream = 0;
        ro_write_mask = 0; ro_write_value = 0;
        ro_ram_controller_ready = 1; ro_ram_read_value = 0;
        ro_ram_read_value_ready = 0; ro_ddr_pending_read = 0;

        // Pre-fill DDR (both)
        ddr_mem[0]  = {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA};
        ddr_mem[1]  = {32'h44444444,  32'h33333333,  32'h22222222,  32'h11111111};
        ddr_mem[2]  = {32'h88888888,  32'h77777777,  32'h66666666,  32'h55555555};

        ro_ddr_mem[0] = {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA};
        ro_ddr_mem[1] = {32'h44444444,  32'h33333333,  32'h22222222,  32'h11111111};
        ro_ddr_mem[4] = {32'hF4F4F4F4,  32'hF3F3F3F3,  32'hF2F2F2F2,  32'hF1F1F1F1};

        reset = 1;
        @(posedge clk); @(posedge clk);
        #1; reset = 0;
        @(posedge clk);

        // =========================================================
        // D-cache tests (READ_ONLY=0)
        // =========================================================

        $display("T1: Read miss (cold cache)");
        do_read(28'h0000000, 0,
                {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T1");

        $display("T2: Output buffer hit");
        do_read(28'h0000000, 0,
                {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T2");

        $display("T3: Second line miss");
        do_read(28'h0000010, 0,
                {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111}, "T3");

        $display("T4: Cache hit");
        do_read(28'h0000000, 0,
                {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T4");

        $display("T5: Write hit");
        do_write(28'h0000000, 16'h000F, {96'b0, 32'hDEADBEEF}, "T5");
        do_read(28'h0000000, 0,
                {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hDEADBEEF}, "T5-rb");

        $display("T6: Partial byte mask");
        do_write(28'h0000000, 16'h0002, {96'b0, 32'h0000FF00}, "T6");
        do_read(28'h0000000, 0,
                {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hDEADFFEF}, "T6-rb");

        $display("T7: Stream read");
        do_read(28'h0000020, 1,
                {32'h88888888, 32'h77777777, 32'h66666666, 32'h55555555}, "T7");

        $display("T8: Dirty eviction");
        ddr_mem[16] = {32'hF4F4F4F4, 32'hF3F3F3F3, 32'hF2F2F2F2, 32'hF1F1F1F1};
        do_read(28'h0000100, 0,
                {32'hF4F4F4F4, 32'hF3F3F3F3, 32'hF2F2F2F2, 32'hF1F1F1F1}, "T8");
        wait_ready(100);
        @(posedge clk); @(posedge clk); @(posedge clk);
        assert(ddr_mem[0] == {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hDEADFFEF}) else begin
            $display("FAIL [T8-wb]: dirty writeback mismatch, got %h", ddr_mem[0]);
            errors++;
        end

        $display("T9: Write miss");
        ddr_mem[3] = {32'hA4A4A4A4, 32'hA3A3A3A3, 32'hA2A2A2A2, 32'hA1A1A1A1};
        do_write(28'h0000030, 16'h000F, {96'b0, 32'hCAFECAFE}, "T9");
        do_read(28'h0000030, 0,
                {32'hA4A4A4A4, 32'hA3A3A3A3, 32'hA2A2A2A2, 32'hCAFECAFE}, "T9-rb");

        $display("T10: Output buffer invalidation");
        do_read(28'h0000010, 0,
                {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111}, "T10-pre");
        do_write(28'h0000010, 16'h000F, {96'b0, 32'hBEEFBEEF}, "T10-wr");
        do_read(28'h0000010, 0,
                {32'h44444444, 32'h33333333, 32'h22222222, 32'hBEEFBEEF}, "T10-rb");

        $display("T11: Stream no pollution");
        do_read(28'h0000020, 1,
                {32'h88888888, 32'h77777777, 32'h66666666, 32'h55555555}, "T11-str");
        do_read(28'h0000020, 0,
                {32'h88888888, 32'h77777777, 32'h66666666, 32'h55555555}, "T11-norm");

        // =========================================================
        // I-cache tests (READ_ONLY=1)
        // =========================================================

        $display("T12: RO — read miss");
        ro_do_read(28'h0000000,
                   {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T12");

        $display("T13: RO — output buffer hit");
        ro_do_read(28'h0000000,
                   {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T13");

        $display("T14: RO — cache hit (different line)");
        ro_do_read(28'h0000010,
                   {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111}, "T14-miss");
        ro_do_read(28'h0000000,
                   {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T14-hit");

        $display("T15: RO — write ignored");
        ro_wait_ready(100);
        @(posedge clk); #1;
        ro_address     = 28'h0000000;
        ro_command     = 2'b10;
        ro_write_mask  = 16'h000F;
        ro_write_value = {96'b0, 32'hDEADDEAD};
        @(posedge clk); #1;
        ro_command = 2'b00;
        // Write command is ignored for READ_ONLY — controller stays ready
        @(posedge clk); @(posedge clk);
        // Read back — should be unchanged
        ro_do_read(28'h0000000,
                   {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T15-rb");

        $display("T16: RO — stream flag ignored (always saves to cache)");
        ro_wait_ready(100);
        @(posedge clk); #1;
        ro_address     = 28'h0000040;
        ro_command     = 2'b01;
        ro_read_stream = 1;  // should be ignored for READ_ONLY
        @(posedge clk); #1;
        ro_command = 2'b00;
        begin
            int cnt;
            cnt = 0;
            while (!ro_read_value_ready && cnt < 100) begin
                @(posedge clk);
                cnt++;
            end
        end
        // Read again without stream — should be cache hit (was saved despite stream=1)
        ro_do_read(28'h0000040,
                   {32'hF4F4F4F4, 32'hF3F3F3F3, 32'hF2F2F2F2, 32'hF1F1F1F1}, "T16-hit");

        $display("T17: RO — no dirty eviction on conflict");
        // Fill idx=0 with tag=0, then read idx=0 with tag=1
        // Should NOT trigger ram_write_trigger (no dirty in READ_ONLY)
        ro_do_read(28'h0000000,
                   {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}, "T17-fill");
        // Conflicting tag, same index
        ro_ddr_mem[16] = {32'hBBBBBBBB, 32'hAAAAAAAA, 32'h99999999, 32'h88888888};
        ro_do_read(28'h0000100,
                   {32'hBBBBBBBB, 32'hAAAAAAAA, 32'h99999999, 32'h88888888}, "T17-conflict");
        // Verify no DDR write happened (READ_ONLY never writes)
        assert(ro_ddr_mem[0] == {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA}) else begin
            $display("FAIL [T17]: RO should never write to DDR, ddr_mem[0] changed");
            errors++;
        end

        // =========================================================
        // Summary
        // =========================================================
        @(posedge clk); @(posedge clk);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILED: %0d errors", errors);

        $finish;
    end

endmodule
