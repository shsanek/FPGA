// SCRATCHPAD — 128 KB BRAM, 1-тактовый доступ.
//
// Программно-управляемый кеш для горячих ресурсов.
// controller_ready = 1 всегда (BRAM синхронный, данные через 1 такт).
// Поддержка byte mask (sb/sh/sw).
//
// Адрес: 0x0800_0000 – 0x0801_FFFF (128 KB)
// 32768 слов × 32 бит = 128 KB = ~32 BRAM36
module SCRATCHPAD #(
    parameter DEPTH   = 32768,  // 128 KB / 4
    parameter ADDR_W  = 15      // $clog2(32768)
)(
    input  wire        clk,
    input  wire        reset,

    input  wire [27:0] address,
    input  wire        read_trigger,
    input  wire        write_trigger,
    input  wire [31:0] write_value,
    input  wire [3:0]  mask,
    output wire [31:0] read_value,
    output wire        controller_ready
);

    wire [ADDR_W-1:0] word_addr = address[ADDR_W+1:2];  // byte addr → word addr

    (* ram_style = "block" *)
    logic [31:0] mem [0:DEPTH-1];

    logic [31:0] dout;

    always_ff @(posedge clk) begin
        if (write_trigger) begin
            if (mask[0]) mem[word_addr][ 7: 0] <= write_value[ 7: 0];
            if (mask[1]) mem[word_addr][15: 8] <= write_value[15: 8];
            if (mask[2]) mem[word_addr][23:16] <= write_value[23:16];
            if (mask[3]) mem[word_addr][31:24] <= write_value[31:24];
        end
        dout <= mem[word_addr];
    end

    assign read_value       = dout;
    assign controller_ready = 1'b1;

endmodule
