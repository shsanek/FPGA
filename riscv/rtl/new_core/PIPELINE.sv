// PIPELINE — full pipelined RISC-V core.
//
// Stages:
//   1. INSTRUCTION_PROVIDER  — fetch from I_CACHE (128-bit bus)
//   2. INSTRUCTION_DECODE    — decode rs1/rs2/rd indices
//   3. REGISTER_DISPATCHER   — hazard check + register read
//   4. EXECUTE_DISPATCHER    — route to ALU (compute/branch/jump/upper/memory/muldiv)
//   5. WRITEBACK_ARBITER     — merge ALU results (priority: single > memory > muldiv)
//   6. WRITEBACK             — write register file + notify dispatcher

module PIPELINE (
    input wire clk,
    input wire reset,

    // === I_CACHE bus (128-bit, for instruction fetch) ===
    output wire [31:0]  icache_bus_address,
    output wire         icache_bus_read,
    input  wire [127:0] icache_bus_read_data,
    input  wire         icache_bus_ready,
    input  wire         icache_bus_read_valid,

    // === Data bus (128-bit, for LOAD/STORE) ===
    output wire [31:0]  data_bus_address,
    output wire         data_bus_read,
    output wire         data_bus_write,
    output wire [127:0] data_bus_write_data,
    output wire [15:0]  data_bus_write_mask,
    input  wire         data_bus_ready,
    input  wire [127:0] data_bus_read_data,
    input  wire         data_bus_read_valid,

    // === Register file ===
    output wire [4:0]  rf_rs1_addr,
    input  wire [31:0] rf_rs1_data,
    output wire [4:0]  rf_rs2_addr,
    input  wire [31:0] rf_rs2_data,
    output wire [4:0]  rf_wr_addr,
    output wire [31:0] rf_wr_data,
    output wire        rf_wr_en,

    // === External flush (debug set_pc) ===
    input  wire [31:0] ext_new_pc,
    input  wire        ext_set_pc
);

    // =========================================================
    // Flush: from branch/jump ALU or external set_pc
    // =========================================================
    wire        alu_flush;
    wire [31:0] alu_new_pc;
    wire        flush    = alu_flush || ext_set_pc;
    wire [31:0] flush_pc = ext_set_pc ? ext_new_pc : alu_new_pc;

    // =========================================================
    // Stage 1 → 2 wires
    // =========================================================
    wire [31:0] s1_pc, s1_instruction;
    wire        s1_valid, s1_ready;

    // =========================================================
    // Stage 2 → 3 wires
    // =========================================================
    wire [31:0] s2_pc, s2_instruction;
    wire [4:0]  s2_rs1_index, s2_rs2_index, s2_rd_index;
    wire        s2_valid, s2_ready;

    // =========================================================
    // Stage 3 → 4 wires
    // =========================================================
    wire [31:0] s3_pc, s3_instruction;
    wire [31:0] s3_rs1_value, s3_rs2_value;
    wire        s3_valid, s3_ready;

    // =========================================================
    // Stage 4 → 5 (ALU results)
    // =========================================================
    wire [4:0]  compute_rd_idx, branch_rd_idx, jump_rd_idx, upper_rd_idx, memory_rd_idx, muldiv_rd_idx;
    wire [31:0] compute_rd_val, branch_rd_val, jump_rd_val, upper_rd_val, memory_rd_val, muldiv_rd_val;
    wire        compute_done,   branch_done,   jump_done,   upper_done,   memory_done,   muldiv_done;
    wire        compute_rdy,    branch_rdy,    jump_rdy,    upper_rdy,    memory_rdy,    muldiv_rdy;

    // =========================================================
    // Stage 5 → 6 wires
    // =========================================================
    wire [4:0]  wb_arb_rd_index;
    wire [31:0] wb_arb_rd_value;
    wire        wb_arb_valid, wb_arb_ready;

    // =========================================================
    // Writeback → REGISTER_DISPATCHER notification
    // =========================================================
    wire [4:0]  wb_done_index;
    wire        wb_done_valid;

    // =========================================================
    // Stage 1: INSTRUCTION_PROVIDER
    // =========================================================
    INSTRUCTION_PROVIDER stage1_fetch (
        .clk(clk), .reset(reset),
        .out_pc(s1_pc), .out_instruction(s1_instruction),
        .next_stage_valid(s1_valid), .next_stage_ready(s1_ready),
        .new_pc(flush_pc), .flush(flush),
        .bus_address(icache_bus_address), .bus_read(icache_bus_read),
        .bus_read_data(icache_bus_read_data),
        .bus_ready(icache_bus_ready), .bus_read_valid(icache_bus_read_valid)
    );

    // =========================================================
    // Stage 2: INSTRUCTION_DECODE
    // =========================================================
    INSTRUCTION_DECODE stage2_decode (
        .clk(clk), .reset(reset),
        .prev_pc(s1_pc), .prev_instruction(s1_instruction),
        .prev_stage_valid(s1_valid), .prev_stage_ready(s1_ready),
        .out_pc(s2_pc), .out_instruction(s2_instruction),
        .out_rs1_index(s2_rs1_index), .out_rs2_index(s2_rs2_index),
        .out_rd_index(s2_rd_index),
        .next_stage_valid(s2_valid), .next_stage_ready(s2_ready),
        .flush(flush)
    );

    // =========================================================
    // Stage 3: REGISTER_DISPATCHER
    // =========================================================
    REGISTER_DISPATCHER stage3_dispatch (
        .clk(clk), .reset(reset),
        .prev_pc(s2_pc), .prev_instruction(s2_instruction),
        .prev_rs1_index(s2_rs1_index), .prev_rs2_index(s2_rs2_index),
        .prev_rd_index(s2_rd_index),
        .prev_stage_valid(s2_valid), .prev_stage_ready(s2_ready),
        .out_pc(s3_pc), .out_instruction(s3_instruction),
        .out_rs1_value(s3_rs1_value), .out_rs2_value(s3_rs2_value),
        .next_stage_valid(s3_valid), .next_stage_ready(s3_ready),
        .rf_rs1_addr(rf_rs1_addr), .rf_rs2_addr(rf_rs2_addr),
        .rf_rs1_data(rf_rs1_data), .rf_rs2_data(rf_rs2_data),
        .wb_rd_index(wb_done_index), .wb_valid(wb_done_valid),
        .flush(flush)
    );

    // =========================================================
    // Stage 4: EXECUTE_DISPATCHER (contains all ALUs)
    // =========================================================
    EXECUTE_DISPATCHER stage4_execute (
        .clk(clk), .reset(reset),
        .prev_pc(s3_pc), .prev_instruction(s3_instruction),
        .prev_rs1_value(s3_rs1_value), .prev_rs2_value(s3_rs2_value),
        .prev_stage_valid(s3_valid), .prev_stage_ready(s3_ready),
        .out_rd_index(wb_arb_rd_index), .out_rd_value(wb_arb_rd_value),
        .next_stage_valid(wb_arb_valid), .next_stage_ready(wb_arb_ready),
        .out_flush(alu_flush), .out_new_pc(alu_new_pc),
        .mem_bus_address(data_bus_address), .mem_bus_read(data_bus_read),
        .mem_bus_write(data_bus_write), .mem_bus_write_data(data_bus_write_data),
        .mem_bus_write_mask(data_bus_write_mask),
        .mem_bus_ready(data_bus_ready), .mem_bus_read_data(data_bus_read_data),
        .mem_bus_read_valid(data_bus_read_valid)
    );

    // =========================================================
    // Stage 5: WRITEBACK
    // =========================================================
    WRITEBACK stage6_writeback (
        .clk(clk), .reset(reset),
        .prev_rd_index(wb_arb_rd_index), .prev_rd_value(wb_arb_rd_value),
        .prev_stage_valid(wb_arb_valid), .prev_stage_ready(wb_arb_ready),
        .rf_wr_addr(rf_wr_addr), .rf_wr_data(rf_wr_data), .rf_wr_en(rf_wr_en),
        .wb_done_index(wb_done_index), .wb_done_valid(wb_done_valid)
    );

endmodule
