// Тест RV32M расширения — многотактовый MUL/DIV через CPU_ALU + MULDIV_UNIT
module CPU_ALU_M_TEST();
    logic        clk, reset;
    logic [2:0]  funct3;
    logic        funct7_5;
    logic        is_muldiv;
    logic [31:0] a, b;
    logic        force_add;
    logic        cpu_stall;
    wire  [31:0] result;
    wire         alu_stall;

    int error = 0;

    CPU_ALU dut (
        .clk       (clk),
        .reset     (reset),
        .funct3    (funct3),
        .funct7_5  (funct7_5),
        .is_muldiv (is_muldiv),
        .a         (a),
        .b         (b),
        .force_add (force_add),
        .cpu_stall (cpu_stall),
        .result    (result),
        .alu_stall (alu_stall)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Ждём пока alu_stall упадёт (done) — с таймаутом
    task wait_done();
        int timeout;
        timeout = 0;
        @(posedge clk); #1;  // дать NBA отработать
        while (alu_stall && timeout < 100) begin
            @(posedge clk); #1;  // ждём NBA settle после каждого фронта
            timeout = timeout + 1;
        end
        if (timeout >= 100) begin
            $display("TIMEOUT waiting for alu_stall to deassert!");
            error = error + 1;
        end
    endtask

    task check(input string name, input [31:0] expected);
        wait_done();
        if (result !== expected) begin
            $display("FAIL %s: a=0x%08X b=0x%08X result=0x%08X expected=0x%08X",
                     name, a, b, result, expected);
            error = error + 1;
        end else begin
            $display("OK   %s", name);
        end
        // Снять is_muldiv чтобы не перезапускать
        is_muldiv = 0;
        @(posedge clk);
    endtask

    // Запуск M-операции
    task run_m(input [2:0] f3, input [31:0] va, input [31:0] vb);
        @(posedge clk);
        funct3    = f3;
        a         = va;
        b         = vb;
        is_muldiv = 1;
        force_add = 0;
        funct7_5  = 0;
        @(posedge clk); // start принят
    endtask

    initial begin
        $dumpfile("CPU_ALU_M_TEST.vcd");
        $dumpvars(0, CPU_ALU_M_TEST);

        reset     = 1;
        force_add = 0;
        funct7_5  = 0;
        is_muldiv = 0;
        cpu_stall = 0;
        a = 0; b = 0; funct3 = 0;
        #20;
        reset = 0;
        @(posedge clk);

        // =====================================================================
        // MUL (funct3=000): нижние 32 бита — 3 такта
        // =====================================================================
        run_m(3'd0, 32'd7, 32'd6);
        check("MUL 7*6", 32'd42);

        run_m(3'd0, 32'hFFFF_FFFF, 32'd3);  // -1 * 3 = -3
        check("MUL -1*3", 32'hFFFF_FFFD);

        run_m(3'd0, 32'h8000_0000, 32'd2);  // INT_MIN * 2 — overflow low = 0
        check("MUL INT_MIN*2", 32'h0000_0000);

        run_m(3'd0, 32'd0, 32'd12345);
        check("MUL 0*x", 32'd0);

        // =====================================================================
        // MULH (funct3=001): верхние 32 бита signed*signed
        // =====================================================================
        run_m(3'd1, 32'd7, 32'd6);
        check("MULH 7*6", 32'd0);

        run_m(3'd1, 32'hFFFF_FFFF, 32'hFFFF_FFFF);
        check("MULH -1*-1", 32'd0);

        run_m(3'd1, 32'h7FFF_FFFF, 32'h7FFF_FFFF);
        check("MULH MAX*MAX", 32'h3FFF_FFFF);

        run_m(3'd1, 32'h8000_0000, 32'h8000_0000);
        check("MULH MIN*MIN", 32'h4000_0000);

        // =====================================================================
        // MULHSU (funct3=010): верхние 32 бита signed*unsigned
        // =====================================================================
        run_m(3'd2, 32'd7, 32'd6);
        check("MULHSU 7*6", 32'd0);

        run_m(3'd2, 32'hFFFF_FFFF, 32'd1);
        check("MULHSU -1*1", 32'hFFFF_FFFF);

        run_m(3'd2, 32'hFFFF_FFFF, 32'hFFFF_FFFF);
        check("MULHSU -1*MAX_U", 32'hFFFF_FFFF);

        // =====================================================================
        // MULHU (funct3=011): верхние 32 бита unsigned*unsigned
        // =====================================================================
        run_m(3'd3, 32'd7, 32'd6);
        check("MULHU 7*6", 32'd0);

        run_m(3'd3, 32'hFFFF_FFFF, 32'hFFFF_FFFF);
        check("MULHU MAX*MAX", 32'hFFFF_FFFE);

        run_m(3'd3, 32'h8000_0000, 32'd2);
        check("MULHU 2G*2", 32'h0000_0001);

        // =====================================================================
        // DIV (funct3=100): signed деление — 34 такта
        // =====================================================================
        run_m(3'd4, 32'd42, 32'd6);
        check("DIV 42/6", 32'd7);

        run_m(3'd4, 32'hFFFF_FFF4, 32'd3);  // -12 / 3 = -4
        check("DIV -12/3", 32'hFFFF_FFFC);

        run_m(3'd4, 32'hFFFF_FFF4, 32'hFFFF_FFFD);  // -12 / -3 = 4
        check("DIV -12/-3", 32'd4);

        run_m(3'd4, 32'd7, 32'd2);  // 7 / 2 = 3
        check("DIV 7/2", 32'd3);

        // Деление на 0 → -1
        run_m(3'd4, 32'd42, 32'd0);
        check("DIV x/0", 32'hFFFF_FFFF);

        // Overflow: INT_MIN / -1 → INT_MIN
        run_m(3'd4, 32'h8000_0000, 32'hFFFF_FFFF);
        check("DIV MIN/-1", 32'h8000_0000);

        // =====================================================================
        // DIVU (funct3=101): unsigned деление
        // =====================================================================
        run_m(3'd5, 32'd42, 32'd6);
        check("DIVU 42/6", 32'd7);

        run_m(3'd5, 32'hFFFF_FFFF, 32'd2);
        check("DIVU MAX/2", 32'h7FFF_FFFF);

        // Деление на 0 → MAX
        run_m(3'd5, 32'd42, 32'd0);
        check("DIVU x/0", 32'hFFFF_FFFF);

        // =====================================================================
        // REM (funct3=110): signed остаток
        // =====================================================================
        run_m(3'd6, 32'd7, 32'd2);
        check("REM 7%2", 32'd1);

        run_m(3'd6, 32'hFFFF_FFF9, 32'd2);  // -7 % 2 = -1
        check("REM -7%2", 32'hFFFF_FFFF);

        run_m(3'd6, 32'd7, 32'hFFFF_FFFE);  // 7 % -2 = 1
        check("REM 7%-2", 32'd1);

        // Остаток от 0 → dividend
        run_m(3'd6, 32'd42, 32'd0);
        check("REM x%0", 32'd42);

        // Overflow: INT_MIN % -1 → 0
        run_m(3'd6, 32'h8000_0000, 32'hFFFF_FFFF);
        check("REM MIN%-1", 32'd0);

        // =====================================================================
        // REMU (funct3=111): unsigned остаток
        // =====================================================================
        run_m(3'd7, 32'd7, 32'd2);
        check("REMU 7%2", 32'd1);

        run_m(3'd7, 32'hFFFF_FFFF, 32'd7);
        check("REMU MAX%7", 32'd3);

        // Остаток от 0 → dividend
        run_m(3'd7, 32'd42, 32'd0);
        check("REMU x%0", 32'd42);

        // =====================================================================
        // Проверка: is_muldiv=0 → обычный ALU (комбинационный, без stall)
        // =====================================================================
        @(posedge clk);
        is_muldiv = 0;
        funct3 = 3'd0; funct7_5 = 0; force_add = 0;
        a = 32'd10; b = 32'd5;
        #1;
        assert(result === 32'd15) else begin
            $display("FAIL ADD: result=0x%08X expected=0x0000000F", result);
            error = error + 1;
        end
        assert(alu_stall === 1'b0) else begin
            $display("FAIL: alu_stall should be 0 for base ALU");
            error = error + 1;
        end
        $display("OK   ADD (not M) — no stall");

        // =====================================================================
        $display("---");
        if (error == 0)
            $display("ALL RV32M TESTS PASSED");
        else
            $display("RV32M TEST FAILED with %0d errors", error);
        $finish;
    end
endmodule
