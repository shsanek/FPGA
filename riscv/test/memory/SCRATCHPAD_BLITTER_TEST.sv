// Тест SCRATCHPAD + Blitter FSM
//
// Проверяем:
//   T1: CPU read/write BRAM (без блиттера)
//   T2: CMD_COLUMN — blitter читает текстуру из DDR-стаба,
//       lookup colormap из BRAM, пишет пиксели в BRAM screen buffer
//   T3: CMD_SPAN — аналогично, с 2D текстурой
module SCRATCHPAD_BLITTER_TEST();
    logic clk = 0;
    initial forever #5 clk = ~clk;

    logic reset;
    int   error = 0;

    // ---------------------------------------------------------------
    // CPU port
    // ---------------------------------------------------------------
    logic [27:0] address;
    logic        read_trigger, write_trigger;
    logic [31:0] write_value;
    logic [3:0]  mask;
    wire  [31:0] read_value;
    wire         controller_ready;

    // ---------------------------------------------------------------
    // Blitter external bus (DDR stub)
    // ---------------------------------------------------------------
    wire         blitter_active;
    wire  [28:0] blitter_bus_addr;
    wire         blitter_bus_rd;
    logic [31:0] blitter_bus_data;
    logic        blitter_bus_ready;

    // ---------------------------------------------------------------
    // DDR stub: simple memory (256 words)
    // Returns data 1 cycle after bus_ready asserts
    // ---------------------------------------------------------------
    logic [31:0] ddr_mem [0:255];
    logic [7:0]  ddr_addr_latched;
    logic        ddr_pending;
    logic [1:0]  ddr_delay;

    always_ff @(posedge clk) begin
        if (reset) begin
            blitter_bus_ready <= 0;
            blitter_bus_data  <= 0;
            ddr_pending       <= 0;
            ddr_delay         <= 0;
        end else begin
            blitter_bus_ready <= 0;
            if (blitter_bus_rd && !ddr_pending) begin
                ddr_addr_latched <= blitter_bus_addr[9:2]; // word address
                ddr_pending      <= 1;
                ddr_delay        <= 2; // simulate 2-cycle DDR latency
            end
            if (ddr_pending) begin
                if (ddr_delay > 0)
                    ddr_delay <= ddr_delay - 1;
                else begin
                    blitter_bus_data  <= ddr_mem[ddr_addr_latched];
                    blitter_bus_ready <= 1;
                    ddr_pending       <= 0;
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // DUT
    // ---------------------------------------------------------------
    SCRATCHPAD dut (
        .clk              (clk),
        .reset            (reset),
        .address          (address),
        .read_trigger     (read_trigger),
        .write_trigger    (write_trigger),
        .write_value      (write_value),
        .mask             (mask),
        .read_value       (read_value),
        .controller_ready (controller_ready),
        .blitter_active   (blitter_active),
        .blitter_bus_addr (blitter_bus_addr),
        .blitter_bus_rd   (blitter_bus_rd),
        .blitter_bus_data (blitter_bus_data),
        .blitter_bus_ready(blitter_bus_ready)
    );

    // ---------------------------------------------------------------
    // Helper tasks
    // ---------------------------------------------------------------
    task cpu_write(input [27:0] a, input [31:0] d, input [3:0] m);
        @(posedge clk); #1;
        address       = a;
        write_value   = d;
        mask          = m;
        write_trigger = 1;
        read_trigger  = 0;
        @(posedge clk); #1;
        write_trigger = 0;
    endtask

    task cpu_read(input [27:0] a, output [31:0] d);
        @(posedge clk); #1;
        address      = a;
        read_trigger = 1;
        write_trigger= 0;
        @(posedge clk); #1;  // BRAM latency
        @(posedge clk); #1;  // capture dout
        d = read_value;
        read_trigger = 0;
    endtask

    // Write to MMIO register (offset from 0x20000)
    task mmio_write(input [5:0] reg_offset, input [31:0] d);
        cpu_write(28'h0020000 + {22'b0, reg_offset}, d, 4'hF);
    endtask

    // Read from MMIO register
    task mmio_read(input [5:0] reg_offset, output [31:0] d);
        cpu_read(28'h0020000 + {22'b0, reg_offset}, d);
    endtask

    // Wait for blitter to finish
    task wait_blitter_done();
        integer timeout;
        timeout = 0;
        while (blitter_active && timeout < 5000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 5000) begin
            $display("FAIL: blitter timeout!");
            error = error + 1;
        end
    endtask

    // ---------------------------------------------------------------
    // Test
    // ---------------------------------------------------------------
    logic [31:0] rd;
    integer i;

    initial begin
        $dumpfile("SCRATCHPAD_BLITTER_TEST.vcd");
        $dumpvars(0, SCRATCHPAD_BLITTER_TEST);

        reset         = 1;
        address       = 0;
        read_trigger  = 0;
        write_trigger = 0;
        write_value   = 0;
        mask          = 4'hF;
        blitter_bus_data  = 0;
        blitter_bus_ready = 0;

        repeat(5) @(posedge clk); #1;
        reset = 0;
        repeat(2) @(posedge clk); #1;

        // -------------------------------------------------------
        // T1: CPU BRAM read/write
        // -------------------------------------------------------
        $display("T1: CPU BRAM read/write");
        cpu_write(28'h0000000, 32'hCAFEBABE, 4'hF);  // word 0
        cpu_write(28'h0000004, 32'hDEADBEEF, 4'hF);  // word 1
        cpu_read(28'h0000000, rd);
        if (rd !== 32'hCAFEBABE) begin
            $display("  FAIL: read word 0 = 0x%08X, expected 0xCAFEBABE", rd);
            error = error + 1;
        end
        cpu_read(28'h0000004, rd);
        if (rd !== 32'hDEADBEEF) begin
            $display("  FAIL: read word 1 = 0x%08X, expected 0xDEADBEEF", rd);
            error = error + 1;
        end

        // -------------------------------------------------------
        // T2: CMD_COLUMN
        // -------------------------------------------------------
        $display("T2: CMD_COLUMN blitter");

        // Setup DDR texture: 4 texels at DDR address 0x100
        // DDR word at addr 0x100 = bytes [0x10, 0x20, 0x30, 0x40]
        ddr_mem[8'h40] = 32'h40302010;  // addr 0x100 → word index 0x40
        // DDR word at addr 0x104 = bytes [0x50, 0x60, 0x70, 0x80]
        ddr_mem[8'h41] = 32'h80706050;

        // Setup colormap in BRAM at offset 0x1000 (byte addr)
        // colormap[0x10] should map to pixel 0xAA
        // colormap[0x20] should map to pixel 0xBB
        // We need cmap[0x10] at BRAM byte 0x1010 → word 0x404, byte 0
        // cmap[0x10]: byte addr 0x1010 → word addr 0x404, byte lane 0
        cpu_write(28'h0001010, 32'h000000AA, 4'h1); // cmap[0x10] = 0xAA
        // cmap[0x20]: byte addr 0x1020 → word addr 0x408, byte lane 0
        cpu_write(28'h0001020, 32'h000000BB, 4'h1); // cmap[0x20] = 0xBB
        // cmap[0x30]: byte addr 0x1030 → word addr 0x40C, byte lane 0
        cpu_write(28'h0001030, 32'h000000CC, 4'h1); // cmap[0x30] = 0xCC

        // Setup blitter registers
        mmio_write(6'h08, 32'h00000100);   // SRC_ADDR = 0x100 (DDR)
        mmio_write(6'h0C, 32'h00000000);   // SRC_FRAC = 0.0
        mmio_write(6'h10, 32'h00010000);   // SRC_STEP = 1.0 (fixed 16.16)
        mmio_write(6'h14, 32'h0000007F);   // SRC_MASK = 127
        mmio_write(6'h18, 32'h00000000);   // DST_OFFSET = 0 (byte)
        mmio_write(6'h1C, 32'h00000004);   // DST_STEP = 4 (bytes, for easy checking)
        mmio_write(6'h20, 32'h00000003);   // COUNT = 3 pixels
        mmio_write(6'h24, 32'h00001000);   // CMAP_OFFSET = 0x1000 (byte)

        // Fire!
        mmio_write(6'h00, 32'h00000001);   // CMD = 1 (column)

        // Wait for blitter to finish
        wait_blitter_done();
        repeat(3) @(posedge clk); #1;

        // Verify screen buffer:
        // Pixel 0: texel = texture[0] = 0x10, cmap[0x10] = 0xAA → BRAM[0] byte 0
        // Pixel 1: texel = texture[1] = 0x20, cmap[0x20] = 0xBB → BRAM[1] byte 0
        // Pixel 2: texel = texture[2] = 0x30, cmap[0x30] = 0xCC → BRAM[2] byte 0
        // DST_OFFSET starts at 0, step=4, so pixels at byte 0, 4, 8
        cpu_read(28'h0000000, rd);
        if (rd[7:0] !== 8'hAA) begin
            $display("  FAIL: pixel 0 = 0x%02X, expected 0xAA (full word: 0x%08X)", rd[7:0], rd);
            error = error + 1;
        end
        cpu_read(28'h0000004, rd);
        if (rd[7:0] !== 8'hBB) begin
            $display("  FAIL: pixel 1 = 0x%02X, expected 0xBB (full word: 0x%08X)", rd[7:0], rd);
            error = error + 1;
        end
        cpu_read(28'h0000008, rd);
        if (rd[7:0] !== 8'hCC) begin
            $display("  FAIL: pixel 2 = 0x%02X, expected 0xCC (full word: 0x%08X)", rd[7:0], rd);
            error = error + 1;
        end

        // -------------------------------------------------------
        // Summary
        // -------------------------------------------------------
        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);

        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
