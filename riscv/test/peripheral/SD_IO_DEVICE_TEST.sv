module SD_IO_DEVICE_TEST();
    reg clk = 0;
    reg reset = 1;
    reg [27:0] address;
    reg read_trigger = 0, write_trigger = 0;
    reg [31:0] write_value;
    reg [3:0] mask = 4'hF;

    wire [31:0] read_value;
    wire controller_ready;
    wire sd_sck, sd_mosi, sd_cs_n;
    reg  sd_miso = 1;
    reg  sd_cd_n = 1; // no card

    SD_IO_DEVICE dut (
        .clk(clk), .reset(reset),
        .address(address),
        .read_trigger(read_trigger),
        .write_trigger(write_trigger),
        .write_value(write_value),
        .mask(mask),
        .read_value(read_value),
        .controller_ready(controller_ready),
        .sd_sck(sd_sck),
        .sd_mosi(sd_mosi),
        .sd_miso(sd_miso),
        .sd_cs_n(sd_cs_n),
        .sd_cd_n(sd_cd_n)
    );

    always #5 clk = ~clk;
    integer errors = 0;

    // MISO: shift out pattern on falling edge SCK
    reg [7:0] miso_pattern;
    integer miso_idx;
    reg sck_prev;

    // Capture MOSI on rising edge
    reg [7:0] mosi_captured;
    integer mosi_idx;

    always @(posedge clk) begin
        sck_prev <= sd_sck;
        if (sd_sck && !sck_prev) begin
            mosi_captured[7 - mosi_idx] <= sd_mosi;
            mosi_idx <= mosi_idx + 1;
        end
        if (!sd_sck && sck_prev) begin
            miso_idx <= miso_idx + 1;
            if (miso_idx < 7)
                sd_miso <= miso_pattern[6 - miso_idx];
        end
    end

    task write_reg(input [1:0] sel, input [31:0] val);
        begin
            address     = {24'b0, sel, 2'b0};
            write_value = val;
            @(posedge clk);
            write_trigger = 1;
            @(posedge clk);
            write_trigger = 0;
        end
    endtask

    task read_reg(input [1:0] sel, output [31:0] val);
        begin
            address = {24'b0, sel, 2'b0};
            @(posedge clk);
            read_trigger = 1;
            @(posedge clk);
            read_trigger = 0;
            val = read_value;
        end
    endtask

    task wait_ready;
        begin
            while (!controller_ready) @(posedge clk);
        end
    endtask

    task spi_xfer(input [7:0] tx, input [7:0] miso_val);
        begin
            mosi_idx     = 0;
            mosi_captured = 8'h00;
            miso_idx     = 0;
            miso_pattern = miso_val;
            sd_miso      = miso_val[7];
            sck_prev     = 0;
            @(posedge clk);
            write_reg(2'd0, {24'b0, tx});
            // Wait for SPI to start (FIFO → SPI has 2-cycle latency)
            while (!dut.spi_busy) @(posedge clk);
            // Wait for SPI to finish
            while (dut.spi_active) @(posedge clk);
            @(posedge clk);
        end
    endtask

    reg [31:0] rd_val;

    initial begin
        $dumpfile("SD_IO_DEVICE_TEST.vcd");
        $dumpvars(0, SD_IO_DEVICE_TEST);

        #20; reset = 0; #20;

        // ---- T1: Reset state ----
        $display("T1: Reset state");
        if (sd_cs_n !== 1'b1 || controller_ready !== 1'b1) begin
            $display("  FAIL: cs_n=%b ready=%b", sd_cs_n, controller_ready);
            errors = errors + 1;
        end else $display("  PASS: CS inactive, ready");

        // ---- T2: Card detect ----
        $display("T2: Card detect (no card)");
        read_reg(2'd2, rd_val);
        if (rd_val[2] !== 1'b0) begin
            $display("  FAIL: card_detect=%b (expected 0)", rd_val[2]);
            errors = errors + 1;
        end else $display("  PASS: no card");

        sd_cd_n = 0; // insert card
        read_reg(2'd2, rd_val);
        $display("T2b: Card inserted");
        if (rd_val[2] !== 1'b1) begin
            $display("  FAIL: card_detect=%b (expected 1)", rd_val[2]);
            errors = errors + 1;
        end else $display("  PASS: card detected");

        // ---- T3: Set CS active ----
        $display("T3: CS active");
        write_reg(2'd1, 32'h1);
        #10;
        if (sd_cs_n !== 1'b0) begin
            $display("  FAIL: cs_n=%b", sd_cs_n);
            errors = errors + 1;
        end else $display("  PASS: cs_n=0");

        // ---- T4: Full-duplex SPI: send 0x40, receive 0xFF ----
        $display("T4: SPI TX=0x40 RX=0xFF");
        spi_xfer(8'h40, 8'hFF);
        if (mosi_captured !== 8'h40) begin
            $display("  FAIL: MOSI=0x%02X exp 0x40", mosi_captured);
            errors = errors + 1;
        end else begin
            read_reg(2'd0, rd_val);
            if (rd_val[7:0] !== 8'hFF) begin
                $display("  FAIL: rx=0x%02X exp 0xFF", rd_val[7:0]);
                errors = errors + 1;
            end else $display("  PASS: MOSI=0x40, rx=0xFF");
        end

        // ---- T5: Send 0xFF, receive 0x01 (R1 idle) ----
        $display("T5: SPI TX=0xFF RX=0x01");
        spi_xfer(8'hFF, 8'h01);
        read_reg(2'd0, rd_val);
        if (rd_val[7:0] !== 8'h01) begin
            $display("  FAIL: rx=0x%02X exp 0x01", rd_val[7:0]);
            errors = errors + 1;
        end else $display("  PASS: rx=0x01 (R1 idle)");

        // ---- T6: Divider ----
        $display("T6: Divider register");
        read_reg(2'd3, rd_val);
        if (rd_val[15:0] !== 16'd101) begin
            $display("  FAIL: default divider=%0d", rd_val[15:0]);
            errors = errors + 1;
        end else $display("  PASS: default divider=101 (~400kHz)");

        write_reg(2'd3, 32'd7);
        read_reg(2'd3, rd_val);
        if (rd_val[15:0] !== 16'd7) begin
            $display("  FAIL: divider=%0d exp 7", rd_val[15:0]);
            errors = errors + 1;
        end else $display("  PASS: divider=7 (~5MHz)");

        #50;
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d TESTS FAILED", errors);
        $finish;
    end
endmodule
