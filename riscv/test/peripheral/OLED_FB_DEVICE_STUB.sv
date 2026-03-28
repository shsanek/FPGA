// Stub OLED_FB_DEVICE for iverilog simulation (no renderer, just bus ack)
module OLED_FB_DEVICE #(
    parameter BRAM_DEPTH = 12288
)(
    input  wire        clk,
    input  wire        reset,
    input  wire [27:0] address,
    input  wire        read_trigger,
    input  wire        write_trigger,
    input  wire [31:0] write_value,
    input  wire [3:0]  mask,
    output wire [31:0] read_value,
    output wire        controller_ready,
    output wire        oled_sck,
    output wire        oled_mosi,
    output wire        oled_cs_n,
    output wire        oled_dc,
    output wire        oled_res_n,
    output wire        oled_vccen,
    output wire        oled_pmoden
);
    assign read_value       = 32'b0;
    assign controller_ready = 1'b1;
    assign oled_sck    = 0;
    assign oled_mosi   = 0;
    assign oled_cs_n   = 1;
    assign oled_dc     = 0;
    assign oled_res_n  = 1;
    assign oled_vccen  = 0;
    assign oled_pmoden = 0;
endmodule
