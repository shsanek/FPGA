// WRITEBACK_ARBITER — collects results from all ALUs, sends to writeback.
//
// Single-cycle ALUs (compute, branch, jump, upper, system) CAN collide when
// dispatched on consecutive cycles to different ALUs. Priority mux resolves.
//
// Multi-cycle ALUs (memory, muldiv) can finish at any time, potentially
// simultaneously with each other or with a single-cycle ALU.
//
// Priority: single-cycle > memory > muldiv
// If lower priority ALU has result but higher is also done — lower waits
// (its next_stage_ready=0, it holds result).

module WRITEBACK_ARBITER (
    input wire clk,
    input wire reset,

    // === Single-cycle ALU outputs (muxed, at most one valid) ===
    input  wire [4:0]  compute_rd_index,
    input  wire [31:0] compute_rd_value,
    input  wire        compute_valid,
    output wire        compute_ready,

    input  wire [4:0]  branch_rd_index,
    input  wire [31:0] branch_rd_value,
    input  wire        branch_valid,
    output wire        branch_ready,

    input  wire [4:0]  jump_rd_index,
    input  wire [31:0] jump_rd_value,
    input  wire        jump_valid,
    output wire        jump_ready,

    input  wire [4:0]  upper_rd_index,
    input  wire [31:0] upper_rd_value,
    input  wire        upper_valid,
    output wire        upper_ready,

    input  wire [4:0]  system_rd_index,
    input  wire [31:0] system_rd_value,
    input  wire        system_valid,
    output wire        system_ready,

    // === Multi-cycle ALU outputs (can arrive anytime) ===
    input  wire [4:0]  memory_rd_index,
    input  wire [31:0] memory_rd_value,
    input  wire        memory_valid,
    output wire        memory_ready,

    input  wire [4:0]  muldiv_rd_index,
    input  wire [31:0] muldiv_rd_value,
    input  wire        muldiv_valid,
    output wire        muldiv_ready,

    // === To WRITEBACK stage ===
    output wire [4:0]  wb_rd_index,
    output wire [31:0] wb_rd_value,
    output wire        wb_valid,
    input  wire        wb_ready          // WRITEBACK can accept
);

    // =========================================================
    // Single-cycle mux (at most one valid, combinational)
    // =========================================================
    wire        single_valid = compute_valid || branch_valid || jump_valid || upper_valid || system_valid;
    wire [4:0]  single_rd_index = compute_valid ? compute_rd_index :
                                  branch_valid  ? branch_rd_index  :
                                  jump_valid    ? jump_rd_index    :
                                  upper_valid   ? upper_rd_index   :
                                                  system_rd_index;
    wire [31:0] single_rd_value = compute_valid ? compute_rd_value :
                                  branch_valid  ? branch_rd_value  :
                                  jump_valid    ? jump_rd_value    :
                                  upper_valid   ? upper_rd_value   :
                                                  system_rd_value;

    // =========================================================
    // Priority arbitration: single > memory > muldiv
    // Only one writeback per cycle (register file has 1 write port)
    // =========================================================
    wire pick_single = single_valid && wb_ready;
    wire pick_memory = !single_valid && memory_valid && wb_ready;
    wire pick_muldiv = !single_valid && !memory_valid && muldiv_valid && wb_ready;

    assign wb_valid    = pick_single || pick_memory || pick_muldiv;
    assign wb_rd_index = pick_single ? single_rd_index :
                         pick_memory ? memory_rd_index :
                                       muldiv_rd_index;
    assign wb_rd_value = pick_single ? single_rd_value :
                         pick_memory ? memory_rd_value :
                                       muldiv_rd_value;

    // =========================================================
    // Ready signals: accepted this cycle?
    // =========================================================
    // Single-cycle ALUs: ready only when THIS ALU won the mux (or no result).
    // Multiple single-cycle ALUs can finish simultaneously — only the winner clears.
    wire pick_compute = wb_ready && compute_valid;
    wire pick_branch  = wb_ready && !compute_valid && branch_valid;
    wire pick_jump    = wb_ready && !compute_valid && !branch_valid && jump_valid;
    wire pick_upper   = wb_ready && !compute_valid && !branch_valid && !jump_valid && upper_valid;
    wire pick_system  = wb_ready && !compute_valid && !branch_valid && !jump_valid && !upper_valid && system_valid;

    assign compute_ready = pick_compute || !compute_valid;
    assign branch_ready  = pick_branch  || !branch_valid;
    assign jump_ready    = pick_jump    || !jump_valid;
    assign upper_ready   = pick_upper   || !upper_valid;
    assign system_ready  = pick_system  || !system_valid;

    // Multi-cycle ALUs: ready only when they win
    assign memory_ready = pick_memory;
    assign muldiv_ready = pick_muldiv;

endmodule
