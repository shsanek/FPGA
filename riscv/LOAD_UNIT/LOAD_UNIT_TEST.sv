module LOAD_UNIT_TEST();
    logic [2:0]  funct3;
    logic [31:0] mem_data;
    logic [1:0]  byte_offset;
    wire  [31:0] result;
    int error = 0;

    LOAD_UNIT dut (
        .funct3(funct3),
        .mem_data(mem_data),
        .byte_offset(byte_offset),
        .result(result)
    );

    initial begin
        $dumpfile("LOAD_UNIT.vcd");
        $dumpvars(0, LOAD_UNIT_TEST);

        mem_data = 32'hAABBCCDD;

        // --- LW ---
        funct3 = 3'b010; byte_offset = 2'd0; #1;
        assert(result === 32'hAABBCCDD) else begin
            $display("FAIL LW: got %h", result); error = error + 1;
        end

        // --- LB (знаковое) ---
        funct3 = 3'b000;
        byte_offset = 2'd0; #1;
        assert(result === 32'hFFFFFFDD) else begin   // 0xDD = -35
            $display("FAIL LB offset=0: got %h", result); error = error + 1;
        end
        byte_offset = 2'd1; #1;
        assert(result === 32'hFFFFFFCC) else begin
            $display("FAIL LB offset=1: got %h", result); error = error + 1;
        end
        byte_offset = 2'd2; #1;
        assert(result === 32'hFFFFFFBB) else begin
            $display("FAIL LB offset=2: got %h", result); error = error + 1;
        end
        byte_offset = 2'd3; #1;
        assert(result === 32'hFFFFFFAA) else begin
            $display("FAIL LB offset=3: got %h", result); error = error + 1;
        end

        // LB положительный байт (0x7F)
        mem_data = 32'h0000007F;
        funct3 = 3'b000; byte_offset = 2'd0; #1;
        assert(result === 32'h0000007F) else begin
            $display("FAIL LB positive: got %h", result); error = error + 1;
        end

        // --- LBU (беззнаковое) ---
        mem_data = 32'hAABBCCDD;
        funct3 = 3'b100;
        byte_offset = 2'd0; #1;
        assert(result === 32'h000000DD) else begin
            $display("FAIL LBU offset=0: got %h", result); error = error + 1;
        end
        byte_offset = 2'd3; #1;
        assert(result === 32'h000000AA) else begin
            $display("FAIL LBU offset=3: got %h", result); error = error + 1;
        end

        // --- LH (знаковое) ---
        mem_data = 32'hAABBCCDD;
        funct3 = 3'b001;
        byte_offset = 2'd0; #1;
        assert(result === 32'hFFFFCCDD) else begin   // 0xCCDD знаковое
            $display("FAIL LH offset=0: got %h", result); error = error + 1;
        end
        byte_offset = 2'd2; #1;
        assert(result === 32'hFFFFAABB) else begin
            $display("FAIL LH offset=2: got %h", result); error = error + 1;
        end

        // LH положительный (0x1234)
        mem_data = 32'h00001234;
        funct3 = 3'b001; byte_offset = 2'd0; #1;
        assert(result === 32'h00001234) else begin
            $display("FAIL LH positive: got %h", result); error = error + 1;
        end

        // --- LHU (беззнаковое) ---
        mem_data = 32'hAABBCCDD;
        funct3 = 3'b101;
        byte_offset = 2'd0; #1;
        assert(result === 32'h0000CCDD) else begin
            $display("FAIL LHU offset=0: got %h", result); error = error + 1;
        end
        byte_offset = 2'd2; #1;
        assert(result === 32'h0000AABB) else begin
            $display("FAIL LHU offset=2: got %h", result); error = error + 1;
        end

        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);

        $finish;
    end
endmodule
