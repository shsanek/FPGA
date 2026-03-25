// Тест системных инструкций RV32I: FENCE / ECALL / EBREAK
//
// FENCE  (0001111): NOP — PC продвигается
// ECALL  (1110011, instr[20]=0): NOP — PC продвигается
// EBREAK (1110011, instr[20]=1): останов CPU до dbg_step
//
// Тесты:
//   T1: FENCE  — CPU игнорирует, x1 = 42 (проверяем что программа дошла до ADDI)
//   T2: ECALL  — аналогично, x2 = 99
//   T3: EBREAK — CPU останавливается; dbg_is_halted=1 до dbg_step;
//               после step — x3 = 7 (ADDI за EBREAK выполнился)
//   T4: EBREAK + внешний HALT → RESUME — escape через CMD_HALT + CMD_RESUME
//               x4 = 55 после resume
module CPU_SINGLE_CYCLE_SYSTEM_TEST();
    logic clk = 0;
    initial forever #5 clk = ~clk;

    logic        reset;
    int          error = 0;

    // Instruction ROM
    logic [31:0] rom [0:31];

    // CPU signals
    logic [31:0] instr_addr;
    wire  [31:0] instr_data = rom[instr_addr[6:2]];

    logic        mem_read_en, mem_write_en;
    logic [31:0] mem_addr, mem_write_data;
    logic [3:0]  mem_byte_mask;
    logic [31:0] mem_read_data = 32'b0;
    logic        mem_stall     = 0;

    logic        dbg_halt = 0;
    logic        dbg_step = 0;
    wire         dbg_is_halted;
    wire  [31:0] dbg_current_pc;
    wire  [31:0] dbg_current_instr;

    CPU_SINGLE_CYCLE #(.DEBUG_ENABLE(1)) cpu (
        .clk              (clk),
        .reset            (reset),
        .instr_addr       (instr_addr),
        .instr_data       (instr_data),
        .mem_read_en      (mem_read_en),
        .mem_write_en     (mem_write_en),
        .mem_addr         (mem_addr),
        .mem_write_data   (mem_write_data),
        .mem_byte_mask    (mem_byte_mask),
        .mem_read_data    (mem_read_data),
        .mem_stall        (mem_stall),
        .instr_stall      (1'b0),
        .dbg_halt         (dbg_halt),
        .dbg_step         (dbg_step),
        .dbg_is_halted    (dbg_is_halted),
        .dbg_current_pc   (dbg_current_pc),
        .dbg_current_instr(dbg_current_instr)
    );

    // Вспомогательная задача: один такт dbg_step=1
    task do_step();
        @(posedge clk); #1;
        dbg_step = 1;
        @(posedge clk); #1;
        dbg_step = 0;
    endtask

    initial begin
        // Инициализация ROM — всё NOP
        for (int i = 0; i < 32; i++) rom[i] = 32'h0000_0013;

        // ============================================================
        // T1: FENCE → PC продвигается, ADDI x1,x0,42 выполняется
        // Программа: FENCE | ADDI x1,x0,42 | JAL x0,0
        //   FENCE:         0x0000000F
        //   ADDI x1,x0,42: {12'd42,5'd0,3'b000,5'd1,7'b0010011} = 0x02A00093
        //   JAL x0,0:      0x0000006F
        // ============================================================
        rom[0] = 32'h0000000F;  // FENCE
        rom[1] = 32'h02A00093;  // addi x1, x0, 42
        rom[2] = 32'h0000006F;  // jal  x0, 0

        reset = 1;
        repeat(3) @(posedge clk); #1;
        reset = 0;
        repeat(10) @(posedge clk); #1;

        assert(cpu.regfile.reg_values[1] === 32'd42) else begin
            $display("FAIL T1: x1 = %0d, expected 42", cpu.regfile.reg_values[1]);
            error++;
        end

        // ============================================================
        // T2: ECALL → NOP, ADDI x2,x0,99 выполняется
        //   ECALL: 0x00000073
        //   ADDI x2,x0,99: {12'd99,5'd0,3'b000,5'd2,7'b0010011} = 0x06300113
        //   JAL x0,0:      0x0000006F
        // ============================================================
        rom[0] = 32'h00000073;  // ECALL
        rom[1] = 32'h06300113;  // addi x2, x0, 99
        rom[2] = 32'h0000006F;  // jal  x0, 0

        reset = 1;
        repeat(3) @(posedge clk); #1;
        reset = 0;
        repeat(10) @(posedge clk); #1;

        assert(cpu.regfile.reg_values[2] === 32'd99) else begin
            $display("FAIL T2: x2 = %0d, expected 99", cpu.regfile.reg_values[2]);
            error++;
        end

        // ============================================================
        // T3: EBREAK → CPU останавливается; dbg_step освобождает
        //   EBREAK: 0x00100073
        //   ADDI x3,x0,7: {12'd7,5'd0,3'b000,5'd3,7'b0010011} = 0x00700193
        //   JAL x0,0:     0x0000006F
        // ============================================================
        rom[0] = 32'h00100073;  // EBREAK
        rom[1] = 32'h00700193;  // addi x3, x0, 7
        rom[2] = 32'h0000006F;  // jal  x0, 0

        reset = 1;
        repeat(3) @(posedge clk); #1;
        reset = 0;

        // После нескольких тактов — CPU должен быть заморожен на EBREAK
        repeat(5) @(posedge clk); #1;

        assert(dbg_is_halted === 1'b1) else begin
            $display("FAIL T3: CPU not halted at EBREAK");
            error++;
        end
        assert(dbg_current_pc === 32'd0) else begin
            $display("FAIL T3: PC = 0x%08X, expected 0x00000000", dbg_current_pc);
            error++;
        end
        // ADDI ещё не должен был выполниться
        assert(cpu.regfile.reg_values[3] === 32'd0) else begin
            $display("FAIL T3: x3 = %0d before step, expected 0", cpu.regfile.reg_values[3]);
            error++;
        end

        // dbg_step — CPU делает один шаг (EBREAK → PC+4)
        do_step();
        repeat(5) @(posedge clk); #1;

        assert(cpu.regfile.reg_values[3] === 32'd7) else begin
            $display("FAIL T3: x3 = %0d after step, expected 7", cpu.regfile.reg_values[3]);
            error++;
        end
        assert(dbg_is_halted === 1'b0) else begin
            $display("FAIL T3: CPU still halted after step");
            error++;
        end

        // ============================================================
        // T4: EBREAK + внешний HALT → RESUME
        //   EBREAK: 0x00100073
        //   ADDI x4,x0,55: {12'd55,5'd0,3'b000,5'd4,7'b0010011} = 0x03700213
        //   JAL x0,0:      0x0000006F
        // ============================================================
        rom[0] = 32'h00100073;  // EBREAK
        rom[1] = 32'h03700213;  // addi x4, x0, 55
        rom[2] = 32'h0000006F;  // jal  x0, 0

        reset = 1;
        repeat(3) @(posedge clk); #1;
        reset = 0;

        // Ждём останова
        repeat(5) @(posedge clk); #1;
        assert(dbg_is_halted === 1'b1) else begin
            $display("FAIL T4: CPU not halted at EBREAK");
            error++;
        end

        // Внешний HALT (не нужен для выхода, но не должен мешать)
        @(posedge clk); #1;
        dbg_halt = 1;
        repeat(3) @(posedge clk); #1;

        // RESUME: dbg_halt → 0
        dbg_halt = 0;
        repeat(10) @(posedge clk); #1;

        assert(cpu.regfile.reg_values[4] === 32'd55) else begin
            $display("FAIL T4: x4 = %0d after resume, expected 55", cpu.regfile.reg_values[4]);
            error++;
        end
        assert(dbg_is_halted === 1'b0) else begin
            $display("FAIL T4: CPU still halted after RESUME");
            error++;
        end

        // ============================================================
        // Итог
        // ============================================================
        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);
        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
