module MEMORY_MUX_TEST;

    localparam CHUNK_PART   = 128;
    localparam MASK_SIZE    = CHUNK_PART / 8;
    localparam ADDRESS_SIZE = 28;

    reg clk;
    initial begin clk = 0; forever #5 clk = ~clk; end

    reg reset;
    int errors;

    // === Port 0 ===
    reg  [ADDRESS_SIZE-1:0] p0_address;
    reg  [1:0]              p0_command;
    reg                     p0_read_stream;
    reg  [MASK_SIZE-1:0]    p0_write_mask;
    reg  [CHUNK_PART-1:0]   p0_write_value;
    wire                    p0_ready;
    wire [CHUNK_PART-1:0]   p0_read_value;
    wire                    p0_read_value_ready;

    // === Port 1 ===
    reg  [ADDRESS_SIZE-1:0] p1_address;
    reg  [1:0]              p1_command;
    reg                     p1_read_stream;
    reg  [MASK_SIZE-1:0]    p1_write_mask;
    reg  [CHUNK_PART-1:0]   p1_write_value;
    wire                    p1_ready;
    wire [CHUNK_PART-1:0]   p1_read_value;
    wire                    p1_read_value_ready;

    // === Downstream (mock MEMORY_CONTROLLER) ===
    wire [ADDRESS_SIZE-1:0] mem_address;
    wire [1:0]              mem_command;
    wire                    mem_read_stream;
    wire [MASK_SIZE-1:0]    mem_write_mask;
    wire [CHUNK_PART-1:0]   mem_write_value;
    reg                     mem_ready;
    reg  [CHUNK_PART-1:0]   mem_read_value;
    reg                     mem_read_value_ready;

    // === Snoop ===
    wire                    snoop_valid;
    wire [ADDRESS_SIZE-1:0] snoop_address;
    wire [MASK_SIZE-1:0]    snoop_mask;
    wire [CHUNK_PART-1:0]   snoop_value;

    MEMORY_MUX #(
        .CHUNK_PART   (CHUNK_PART),
        .MASK_SIZE    (MASK_SIZE),
        .ADDRESS_SIZE (ADDRESS_SIZE)
    ) dut (
        .clk                 (clk),
        .reset               (reset),
        .p0_address          (p0_address),
        .p0_command          (p0_command),
        .p0_read_stream      (p0_read_stream),
        .p0_write_mask       (p0_write_mask),
        .p0_write_value      (p0_write_value),
        .p0_ready            (p0_ready),
        .p0_read_value       (p0_read_value),
        .p0_read_value_ready (p0_read_value_ready),
        .p1_address          (p1_address),
        .p1_command          (p1_command),
        .p1_read_stream      (p1_read_stream),
        .p1_write_mask       (p1_write_mask),
        .p1_write_value      (p1_write_value),
        .p1_ready            (p1_ready),
        .p1_read_value       (p1_read_value),
        .p1_read_value_ready (p1_read_value_ready),
        .mem_address         (mem_address),
        .mem_command         (mem_command),
        .mem_read_stream     (mem_read_stream),
        .mem_write_mask      (mem_write_mask),
        .mem_write_value     (mem_write_value),
        .mem_ready           (mem_ready),
        .mem_read_value      (mem_read_value),
        .mem_read_value_ready(mem_read_value_ready),
        .snoop_valid         (snoop_valid),
        .snoop_address       (snoop_address),
        .snoop_mask          (snoop_mask),
        .snoop_value         (snoop_value)
    );

    // === Mock MEMORY_CONTROLLER behavior ===
    // Responds to read after 3 cycles, write completes in 1 cycle
    reg [3:0] mc_delay;
    reg mc_busy;
    reg [1:0] mc_command_latched;
    reg [CHUNK_PART-1:0] mc_response_data;

    always_ff @(posedge clk) begin
        mem_read_value_ready <= 0;

        if (reset) begin
            mc_busy  <= 0;
            mem_ready <= 1;
        end else if (mem_command != 0 && mem_ready) begin
            mc_command_latched <= mem_command;
            mc_busy <= 1;
            mem_ready <= 0;
            if (mem_command == 2'b01) begin
                // Read: respond with address-based pattern
                mc_response_data <= {mem_address[27:0], 4'b0000, mem_address[27:0], 4'b0000,
                                     mem_address[27:0], 4'b0000, mem_address[27:0], 4'b0000};
                mc_delay <= 2;
            end else begin
                // Write: complete in 1 cycle
                mc_delay <= 0;
            end
        end else if (mc_busy) begin
            if (mc_delay == 0) begin
                if (mc_command_latched == 2'b01) begin
                    mem_read_value <= mc_response_data;
                    mem_read_value_ready <= 1;
                end
                mc_busy <= 0;
                mem_ready <= 1;
            end else begin
                mc_delay <= mc_delay - 1;
            end
        end
    end

    // === Helper tasks ===

    task automatic p0_read(
        input [ADDRESS_SIZE-1:0] addr,
        input string label
    );
        while (!p0_ready) @(posedge clk);
        @(posedge clk); #1;
        p0_address = addr;
        p0_command = 2'b01;
        p0_read_stream = 0;
        @(posedge clk); #1;
        p0_command = 2'b00;
        begin
            int cnt; cnt = 0;
            while (!p0_read_value_ready && cnt < 50) begin @(posedge clk); cnt++; end
            assert(cnt < 50) else begin $display("TIMEOUT [%s]", label); errors++; end
        end
    endtask

    task automatic p0_write(
        input [ADDRESS_SIZE-1:0] addr,
        input [MASK_SIZE-1:0]    mask_val,
        input [CHUNK_PART-1:0]   data,
        input string label
    );
        while (!p0_ready) @(posedge clk);
        @(posedge clk); #1;
        p0_address = addr;
        p0_command = 2'b10;
        p0_read_stream = 0;
        p0_write_mask = mask_val;
        p0_write_value = data;
        @(posedge clk); #1;
        p0_command = 2'b00;
        // Wait for ready (write done)
        while (!p0_ready) @(posedge clk);
    endtask

    task automatic p1_read(
        input [ADDRESS_SIZE-1:0] addr,
        input string label
    );
        while (!p1_ready) @(posedge clk);
        @(posedge clk); #1;
        p1_address = addr;
        p1_command = 2'b01;
        p1_read_stream = 1;
        @(posedge clk); #1;
        p1_command = 2'b00;
        begin
            int cnt; cnt = 0;
            while (!p1_read_value_ready && cnt < 50) begin @(posedge clk); cnt++; end
            assert(cnt < 50) else begin $display("TIMEOUT [%s]", label); errors++; end
        end
    endtask

    // === Tests ===
    initial begin
        $dumpfile("MEMORY_MUX_TEST.vcd");
        $dumpvars(0, MEMORY_MUX_TEST);

        errors = 0;
        p0_address = 0; p0_command = 0; p0_read_stream = 0;
        p0_write_mask = 0; p0_write_value = 0;
        p1_address = 0; p1_command = 0; p1_read_stream = 0;
        p1_write_mask = 0; p1_write_value = 0;
        mem_ready = 1; mem_read_value = 0; mem_read_value_ready = 0;
        mc_busy = 0;

        reset = 1;
        @(posedge clk); @(posedge clk);
        #1; reset = 0;
        @(posedge clk);

        // =========================================================
        // T1: Port0 read
        // =========================================================
        $display("T1: Port0 read");
        p0_read(28'h0000100, "T1");
        // Verify downstream saw the command
        // (read_value has address-based pattern)
        assert(p0_read_value[31:0] == {28'h0000100, 4'b0000}) else begin
            $display("FAIL [T1]: p0 read data mismatch, got %h", p0_read_value[31:0]);
            errors++;
        end

        // =========================================================
        // T2: Port1 read
        // =========================================================
        $display("T2: Port1 read");
        p1_read(28'h0000200, "T2");
        assert(p1_read_value[31:0] == {28'h0000200, 4'b0000}) else begin
            $display("FAIL [T2]: p1 read data mismatch, got %h", p1_read_value[31:0]);
            errors++;
        end

        // =========================================================
        // T3: Port0 read_stream forwarded correctly
        // =========================================================
        $display("T3: read_stream forwarded");
        while (!p1_ready) @(posedge clk);
        @(posedge clk); #1;
        p1_address = 28'h0000300;
        p1_command = 2'b01;
        p1_read_stream = 1;
        @(posedge clk); #1;
        // Check mem_read_stream was 1
        assert(mem_read_stream == 1) else begin
            $display("FAIL [T3]: mem_read_stream should be 1");
            errors++;
        end
        p1_command = 2'b00;
        while (!p1_read_value_ready) @(posedge clk);

        // =========================================================
        // T4: Port0 write + snoop
        // =========================================================
        $display("T4: Port0 write + snoop");
        p0_write(28'h0000400, 16'h000F, {96'b0, 32'hCAFECAFE}, "T4");
        // Snoop should have fired
        // (can't check after the fact since it's a pulse — verified via VCD)

        // =========================================================
        // T5: Simultaneous send — port0 wins, port1 queued
        // =========================================================
        $display("T5: Simultaneous send (race)");
        // Both ports send at the same time
        while (!p0_ready || !p1_ready) @(posedge clk);
        @(posedge clk); #1;
        p0_address = 28'h0000500;
        p0_command = 2'b01;
        p0_read_stream = 0;
        p1_address = 28'h0000600;
        p1_command = 2'b01;
        p1_read_stream = 1;
        @(posedge clk); #1;
        p0_command = 2'b00;
        p1_command = 2'b00;
        // Port0 should be served first
        begin
            int cnt; cnt = 0;
            while (!p0_read_value_ready && cnt < 50) begin @(posedge clk); cnt++; end
            assert(cnt < 50) else begin $display("TIMEOUT [T5-p0]"); errors++; end
        end
        assert(p0_read_value[31:0] == {28'h0000500, 4'b0000}) else begin
            $display("FAIL [T5-p0]: wrong data, got %h", p0_read_value[31:0]);
            errors++;
        end
        // Port1 should be served next (from queue)
        begin
            int cnt; cnt = 0;
            while (!p1_read_value_ready && cnt < 50) begin @(posedge clk); cnt++; end
            assert(cnt < 50) else begin $display("TIMEOUT [T5-p1]"); errors++; end
        end
        assert(p1_read_value[31:0] == {28'h0000600, 4'b0000}) else begin
            $display("FAIL [T5-p1]: wrong data, got %h", p1_read_value[31:0]);
            errors++;
        end

        // =========================================================
        // T6: Port0 priority — port1 waits
        // =========================================================
        $display("T6: Port0 priority");
        // Send port0 read, then immediately port1
        p0_read(28'h0000700, "T6-p0");
        p1_read(28'h0000800, "T6-p1");
        assert(p1_read_value[31:0] == {28'h0000800, 4'b0000}) else begin
            $display("FAIL [T6]: p1 data mismatch");
            errors++;
        end

        // =========================================================
        // T7: Snoop fires on write with correct data
        // =========================================================
        $display("T7: Snoop data check");
        while (!p0_ready) @(posedge clk);
        @(posedge clk); #1;
        p0_address = 28'hABCD000;
        p0_command = 2'b10;
        p0_write_mask = 16'hFF00;
        p0_write_value = {64'hDEAD_BEEF_CAFE_BABE, 64'h0};
        @(posedge clk);
        // Check snoop signals (they were set on the posedge we just passed)
        #1;
        assert(snoop_valid == 1) else begin
            $display("FAIL [T7]: snoop_valid should be 1");
            errors++;
        end
        assert(snoop_address == 28'hABCD000) else begin
            $display("FAIL [T7]: snoop_address mismatch");
            errors++;
        end
        assert(snoop_mask == 16'hFF00) else begin
            $display("FAIL [T7]: snoop_mask mismatch");
            errors++;
        end
        p0_command = 2'b00;
        while (!p0_ready) @(posedge clk);

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
