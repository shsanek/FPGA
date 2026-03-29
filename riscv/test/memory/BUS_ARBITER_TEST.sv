module BUS_ARBITER_TEST;

    localparam DATA_WIDTH = 128;
    localparam MASK_WIDTH = DATA_WIDTH / 8;
    localparam ADDR_WIDTH = 32;

    reg clk;
    initial begin clk = 0; forever #5 clk = ~clk; end
    reg reset;
    int errors;

    // === Port 0 ===
    reg  [ADDR_WIDTH-1:0]  p0_address;
    reg                    p0_read, p0_write;
    reg  [DATA_WIDTH-1:0]  p0_write_data;
    reg  [MASK_WIDTH-1:0]  p0_write_mask;
    wire                   p0_ready;
    wire [DATA_WIDTH-1:0]  p0_read_data;
    wire                   p0_read_valid;

    // === Port 1 ===
    reg  [ADDR_WIDTH-1:0]  p1_address;
    reg                    p1_read, p1_write;
    reg  [DATA_WIDTH-1:0]  p1_write_data;
    reg  [MASK_WIDTH-1:0]  p1_write_mask;
    wire                   p1_ready;
    wire [DATA_WIDTH-1:0]  p1_read_data;
    wire                   p1_read_valid;

    // === Downstream ===
    wire [ADDR_WIDTH-1:0]  bus_address;
    wire                   bus_read, bus_write;
    wire [DATA_WIDTH-1:0]  bus_write_data;
    wire [MASK_WIDTH-1:0]  bus_write_mask;
    reg                    bus_ready;
    reg  [DATA_WIDTH-1:0]  bus_read_data;
    reg                    bus_read_valid;

    BUS_ARBITER #(
        .DATA_WIDTH(DATA_WIDTH), .MASK_WIDTH(MASK_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (.*);

    // === Mock downstream: 3-cycle read, 1-cycle write ===
    reg [3:0] mock_delay;
    reg mock_busy;
    reg [DATA_WIDTH-1:0] mock_response;

    always_ff @(posedge clk) begin
        bus_read_valid <= 0;
        if (reset) begin
            bus_ready <= 1;
            mock_busy <= 0;
        end else begin
            if (bus_write && bus_ready) begin
                bus_ready <= 0;
            end
            if (bus_read && bus_ready) begin
                // Response = address-based pattern
                mock_response <= {bus_address, bus_address, bus_address, bus_address};
                mock_busy <= 1;
                mock_delay <= 2;
                bus_ready <= 0;
            end else if (mock_busy) begin
                if (mock_delay == 0) begin
                    bus_read_data <= mock_response;
                    bus_read_valid <= 1;
                    mock_busy <= 0;
                    bus_ready <= 1;
                end else
                    mock_delay <= mock_delay - 1;
            end else if (!bus_ready)
                bus_ready <= 1;
        end
    end

    // === Helpers ===

    task automatic send_p0_read(input [ADDR_WIDTH-1:0] addr);
        while (!p0_ready) @(posedge clk);
        @(posedge clk); #1;
        p0_address = addr; p0_read = 1;
        @(posedge clk); #1;
        p0_read = 0;
    endtask

    task automatic wait_p0_read_valid(input int timeout, input string label);
        begin
            int cnt = 0;
            while (!p0_read_valid && cnt < timeout) begin @(posedge clk); cnt++; end
            assert(cnt < timeout) else begin $display("TIMEOUT [%s]", label); errors++; end
        end
    endtask

    task automatic send_p1_read(input [ADDR_WIDTH-1:0] addr);
        while (!p1_ready) @(posedge clk);
        @(posedge clk); #1;
        p1_address = addr; p1_read = 1;
        @(posedge clk); #1;
        p1_read = 0;
    endtask

    task automatic wait_p1_read_valid(input int timeout, input string label);
        begin
            int cnt = 0;
            while (!p1_read_valid && cnt < timeout) begin @(posedge clk); cnt++; end
            assert(cnt < timeout) else begin $display("TIMEOUT [%s]", label); errors++; end
        end
    endtask

    // === Tests ===
    initial begin
        $dumpfile("BUS_ARBITER_TEST.vcd");
        $dumpvars(0, BUS_ARBITER_TEST);

        errors = 0;
        p0_address = 0; p0_read = 0; p0_write = 0;
        p0_write_data = 0; p0_write_mask = 0;
        p1_address = 0; p1_read = 0; p1_write = 0;
        p1_write_data = 0; p1_write_mask = 0;

        reset = 1;
        @(posedge clk); @(posedge clk);
        #1; reset = 0;
        @(posedge clk);

        // =========================================================
        $display("T1: Port0 read");
        send_p0_read(32'h0000_1000);
        wait_p0_read_valid(50, "T1");
        assert(p0_read_data == {4{32'h0000_1000}}) else begin
            $display("FAIL [T1]: data mismatch"); errors++;
        end

        // =========================================================
        $display("T2: Port1 read");
        send_p1_read(32'h0000_2000);
        wait_p1_read_valid(50, "T2");
        assert(p1_read_data == {4{32'h0000_2000}}) else begin
            $display("FAIL [T2]: data mismatch"); errors++;
        end

        // =========================================================
        $display("T3: Port0 write");
        while (!p0_ready) @(posedge clk);
        @(posedge clk); #1;
        p0_address = 32'h0000_3000;
        p0_write = 1;
        p0_write_data = 128'hDEADBEEF;
        p0_write_mask = 16'h000F;
        @(posedge clk); #1;
        p0_write = 0;
        // Wait for ready (write done)
        while (!p0_ready) @(posedge clk);
        $display("  write done");

        // =========================================================
        $display("T4: Simultaneous send — p0 wins, p1 latched");
        // Both send at the same time
        while (!p0_ready || !p1_ready) @(posedge clk);
        @(posedge clk); #1;
        p0_address = 32'h0000_4000; p0_read = 1;
        p1_address = 32'h0000_5000; p1_read = 1;
        @(posedge clk); #1;
        p0_read = 0; p1_read = 0;

        // Port0 should respond first
        wait_p0_read_valid(50, "T4-p0");
        assert(p0_read_data == {4{32'h0000_4000}}) else begin
            $display("FAIL [T4-p0]: data mismatch"); errors++;
        end
        // Port1 should respond after (from latch)
        wait_p1_read_valid(50, "T4-p1");
        assert(p1_read_data == {4{32'h0000_5000}}) else begin
            $display("FAIL [T4-p1]: data mismatch"); errors++;
        end

        // =========================================================
        $display("T5: Port1 sends while arbiter busy with port0");
        // Start p0 read
        send_p0_read(32'h0000_6000);
        // While busy, p1 sends — gets latched
        @(posedge clk); #1;
        p1_address = 32'h0000_7000; p1_read = 1;
        @(posedge clk); #1;
        p1_read = 0;
        // p0 response
        wait_p0_read_valid(50, "T5-p0");
        assert(p0_read_data == {4{32'h0000_6000}}) else begin
            $display("FAIL [T5-p0]: data mismatch"); errors++;
        end
        // p1 response (from latch, served after p0)
        wait_p1_read_valid(50, "T5-p1");
        assert(p1_read_data == {4{32'h0000_7000}}) else begin
            $display("FAIL [T5-p1]: data mismatch"); errors++;
        end

        // =========================================================
        // =========================================================
        $display("T6: Latch not lost — p1 survives full p0 transaction");
        // p0 does full read-write-read cycle, p1 waits in latch
        send_p0_read(32'hAAAA_0000);
        @(posedge clk); #1;
        p1_address = 32'hBBBB_0000; p1_read = 1;
        @(posedge clk); #1;
        p1_read = 0;
        wait_p0_read_valid(50, "T7-p0");
        // p1 still latched, now served
        wait_p1_read_valid(50, "T7-p1");
        assert(p1_read_data == {4{32'hBBBB_0000}}) else begin
            $display("FAIL [T6-p1]: data mismatch"); errors++;
        end

        // =========================================================
        @(posedge clk); @(posedge clk);
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("FAILED: %0d errors", errors);
        $finish;
    end

endmodule
