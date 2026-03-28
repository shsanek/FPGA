// SCRATCHPAD — 128 KB BRAM, 1-тактовый доступ + Hardware Blitter.
//
// Port A: CPU read/write (через шину, как обычно)
// Port B: Blitter read/write (внутренний, для colormap lookup + pixel write)
//
// Blitter MMIO регистры доступны по offset 0x20000 от базы SCRATCHPAD.
// Blitter читает текстуру из DDR через внешнюю шину (blitter_bus_*),
// читает colormap и пишет пиксели через BRAM port B.
//
// Адрес: 0x0800_0000 – 0x0801_FFFF (128 KB BRAM)
//        0x0802_0000 – 0x0802_003F (Blitter MMIO)
// 32768 слов × 32 бит = 128 KB = ~32 BRAM36
module SCRATCHPAD #(
    parameter DEPTH   = 32768,  // 128 KB / 4
    parameter ADDR_W  = 15      // $clog2(32768)
)(
    input  wire        clk,
    input  wire        reset,

    // CPU port (Port A)
    input  wire [27:0] address,
    input  wire        read_trigger,
    input  wire        write_trigger,
    input  wire [31:0] write_value,
    input  wire [3:0]  mask,
    output wire [31:0] read_value,
    output wire        controller_ready,

    // Blitter → external bus (для чтения текстур из DDR)
    output wire        blitter_active,
    output wire [29:0] blitter_bus_addr,
    output wire        blitter_bus_rd,
    input  wire [31:0] blitter_bus_data,
    input  wire        blitter_bus_ready
);

    // ---------------------------------------------------------------
    // Address decode: BRAM vs MMIO
    // ---------------------------------------------------------------
    // address[17] == 0 → BRAM (0x00000–0x1FFFF = 128 KB)
    // address[17] == 1 → MMIO regs (0x20000+)
    wire is_mmio = address[17];
    wire [ADDR_W-1:0] word_addr = address[ADDR_W+1:2];  // byte addr → word addr

    // ---------------------------------------------------------------
    // Dual-port BRAM
    // ---------------------------------------------------------------
    // Port A: CPU (read/write)
    // Port B: Blitter (read/write)
    (* ram_style = "block" *)
    logic [31:0] mem [0:DEPTH-1];

    // Port A
    logic [31:0] dout_a;
    always_ff @(posedge clk) begin
        if (write_trigger && !is_mmio) begin
            if (mask[0]) mem[word_addr][ 7: 0] <= write_value[ 7: 0];
            if (mask[1]) mem[word_addr][15: 8] <= write_value[15: 8];
            if (mask[2]) mem[word_addr][23:16] <= write_value[23:16];
            if (mask[3]) mem[word_addr][31:24] <= write_value[31:24];
        end
        dout_a <= mem[word_addr];
    end

    // Port B
    logic [ADDR_W-1:0] bram_b_addr;
    logic [31:0]       bram_b_din;
    logic [3:0]        bram_b_we;
    logic [31:0]       dout_b;
    always_ff @(posedge clk) begin
        if (bram_b_we[0]) mem[bram_b_addr][ 7: 0] <= bram_b_din[ 7: 0];
        if (bram_b_we[1]) mem[bram_b_addr][15: 8] <= bram_b_din[15: 8];
        if (bram_b_we[2]) mem[bram_b_addr][23:16] <= bram_b_din[23:16];
        if (bram_b_we[3]) mem[bram_b_addr][31:24] <= bram_b_din[31:24];
        dout_b <= mem[bram_b_addr];
    end

    // ---------------------------------------------------------------
    // Blitter MMIO registers
    // ---------------------------------------------------------------
    // 0x00 CMD          (W)  1=column, 2=span → start
    // 0x04 STATUS       (R)  bit0: busy
    // 0x08 SRC_ADDR     (W)  DDR address of texture (28-bit)
    // 0x0C SRC_FRAC     (W)  start position (fixed 16.16)
    // 0x10 SRC_STEP     (W)  step per pixel (fixed 16.16)
    // 0x14 SRC_MASK     (W)  wrap mask (63 or 127)
    // 0x18 DST_OFFSET   (W)  pixel offset in scratchpad (byte addr)
    // 0x1C DST_STEP     (W)  step: 320 for column, 1 for span
    // 0x20 COUNT        (W)  pixel count
    // 0x24 CMAP_OFFSET  (W)  colormap offset in scratchpad (byte addr)
    // 0x28 SRC_YFRAC    (W)  V coordinate (fixed 16.16) — span only
    // 0x2C SRC_YSTEP    (W)  dV/dx (fixed 16.16) — span only
    // 0x30 SRC_SHIFT    (W)  log2(texture width) — span only

    logic [1:0]  reg_cmd;
    logic [29:0] reg_src_addr;
    logic [31:0] reg_src_frac;
    logic [31:0] reg_src_step;
    logic [31:0] reg_src_mask;
    logic [31:0] reg_dst_offset;
    logic [31:0] reg_dst_step;
    logic [31:0] reg_count;
    logic [31:0] reg_cmap_offset;
    logic [31:0] reg_src_yfrac;
    logic [31:0] reg_src_ystep;
    logic [4:0]  reg_src_shift;

    // ---------------------------------------------------------------
    // Blitter FSM state (declared early for MMIO STATUS read)
    // ---------------------------------------------------------------
    localparam [3:0]
        S_IDLE        = 4'd0,
        S_FETCH_TEX   = 4'd1,
        S_WAIT_TEX    = 4'd2,
        S_LOOKUP_CMAP = 4'd3,
        S_READ_CMAP   = 4'd4,
        S_WRITE_PIXEL = 4'd5,
        S_NEXT        = 4'd6,
        S_DONE        = 4'd7;

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

    // CPU read mux
    assign read_value       = is_mmio ? mmio_rd_data : dout_a;
    assign controller_ready = 1'b1;

    // Working registers (updated during blit)
    logic [31:0] w_src_frac;
    logic [31:0] w_dst_offset;
    logic [31:0] w_count;
    logic [31:0] w_src_yfrac;
    logic [7:0]  w_texel;

    // Blitter bus outputs
    logic        blit_rd;
    logic [29:0] blit_addr;

    assign blitter_active   = blit_busy;
    assign blitter_bus_rd   = blit_rd;
    assign blitter_bus_addr = blit_addr;

    // Texture address calculation
    wire [31:0] tex_idx_col = (w_src_frac >> 16) & reg_src_mask;
    // For span: spot = ((yfrac >> (16-shift)) & ((1<<shift)-1) << shift) + ((xfrac >> 16) & ((1<<shift)-1))
    wire [31:0] span_mask = (32'd1 << reg_src_shift) - 32'd1;
    wire [31:0] span_y_part = (w_src_yfrac >> (5'd16 - reg_src_shift)) & (span_mask << reg_src_shift);
    wire [31:0] span_x_part = (w_src_frac >> 16) & span_mask;
    wire [31:0] tex_idx_span = span_y_part + span_x_part;

    wire [31:0] tex_idx = (reg_cmd == 2'd2) ? tex_idx_span : tex_idx_col;
    wire [27:0] tex_ddr_addr = reg_src_addr[27:0] + tex_idx[27:0];
    wire [1:0]  tex_byte_lane = tex_ddr_addr[1:0];

    // Colormap address in BRAM (byte → word)
    wire [31:0] cmap_byte_addr = reg_cmap_offset + {24'b0, w_texel};
    wire [ADDR_W-1:0] cmap_word_addr = cmap_byte_addr[ADDR_W+1:2];
    wire [1:0] cmap_byte_lane = cmap_byte_addr[1:0];

    // Destination address in BRAM (byte → word)
    wire [ADDR_W-1:0] dst_word_addr = w_dst_offset[ADDR_W+1:2];
    wire [1:0] dst_byte_lane = w_dst_offset[1:0];

    // MMIO write + Blitter FSM
    always_ff @(posedge clk) begin
        if (reset) begin
            blit_state     <= S_IDLE;
            blit_rd        <= 1'b0;
            blit_addr      <= 30'b0;
            bram_b_we      <= 4'b0;
            bram_b_addr    <= {ADDR_W{1'b0}};
            bram_b_din     <= 32'b0;
            reg_cmd        <= 2'b0;
            reg_src_addr   <= 30'b0;
            reg_src_frac   <= 32'b0;
            reg_src_step   <= 32'b0;
            reg_src_mask   <= 32'b0;
            reg_dst_offset <= 32'b0;
            reg_dst_step   <= 32'b0;
            reg_count      <= 32'b0;
            reg_cmap_offset<= 32'b0;
            reg_src_yfrac  <= 32'b0;
            reg_src_ystep  <= 32'b0;
            reg_src_shift  <= 5'b0;
            w_src_frac     <= 32'b0;
            w_dst_offset   <= 32'b0;
            w_count        <= 32'b0;
            w_src_yfrac    <= 32'b0;
            w_texel        <= 8'b0;
        end else begin
            // Default: clear port B write enable
            bram_b_we <= 4'b0;

            // MMIO register writes (only when blitter idle)
            if (write_trigger && is_mmio && !blit_busy) begin
                case (address[5:2])
                    4'h0: reg_cmd        <= write_value[1:0];
                    // 4'h1: STATUS is read-only
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
                S_IDLE: begin
                    blit_rd <= 1'b0;
                    // CMD write triggers blitter start
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

                S_FETCH_TEX: begin
                    // Issue DDR read for texture byte
                    // Address is word-aligned (drop low 2 bits for bus)
                    blit_addr <= {reg_src_addr[29:28], tex_ddr_addr[27:2], 2'b0};
                    blit_rd   <= 1'b1;
                    blit_state <= S_WAIT_TEX;
                end

                S_WAIT_TEX: begin
                    if (blitter_bus_ready) begin
                        // Extract the correct byte from the 32-bit word
                        case (tex_byte_lane)
                            2'd0: w_texel <= blitter_bus_data[ 7: 0];
                            2'd1: w_texel <= blitter_bus_data[15: 8];
                            2'd2: w_texel <= blitter_bus_data[23:16];
                            2'd3: w_texel <= blitter_bus_data[31:24];
                        endcase
                        blit_rd    <= 1'b0;
                        blit_state <= S_LOOKUP_CMAP;
                    end
                end

                S_LOOKUP_CMAP: begin
                    // Set up BRAM port B read for colormap lookup
                    bram_b_addr <= cmap_word_addr;
                    blit_state  <= S_READ_CMAP;
                end

                S_READ_CMAP: begin
                    // BRAM has 1-cycle latency; dout_b now has the data
                    // Extract pixel byte from colormap word
                    blit_state <= S_WRITE_PIXEL;
                end

                S_WRITE_PIXEL: begin
                    // Write pixel to screen buffer via port B
                    bram_b_addr <= dst_word_addr;
                    case (dst_byte_lane)
                        2'd0: begin
                            bram_b_we  <= 4'b0001;
                            case (cmap_byte_lane)
                                2'd0: bram_b_din <= {24'b0, dout_b[ 7: 0]};
                                2'd1: bram_b_din <= {24'b0, dout_b[15: 8]};
                                2'd2: bram_b_din <= {24'b0, dout_b[23:16]};
                                2'd3: bram_b_din <= {24'b0, dout_b[31:24]};
                            endcase
                        end
                        2'd1: begin
                            bram_b_we  <= 4'b0010;
                            case (cmap_byte_lane)
                                2'd0: bram_b_din <= {16'b0, dout_b[ 7: 0], 8'b0};
                                2'd1: bram_b_din <= {16'b0, dout_b[15: 8], 8'b0};
                                2'd2: bram_b_din <= {16'b0, dout_b[23:16], 8'b0};
                                2'd3: bram_b_din <= {16'b0, dout_b[31:24], 8'b0};
                            endcase
                        end
                        2'd2: begin
                            bram_b_we  <= 4'b0100;
                            case (cmap_byte_lane)
                                2'd0: bram_b_din <= {8'b0, dout_b[ 7: 0], 16'b0};
                                2'd1: bram_b_din <= {8'b0, dout_b[15: 8], 16'b0};
                                2'd2: bram_b_din <= {8'b0, dout_b[23:16], 16'b0};
                                2'd3: bram_b_din <= {8'b0, dout_b[31:24], 16'b0};
                            endcase
                        end
                        2'd3: begin
                            bram_b_we  <= 4'b1000;
                            case (cmap_byte_lane)
                                2'd0: bram_b_din <= {dout_b[ 7: 0], 24'b0};
                                2'd1: bram_b_din <= {dout_b[15: 8], 24'b0};
                                2'd2: bram_b_din <= {dout_b[23:16], 24'b0};
                                2'd3: bram_b_din <= {dout_b[31:24], 24'b0};
                            endcase
                        end
                    endcase
                    blit_state <= S_NEXT;
                end

                S_NEXT: begin
                    // Update working registers
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
