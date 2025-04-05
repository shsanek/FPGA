module REGISTER_32_BLOCK_32 (
    input wire clk,
    
    input wire reset_trigger,

    input wire [4:0] rs1,
    input wire [4:0] rs2,
    input wire [4:0] rd,

    input wire write_trigger,
    input wire [31:0] write_value,

    output logic [31:0] rs1_value,
    output logic [31:0] rs2_value 
);
    logic [31:0] reg_values [0:31];

    always_ff @(posedge clk or posedge reset_trigger) begin
        if (reset_trigger) begin
            for (int i = 0; i < 32; i++) begin
                reg_values[i] <= 32'b0;
            end
        end else if (write_trigger && rd != 0) begin
            reg_values[rd] <= write_value;
        end
    end

    always_ff @(posedge clk) begin
        rs1_value <= reg_values[rs1];
        rs2_value <= reg_values[rs2];
    end

endmodule