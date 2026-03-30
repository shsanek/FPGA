// EXECUTE_DISPATCHER — pipeline stage 4: route instruction to the correct ALU.
//
// Receives pc, instruction, rs1_value, rs2_value from REGISTER_DISPATCHER.
// Decodes opcode → selects one of 6 ALU units.
// Sends to the selected ALU if it's free (prev_stage_ready=1).
// Collects result from any ALU that finishes (next_stage_valid=1).
//
// Only one instruction dispatched at a time per ALU, but multiple ALUs
// can work in parallel (e.g. ALU_COMPUTE finishes while ALU_MEMORY busy).

module EXECUTE_DISPATCHER (
    input wire clk,
    input wire reset,

    // === From REGISTER_DISPATCHER ===
    input  wire [31:0] prev_pc,
    input  wire [31:0] prev_instruction,
    input  wire [31:0] prev_rs1_value,
    input  wire [31:0] prev_rs2_value,
    input  wire        prev_stage_valid,
    output wire        prev_stage_ready,

    // === To writeback (merged from all ALUs) ===
    output wire [4:0]  out_rd_index,
    output wire [31:0] out_rd_value,
    output wire        next_stage_valid,
    input  wire        next_stage_ready,

    // === Flush ===
    output wire        out_flush,
    output wire [31:0] out_new_pc,

    // === ALU_MEMORY bus master (exposed to top) ===
    output wire [31:0]  mem_bus_address,
    output wire         mem_bus_read,
    output wire         mem_bus_write,
    output wire [127:0] mem_bus_write_data,
    output wire [15:0]  mem_bus_write_mask,
    input  wire         mem_bus_ready,
    input  wire [127:0] mem_bus_read_data,
    input  wire         mem_bus_read_valid
);

    // =========================================================
    // Opcode decode (combinational)
    // =========================================================
    wire [6:0] opcode = prev_instruction[6:0];

    wire sel_compute = (opcode == 7'b0110011) || (opcode == 7'b0010011);  // R/I-type
    wire sel_branch  = (opcode == 7'b1100011);
    wire sel_jump    = (opcode == 7'b1101111) || (opcode == 7'b1100111);  // JAL/JALR
    wire sel_upper   = (opcode == 7'b0110111) || (opcode == 7'b0010111);  // LUI/AUIPC
    wire sel_memory  = (opcode == 7'b0000011) || (opcode == 7'b0100011);  // LOAD/STORE
    wire sel_muldiv  = (opcode == 7'b0110011) && (prev_instruction[25]);  // funct7[0]=1 → M-ext

    // Override: if M-ext, it's muldiv not compute
    wire sel_compute_final = sel_compute && !sel_muldiv;

    // =========================================================
    // ALU ready signals (each ALU's prev_stage_ready)
    // =========================================================
    wire compute_ready, branch_ready, jump_ready, upper_ready, memory_ready, muldiv_ready, system_ready;

    // Catch-all: FENCE, ECALL, EBREAK, unknown opcodes
    wire sel_system = !sel_compute_final && !sel_branch && !sel_jump &&
                      !sel_upper && !sel_memory && !sel_muldiv;

    // Selected ALU is ready?
    wire target_ready = (sel_compute_final && compute_ready) ||
                        (sel_branch        && branch_ready)  ||
                        (sel_jump          && jump_ready)    ||
                        (sel_upper         && upper_ready)   ||
                        (sel_memory        && memory_ready)  ||
                        (sel_muldiv        && muldiv_ready)  ||
                        (sel_system        && system_ready);

    // =========================================================
    // ALU result wires (declared before use in flush_locked logic)
    // =========================================================
    wire [4:0]  compute_rd_idx, branch_rd_idx, jump_rd_idx, upper_rd_idx, memory_rd_idx, muldiv_rd_idx, system_rd_idx;
    wire [31:0] compute_rd_val, branch_rd_val, jump_rd_val, upper_rd_val, memory_rd_val, muldiv_rd_val, system_rd_val;
    wire        compute_done,   branch_done,   jump_done,   upper_done,   memory_done,   muldiv_done,   system_done;
    wire        compute_wb_rdy, branch_wb_rdy, jump_wb_rdy, upper_wb_rdy, memory_wb_rdy, muldiv_wb_rdy, system_wb_rdy;

    wire [31:0] branch_new_pc, jump_new_pc;
    wire        branch_flush, jump_flush;

    // Flush lock: blocks dispatch while branch/jump in flight.
    reg flush_locked;

    // Block dispatch while branch/jump in flight (flush_locked)
    assign prev_stage_ready = target_ready && !flush_locked;

    // Gate valid to each ALU
    wire compute_valid = prev_stage_valid && sel_compute_final && compute_ready  && !flush_locked;
    wire branch_valid  = prev_stage_valid && sel_branch        && branch_ready   && !flush_locked;
    wire jump_valid    = prev_stage_valid && sel_jump           && jump_ready     && !flush_locked;
    wire upper_valid   = prev_stage_valid && sel_upper          && upper_ready    && !flush_locked;
    wire memory_valid  = prev_stage_valid && sel_memory         && memory_ready   && !flush_locked;
    wire muldiv_valid  = prev_stage_valid && sel_muldiv         && muldiv_ready   && !flush_locked;
    wire system_valid  = prev_stage_valid && sel_system         && system_ready   && !flush_locked;

    // Set when branch/jump dispatched. Cleared when branch/jump ALU finishes.
    always_ff @(posedge clk) begin
        if (reset)
            flush_locked <= 0;
        else if (branch_done || jump_done)
            flush_locked <= 0;
        else if ((branch_valid || jump_valid) && !flush_locked)
            flush_locked <= 1;
    end

    // =========================================================
    // ALU instances
    // =========================================================
    ALU_COMPUTE alu_compute (
        .clk(clk), .reset(reset),
        .prev_instruction(prev_instruction),
        .prev_rs1_value(prev_rs1_value), .prev_rs2_value(prev_rs2_value),
        .prev_stage_valid(compute_valid), .prev_stage_ready(compute_ready),
        .out_rd_index(compute_rd_idx), .out_rd_value(compute_rd_val),
        .next_stage_valid(compute_done), .next_stage_ready(compute_wb_rdy)
    );

    ALU_BRANCH alu_branch (
        .clk(clk), .reset(reset),
        .prev_pc(prev_pc), .prev_instruction(prev_instruction),
        .prev_rs1_value(prev_rs1_value), .prev_rs2_value(prev_rs2_value),
        .prev_stage_valid(branch_valid), .prev_stage_ready(branch_ready),
        .out_rd_index(branch_rd_idx), .out_rd_value(branch_rd_val),
        .next_stage_valid(branch_done), .next_stage_ready(branch_wb_rdy),
        .out_flush(branch_flush), .out_new_pc(branch_new_pc)
    );

    ALU_JUMP alu_jump (
        .clk(clk), .reset(reset),
        .prev_pc(prev_pc), .prev_instruction(prev_instruction),
        .prev_rs1_value(prev_rs1_value),
        .prev_stage_valid(jump_valid), .prev_stage_ready(jump_ready),
        .out_rd_index(jump_rd_idx), .out_rd_value(jump_rd_val),
        .next_stage_valid(jump_done), .next_stage_ready(jump_wb_rdy),
        .out_flush(jump_flush), .out_new_pc(jump_new_pc)
    );

    ALU_UPPER alu_upper (
        .clk(clk), .reset(reset),
        .prev_pc(prev_pc), .prev_instruction(prev_instruction),
        .prev_stage_valid(upper_valid), .prev_stage_ready(upper_ready),
        .out_rd_index(upper_rd_idx), .out_rd_value(upper_rd_val),
        .next_stage_valid(upper_done), .next_stage_ready(upper_wb_rdy)
    );

    ALU_MEMORY alu_memory (
        .clk(clk), .reset(reset),
        .prev_instruction(prev_instruction),
        .prev_rs1_value(prev_rs1_value), .prev_rs2_value(prev_rs2_value),
        .prev_stage_valid(memory_valid), .prev_stage_ready(memory_ready),
        .out_rd_index(memory_rd_idx), .out_rd_value(memory_rd_val),
        .next_stage_valid(memory_done), .next_stage_ready(memory_wb_rdy),
        .bus_address(mem_bus_address), .bus_read(mem_bus_read),
        .bus_write(mem_bus_write), .bus_write_data(mem_bus_write_data),
        .bus_write_mask(mem_bus_write_mask),
        .bus_ready(mem_bus_ready), .bus_read_data(mem_bus_read_data),
        .bus_read_valid(mem_bus_read_valid)
    );

    ALU_MULDIV alu_muldiv (
        .clk(clk), .reset(reset),
        .prev_instruction(prev_instruction),
        .prev_rs1_value(prev_rs1_value), .prev_rs2_value(prev_rs2_value),
        .prev_stage_valid(muldiv_valid), .prev_stage_ready(muldiv_ready),
        .out_rd_index(muldiv_rd_idx), .out_rd_value(muldiv_rd_val),
        .next_stage_valid(muldiv_done), .next_stage_ready(muldiv_wb_rdy)
    );

    ALU_SYSTEM alu_system (
        .clk(clk), .reset(reset),
        .prev_instruction(prev_instruction),
        .prev_stage_valid(system_valid), .prev_stage_ready(system_ready),
        .out_rd_index(system_rd_idx), .out_rd_value(system_rd_val),
        .next_stage_valid(system_done), .next_stage_ready(system_wb_rdy)
    );

    // =========================================================
    // WRITEBACK_ARBITER: per-ALU ready, priority merge
    // =========================================================
    WRITEBACK_ARBITER wb_arb (
        .compute_rd_index(compute_rd_idx), .compute_rd_value(compute_rd_val),
        .compute_valid(compute_done), .compute_ready(compute_wb_rdy),
        .branch_rd_index(branch_rd_idx), .branch_rd_value(branch_rd_val),
        .branch_valid(branch_done), .branch_ready(branch_wb_rdy),
        .jump_rd_index(jump_rd_idx), .jump_rd_value(jump_rd_val),
        .jump_valid(jump_done), .jump_ready(jump_wb_rdy),
        .upper_rd_index(upper_rd_idx), .upper_rd_value(upper_rd_val),
        .upper_valid(upper_done), .upper_ready(upper_wb_rdy),
        .system_rd_index(system_rd_idx), .system_rd_value(system_rd_val),
        .system_valid(system_done), .system_ready(system_wb_rdy),
        .memory_rd_index(memory_rd_idx), .memory_rd_value(memory_rd_val),
        .memory_valid(memory_done), .memory_ready(memory_wb_rdy),
        .muldiv_rd_index(muldiv_rd_idx), .muldiv_rd_value(muldiv_rd_val),
        .muldiv_valid(muldiv_done), .muldiv_ready(muldiv_wb_rdy),
        .wb_rd_index(out_rd_index), .wb_rd_value(out_rd_value),
        .wb_valid(next_stage_valid), .wb_ready(next_stage_ready)
    );

    // Flush from branch or jump
    assign out_flush  = branch_flush || jump_flush;
    assign out_new_pc = jump_flush ? jump_new_pc : branch_new_pc;

endmodule
