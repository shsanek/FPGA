// CORE — single RISC-V core: pipeline + I_CACHE + register file + bus arbiter.
//
// One external bus port (128-bit standard interface).
// Internally: I_CACHE miss and MEM (load/store) share bus via BUS_ARBITER.
// INSTRUCTION_PROVIDER uses peek to read I_CACHE without bus requests.

module CORE #(
    parameter ICACHE_DEPTH = 256,
    parameter ICACHE_WAYS  = 1
)(
    input wire clk,
    input wire reset,

    // === External 128-bit bus ===
    output wire [31:0]  bus_address,
    output wire         bus_read,
    output wire         bus_write,
    output wire [127:0] bus_write_data,
    output wire [15:0]  bus_write_mask,
    input  wire         bus_ready,
    input  wire [127:0] bus_read_data,
    input  wire         bus_read_valid,

    // === External flush (debug set_pc) ===
    input  wire [31:0]  ext_new_pc,
    input  wire         ext_set_pc,

    // === Stall / debug ===
    input  wire         stall,              // 1 = stop fetching instructions
    output wire         pipeline_empty,     // 1 = all stages idle
    output wire [31:0]  dbg_last_alu_pc,    // last PC dispatched to ALU
    output wire [31:0]  dbg_last_alu_instr, // last instruction dispatched to ALU
    output wire [63:0]  instr_count         // instructions dispatched to ALU
);

    // =========================================================
    // Register file (32 x 32-bit, x0 hardwired to 0)
    // =========================================================
    reg [31:0] regfile [1:31];

    wire [4:0]  rf_rs1_addr, rf_rs2_addr, rf_wr_addr;
    wire [31:0] rf_wr_data;
    wire        rf_wr_en;
    wire [31:0] rf_rs1_data = (rf_rs1_addr == 0) ? 32'b0 : regfile[rf_rs1_addr];
    wire [31:0] rf_rs2_data = (rf_rs2_addr == 0) ? 32'b0 : regfile[rf_rs2_addr];

    always_ff @(posedge clk) begin
        if (rf_wr_en && rf_wr_addr != 0)
            regfile[rf_wr_addr] <= rf_wr_data;
    end

    // =========================================================
    // Pipeline ↔ I_CACHE wires
    // =========================================================
    wire [31:0]  icache_pipe_addr;
    wire         icache_pipe_read;
    wire         icache_pipe_ready;

    // Peek from I_CACHE output buffer
    wire [31:0]  icache_peek_addr;
    wire [127:0] icache_peek_data;
    wire         icache_peek_valid;

    // =========================================================
    // Pipeline ↔ Data bus wires (from ALU_MEMORY)
    // =========================================================
    wire [31:0]  data_pipe_addr;
    wire         data_pipe_read;
    wire         data_pipe_write;
    wire [127:0] data_pipe_write_data;
    wire [15:0]  data_pipe_write_mask;
    wire         data_pipe_ready;
    wire [127:0] data_pipe_read_data;
    wire         data_pipe_read_valid;

    // =========================================================
    // I_CACHE external bus wires (miss → arbiter)
    // =========================================================
    wire [31:0]  icache_ext_addr;
    wire         icache_ext_read;
    wire         icache_ext_write;
    wire [127:0] icache_ext_write_data;
    wire [15:0]  icache_ext_write_mask;
    wire         icache_ext_ready;
    wire [127:0] icache_ext_read_data;
    wire         icache_ext_read_valid;

    // =========================================================
    // Flush
    // =========================================================
    wire pipeline_flush;  // from PIPELINE out_flush

    // =========================================================
    // Pipeline
    // =========================================================
    PIPELINE pipeline_inst (
        .clk(clk), .reset(reset),
        // I_CACHE: bus + peek
        .icache_bus_address(icache_pipe_addr),
        .icache_bus_read(icache_pipe_read),
        .icache_bus_ready(icache_pipe_ready),
        .icache_peek_address(icache_peek_addr),
        .icache_peek_data(icache_peek_data),
        .icache_peek_valid(icache_peek_valid),
        // Data bus
        .data_bus_address(data_pipe_addr),
        .data_bus_read(data_pipe_read),
        .data_bus_write(data_pipe_write),
        .data_bus_write_data(data_pipe_write_data),
        .data_bus_write_mask(data_pipe_write_mask),
        .data_bus_ready(data_pipe_ready),
        .data_bus_read_data(data_pipe_read_data),
        .data_bus_read_valid(data_pipe_read_valid),
        // Register file
        .rf_rs1_addr(rf_rs1_addr), .rf_rs1_data(rf_rs1_data),
        .rf_rs2_addr(rf_rs2_addr), .rf_rs2_data(rf_rs2_data),
        .rf_wr_addr(rf_wr_addr), .rf_wr_data(rf_wr_data), .rf_wr_en(rf_wr_en),
        // Flush
        .ext_new_pc(ext_new_pc), .ext_set_pc(ext_set_pc),
        // Stall / debug
        .stall(stall), .pipeline_empty(pipeline_empty),
        .dbg_last_alu_pc(dbg_last_alu_pc), .dbg_last_alu_instr(dbg_last_alu_instr),
        .out_flush(pipeline_flush),
        .instr_count(instr_count)
    );

    // =========================================================
    // I_CACHE (MCV2 READ_ONLY=1)
    // =========================================================
    MEMORY_CONTROLLER_V2 #(
        .DEPTH(ICACHE_DEPTH), .WAYS(ICACHE_WAYS), .READ_ONLY(1)
    ) icache (
        .clk(clk), .reset(reset || pipeline_flush),
        // Invalidate (not connected)
        .invalidate_ready(), .invalidate_address(32'b0), .invalidate_trigger(1'b0),
        // Peek outputs
        .peek_line_address(icache_peek_addr),
        .peek_line_data(icache_peek_data),
        .peek_line_valid(icache_peek_valid),
        // Upstream: from pipeline
        .bus_address(icache_pipe_addr),
        .bus_read(icache_pipe_read),
        .bus_write(1'b0),
        .bus_write_data(128'b0),
        .bus_write_mask(16'b0),
        .bus_ready(icache_pipe_ready),
        .bus_read_data(),   // not used — peek replaces this
        .bus_read_valid(),  // not used
        // Downstream: miss → arbiter port1
        .external_address(icache_ext_addr),
        .external_read(icache_ext_read),
        .external_write(icache_ext_write),
        .external_write_data(icache_ext_write_data),
        .external_write_mask(icache_ext_write_mask),
        .external_ready(icache_ext_ready),
        .external_read_data(icache_ext_read_data),
        .external_read_valid(icache_ext_read_valid)
    );

    // =========================================================
    // BUS_ARBITER: MEM data (port0, priority) + I_CACHE miss (port1)
    // =========================================================
    BUS_ARBITER arbiter (
        .clk(clk), .reset(reset),
        // Port 0: MEM data — priority
        .p0_address(data_pipe_addr),
        .p0_read(data_pipe_read),
        .p0_write(data_pipe_write),
        .p0_write_data(data_pipe_write_data),
        .p0_write_mask(data_pipe_write_mask),
        .p0_ready(data_pipe_ready),
        .p0_read_data(data_pipe_read_data),
        .p0_read_valid(data_pipe_read_valid),
        // Port 1: I_CACHE miss
        .p1_address(icache_ext_addr),
        .p1_read(icache_ext_read),
        .p1_write(icache_ext_write),
        .p1_write_data(icache_ext_write_data),
        .p1_write_mask(icache_ext_write_mask),
        .p1_ready(icache_ext_ready),
        .p1_read_data(icache_ext_read_data),
        .p1_read_valid(icache_ext_read_valid),
        // Downstream: external bus
        .bus_address(bus_address),
        .bus_read(bus_read),
        .bus_write(bus_write),
        .bus_write_data(bus_write_data),
        .bus_write_mask(bus_write_mask),
        .bus_ready(bus_ready),
        .bus_read_data(bus_read_data),
        .bus_read_valid(bus_read_valid)
    );

endmodule
