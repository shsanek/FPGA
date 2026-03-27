// Simple synchronous FIFO for UART byte buffering.
// Depth must be a power of 2.
module UART_FIFO #(
    parameter DEPTH = 16,
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             reset,

    // Write side
    input  wire [WIDTH-1:0] wr_data,
    input  wire             wr_en,
    output wire             full,

    // Read side
    output wire [WIDTH-1:0] rd_data,
    input  wire             rd_en,
    output wire             empty
);
    localparam ADDR_BITS = $clog2(DEPTH);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_BITS:0] wr_ptr;
    reg [ADDR_BITS:0] rd_ptr;

    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[ADDR_BITS] != rd_ptr[ADDR_BITS]) &&
                   (wr_ptr[ADDR_BITS-1:0] == rd_ptr[ADDR_BITS-1:0]);
    assign rd_data = mem[rd_ptr[ADDR_BITS-1:0]];

    always @(posedge clk) begin
        if (reset) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr[ADDR_BITS-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1;
            end
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1;
            end
        end
    end

endmodule
