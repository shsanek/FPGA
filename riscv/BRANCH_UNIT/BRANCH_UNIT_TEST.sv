module BRANCH_UNIT_TEST();
    logic [2:0]  funct3;
    logic [31:0] rs1, rs2, pc, imm;
    wire         branch_taken;
    wire  [31:0] target_pc;
    int error = 0;

    BRANCH_UNIT dut (
        .funct3(funct3),
        .rs1(rs1),
        .rs2(rs2),
        .pc(pc),
        .imm(imm),
        .branch_taken(branch_taken),
        .target_pc(target_pc)
    );

    initial begin
        $dumpfile("BRANCH_UNIT.vcd");
        $dumpvars(0, BRANCH_UNIT_TEST);

        pc = 32'h1000; imm = 32'h10;   // target = 0x1010

        // --- BEQ ---
        funct3 = 3'b000;
        rs1 = 32'd5;  rs2 = 32'd5;  #1;
        assert(branch_taken === 1 && target_pc === 32'h1010) else begin
            $display("FAIL BEQ taken: taken=%b target=%h", branch_taken, target_pc); error = error + 1;
        end

        rs1 = 32'd5;  rs2 = 32'd6;  #1;
        assert(branch_taken === 0) else begin
            $display("FAIL BEQ not taken"); error = error + 1;
        end

        // --- BNE ---
        funct3 = 3'b001;
        rs1 = 32'd5;  rs2 = 32'd6;  #1;
        assert(branch_taken === 1) else begin
            $display("FAIL BNE taken"); error = error + 1;
        end

        rs1 = 32'd5;  rs2 = 32'd5;  #1;
        assert(branch_taken === 0) else begin
            $display("FAIL BNE not taken"); error = error + 1;
        end

        // --- BLT (signed) ---
        funct3 = 3'b100;
        rs1 = 32'hFFFFFFFF; rs2 = 32'd0;  #1;  // -1 < 0 → taken
        assert(branch_taken === 1) else begin
            $display("FAIL BLT -1<0"); error = error + 1;
        end

        rs1 = 32'd1; rs2 = 32'd0;  #1;           // 1 < 0 → not taken
        assert(branch_taken === 0) else begin
            $display("FAIL BLT 1<0"); error = error + 1;
        end

        rs1 = 32'd5; rs2 = 32'd5;  #1;           // 5 < 5 → not taken
        assert(branch_taken === 0) else begin
            $display("FAIL BLT equal"); error = error + 1;
        end

        // --- BGE (signed) ---
        funct3 = 3'b101;
        rs1 = 32'd0;        rs2 = 32'hFFFFFFFF; #1;  // 0 >= -1 → taken
        assert(branch_taken === 1) else begin
            $display("FAIL BGE 0>=-1"); error = error + 1;
        end

        rs1 = 32'd5; rs2 = 32'd5; #1;                // 5 >= 5 → taken
        assert(branch_taken === 1) else begin
            $display("FAIL BGE equal"); error = error + 1;
        end

        rs1 = 32'hFFFFFFFF; rs2 = 32'd1; #1;         // -1 >= 1 → not taken
        assert(branch_taken === 0) else begin
            $display("FAIL BGE -1>=1"); error = error + 1;
        end

        // --- BLTU (unsigned) ---
        funct3 = 3'b110;
        rs1 = 32'd0; rs2 = 32'hFFFFFFFF; #1;  // 0 < 0xFFFFFFFF → taken
        assert(branch_taken === 1) else begin
            $display("FAIL BLTU 0<0xFFFF"); error = error + 1;
        end

        rs1 = 32'hFFFFFFFF; rs2 = 32'd0; #1;  // 0xFFFFFFFF < 0 → not taken
        assert(branch_taken === 0) else begin
            $display("FAIL BLTU 0xFFFF<0"); error = error + 1;
        end

        // --- BGEU (unsigned) ---
        funct3 = 3'b111;
        rs1 = 32'hFFFFFFFF; rs2 = 32'd0; #1;  // 0xFFFFFFFF >= 0 → taken
        assert(branch_taken === 1) else begin
            $display("FAIL BGEU 0xFFFF>=0"); error = error + 1;
        end

        rs1 = 32'd5; rs2 = 32'd5; #1;         // 5 >= 5 → taken
        assert(branch_taken === 1) else begin
            $display("FAIL BGEU equal"); error = error + 1;
        end

        rs1 = 32'd0; rs2 = 32'hFFFFFFFF; #1;  // 0 >= 0xFFFFFFFF → not taken
        assert(branch_taken === 0) else begin
            $display("FAIL BGEU 0>=0xFFFF"); error = error + 1;
        end

        // --- target_pc с отрицательным offset ---
        pc = 32'h2000; imm = 32'hFFFFFFF0; // -16 → target = 0x1FF0
        funct3 = 3'b000; rs1 = 32'd1; rs2 = 32'd1; #1;
        assert(target_pc === 32'h1FF0) else begin
            $display("FAIL target_pc negative offset: got %h", target_pc); error = error + 1;
        end

        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);

        $finish;
    end
endmodule
