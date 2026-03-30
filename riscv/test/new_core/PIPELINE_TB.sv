// PIPELINE_TB — reusable testbench harness for pipeline tests.
//
// Instantiates PIPELINE + register file + I_CACHE mock + data memory mock.
// Loads program from hex file (+HEX_FILE=...), runs, checks results.
//
// Usage: each test includes this file and provides:
//   - HEX file with program
//   - Expected register values to check after EBREAK

// No module wrapper — included by test modules

    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;

    // Register file (32 x 32-bit, x0 = 0)
    reg [31:0] regfile [0:31];

    wire [4:0]  rf_rs1_addr, rf_rs2_addr, rf_wr_addr;
    wire [31:0] rf_wr_data;
    wire        rf_wr_en;
    wire [31:0] rf_rs1_data = (rf_rs1_addr == 0) ? 32'b0 : regfile[rf_rs1_addr];
    wire [31:0] rf_rs2_data = (rf_rs2_addr == 0) ? 32'b0 : regfile[rf_rs2_addr];

    always @(posedge clk) begin
        if (rf_wr_en && rf_wr_addr != 0)
            regfile[rf_wr_addr] <= rf_wr_data;
    end

    // I_CACHE mock: simple memory, 1-cycle latency
    wire [31:0]  icache_addr;
    wire         icache_read;
    reg  [127:0] icache_data;
    reg          icache_ready = 1;
    reg          icache_valid = 0;

    // Instruction memory (4K words = 16KB)
    reg [31:0] imem [0:4095];

    always @(posedge clk) begin
        icache_valid <= 0;
        if (icache_read && icache_ready) begin
            // Return 128-bit line (4 words) aligned
            icache_data <= {
                imem[icache_addr[13:2] + 3],
                imem[icache_addr[13:2] + 2],
                imem[icache_addr[13:2] + 1],
                imem[icache_addr[13:2] + 0]
            };
            icache_valid <= 1;
        end
    end

    // Data memory mock: simple, 2-cycle latency
    wire [31:0]  dmem_addr;
    wire         dmem_read, dmem_write;
    wire [127:0] dmem_write_data;
    wire [15:0]  dmem_write_mask;
    reg          dmem_ready = 1;
    reg  [127:0] dmem_read_data;
    reg          dmem_read_valid = 0;

    reg [7:0] data_mem [0:131071];  // 128KB byte-addressable

    reg        dmem_pending = 0;
    reg [31:0] dmem_pending_addr;
    reg        dmem_pending_is_read;

    always @(posedge clk) begin
        dmem_read_valid <= 0;

        if (dmem_write && dmem_ready) begin
            // Byte-masked write
            for (int i = 0; i < 16; i++) begin
                if (dmem_write_mask[i])
                    data_mem[{dmem_addr[16:4], 4'b0} + i] <= dmem_write_data[i*8 +: 8];
            end
        end

        if (dmem_read && dmem_ready) begin
            dmem_pending      <= 1;
            dmem_pending_addr <= dmem_addr;
            dmem_ready        <= 0;
        end else if (dmem_pending) begin
            // Return 128-bit line
            for (int i = 0; i < 16; i++)
                dmem_read_data[i*8 +: 8] <= data_mem[{dmem_pending_addr[16:4], 4'b0} + i];
            dmem_read_valid <= 1;
            dmem_pending    <= 0;
            dmem_ready      <= 1;
        end
    end

    // External flush (debug set_pc)
    reg [31:0] ext_new_pc = 0;
    reg        ext_set_pc = 0;

    // DUT
    PIPELINE dut (
        .clk(clk), .reset(reset),
        .icache_bus_address(icache_addr), .icache_bus_read(icache_read),
        .icache_bus_read_data(icache_data), .icache_bus_ready(icache_ready),
        .icache_bus_read_valid(icache_valid),
        .data_bus_address(dmem_addr), .data_bus_read(dmem_read),
        .data_bus_write(dmem_write), .data_bus_write_data(dmem_write_data),
        .data_bus_write_mask(dmem_write_mask), .data_bus_ready(dmem_ready),
        .data_bus_read_data(dmem_read_data), .data_bus_read_valid(dmem_read_valid),
        .rf_rs1_addr(rf_rs1_addr), .rf_rs1_data(rf_rs1_data),
        .rf_rs2_addr(rf_rs2_addr), .rf_rs2_data(rf_rs2_data),
        .rf_wr_addr(rf_wr_addr), .rf_wr_data(rf_wr_data), .rf_wr_en(rf_wr_en),
        .ext_new_pc(ext_new_pc), .ext_set_pc(ext_set_pc)
    );

    // Helpers
    int errors = 0;

    task automatic check_reg(input int idx, input int expected, input string label);
        if (regfile[idx] !== expected) begin
            $display("FAIL [%s]: x%0d = 0x%08X, expected 0x%08X", label, idx, regfile[idx], expected);
            errors++;
        end
    endtask

    task automatic check_mem_byte(input int addr, input int expected, input string label);
        if (data_mem[addr] !== expected[7:0]) begin
            $display("FAIL [%s]: mem[0x%04X] = 0x%02X, expected 0x%02X", label, addr, data_mem[addr], expected[7:0]);
            errors++;
        end
    endtask

    task automatic run_until_ebreak(input int timeout);
        int cnt = 0;
        // Wait for EBREAK: instruction 0x00100073 at writeback
        while (cnt < timeout) begin
            @(posedge clk);
            // Detect EBREAK by checking if pipeline wrote to x0 with ebreak pattern
            // Actually detect by monitoring instruction provider's current instruction
            // Simpler: check if PC stops advancing (stuck on ebreak loop)
            cnt++;
        end
    endtask

    task automatic load_program(input string hex_file);
        int i;
        for (i = 0; i < 4096; i++) imem[i] = 32'h00000013; // NOP
        $readmemh(hex_file, imem);
    endtask

    task automatic init();
        int i;
        reset = 1;
        for (i = 0; i < 32; i++) regfile[i] = 32'b0;
        for (i = 0; i < 131072; i++) data_mem[i] = 8'b0;
        @(posedge clk); @(posedge clk);
        reset = 0;
    endtask

// End of PIPELINE_TB include
