// Тест CPU_SINGLE_CYCLE
// Программа в ROM выполняет арифметику, load/store, ветвления, переходы.
// Регистры читаются через иерархические ссылки (dut.regfile.reg_values).
module CPU_SINGLE_CYCLE_TEST();
    logic clk = 0;
    logic reset;
    wire  [31:0] instr_addr;
    logic [31:0] instr_data;
    wire         mem_read_en, mem_write_en;
    wire  [31:0] mem_addr, mem_write_data;
    wire  [3:0]  mem_byte_mask;
    logic [31:0] mem_read_data;
    int error = 0;

    CPU_SINGLE_CYCLE #(.DEBUG_ENABLE(0)) dut (
        .clk            (clk),
        .reset          (reset),
        .instr_addr     (instr_addr),
        .instr_data     (instr_data),
        .mem_read_en    (mem_read_en),
        .mem_write_en   (mem_write_en),
        .mem_addr       (mem_addr),
        .mem_write_data (mem_write_data),
        .mem_byte_mask  (mem_byte_mask),
        .mem_read_data  (mem_read_data),
        .dbg_halt       (1'b0),
        .dbg_step       (1'b0),
        .dbg_is_halted  (),
        .dbg_current_pc (),
        .dbg_current_instr()
    );

    // -----------------------------------------------------------------
    // Тактовый генератор
    // -----------------------------------------------------------------
    initial forever #5 clk = ~clk;

    // -----------------------------------------------------------------
    // ROM — инструкционная память (256 слов)
    // -----------------------------------------------------------------
    logic [31:0] rom [0:255];
    assign instr_data = rom[instr_addr[9:2]];

    initial begin
        // Инициализация незадействованных адресов как NOP
        for (int i = 0; i < 256; i++) rom[i] = 32'h00000013; // addi x0,x0,0

        //  Адрес   Инструкция                 Комментарий
        rom[0]  = 32'h00A00093; // 0x00: addi x1,  x0, 10
        rom[1]  = 32'h01400113; // 0x04: addi x2,  x0, 20
        rom[2]  = 32'h002081B3; // 0x08: add  x3,  x1, x2   → x3 = 30
        rom[3]  = 32'h40110233; // 0x0C: sub  x4,  x2, x1   → x4 = 10
        rom[4]  = 32'h00302023; // 0x10: sw   x3,  0(x0)    → mem[0] = 30
        rom[5]  = 32'h00002283; // 0x14: lw   x5,  0(x0)    → x5 = 30
        rom[6]  = 32'h00001337; // 0x18: lui  x6,  1        → x6 = 0x1000
        rom[7]  = 32'h00000397; // 0x1C: auipc x7, 0        → x7 = 0x1C
        rom[8]  = 32'h00108463; // 0x20: beq  x1, x1, +8   → взять (→0x28)
        rom[9]  = 32'h0FF00093; // 0x24: addi x1, x0, 0xFF  SKIPPED
        rom[10] = 32'h02A00413; // 0x28: addi x8, x0, 42
        rom[11] = 32'h00209463; // 0x2C: bne  x1, x2, +8   → взять (→0x34)
        rom[12] = 32'h0FF00493; // 0x30: addi x9, x0, 0xFF  SKIPPED
        rom[13] = 32'h04D00493; // 0x34: addi x9, x0, 77
        rom[14] = 32'h0080056F; // 0x38: jal  x10, +8      → x10=0x3C, PC→0x40
        rom[15] = 32'h0FF00593; // 0x3C: addi x11,x0,0xFF   SKIPPED
        rom[16] = 32'h03700593; // 0x40: addi x11,x0, 55
        rom[17] = 32'h0000006F; // 0x44: jal  x0, 0        → infinite loop
    end

    // -----------------------------------------------------------------
    // RAM — память данных (256 слов, комбинационное чтение)
    // -----------------------------------------------------------------
    logic [31:0] ram [0:255];

    assign mem_read_data = ram[mem_addr[9:2]];

    always_ff @(posedge clk) begin
        if (mem_write_en) begin
            if (mem_byte_mask[0]) ram[mem_addr[9:2]][7:0]   <= mem_write_data[7:0];
            if (mem_byte_mask[1]) ram[mem_addr[9:2]][15:8]  <= mem_write_data[15:8];
            if (mem_byte_mask[2]) ram[mem_addr[9:2]][23:16] <= mem_write_data[23:16];
            if (mem_byte_mask[3]) ram[mem_addr[9:2]][31:24] <= mem_write_data[31:24];
        end
    end

    initial begin
        for (int i = 0; i < 256; i++) ram[i] = 32'b0;
    end

    // -----------------------------------------------------------------
    // Тест
    // -----------------------------------------------------------------
    initial begin
        $dumpfile("CPU_SINGLE_CYCLE.vcd");
        $dumpvars(0, CPU_SINGLE_CYCLE_TEST);

        // Сброс
        reset = 1; #20; reset = 0;

        // Ждём 25 тактов — достаточно для выполнения всех инструкций
        repeat(25) @(posedge clk); #1;

        // --- Арифметика ---
        assert(dut.regfile.reg_values[1]  === 32'd10) else begin
            $display("FAIL x1: got %0d", dut.regfile.reg_values[1]); error = error + 1;
        end
        assert(dut.regfile.reg_values[2]  === 32'd20) else begin
            $display("FAIL x2: got %0d", dut.regfile.reg_values[2]); error = error + 1;
        end
        assert(dut.regfile.reg_values[3]  === 32'd30) else begin
            $display("FAIL x3 (ADD): got %0d", dut.regfile.reg_values[3]); error = error + 1;
        end
        assert(dut.regfile.reg_values[4]  === 32'd10) else begin
            $display("FAIL x4 (SUB): got %0d", dut.regfile.reg_values[4]); error = error + 1;
        end

        // --- Load/Store ---
        assert(dut.regfile.reg_values[5]  === 32'd30) else begin
            $display("FAIL x5 (LW): got %0d", dut.regfile.reg_values[5]); error = error + 1;
        end

        // --- LUI / AUIPC ---
        assert(dut.regfile.reg_values[6]  === 32'h00001000) else begin
            $display("FAIL x6 (LUI): got %h", dut.regfile.reg_values[6]); error = error + 1;
        end
        assert(dut.regfile.reg_values[7]  === 32'h0000001C) else begin
            $display("FAIL x7 (AUIPC): got %h", dut.regfile.reg_values[7]); error = error + 1;
        end

        // --- BEQ taken: x1 не должен быть 0xFF ---
        assert(dut.regfile.reg_values[1]  === 32'd10) else begin
            $display("FAIL BEQ skip check x1: got %h", dut.regfile.reg_values[1]); error = error + 1;
        end
        assert(dut.regfile.reg_values[8]  === 32'd42) else begin
            $display("FAIL x8 (after BEQ): got %0d", dut.regfile.reg_values[8]); error = error + 1;
        end

        // --- BNE taken: x9 не должен быть 0xFF ---
        assert(dut.regfile.reg_values[9]  === 32'd77) else begin
            $display("FAIL x9 (BNE): got %0d", dut.regfile.reg_values[9]); error = error + 1;
        end

        // --- JAL: x10 = return addr, x11 не должен быть 0xFF ---
        assert(dut.regfile.reg_values[10] === 32'h0000003C) else begin
            $display("FAIL x10 (JAL ret): got %h", dut.regfile.reg_values[10]); error = error + 1;
        end
        assert(dut.regfile.reg_values[11] === 32'd55) else begin
            $display("FAIL x11 (after JAL): got %0d", dut.regfile.reg_values[11]); error = error + 1;
        end

        // --- x0 всегда 0 ---
        assert(dut.regfile.reg_values[0]  === 32'd0) else begin
            $display("FAIL x0 not zero"); error = error + 1;
        end

        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);

        $finish;
    end
endmodule
