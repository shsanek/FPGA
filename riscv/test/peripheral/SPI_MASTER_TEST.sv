module SPI_MASTER_TEST();
    reg clk = 0;
    reg reset = 1;
    reg [7:0] data;
    reg trigger = 0;
    reg [15:0] divider = 16'd1; // быстрый для теста: полупериод = 2 такта clk

    wire busy, done, sck, mosi;
    reg  miso_r = 1;  // MISO input (simulated slave response)
    wire [7:0] rx_data;

    SPI_MASTER #(.DATA_WIDTH(8)) dut (
        .clk(clk), .reset(reset),
        .data(data), .trigger(trigger), .divider(divider),
        .busy(busy), .done(done),
        .sck(sck), .mosi(mosi),
        .miso(miso_r), .rx_data(rx_data)
    );

    always #5 clk = ~clk;

    integer errors = 0;

    // Захват MOSI на rising edge SCK (как делает slave)
    reg [7:0] captured;
    integer cap_idx;
    reg sck_prev;

    // Simulated MISO: shift out miso_pattern on falling edge SCK
    reg [7:0] miso_pattern;
    integer miso_idx;

    always @(posedge clk) begin
        sck_prev <= sck;
        if (sck && !sck_prev) begin
            // Rising edge SCK — sample MOSI
            captured[7 - cap_idx] <= mosi;
            cap_idx <= cap_idx + 1;
        end
        if (!sck && sck_prev) begin
            // Falling edge SCK — shift out next MISO bit
            miso_idx <= miso_idx + 1;
            if (miso_idx < 7)
                miso_r <= miso_pattern[6 - miso_idx];
        end
    end

    task send_byte(input [7:0] tx_val, input [7:0] miso_val);
        begin
            cap_idx      = 0;
            captured     = 8'h00;
            miso_idx     = 0;
            miso_pattern = miso_val;
            miso_r       = miso_val[7]; // MSB ready before first rising edge
            data         = tx_val;
            @(posedge clk);
            trigger = 1;
            @(posedge clk);
            trigger = 0;
            while (!done) @(posedge clk);
            @(posedge clk); // settle
        end
    endtask

    initial begin
        $dumpfile("SPI_MASTER_TEST.vcd");
        $dumpvars(0, SPI_MASTER_TEST);

        #20;
        reset = 0;
        #20;

        // ---- Test 1: Send 0xA5, MISO=0xFF ----
        $display("Test 1: TX=0xA5, MISO=0xFF");
        send_byte(8'hA5, 8'hFF);
        if (captured !== 8'hA5) begin
            $display("  FAIL: MOSI captured=0x%02X, expected=0xA5", captured);
            errors = errors + 1;
        end else if (rx_data !== 8'hFF) begin
            $display("  FAIL: rx_data=0x%02X, expected=0xFF", rx_data);
            errors = errors + 1;
        end else begin
            $display("  PASS: MOSI=0x%02X, MISO rx=0x%02X", captured, rx_data);
        end

        #20;

        // ---- Test 2: Send 0x00, MISO=0xA5 ----
        $display("Test 2: TX=0x00, MISO=0xA5");
        send_byte(8'h00, 8'hA5);
        if (captured !== 8'h00) begin
            $display("  FAIL: MOSI captured=0x%02X", captured);
            errors = errors + 1;
        end else if (rx_data !== 8'hA5) begin
            $display("  FAIL: rx_data=0x%02X, expected=0xA5", rx_data);
            errors = errors + 1;
        end else begin
            $display("  PASS: MOSI=0x%02X, MISO rx=0x%02X", captured, rx_data);
        end

        #20;

        // ---- Test 3: Full duplex 0x3C / 0xC3 ----
        $display("Test 3: TX=0x3C, MISO=0xC3");
        send_byte(8'h3C, 8'hC3);
        if (captured !== 8'h3C || rx_data !== 8'hC3) begin
            $display("  FAIL: MOSI=0x%02X(exp 0x3C), rx=0x%02X(exp 0xC3)", captured, rx_data);
            errors = errors + 1;
        end else begin
            $display("  PASS: MOSI=0x%02X, MISO rx=0x%02X", captured, rx_data);
        end

        #20;

        // ---- Test 4: MISO=0x00 ----
        $display("Test 4: TX=0xFF, MISO=0x00");
        send_byte(8'hFF, 8'h00);
        if (rx_data !== 8'h00) begin
            $display("  FAIL: rx_data=0x%02X, expected=0x00", rx_data);
            errors = errors + 1;
        end else begin
            $display("  PASS: rx_data=0x%02X", rx_data);
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

        // ---- Test 6: busy=0 when idle ----
        $display("Test 6: busy=0 when idle");
        if (busy !== 1'b0) begin
            $display("  FAIL: busy should be 0");
            errors = errors + 1;
        end else begin
            $display("  PASS: busy=0");
        end

        #20;

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TESTS FAILED", errors);

        $finish;
    end

endmodule
