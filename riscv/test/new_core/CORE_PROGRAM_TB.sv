// CORE_PROGRAM_TB — test harness for running real C programs on new CORE.
//
// Like CORE_TB but with:
//  - Larger I-cache (512 lines = 8KB, fits test programs up to ~1600 words)
//  - UART mock at 0x40000000 (captures text output)
//  - UART status at 0x40000008 (always ready)
//  - Larger mock memory for data

// No module wrapper — included by test files.

    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;

    wire [31:0]  bus_address;
    wire         bus_read, bus_write;
    wire [127:0] bus_write_data;
    wire [15:0]  bus_write_mask;
    reg          bus_ready = 1;
    reg  [127:0] bus_read_data;
    reg          bus_read_valid = 0;

    // Unified memory: 128K words = 512KB (code at 0x0, data at 0x10000)
    reg [31:0] mem [0:131071];

    reg        mem_pending = 0;
    reg [31:0] mem_pending_addr;

    // UART output capture
    reg [7:0] uart_buf [0:4095];
    int uart_len = 0;

    // I/O address detection
    wire is_io = (bus_address[31:28] == 4'h4);  // 0x4xxxxxxx = I/O

    always @(posedge clk) begin
        bus_read_valid <= 0;

        if (reset) begin
            bus_ready   <= 1;
            mem_pending <= 0;
            uart_len    <= 0;
        end else begin
            // === I/O writes (UART) ===
            if (bus_write && bus_ready && is_io) begin
                if (bus_address[15:0] == 16'h0000) begin
                    // UART TX: capture lowest byte
                    if (uart_len < 4096)
                        uart_buf[uart_len] = bus_write_data[7:0];
                    uart_len <= uart_len + 1;
                end
                // Other I/O writes: ignore
            end

            // === I/O reads ===
            if (bus_read && bus_ready && is_io) begin
                mem_pending      <= 1;
                mem_pending_addr <= bus_address;
                bus_ready        <= 0;
            end

            // === Memory writes ===
            else if (bus_write && bus_ready && !is_io) begin
                reg [31:0] base;
                base = {bus_address[31:4], 4'b0000};
                for (int i = 0; i < 4; i++) begin
                    reg [31:0] word;
                    word = mem[((base >> 2) + i) & 17'h1FFFF];
                    for (int b = 0; b < 4; b++) begin
                        if (bus_write_mask[i*4 + b])
                            word[b*8 +: 8] = bus_write_data[(i*4+b)*8 +: 8];
                    end
                    mem[((base >> 2) + i) & 17'h1FFFF] = word;
                end
            end

            // === Memory reads ===
            else if (bus_read && bus_ready && !is_io) begin
                mem_pending      <= 1;
                mem_pending_addr <= bus_address;
                bus_ready        <= 0;
            end

            // === Pending read response (1-cycle latency) ===
            else if (mem_pending) begin
                if (mem_pending_addr[31:28] == 4'h4) begin
                    // I/O read response
                    if (mem_pending_addr[15:0] == 16'h0008)
                        bus_read_data = {96'b0, 32'h0000_0002};  // UART status: tx_ready=1
                    else
                        bus_read_data = 128'b0;
                end else begin
                    reg [31:0] base;
                    base = {mem_pending_addr[31:4], 4'b0000};
                    bus_read_data = {
                        mem[((base >> 2) + 3) & 17'h1FFFF],
                        mem[((base >> 2) + 2) & 17'h1FFFF],
                        mem[((base >> 2) + 1) & 17'h1FFFF],
                        mem[((base >> 2) + 0) & 17'h1FFFF]
                    };
                end
                bus_read_valid <= 1;
                mem_pending    <= 0;
                bus_ready      <= 1;
            end
        end
    end

    reg [31:0] ext_new_pc = 0;
    reg        ext_set_pc = 0;
    reg        core_stall = 0;
    wire       pipeline_empty;
    wire [31:0] dbg_pc, dbg_instr;
    wire [63:0] instr_count;

    CORE #(.ICACHE_DEPTH(512), .ICACHE_WAYS(1)) dut (
        .clk(clk), .reset(reset),
        .bus_address(bus_address), .bus_read(bus_read), .bus_write(bus_write),
        .bus_write_data(bus_write_data), .bus_write_mask(bus_write_mask),
        .bus_ready(bus_ready), .bus_read_data(bus_read_data), .bus_read_valid(bus_read_valid),
        .ext_new_pc(ext_new_pc), .ext_set_pc(ext_set_pc),
        .stall(core_stall), .pipeline_empty(pipeline_empty),
        .dbg_last_alu_pc(dbg_pc), .dbg_last_alu_instr(dbg_instr),
        .instr_count(instr_count)
    );

    int errors = 0;
    int cycle_count;

    task automatic load_program(input string hex_file);
        int i;
        for (i = 0; i < 131072; i++) mem[i] = 32'h00000013;
        $readmemh(hex_file, mem);
    endtask

    task automatic run_program(input int max_cycles);
        reset = 1;
        @(posedge clk); @(posedge clk);
        reset = 0;
        core_stall = 0;
        cycle_count = 0;
        while (cycle_count < max_cycles) begin
            @(posedge clk); #1;
            cycle_count++;
            if (dut.pipeline_inst.s3_valid && dut.pipeline_inst.s3_ready &&
                dut.pipeline_inst.s3_instruction == 32'h00100073)
                break;
        end
        if (cycle_count >= max_cycles)
            $display("TIMEOUT after %0d cycles (last_pc=0x%08X)", max_cycles, dbg_pc);
    endtask

    // Check UART output contains "ALL OK" or "PASSED"
    task automatic check_output_ok;
        int found = 0;
        for (int i = 0; i < uart_len - 5; i++) begin
            if (uart_buf[i] == "A" && uart_buf[i+1] == "L" && uart_buf[i+2] == "L" &&
                uart_buf[i+3] == " " && uart_buf[i+4] == "O" && uart_buf[i+5] == "K")
                found = 1;
        end
        for (int i = 0; i < uart_len - 5; i++) begin
            if (uart_buf[i] == "P" && uart_buf[i+1] == "A" && uart_buf[i+2] == "S" &&
                uart_buf[i+3] == "S" && uart_buf[i+4] == "E" && uart_buf[i+5] == "D")
                found = 1;
        end
        if (!found) begin
            $display("FAIL: UART output does not contain 'ALL OK'");
            // Print captured output
            $write("  UART[%0d]: ", uart_len);
            for (int i = 0; i < uart_len && i < 200; i++)
                $write("%c", uart_buf[i]);
            $display("");
            errors++;
        end
    endtask

    // Check UART has no "FAIL"
    task automatic check_no_fail;
        for (int i = 0; i < uart_len - 3; i++) begin
            if (uart_buf[i] == "F" && uart_buf[i+1] == "A" && uart_buf[i+2] == "I" &&
                uart_buf[i+3] == "L") begin
                $display("FAIL: UART output contains 'FAIL'");
                $write("  UART[%0d]: ", uart_len);
                for (int j = 0; j < uart_len && j < 200; j++)
                    $write("%c", uart_buf[j]);
                $display("");
                errors++;
                return;
            end
        end
    endtask

// End of CORE_PROGRAM_TB include
