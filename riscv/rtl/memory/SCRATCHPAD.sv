// SCRATCHPAD — 128 KB BRAM + Hardware Blitter (bus master).
//
// BRAM: простой single-port, как обычно. CPU обращается через шину.
// Blitter: FSM с MMIO регистрами. ВСЕ обращения через внешнюю шину:
//   - Чтение текстуры → DDR (через MEMORY_CONTROLLER)
//   - Чтение colormap → SCRATCHPAD (через PERIPHERAL_BUS → сюда же)
//   - Запись пикселя  → SCRATCHPAD (через PERIPHERAL_BUS → сюда же)
//
// Адрес: 0x0800_0000 – 0x0801_FFFF (128 KB BRAM)
//        0x0802_0000 – 0x0802_003F (Blitter MMIO)
module SCRATCHPAD #(
    parameter DEPTH   = 32768,  // 128 KB / 4
    parameter ADDR_W  = 15      // $clog2(32768)
)(
    input  wire        clk,
    input  wire        reset,

    // CPU / bus port (standard)
    input  wire [27:0] address,
    input  wire        read_trigger,
    input  wire        write_trigger,
    input  wire [31:0] write_value,
    input  wire [3:0]  mask,
    output wire [31:0] read_value,
    output wire        controller_ready,

    // Blitter bus master interface
    output wire        blitter_active,
    output wire [29:0] blitter_bus_addr,
    output wire        blitter_bus_rd,
    output wire        blitter_bus_wr,
    output wire [31:0] blitter_bus_wr_data,
    output wire [3:0]  blitter_bus_mask,
    input  wire [31:0] blitter_bus_data,
    input  wire        blitter_bus_ready
);

    // ---------------------------------------------------------------
    // Address decode
    // ---------------------------------------------------------------
    wire is_mmio = address[17];
    wire [ADDR_W-1:0] word_addr = address[ADDR_W+1:2];

    // ---------------------------------------------------------------
    // Simple single-port BRAM (original, untouched)
    // ---------------------------------------------------------------
    (* ram_style = "block" *)
    logic [31:0] mem [0:DEPTH-1];

    logic [31:0] dout;

    always_ff @(posedge clk) begin
        if (write_trigger && !is_mmio) begin
            if (mask[0]) mem[word_addr][ 7: 0] <= write_value[ 7: 0];
            if (mask[1]) mem[word_addr][15: 8] <= write_value[15: 8];
            if (mask[2]) mem[word_addr][23:16] <= write_value[23:16];
            if (mask[3]) mem[word_addr][31:24] <= write_value[31:24];
        end
        dout <= mem[word_addr];
    end

    // ---------------------------------------------------------------
    // Blitter MMIO registers
    // ---------------------------------------------------------------
    logic [1:0]  reg_cmd;
    logic [29:0] reg_src_addr;
    logic [31:0] reg_src_frac, reg_src_step, reg_src_mask;
    logic [31:0] reg_dst_offset, reg_dst_step;
    logic [31:0] reg_count, reg_cmap_offset;
    logic [31:0] reg_src_yfrac, reg_src_ystep;
    logic [4:0]  reg_src_shift;

    // ---------------------------------------------------------------
    // Blitter FSM
    // ---------------------------------------------------------------
    localparam [3:0]
        S_IDLE        = 4'd0,
        S_FETCH_TEX   = 4'd1,   // set DDR addr, rd=1
        S_SETTLE_TEX  = 4'd2,   // bus settles (registered outputs)
        S_WAIT_TEX    = 4'd3,   // wait ready, grab texel
        S_FETCH_CMAP  = 4'd4,   // set scratchpad cmap addr, rd=1
        S_SETTLE_CMAP = 4'd5,
        S_WAIT_CMAP   = 4'd6,   // wait ready, grab pixel from colormap
        S_WRITE_PIXEL = 4'd7,   // set scratchpad dst addr, wr=1
        S_SETTLE_WR   = 4'd8,
        S_WAIT_WR     = 4'd9,   // wait ready (write accepted)
        S_NEXT        = 4'd10,
        S_DONE        = 4'd11;

    logic [3:0]  blit_state;
    wire         blit_busy = (blit_state != S_IDLE);

    // MMIO read
    logic [31:0] mmio_rd_data;
    always_comb begin
        case (address[5:2])
            4'h0: mmio_rd_data = {30'b0, reg_cmd};
            4'h1: mmio_rd_data = {31'b0, blit_busy};
            4'h2: mmio_rd_data = {2'b0, reg_src_addr};
            4'h3: mmio_rd_data = reg_src_frac;
            4'h4: mmio_rd_data = reg_src_step;
            4'h5: mmio_rd_data = reg_src_mask;
            4'h6: mmio_rd_data = reg_dst_offset;
            4'h7: mmio_rd_data = reg_dst_step;
            4'h8: mmio_rd_data = reg_count;
            4'h9: mmio_rd_data = reg_cmap_offset;
            4'hA: mmio_rd_data = reg_src_yfrac;
            4'hB: mmio_rd_data = reg_src_ystep;
            4'hC: mmio_rd_data = {27'b0, reg_src_shift};
            default: mmio_rd_data = 32'b0;
        endcase
    end

    assign read_value       = is_mmio ? mmio_rd_data : dout;
    assign controller_ready = 1'b1;

    // ---------------------------------------------------------------
    // Working registers
    // ---------------------------------------------------------------
    logic [31:0] w_src_frac, w_dst_offset, w_count, w_src_yfrac;
    logic [7:0]  w_texel;
    logic [7:0]  w_pixel;

    // Bus master outputs (registered)
    logic [29:0] blit_addr;
    logic        blit_rd, blit_wr;
    logic [31:0] blit_wr_data;
    logic [3:0]  blit_mask;

    assign blitter_active     = blit_busy;
    assign blitter_bus_addr   = blit_addr;
    assign blitter_bus_rd     = blit_rd;
    assign blitter_bus_wr     = blit_wr;
    assign blitter_bus_wr_data = blit_wr_data;
    assign blitter_bus_mask   = blit_mask;

    // ---------------------------------------------------------------
    // Address calculations
    // ---------------------------------------------------------------
    // Scratchpad base in 30-bit bus address space:
    // addr[29]=0, addr[28]=1, addr[18]=1 → 0x10040000
    localparam [29:0] SP_BASE = 30'h10040000;

    // Texture index
    wire [31:0] tex_idx_col = (w_src_frac >> 16) & reg_src_mask;
    wire [31:0] span_mask   = (32'd1 << reg_src_shift) - 32'd1;
    wire [31:0] span_y_part = ($signed(w_src_yfrac) >>> (5'd16 - reg_src_shift)) & (span_mask << reg_src_shift);
    wire [31:0] span_x_part = ($signed(w_src_frac) >>> 16) & span_mask;
    wire [31:0] tex_idx_span = span_y_part + span_x_part;
    wire [31:0] tex_idx = (reg_cmd == 2'd2) ? tex_idx_span : tex_idx_col;

    // DDR texture address (full 30-bit bus addr)
    wire [27:0] tex_ddr_byte = reg_src_addr[27:0] + tex_idx[27:0];
    wire [29:0] tex_bus_addr = {reg_src_addr[29:28], tex_ddr_byte[27:2], 2'b0};
    wire [1:0]  tex_byte_lane = tex_ddr_byte[1:0];

    // Scratchpad colormap address (30-bit bus addr)
    wire [31:0] cmap_byte_off = reg_cmap_offset + {24'b0, w_texel};
    wire [29:0] cmap_bus_addr = SP_BASE + {12'b0, cmap_byte_off[17:2], 2'b0};
    wire [1:0]  cmap_byte_lane = cmap_byte_off[1:0];

    // Scratchpad destination address (30-bit bus addr)
    wire [29:0] dst_bus_addr = SP_BASE + {12'b0, w_dst_offset[17:2], 2'b0};
    wire [1:0]  dst_byte_lane = w_dst_offset[1:0];

    // ---------------------------------------------------------------
    // FSM
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            blit_state   <= S_IDLE;
            blit_rd      <= 1'b0;
            blit_wr      <= 1'b0;
            blit_addr    <= 30'b0;
            blit_wr_data <= 32'b0;
            blit_mask    <= 4'b0;
            reg_cmd      <= 2'b0;
            reg_src_addr <= 30'b0;
            reg_src_frac <= 32'b0;  reg_src_step <= 32'b0;  reg_src_mask <= 32'b0;
            reg_dst_offset <= 32'b0; reg_dst_step <= 32'b0;
            reg_count    <= 32'b0;  reg_cmap_offset <= 32'b0;
            reg_src_yfrac<= 32'b0;  reg_src_ystep <= 32'b0;  reg_src_shift <= 5'b0;
            w_src_frac   <= 32'b0;  w_dst_offset <= 32'b0;
            w_count      <= 32'b0;  w_src_yfrac  <= 32'b0;
            w_texel      <= 8'b0;   w_pixel      <= 8'b0;
        end else begin
            // MMIO writes (only when idle)
            if (write_trigger && is_mmio && !blit_busy) begin
                case (address[5:2])
                    4'h0: reg_cmd        <= write_value[1:0];
                    4'h2: reg_src_addr   <= write_value[29:0];
                    4'h3: reg_src_frac   <= write_value;
                    4'h4: reg_src_step   <= write_value;
                    4'h5: reg_src_mask   <= write_value;
                    4'h6: reg_dst_offset <= write_value;
                    4'h7: reg_dst_step   <= write_value;
                    4'h8: reg_count      <= write_value;
                    4'h9: reg_cmap_offset<= write_value;
                    4'hA: reg_src_yfrac  <= write_value;
                    4'hB: reg_src_ystep  <= write_value;
                    4'hC: reg_src_shift  <= write_value[4:0];
                    default: ;
                endcase
            end

            case (blit_state)
                // ---- IDLE ----
                S_IDLE: begin
                    blit_rd <= 1'b0;
                    blit_wr <= 1'b0;
                    if (write_trigger && is_mmio && address[5:2] == 4'h0
                        && write_value[1:0] != 2'b0) begin
                        reg_cmd      <= write_value[1:0];
                        w_src_frac   <= reg_src_frac;
                        w_dst_offset <= reg_dst_offset;
                        w_count      <= reg_count;
                        w_src_yfrac  <= reg_src_yfrac;
                        blit_state   <= S_FETCH_TEX;
                    end
                end

                // ---- Phase 1: Read texture byte from DDR ----
                S_FETCH_TEX: begin
                    blit_addr  <= tex_bus_addr;
                    blit_rd    <= 1'b1;
                    blit_wr    <= 1'b0;
                    blit_state <= S_SETTLE_TEX;
                end

                S_SETTLE_TEX: begin
                    // Registered outputs now on bus. MC processes address.
                    blit_state <= S_WAIT_TEX;
                end

                S_WAIT_TEX: begin
                    if (blitter_bus_ready) begin
                        case (tex_byte_lane)
                            2'd0: w_texel <= blitter_bus_data[ 7: 0];
                            2'd1: w_texel <= blitter_bus_data[15: 8];
                            2'd2: w_texel <= blitter_bus_data[23:16];
                            2'd3: w_texel <= blitter_bus_data[31:24];
                        endcase
                        blit_rd    <= 1'b0;
                        blit_state <= S_FETCH_CMAP;
                    end
                end

                // ---- Phase 2: Read colormap from scratchpad ----
                S_FETCH_CMAP: begin
                    blit_addr  <= cmap_bus_addr;
                    blit_rd    <= 1'b1;
                    blit_wr    <= 1'b0;
                    blit_state <= S_SETTLE_CMAP;
                end

                S_SETTLE_CMAP: begin
                    // Bus has scratchpad addr. BRAM reads this cycle.
                    blit_state <= S_WAIT_CMAP;
                end

                S_WAIT_CMAP: begin
                    if (blitter_bus_ready) begin
                        case (cmap_byte_lane)
                            2'd0: w_pixel <= blitter_bus_data[ 7: 0];
                            2'd1: w_pixel <= blitter_bus_data[15: 8];
                            2'd2: w_pixel <= blitter_bus_data[23:16];
                            2'd3: w_pixel <= blitter_bus_data[31:24];
                        endcase
                        blit_rd    <= 1'b0;
                        blit_state <= S_WRITE_PIXEL;
                    end
                end

                // ---- Phase 3: Write pixel to scratchpad ----
                S_WRITE_PIXEL: begin
                    blit_addr  <= dst_bus_addr;
                    blit_rd    <= 1'b0;
                    blit_wr    <= 1'b1;
                    case (dst_byte_lane)
                        2'd0: begin blit_mask <= 4'b0001; blit_wr_data <= {24'b0, w_pixel}; end
                        2'd1: begin blit_mask <= 4'b0010; blit_wr_data <= {16'b0, w_pixel, 8'b0}; end
                        2'd2: begin blit_mask <= 4'b0100; blit_wr_data <= {8'b0, w_pixel, 16'b0}; end
                        2'd3: begin blit_mask <= 4'b1000; blit_wr_data <= {w_pixel, 24'b0}; end
                    endcase
                    blit_state <= S_SETTLE_WR;
                end

                S_SETTLE_WR: begin
                    // Write signals now on bus.
                    blit_state <= S_WAIT_WR;
                end

                S_WAIT_WR: begin
                    if (blitter_bus_ready) begin
                        blit_wr    <= 1'b0;
                        blit_state <= S_NEXT;
                    end
                end

                // ---- Next pixel / done ----
                S_NEXT: begin
                    w_src_frac   <= w_src_frac + reg_src_step;
                    w_dst_offset <= w_dst_offset + reg_dst_step;
                    w_count      <= w_count - 32'd1;
                    if (reg_cmd == 2'd2)
                        w_src_yfrac <= w_src_yfrac + reg_src_ystep;
                    blit_state <= (w_count > 32'd1) ? S_FETCH_TEX : S_DONE;
                end

                S_DONE: begin
                    reg_cmd    <= 2'b0;
                    blit_state <= S_IDLE;
                end

                default: blit_state <= S_IDLE;
            endcase
        end
    end

endmodule
