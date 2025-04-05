module OP_0110011(
    input wire [6:0] funct7,
    input wire [2:0] funct3,

    input wire [31:0] rs1,
    input wire [31:0] rs2,

    input wire clk,

    output logic [31:0] output_value
);
    always_ff @(posedge clk) begin
        case(funct3)
            3'd0: begin
                if (!funct7[5]) begin
                    output_value = rs1 + rs2;
                end else begin 
                    output_value = rs1 - rs2;
                end
            end
            3'd1: begin
                output_value = rs1 << rs2[4:0];
            end
            3'd2: begin
                if ($signed(rs1) < $signed(rs2)) begin
                    output_value = 1;
                end else begin
                    output_value = 0;
                end
            end
            3'd3: begin
                if (rs1 < rs2) begin
                    output_value = 1;
                end else begin
                    output_value = 0;
                end
            end
            3'd4: begin
                output_value = rs1 ^ rs2;
            end
            3'd5: begin
                if (!funct7[5]) begin
                    output_value = rs1 >> rs2[4:0];
                end else begin
                    output_value = $signed(rs1) >>> rs2[4:0];
                end
            end
            3'd6: begin
                output_value = rs1 | rs2;
            end
            3'd7: begin
                output_value = rs1 & rs2;
            end
        endcase
    end
endmodule
