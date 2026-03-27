module IMMEDIATE_GENERATOR_TEST();
    logic [31:0] instruction;
    wire  [31:0] imm;
    int error = 0;

    IMMEDIATE_GENERATOR dut (
        .instruction(instruction),
        .imm(imm)
    );

    initial begin
        $dumpfile("IMMEDIATE_GENERATOR.vcd");
        $dumpvars(0, IMMEDIATE_GENERATOR_TEST);

        // --- I-type ---
        // ADDI x1, x2, 5
        // inst = 000000000101_00010_000_00001_0010011
        instruction = 32'h00510093; #1;
        assert(imm === 32'h00000005) else begin
            $display("FAIL I-type +5: got %h", imm); error = error + 1;
        end

        // ADDI x1, x2, -3  (imm = 0xFFFFFFFD)
        // inst = 111111111101_00010_000_00001_0010011
        instruction = 32'hFFD10093; #1;
        assert(imm === 32'hFFFFFFFD) else begin
            $display("FAIL I-type -3: got %h", imm); error = error + 1;
        end

        // LW x1, 12(x2)
        // inst = 000000001100_00010_010_00001_0000011
        instruction = 32'h00C10083; #1;
        assert(imm === 32'h0000000C) else begin
            $display("FAIL I-type LOAD +12: got %h", imm); error = error + 1;
        end

        // JALR x0, x1, -4
        // inst = 111111111100_00001_000_00000_1100111
        instruction = 32'hFFC08067; #1;
        assert(imm === 32'hFFFFFFFC) else begin
            $display("FAIL I-type JALR -4: got %h", imm); error = error + 1;
        end

        // --- S-type ---
        // SW x3, 8(x2)
        // imm[11:5]=0000000  imm[4:0]=01000
        // inst = 0000000_00011_00010_010_01000_0100011
        instruction = 32'h00312423; #1;
        assert(imm === 32'h00000008) else begin
            $display("FAIL S-type +8: got %h", imm); error = error + 1;
        end

        // SW x3, -8(x2)
        // imm = -8 = 0xFFFFFFF8  imm[11:5]=1111111 imm[4:0]=11000
        // inst = 1111111_00011_00010_010_11000_0100011
        instruction = 32'hFE312C23; #1;
        assert(imm === 32'hFFFFFFF8) else begin
            $display("FAIL S-type -8: got %h", imm); error = error + 1;
        end

        // --- B-type ---
        // BEQ x1, x2, +16
        // imm[12]=0 imm[11]=0 imm[10:5]=000000 imm[4:1]=1000
        // inst = 0_000000_00010_00001_000_1000_0_1100011
        instruction = 32'h00208863; #1;
        assert(imm === 32'h00000010) else begin
            $display("FAIL B-type +16: got %h", imm); error = error + 1;
        end

        // BNE x1, x2, -8
        // imm = -8 = 0xFFFFFFF8
        // imm[12]=1 imm[11]=1 imm[10:5]=111111 imm[4:1]=1100
        // inst = 1_111111_00010_00001_001_1100_1_1100011
        instruction = 32'hFE209CE3; #1;
        assert(imm === 32'hFFFFFFF8) else begin
            $display("FAIL B-type -8: got %h", imm); error = error + 1;
        end

        // --- U-type ---
        // LUI x1, 0x12345
        // inst = 00010010001101000101_00001_0110111
        instruction = 32'h123450B7; #1;
        assert(imm === 32'h12345000) else begin
            $display("FAIL U-type LUI: got %h", imm); error = error + 1;
        end

        // AUIPC x1, 0xABCDE
        // inst = 10101011110011011110_00001_0010111
        instruction = 32'hABCDE097; #1;
        assert(imm === 32'hABCDE000) else begin
            $display("FAIL U-type AUIPC: got %h", imm); error = error + 1;
        end

        // --- J-type ---
        // JAL x0, +16
        // imm[20]=0 imm[19:12]=00000000 imm[11]=0 imm[10:1]=0000001000
        // inst = 0_0000001000_0_00000000_00000_1101111
        instruction = 32'h0100006F; #1;
        assert(imm === 32'h00000010) else begin
            $display("FAIL J-type +16: got %h", imm); error = error + 1;
        end

        // JAL x1, -4
        // imm = -4 = 0xFFFFFFFC
        // imm[20]=1 imm[19:12]=11111111 imm[11]=1 imm[10:1]=1111111110
        // inst = 1_1111111110_1_11111111_00001_1101111
        instruction = 32'hFFDFF0EF; #1;
        assert(imm === 32'hFFFFFFFC) else begin
            $display("FAIL J-type -4: got %h", imm); error = error + 1;
        end

        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);

        $finish;
    end
endmodule
