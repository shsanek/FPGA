module SPI_MASTER_TEST();
    reg clk = 0;
    reg reset = 1;
    reg [7:0] data;
    reg trigger = 0;
    reg [15:0] divider = 16'd1; // быстрый для теста: полупериод = 2 такта clk

    wire busy, done, sck, mosi;

    SPI_MASTER #(.DATA_WIDTH(8)) dut (
        .clk(clk), .reset(reset),
        .data(data), .trigger(trigger), .divider(divider),
        .busy(busy), .done(done),
        .sck(sck), .mosi(mosi)
    );

    always #5 clk = ~clk;

    integer errors = 0;

    // Захват MOSI на rising edge SCK (как делает slave)
    reg [7:0] captured;
    integer cap_idx;
    reg sck_prev;

    always @(posedge clk) begin
        sck_prev <= sck;
        if (sck && !sck_prev) begin
            // Rising edge SCK — sample MOSI
            captured[7 - cap_idx] <= mosi;
            cap_idx <= cap_idx + 1;
        end
    end

    task send_byte(input [7:0] val);
        begin
            cap_idx  = 0;
            captured = 8'h00;
            data     = val;
            @(posedge clk);
            trigger = 1;
            @(posedge clk);
            trigger = 0;
            // Ждём done
            while (!done) @(posedge clk);
            @(posedge clk); // один такт на settle
        end
    endtask

    initial begin
        $dumpfile("SPI_MASTER_TEST.vcd");
        $dumpvars(0, SPI_MASTER_TEST);

        // Reset
        #20;
        reset = 0;
        #20;

        // ---- Test 1: Send 0xA5 ----
        $display("Test 1: Send 0xA5");
        send_byte(8'hA5);
        if (captured !== 8'hA5) begin
            $display("  FAIL: captured=0x%02X, expected=0xA5", captured);
            errors = errors + 1;
        end else begin
            $display("  PASS: captured=0x%02X", captured);
        end

        #20;

        // ---- Test 2: Send 0x3C ----
        $display("Test 2: Send 0x3C");
        send_byte(8'h3C);
        if (captured !== 8'h3C) begin
            $display("  FAIL: captured=0x%02X, expected=0x3C", captured);
            errors = errors + 1;
        end else begin
            $display("  PASS: captured=0x%02X", captured);
        end

        #20;

        // ---- Test 3: Send 0xFF ----
        $display("Test 3: Send 0xFF");
        send_byte(8'hFF);
        if (captured !== 8'hFF) begin
            $display("  FAIL: captured=0x%02X, expected=0xFF", captured);
            errors = errors + 1;
        end else begin
            $display("  PASS: captured=0x%02X", captured);
        end

        #20;

        // ---- Test 4: Send 0x00 ----
        $display("Test 4: Send 0x00");
        send_byte(8'h00);
        if (captured !== 8'h00) begin
            $display("  FAIL: captured=0x%02X, expected=0x00", captured);
            errors = errors + 1;
        end else begin
            $display("  PASS: captured=0x%02X", captured);
        end

        #20;

        // ---- Test 5: SCK idle low ----
        $display("Test 5: SCK idle state");
        if (sck !== 1'b0) begin
            $display("  FAIL: SCK not idle low");
            errors = errors + 1;
        end else begin
            $display("  PASS: SCK idle low");
        end

        // ---- Test 6: busy/done signals ----
        $display("Test 6: busy=0 when idle");
        if (busy !== 1'b0) begin
            $display("  FAIL: busy should be 0");
            errors = errors + 1;
        end else begin
            $display("  PASS: busy=0");
        end

        #20;

        // ---- Summary ----
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TESTS FAILED", errors);

        $finish;
    end

endmodule
