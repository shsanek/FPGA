// ALU_MEMORY — LOAD and STORE via bus. Multi-cycle.
//
// LOAD:  rd = mem[rs1 + imm], sign/zero extended by funct3
// STORE: mem[rs1 + imm] = rs2 (byte/half/word by funct3), rd = 5'd0
//
// Uses 128-bit bus interface. Handles byte/half/word alignment internally.

module ALU_MEMORY #(
    parameter ADDR_WIDTH = 32
)(
    input wire clk,
    input wire reset,

    // === From REGISTER_DISPATCHER ===
    input  wire [31:0] prev_instruction,
    input  wire [31:0] prev_rs1_value,
    input  wire [31:0] prev_rs2_value,
    input  wire        prev_stage_valid,
    output wire        prev_stage_ready,

    // === To writeback ===
    output reg  [4:0]  out_rd_index,
    output reg  [31:0] out_rd_value,
    output reg         next_stage_valid,
    input  wire        next_stage_ready,

    // === 128-bit bus master (to data bus) ===
    output reg  [ADDR_WIDTH-1:0] bus_address,
    output reg                   bus_read,
    output reg                   bus_write,
    output reg  [127:0]          bus_write_data,
    output reg  [15:0]           bus_write_mask,
    input  wire                  bus_ready,
    input  wire [127:0]          bus_read_data,
    input  wire                  bus_read_valid
);

    wire blocked = next_stage_valid && !next_stage_ready;

    wire [6:0] opcode = prev_instruction[6:0];
    wire [2:0] funct3 = prev_instruction[14:12];
    wire [4:0] rd     = prev_instruction[11:7];

    wire is_load  = (opcode == 7'b0000011);
    wire is_store = (opcode == 7'b0100011);

    // I-type immediate (LOAD)
    wire [31:0] imm_i = {{20{prev_instruction[31]}}, prev_instruction[31:20]};
    // S-type immediate (STORE)
    wire [31:0] imm_s = {{20{prev_instruction[31]}}, prev_instruction[31:25], prev_instruction[11:7]};

    wire [31:0] addr = prev_rs1_value + (is_store ? imm_s : imm_i);

    // =========================================================
    // FSM
    // =========================================================
    typedef enum logic [1:0] {
        S_IDLE,
        S_BUS_REQ,
        S_BUS_WAIT
    } state_t;

    state_t state;

    // Latched
    reg [31:0] lat_addr;
    reg [2:0]  lat_funct3;
    reg [4:0]  lat_rd;
    reg        lat_is_load;

    assign prev_stage_ready = (state == S_IDLE) && !blocked;

    // Byte offset within 128-bit line
    wire [3:0] byte_off = lat_addr[3:0];

    // =========================================================
    // Write data/mask positioning (for STORE)
    // =========================================================
    reg [127:0] wr_data_positioned;
    reg [15:0]  wr_mask_positioned;

    always_comb begin
        wr_data_positioned = 128'b0;
        wr_mask_positioned = 16'b0;
        case (lat_funct3[1:0])
            2'b00: begin // SB
                wr_data_positioned[byte_off*8 +: 8] = prev_rs2_value[7:0];
                wr_mask_positioned[byte_off] = 1;
            end
            2'b01: begin // SH
                wr_data_positioned[{byte_off[3:1], 3'b0} +: 16] = prev_rs2_value[15:0];
                wr_mask_positioned[{byte_off[3:1], 1'b0} +: 2] = 2'b11;
            end
            2'b10: begin // SW
                wr_data_positioned[{byte_off[3:2], 4'b0} +: 32] = prev_rs2_value;
                wr_mask_positioned[{byte_off[3:2], 2'b0} +: 4] = 4'b1111;
            end
            default: ;
        endcase
    end

    // =========================================================
    // Load data extraction (from 128-bit line)
    // =========================================================
    reg [31:0] load_result;
    always_comb begin
        load_result = 32'b0;
        case (lat_funct3)
            3'b000: begin // LB (sign-extend)
                reg [7:0] b;
                b = bus_read_data[byte_off*8 +: 8];
                load_result = {{24{b[7]}}, b};
            end
            3'b001: begin // LH (sign-extend)
                reg [15:0] h;
                h = bus_read_data[{byte_off[3:1], 3'b0} +: 16];
                load_result = {{16{h[15]}}, h};
            end
            3'b010: begin // LW
                load_result = bus_read_data[{byte_off[3:2], 4'b0} +: 32];
            end
            3'b100: begin // LBU (zero-extend)
                load_result = {24'b0, bus_read_data[byte_off*8 +: 8]};
            end
            3'b101: begin // LHU (zero-extend)
                load_result = {16'b0, bus_read_data[{byte_off[3:1], 3'b0} +: 16]};
            end
            default: load_result = 32'b0;
        endcase
    end

    // Latched rs2 for store (need to hold during bus transaction)
    reg [31:0] lat_rs2_value;

    always_ff @(posedge clk) begin
        if (reset) begin
            state            <= S_IDLE;
            next_stage_valid <= 0;
            out_rd_index     <= 5'd0;
            out_rd_value     <= 32'b0;
            bus_read         <= 0;
            bus_write        <= 0;
        end else begin
            bus_read  <= 0;
            bus_write <= 0;

            if (next_stage_valid && next_stage_ready)
                next_stage_valid <= 0;

            case (state)
                S_IDLE: begin
                    if (!blocked && prev_stage_valid) begin
                        lat_addr       <= addr;
                        lat_funct3     <= funct3;
                        lat_rd         <= is_load ? rd : 5'd0;
                        lat_is_load    <= is_load;
                        lat_rs2_value  <= prev_rs2_value;
                        state          <= S_BUS_REQ;
                    end
                end

                S_BUS_REQ: begin
                    if (bus_ready) begin
                        bus_address    <= lat_addr;
                        bus_read       <= lat_is_load;
                        bus_write      <= !lat_is_load;
                        bus_write_data <= wr_data_positioned;
                        bus_write_mask <= wr_mask_positioned;
                        state          <= S_BUS_WAIT;
                    end
                end

                S_BUS_WAIT: begin
                    if (lat_is_load) begin
                        if (bus_read_valid) begin
                            out_rd_index     <= lat_rd;
                            out_rd_value     <= load_result;
                            next_stage_valid <= 1;
                            state            <= S_IDLE;
                        end
                    end else begin
                        // Store: done when bus_ready returns
                        if (bus_ready) begin
                            out_rd_index     <= 5'd0;
                            out_rd_value     <= 32'b0;
                            next_stage_valid <= 1;
                            state            <= S_IDLE;
                        end
                    end
                end
            endcase
        end
    end

endmodule
