// BUS_128_TO_32 — bridge between 128-bit standard bus and 32-bit device.
//
// Pure pass-through with width conversion. No internal logic.
// Device generates its own read_valid signal.

module BUS_128_TO_32 #(
    parameter ADDR_WIDTH = 32
)(
    input wire clk,
    input wire reset,

    // === 128-bit bus slave (upstream) ===
    input  wire [ADDR_WIDTH-1:0] bus_address,
    input  wire                  bus_read,
    input  wire                  bus_write,
    input  wire [127:0]          bus_write_data,
    input  wire [15:0]           bus_write_mask,
    output wire                  bus_ready,
    output wire [127:0]          bus_read_data,
    output wire                  bus_read_valid,

    // === 32-bit device (downstream) ===
    output wire [ADDR_WIDTH-1:0] dev_address,
    output wire                  dev_read,
    output wire                  dev_write,
    output wire [31:0]           dev_write_data,
    output wire [3:0]            dev_write_mask,
    input  wire [31:0]           dev_read_data,
    input  wire                  dev_ready,
    input  wire                  dev_read_valid
);

    assign dev_address    = bus_address;
    assign dev_read       = bus_read;
    assign dev_write      = bus_write;
    assign dev_write_data = bus_write_data[31:0];
    assign dev_write_mask = bus_write_mask[3:0];

    assign bus_ready      = dev_ready;
    assign bus_read_data  = {96'b0, dev_read_data};
    assign bus_read_valid = dev_read_valid;

endmodule
