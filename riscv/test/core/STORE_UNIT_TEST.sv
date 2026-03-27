module STORE_UNIT_TEST();
    logic [2:0]  funct3;
    logic [31:0] rs2;
    logic [1:0]  byte_offset;
    wire  [31:0] write_data;
    wire  [3:0]  byte_mask;
    int error = 0;

    STORE_UNIT dut (
        .funct3(funct3),
        .rs2(rs2),
        .byte_offset(byte_offset),
        .write_data(write_data),
        .byte_mask(byte_mask)
    );

    initial begin
        $dumpfile("STORE_UNIT.vcd");
        $dumpvars(0, STORE_UNIT_TEST);

        rs2 = 32'hAABBCCDD;

        // --- SW ---
        funct3 = 3'b010; byte_offset = 2'd0; #1;
        assert(write_data === 32'hAABBCCDD && byte_mask === 4'b1111) else begin
            $display("FAIL SW: data=%h mask=%b", write_data, byte_mask); error = error + 1;
        end

        // --- SB ---
        funct3 = 3'b000;
        byte_offset = 2'd0; #1;
        assert(write_data === 32'h000000DD && byte_mask === 4'b0001) else begin
            $display("FAIL SB offset=0: data=%h mask=%b", write_data, byte_mask); error = error + 1;
        end
        byte_offset = 2'd1; #1;
        assert(write_data === 32'h0000DD00 && byte_mask === 4'b0010) else begin
            $display("FAIL SB offset=1: data=%h mask=%b", write_data, byte_mask); error = error + 1;
        end
        byte_offset = 2'd2; #1;
        assert(write_data === 32'h00DD0000 && byte_mask === 4'b0100) else begin
            $display("FAIL SB offset=2: data=%h mask=%b", write_data, byte_mask); error = error + 1;
        end
        byte_offset = 2'd3; #1;
        assert(write_data === 32'hDD000000 && byte_mask === 4'b1000) else begin
            $display("FAIL SB offset=3: data=%h mask=%b", write_data, byte_mask); error = error + 1;
        end

        // --- SH ---
        funct3 = 3'b001;
        byte_offset = 2'd0; #1;
        assert(write_data === 32'h0000CCDD && byte_mask === 4'b0011) else begin
            $display("FAIL SH offset=0: data=%h mask=%b", write_data, byte_mask); error = error + 1;
        end
        byte_offset = 2'd2; #1;
        assert(write_data === 32'hCCDD0000 && byte_mask === 4'b1100) else begin
            $display("FAIL SH offset=2: data=%h mask=%b", write_data, byte_mask); error = error + 1;
        end

        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);

        $finish;
    end
endmodule
