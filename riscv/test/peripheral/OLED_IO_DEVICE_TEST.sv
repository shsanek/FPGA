module OLED_IO_DEVICE_TEST();
    reg clk = 0;
    reg reset = 1;
    reg [27:0] address;
    reg read_trigger = 0, write_trigger = 0;
    reg [31:0] write_value;
    reg [3:0] mask = 4'hF;

    wire [31:0] read_value;
    wire controller_ready;
    wire oled_sck, oled_mosi, oled_cs_n, oled_dc, oled_res_n, oled_vccen, oled_pmoden;

    OLED_IO_DEVICE dut (
        .clk(clk), .reset(reset),
        .address(address),
        .read_trigger(read_trigger),
        .write_trigger(write_trigger),
        .write_value(write_value),
        .mask(mask),
        .read_value(read_value),
        .controller_ready(controller_ready),
        .oled_sck(oled_sck),
        .oled_mosi(oled_mosi),
        .oled_cs_n(oled_cs_n),
        .oled_dc(oled_dc),
        .oled_res_n(oled_res_n),
        .oled_vccen(oled_vccen),
        .oled_pmoden(oled_pmoden)
    );

    always #5 clk = ~clk;
    integer errors = 0;

    // Захват MOSI по rising edge SCK
    reg [7:0] captured;
    integer cap_idx;
    reg sck_prev;

    always @(posedge clk) begin
        sck_prev <= oled_sck;
        if (oled_sck && !sck_prev) begin
            captured[7 - cap_idx] <= oled_mosi;
            cap_idx <= cap_idx + 1;
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

    reg [31:0] rd_val;

    initial begin
        $dumpfile("OLED_IO_DEVICE_TEST.vcd");
        $dumpvars(0, OLED_IO_DEVICE_TEST);

        #20;
        reset = 0;
        #20;

        // ---- Test 1: Reset state ----
        $display("Test 1: Reset state");
        if (oled_cs_n !== 1'b1) begin
            $display("  FAIL: CS_N should be 1 (inactive)");
            errors = errors + 1;
        end
        if (oled_res_n !== 1'b1) begin
            $display("  FAIL: RES_N should be 1 (inactive)");
            errors = errors + 1;
        end
        if (oled_pmoden !== 1'b0) begin
            $display("  FAIL: PMODEN should be 0");
            errors = errors + 1;
        end
        if (controller_ready !== 1'b1) begin
            $display("  FAIL: controller_ready should be 1");
            errors = errors + 1;
        end
        $display("  CS_N=%b RES_N=%b PMODEN=%b ready=%b", oled_cs_n, oled_res_n, oled_pmoden, controller_ready);

        // ---- Test 2: Write CONTROL — enable PMODEN, VCCEN, assert CS ----
        $display("Test 2: Write CONTROL = 0x19 (PMODEN=1, VCCEN=1, CS=1)");
        write_reg(2'd1, 32'h19); // bits: PMODEN=1, VCCEN=1, RES=0, DC=0, CS=1
        #10;
        if (oled_cs_n !== 1'b0) begin
            $display("  FAIL: CS_N should be 0 (active)");
            errors = errors + 1;
        end
        if (oled_pmoden !== 1'b1) begin
            $display("  FAIL: PMODEN should be 1");
            errors = errors + 1;
        end
        if (oled_vccen !== 1'b1) begin
            $display("  FAIL: VCCEN should be 1");
            errors = errors + 1;
        end
        $display("  CS_N=%b DC=%b RES_N=%b VCCEN=%b PMODEN=%b", oled_cs_n, oled_dc, oled_res_n, oled_vccen, oled_pmoden);

        // ---- Test 3: Read CONTROL back ----
        $display("Test 3: Read CONTROL");
        read_reg(2'd1, rd_val);
        if (rd_val[4:0] !== 5'h19) begin
            $display("  FAIL: read=0x%02X, expected=0x19", rd_val[4:0]);
            errors = errors + 1;
        end else begin
            $display("  PASS: control=0x%02X", rd_val[4:0]);
        end

        // ---- Test 4: Send SPI byte 0xAE (Display OFF command) ----
        $display("Test 4: SPI send 0xAE");
        cap_idx  = 0;
        captured = 8'h00;
        @(posedge clk); // settle cap_idx
        write_reg(2'd0, 32'hAE);
        // Должен стать busy
        #10;
        if (controller_ready !== 1'b0) begin
            $display("  WARN: controller_ready should be 0 during SPI");
        end
        wait_ready;
        @(posedge clk);
        if (captured !== 8'hAE) begin
            $display("  FAIL: captured=0x%02X, expected=0xAE", captured);
            errors = errors + 1;
        end else begin
            $display("  PASS: SPI captured=0x%02X", captured);
        end

        // ---- Test 5: Read STATUS ----
        $display("Test 5: Read STATUS (idle)");
        read_reg(2'd2, rd_val);
        if (rd_val[1] !== 1'b0) begin
            $display("  FAIL: spi_busy should be 0");
            errors = errors + 1;
        end else begin
            $display("  PASS: spi_busy=0");
        end

        // ---- Test 6: Set D/C=1 (data mode), send pixel data ----
        $display("Test 6: D/C=1, send 0xFF");
        write_reg(2'd1, 32'h1B); // PMODEN=1, VCCEN=1, RES=0, DC=1, CS=1
        #10;
        if (oled_dc !== 1'b1) begin
            $display("  FAIL: DC should be 1");
            errors = errors + 1;
        end
        cap_idx  = 0;
        captured = 8'h00;
        sck_prev = 0;
        @(posedge clk);
        @(posedge clk); // settle cap_idx
        write_reg(2'd0, 32'hFF);
        @(posedge clk); // let SPI start
        @(posedge clk);
        wait_ready;
        @(posedge clk);
        if (captured !== 8'hFF) begin
            $display("  FAIL: captured=0x%02X, expected=0xFF", captured);
            errors = errors + 1;
        end else begin
            $display("  PASS: SPI captured=0x%02X with DC=1", captured);
        end

        // ---- Test 7: Write/read DIVIDER ----
        $display("Test 7: DIVIDER register");
        write_reg(2'd3, 32'd20);
        read_reg(2'd3, rd_val);
        if (rd_val[15:0] !== 16'd20) begin
            $display("  FAIL: divider=%0d, expected=20", rd_val[15:0]);
            errors = errors + 1;
        end else begin
            $display("  PASS: divider=%0d", rd_val[15:0]);
        end

        #50;

        // ---- Summary ----
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TESTS FAILED", errors);

        $finish;
    end

endmodule
