module core_test_bench_ipc;

    // Override CORE_TB — use larger I-cache so program fits
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

    reg [31:0] mem [0:65535];

    reg        mem_pending = 0;
    reg [31:0] mem_pending_addr;

    always @(posedge clk) begin
        bus_read_valid <= 0;

        if (reset) begin
            bus_ready   <= 1;
            mem_pending <= 0;
        end else begin
            if (bus_write && bus_ready) begin
                reg [31:0] base;
                base = {bus_address[31:4], 4'b0000};
                for (int i = 0; i < 4; i++) begin
                    reg [31:0] word;
                    word = mem[(base >> 2) + i];
                    for (int b = 0; b < 4; b++) begin
                        if (bus_write_mask[i*4 + b])
                            word[b*8 +: 8] = bus_write_data[(i*4+b)*8 +: 8];
                    end
                    mem[(base >> 2) + i] = word;
                end
            end

            if (bus_read && bus_ready) begin
                mem_pending      <= 1;
                mem_pending_addr <= bus_address;
                bus_ready        <= 0;
            end else if (mem_pending) begin
                reg [31:0] base;
                base = {mem_pending_addr[31:4], 4'b0000};
                bus_read_data = {mem[(base >> 2) + 3], mem[(base >> 2) + 2],
                                 mem[(base >> 2) + 1], mem[(base >> 2) + 0]};
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
    wire [31:0] instr_count;

    // Large I-cache: 64 lines = 1KB (fits 198-word program)
    CORE #(.ICACHE_DEPTH(64), .ICACHE_WAYS(1)) dut (
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
        for (i = 0; i < 65536; i++) mem[i] = 32'h00000013;
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
            $display("TIMEOUT after %0d cycles (last_pc=0x%08X last_instr=0x%08X)",
                max_cycles, dbg_pc, dbg_instr);
    endtask

    initial begin
        load_program("/tmp/bench_ipc.hex");
        run_program(5000000);

        $display("bench_ipc: %0d cycles, %0d instrs, IPC=%0d.%02d (10 iters, N=32)",
            cycle_count, instr_count,
            instr_count / cycle_count,
            (instr_count * 100 / cycle_count) % 100);

        if (cycle_count >= 5000000) begin
            $display("bench_ipc: TIMEOUT");
            errors++;
        end

        if (errors == 0) $display("bench_ipc: PASSED");
        else $display("bench_ipc: FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
