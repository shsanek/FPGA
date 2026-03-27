// FLASH_LOADER_TEST — тест аппаратного загрузчика из SPI flash.
//
// Mock SPI flash: при получении cmd 0x03 + 3 байта адреса,
// последовательно отдаёт байты из внутреннего массива test_data.
module FLASH_LOADER_TEST();
    reg clk = 0;
    reg reset = 1;
    reg ddr_ready = 0;

    // Bus
    wire        bus_request;
    wire [27:0] mc_address;
    wire        mc_write_trigger;
    wire [31:0] mc_write_data;
    wire [3:0]  mc_write_mask;
    reg         mc_ready;
    wire        set_pc;
    wire [31:0] new_pc;
    wire        active;

    // SPI
    wire flash_cs_n, flash_sck, flash_mosi;
    reg  flash_miso;

    FLASH_LOADER #(
        .FLASH_OFFSET(24'h300000),
        .SPI_DIVIDER(1)           // быстрый SPI для теста
    ) dut (
        .clk(clk), .reset(reset),
        .ddr_ready(ddr_ready),
        .bus_request(bus_request),
        .bus_granted(bus_request),  // auto-grant
        .mc_address(mc_address),
        .mc_write_trigger(mc_write_trigger),
        .mc_write_data(mc_write_data),
        .mc_write_mask(mc_write_mask),
        .mc_ready(mc_ready),
        .set_pc(set_pc),
        .new_pc(new_pc),
        .flash_cs_n(flash_cs_n),
        .flash_sck(flash_sck),
        .flash_mosi(flash_mosi),
        .flash_miso(flash_miso),
        .active(active)
    );

    initial forever #5 clk = ~clk;

    // ---------------------------------------------------------------
    // Mock SPI Flash
    // ---------------------------------------------------------------
    // Test data: header (magic + size + load_addr) + payload
    // Magic:     0xB007C0DE (LE: DE C0 07 B0)
    // Size:      8 bytes    (LE: 08 00 00 00)
    // Load_addr: 0x07F00000 (LE: 00 00 F0 07)
    // Payload:   0x12345678 0xDEADBEEF (LE bytes)
    localparam FLASH_SIZE = 20;
    logic [7:0] flash_mem [0:FLASH_SIZE-1];
    initial begin
        // Header: magic
        flash_mem[0]  = 8'hDE;
        flash_mem[1]  = 8'hC0;
        flash_mem[2]  = 8'h07;
        flash_mem[3]  = 8'hB0;
        // Header: size = 8
        flash_mem[4]  = 8'h08;
        flash_mem[5]  = 8'h00;
        flash_mem[6]  = 8'h00;
        flash_mem[7]  = 8'h00;
        // Header: load_addr = 0x07F00000
        flash_mem[8]  = 8'h00;
        flash_mem[9]  = 8'h00;
        flash_mem[10] = 8'hF0;
        flash_mem[11] = 8'h07;
        // Payload word 0: 0x12345678
        flash_mem[12] = 8'h78;
        flash_mem[13] = 8'h56;
        flash_mem[14] = 8'h34;
        flash_mem[15] = 8'h12;
        // Payload word 1: 0xDEADBEEF
        flash_mem[16] = 8'hEF;
        flash_mem[17] = 8'hBE;
        flash_mem[18] = 8'hAD;
        flash_mem[19] = 8'hDE;
    end

    // SPI flash model: cmd(1) + addr(3) → stream data
    integer spi_bit_cnt = 0;
    integer spi_byte_cnt = 0;
    integer spi_phase = 0;    // 0=cmd+addr, 1=data
    logic [7:0] spi_cmd_buf;
    logic [23:0] spi_addr_buf;
    integer flash_read_idx = 0;
    logic [7:0] flash_out_byte;
    integer flash_out_bit = 7;

    // Отдаём данные по MISO на falling edge SCK
    always @(negedge flash_sck or posedge flash_cs_n) begin
        if (flash_cs_n) begin
            spi_bit_cnt   <= 0;
            spi_byte_cnt  <= 0;
            spi_phase     <= 0;
            flash_read_idx <= 0;
            flash_out_bit <= 7;
            flash_miso    <= 1'b1;
        end else begin
            if (spi_phase == 0) begin
                // Принимаем cmd + addr (4 байта = 32 бита)
                spi_bit_cnt <= spi_bit_cnt + 1;
                if (spi_bit_cnt == 31) begin
                    spi_phase <= 1;
                    flash_out_byte <= flash_mem[0];
                    flash_out_bit <= 7;
                    flash_miso <= flash_mem[0][7];
                end
            end else begin
                // Отдаём данные MSB first
                if (flash_out_bit == 0) begin
                    flash_read_idx <= flash_read_idx + 1;
                    flash_out_byte <= flash_mem[flash_read_idx + 1];
                    flash_out_bit <= 7;
                    flash_miso <= flash_mem[flash_read_idx + 1][7];
                end else begin
                    flash_out_bit <= flash_out_bit - 1;
                    flash_miso <= flash_out_byte[flash_out_bit - 1];
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // DDR model: запоминаем записанные слова
    // ---------------------------------------------------------------
    integer ddr_wr_cnt = 0;
    logic [31:0] ddr_wr_addr_log [0:15];
    logic [31:0] ddr_wr_data_log [0:15];

    always @(posedge clk) begin
        mc_ready <= 1'b0;
        if (mc_write_trigger && !mc_ready) begin
            ddr_wr_addr_log[ddr_wr_cnt] <= mc_address;
            ddr_wr_data_log[ddr_wr_cnt] <= mc_write_data;
            mc_ready <= 1'b1;
            ddr_wr_cnt <= ddr_wr_cnt + 1;
        end
    end

    // ---------------------------------------------------------------
    // Test
    // ---------------------------------------------------------------
    integer errors = 0;
    integer timeout;

    initial begin
        $dumpfile("FLASH_LOADER_TEST.vcd");
        $dumpvars(0, FLASH_LOADER_TEST);

        mc_ready = 0;

        // Reset
        #20 reset = 0;
        #10;

        // T1: bus_request should be 1 immediately
        assert(bus_request == 1) else begin
            $display("T1 FAIL: bus_request should be 1 after reset");
            errors++;
        end
        assert(active == 1) else begin
            $display("T1 FAIL: active should be 1");
            errors++;
        end

        // T2: Wait in WAIT_DDR, nothing happens
        #100;
        assert(flash_cs_n == 1) else begin
            $display("T2 FAIL: CS should be inactive while waiting DDR");
            errors++;
        end

        // T3: Signal DDR ready
        ddr_ready = 1;

        // Wait for loading to complete (timeout)
        timeout = 0;
        while (active && timeout < 50000) begin
            #10;
            timeout++;
        end

        if (timeout >= 50000) begin
            $display("TIMEOUT: loader did not finish");
            errors++;
        end else begin
            $display("Loader finished in %0d cycles", timeout);
        end

        #20;

        // T4: Check results
        assert(bus_request == 0) else begin
            $display("T4 FAIL: bus_request should be 0 after done");
            errors++;
        end
        assert(active == 0) else begin
            $display("T4 FAIL: active should be 0 after done");
            errors++;
        end

        // T5: Check DDR contents
        if (ddr_wr_cnt != 2) begin
            $display("T5 FAIL: expected 2 DDR writes, got %0d", ddr_wr_cnt);
            errors++;
        end

        // Check addresses: load_addr=0x07F00000 → first write at 0x7F00000 (28-bit)
        if (ddr_wr_addr_log[0] !== 28'h7F00000) begin
            $display("T5 FAIL: addr[0] = %07h, expected 7F00000", ddr_wr_addr_log[0]);
            errors++;
        end
        if (ddr_wr_addr_log[1] !== 28'h7F00004) begin
            $display("T5 FAIL: addr[1] = %07h, expected 7F00004", ddr_wr_addr_log[1]);
            errors++;
        end

        if (ddr_wr_data_log[0] !== 32'h12345678) begin
            $display("T5 FAIL: data[0] = %08h, expected 12345678", ddr_wr_data_log[0]);
            errors++;
        end
        if (ddr_wr_data_log[1] !== 32'hDEADBEEF) begin
            $display("T5 FAIL: data[1] = %08h, expected DEADBEEF", ddr_wr_data_log[1]);
            errors++;
        end

        // T6: Check new_pc = load_addr
        assert(new_pc == 32'h07F00000) else begin
            $display("T6 FAIL: new_pc = %08h, expected 07F00000", new_pc);
            errors++;
        end

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d ERRORS", errors);

        $finish;
    end

endmodule
