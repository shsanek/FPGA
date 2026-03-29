// BUS_128_TO_32 — bridge between 128-bit standard bus and 32-bit device.
//
// Upstream: standard 128-bit bus slave interface.
// Downstream: 32-bit device interface (address, triggers, data, mask, ready).
//
// Data mapping: bus_write_data[31:0] → device, device read → bus_read_data[31:0].
// Mask mapping: bus_write_mask[3:0] → device 4-bit mask.
// bus_read_valid: pulse 1 cycle after bus_read when bus_ready.

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
    output reg                   bus_read_valid,

    // === 32-bit device (downstream) ===
    output wire [ADDR_WIDTH-1:0] dev_address,
    output wire                  dev_read,
    output wire                  dev_write,
    output wire [31:0]           dev_write_data,
    output wire [3:0]            dev_write_mask,
    input  wire [31:0]           dev_read_data,
    input  wire                  dev_ready
);

    // Pass-through with width conversion
    assign dev_address    = bus_address;
    assign dev_read       = bus_read;
    assign dev_write      = bus_write;
    assign dev_write_data = bus_write_data[31:0];
    assign dev_write_mask = bus_write_mask[3:0];

    assign bus_ready     = dev_ready;
    assign bus_read_data = {96'b0, dev_read_data};

    // Read valid: pulse 1 cycle after read
    always_ff @(posedge clk) begin
        if (reset)
            bus_read_valid <= 0;
        else
            bus_read_valid <= bus_read && dev_ready;
    end

endmodule
