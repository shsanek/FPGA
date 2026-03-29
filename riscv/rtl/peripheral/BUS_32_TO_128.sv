// BUS_32_TO_128 — combinational bridge from 32-bit CPU to 128-bit bus.
//
// No registers, no clock — pure wires.
//
// Write: positions 32-bit data + 4-bit mask into 128-bit line by addr[3:2].
// Read:  selects 32-bit word from 128-bit line by addr[3:2].
// Address: passed through as-is (bus uses full 32 bits).

module BUS_32_TO_128 (
    // === 32-bit CPU side ===
    input  wire [31:0] cpu_address,
    input  wire        cpu_read,
    input  wire        cpu_write,
    input  wire [31:0] cpu_write_data,
    input  wire [3:0]  cpu_write_mask,
    output wire [31:0] cpu_read_data,
    output wire        cpu_ready,
    output wire        cpu_read_valid,

    // === 128-bit bus side ===
    output wire [31:0]  bus_address,
    output wire         bus_read,
    output wire         bus_write,
    output wire [127:0] bus_write_data,
    output wire [15:0]  bus_write_mask,
    input  wire         bus_ready,
    input  wire [127:0] bus_read_data,
    input  wire         bus_read_valid
);

    // Word select from address
    wire [1:0] word_sel = cpu_address[3:2];

    // === Address, triggers, ready: pass-through ===
    assign bus_address  = cpu_address;
    assign bus_read     = cpu_read;
    assign bus_write    = cpu_write;
    assign cpu_ready    = bus_ready;
    assign cpu_read_valid = bus_read_valid;

    // === Write 32→128: position data + mask by word_sel ===
    assign bus_write_data = {
        word_sel == 2'd3 ? cpu_write_data : 32'b0,
        word_sel == 2'd2 ? cpu_write_data : 32'b0,
        word_sel == 2'd1 ? cpu_write_data : 32'b0,
        word_sel == 2'd0 ? cpu_write_data : 32'b0
    };

    assign bus_write_mask = {
        word_sel == 2'd3 ? cpu_write_mask : 4'b0,
        word_sel == 2'd2 ? cpu_write_mask : 4'b0,
        word_sel == 2'd1 ? cpu_write_mask : 4'b0,
        word_sel == 2'd0 ? cpu_write_mask : 4'b0
    };

    // === Read 128→32: select word by word_sel ===
    assign cpu_read_data = word_sel == 2'd3 ? bus_read_data[127:96] :
                           word_sel == 2'd2 ? bus_read_data[95:64]  :
                           word_sel == 2'd1 ? bus_read_data[63:32]  :
                                              bus_read_data[31:0];

endmodule
