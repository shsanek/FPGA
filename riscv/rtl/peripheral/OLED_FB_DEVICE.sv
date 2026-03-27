// OLED Framebuffer Device — BRAM framebuffer + аппаратный рендерер.
//
// Заменяет OLED_IO_DEVICE на шине. CPU пишет пиксели в BRAM через MMIO,
// затем триггерит flush — рендерер аппаратно отправляет кадр на SSD1331.
//
// Адресное пространство (внутри слота 0x1001_0000):
//   0x0000  CONTROL    (W)   bit 0: flush, bit 1: mode (0=RGB565, 1=PAL256)
//   0x0004  STATUS     (R)   bit 0: busy (flush в процессе)
//   0x0008  VP_WIDTH   (W/R) ширина viewport (96–256)
//   0x000C  VP_HEIGHT  (W/R) высота viewport (64–256)
//   0x0010–0x020F  PALETTE  (W/R) 256×16 бит RGB565
//   0x4000–0xFFFF  FRAMEBUFFER (W/R) пиксели
//
// Во время flush: controller_ready=0, CPU stall на любом обращении.
module OLED_FB_DEVICE (
    input  wire        clk,
    input  wire        reset,

    // Bus interface (от PERIPHERAL_BUS)
    input  wire [27:0] address,
    input  wire        read_trigger,
    input  wire        write_trigger,
    input  wire [31:0] write_value,
    input  wire [3:0]  mask,
    output wire [31:0] read_value,
    output wire        controller_ready,

    // OLED SPI пины
    output wire        oled_cs_n,
    output wire        oled_mosi,
    output wire        oled_sck,
    output wire        oled_dc,
    output wire        oled_res_n,
    output wire        oled_vccen,
    output wire        oled_pmoden
);

    // =========================================================
    // Параметры
    // =========================================================
    localparam FB_ADDR_START = 16'h4000;  // начало FB в адресном пространстве
    localparam PAL_ADDR_START = 16'h0010; // начало палитры
    localparam PAL_ADDR_END   = 16'h0210; // конец палитры (512 байт)

    localparam SCREEN_W = 96;
    localparam SCREEN_H = 64;

    // BRAM: по умолчанию 48 KB = 12288 слов по 32 бита
    // Для симуляции можно уменьшить через параметр
    parameter BRAM_DEPTH = 12288;
    localparam BRAM_ADDR_W = $clog2(BRAM_DEPTH);

    // SPI делитель (~10 MHz при 81.25 MHz clk)
    localparam SPI_DIVIDER = 16'd3;

    // =========================================================
    // Регистры
    // =========================================================
    logic        mode_r;         // 0=RGB565, 1=PAL256
    logic [8:0]  vp_width_r;    // 96–256
    logic [8:0]  vp_height_r;   // 64–256
    logic        flush_trigger;  // импульс flush

    // =========================================================
    // BRAM (dual-port)
    // =========================================================
    // Port A: CPU read/write (32-бит)
    // Port B: Renderer read (32-бит)
    (* ram_style = "block" *)
    logic [31:0] bram [0:BRAM_DEPTH-1];

    logic [BRAM_ADDR_W-1:0] bram_addr_a;
    logic [31:0]             bram_din_a;
    logic [31:0]             bram_dout_a;
    logic [3:0]              bram_we_a;

    logic [BRAM_ADDR_W-1:0] bram_addr_b;
    logic [31:0]             bram_dout_b;

    // Port A: CPU (read/write with byte mask)
    always_ff @(posedge clk) begin
        if (bram_we_a[0]) bram[bram_addr_a][ 7: 0] <= bram_din_a[ 7: 0];
        if (bram_we_a[1]) bram[bram_addr_a][15: 8] <= bram_din_a[15: 8];
        if (bram_we_a[2]) bram[bram_addr_a][23:16] <= bram_din_a[23:16];
        if (bram_we_a[3]) bram[bram_addr_a][31:24] <= bram_din_a[31:24];
        bram_dout_a <= bram[bram_addr_a];
    end

    // Port B: Renderer (read-only)
    always_ff @(posedge clk) begin
        bram_dout_b <= bram[bram_addr_b];
    end

    // =========================================================
    // Палитра (256×16 бит, distributed RAM)
    // =========================================================
    (* ram_style = "distributed" *)
    logic [15:0] palette [0:255];

    // =========================================================
    // Адресное декодирование
    // =========================================================
    wire [15:0] local_addr = address[15:0];
    wire is_fb      = (local_addr >= FB_ADDR_START);
    wire is_palette = (local_addr >= PAL_ADDR_START) && (local_addr < PAL_ADDR_END);
    wire is_reg     = (local_addr < PAL_ADDR_START);

    wire [1:0]  reg_sel = local_addr[3:2];
    wire [7:0]  pal_idx = local_addr[8:1]; // 16-бит записи, 512 байт / 2
    wire [BRAM_ADDR_W-1:0] fb_word_addr = local_addr[BRAM_ADDR_W+1:2]; // /4 для 32-бит слов

    // =========================================================
    // Renderer
    // =========================================================
    wire        rend_busy;
    wire        rend_done;

    // Viewport → scale
    // scale_shift: наименьший N где (w >> N) <= 96 И (h >> N) <= 64
    logic [2:0] scale_shift;
    logic [3:0] stride_shift; // log2(stride), stride = ближайшая степень двойки >= vp_width

    always_comb begin
        // stride_shift
        if (vp_width_r <= 128)
            stride_shift = 7;
        else
            stride_shift = 8; // 256

        // scale_shift
        scale_shift = 0;
        if ((vp_width_r > SCREEN_W) || (vp_height_r > SCREEN_H)) begin
            scale_shift = 1;
            if (((vp_width_r >> 1) > SCREEN_W) || ((vp_height_r >> 1) > SCREEN_H))
                scale_shift = 2;
        end
    end

    wire [6:0] disp_w = vp_width_r[8:0]  >> scale_shift;
    wire [6:0] disp_h = vp_height_r[8:0] >> scale_shift;
    wire [6:0] offset_x = (SCREEN_W[6:0] - disp_w) >> 1;
    wire [6:0] offset_y = (SCREEN_H[6:0] - disp_h) >> 1;

    // =========================================================
    // Renderer FSM
    // =========================================================
    typedef enum logic [3:0] {
        R_IDLE,
        R_INIT_POWER,
        R_INIT_RESET_HI,
        R_INIT_RESET_LO,
        R_INIT_CMD,
        R_INIT_VCCEN,
        R_INIT_DISPLAY_ON,
        R_SET_WINDOW,
        R_PIXEL_ADDR,
        R_PIXEL_READ,
        R_PIXEL_LOOKUP,
        R_PIXEL_SEND_HI,
        R_PIXEL_SEND_LO,
        R_PIXEL_NEXT,
        R_DONE
    } render_state_t;

    render_state_t rstate;
    logic        oled_initialized;
    logic [6:0]  scr_x, scr_y;
    logic [15:0] cur_pixel;
    logic [31:0] delay_cnt;
    logic [BRAM_ADDR_W+1:0] pixel_addr_r; // linear pixel/byte address

    // SSD1331 init commands (stored in ROM)
    localparam INIT_CMD_COUNT = 36;
    logic [7:0] init_cmds [0:INIT_CMD_COUNT-1];
    logic [5:0] init_cmd_idx;

    initial begin
        init_cmds[ 0] = 8'hAE; // Display OFF
        init_cmds[ 1] = 8'hA0; // Remap
        init_cmds[ 2] = 8'h72; // RGB, 65k
        init_cmds[ 3] = 8'hA1; // Start line
        init_cmds[ 4] = 8'h00;
        init_cmds[ 5] = 8'hA2; // Display offset
        init_cmds[ 6] = 8'h00;
        init_cmds[ 7] = 8'hA4; // Normal display
        init_cmds[ 8] = 8'hA8; // Multiplex
        init_cmds[ 9] = 8'h3F; // 64 lines
        init_cmds[10] = 8'hAD; // Master config
        init_cmds[11] = 8'h8E;
        init_cmds[12] = 8'hB0; // Power save OFF
        init_cmds[13] = 8'h0B;
        init_cmds[14] = 8'hB1; // Phase period
        init_cmds[15] = 8'h31;
        init_cmds[16] = 8'hB3; // Clock divider
        init_cmds[17] = 8'hF0;
        init_cmds[18] = 8'hBB; // Precharge
        init_cmds[19] = 8'h3A;
        init_cmds[20] = 8'hBE; // VCOMH
        init_cmds[21] = 8'h3E;
        init_cmds[22] = 8'h87; // Master current
        init_cmds[23] = 8'h06;
        init_cmds[24] = 8'h81; // Contrast A
        init_cmds[25] = 8'h91;
        init_cmds[26] = 8'h82; // Contrast B
        init_cmds[27] = 8'h50;
        init_cmds[28] = 8'h83; // Contrast C
        init_cmds[29] = 8'h7D;
        // Set window commands (will be sent before each frame)
        init_cmds[30] = 8'h15; // Column addr
        init_cmds[31] = 8'h00;
        init_cmds[32] = 8'h5F; // 95
        init_cmds[33] = 8'h75; // Row addr
        init_cmds[34] = 8'h00;
        init_cmds[35] = 8'h3F; // 63
    end

    // SPI interface
    logic       spi_trigger;
    logic [7:0] spi_data;
    wire        spi_busy;
    wire        spi_done;
    logic       spi_dc;     // 0=command, 1=data

    // Control pins
    logic       ctl_cs;
    logic       ctl_dc;
    logic       ctl_res;
    logic       ctl_vccen;
    logic       ctl_pmoden;

    assign oled_cs_n   = ~ctl_cs;
    assign oled_dc     = ctl_dc;
    assign oled_res_n  = ctl_res;    // active-low externally, but we store active-high
    assign oled_vccen  = ctl_vccen;
    assign oled_pmoden = ctl_pmoden;

    // SPI Master instance (внутренний, не на шине)
    wire spi_sck_w, spi_mosi_w;
    assign oled_sck  = spi_sck_w;
    assign oled_mosi = spi_mosi_w;

    SPI_MASTER spi (
        .clk     (clk),
        .reset   (reset),
        .data    (spi_data),
        .trigger (spi_trigger),
        .divider (SPI_DIVIDER),
        .busy    (spi_busy),
        .done    (spi_done),
        .sck     (spi_sck_w),
        .mosi    (spi_mosi_w),
        .miso    (1'b0),
        .rx_data ()
    );

    // =========================================================
    // Busy / controller_ready
    // =========================================================
    assign rend_busy = (rstate != R_IDLE);
    assign controller_ready = !rend_busy;

    // =========================================================
    // CPU read mux
    // =========================================================
    logic [31:0] rdata;
    always_comb begin
        if (is_fb) begin
            rdata = bram_dout_a;
        end else if (is_palette) begin
            rdata = {16'b0, palette[pal_idx]};
        end else begin
            case (reg_sel)
                2'd0: rdata = {30'b0, mode_r, 1'b0};       // CONTROL (flush bit not readable)
                2'd1: rdata = {31'b0, rend_busy};           // STATUS
                2'd2: rdata = {23'b0, vp_width_r};          // VP_WIDTH
                2'd3: rdata = {23'b0, vp_height_r};         // VP_HEIGHT
                default: rdata = 32'b0;
            endcase
        end
    end
    assign read_value = rdata;

    // =========================================================
    // BRAM Port A address (CPU side)
    // =========================================================
    always_comb begin
        bram_addr_a = fb_word_addr;
        bram_din_a  = write_value;
        bram_we_a   = 4'b0;
        if (is_fb && write_trigger && !rend_busy)
            bram_we_a = mask;
    end

    // =========================================================
    // Delay helper
    // =========================================================
    localparam DELAY_1MS  = 81250;
    localparam DELAY_20MS = 20 * DELAY_1MS;
    localparam DELAY_100MS = 100 * DELAY_1MS;

    // =========================================================
    // Main FSM
    // =========================================================
    always_ff @(posedge clk) begin
        if (reset) begin
            rstate           <= R_IDLE;
            oled_initialized <= 1'b0;
            mode_r           <= 1'b0;
            vp_width_r       <= 9'd96;
            vp_height_r      <= 9'd64;
            flush_trigger    <= 1'b0;
            spi_trigger      <= 1'b0;
            ctl_cs           <= 1'b0;
            ctl_dc           <= 1'b0;
            ctl_res          <= 1'b1; // not in reset
            ctl_vccen        <= 1'b0;
            ctl_pmoden       <= 1'b0;
            scr_x            <= 0;
            scr_y            <= 0;
            init_cmd_idx     <= 0;
            delay_cnt        <= 0;
            cur_pixel        <= 16'h0;
            bram_addr_b      <= 0;
            pixel_addr_r     <= 0;
        end else begin
            spi_trigger <= 1'b0;
            flush_trigger <= 1'b0;

            // --- Register writes (only when not busy) ---
            if (write_trigger && !rend_busy && is_reg) begin
                case (reg_sel)
                    2'd0: begin
                        if (write_value[0]) flush_trigger <= 1'b1;
                        mode_r <= write_value[1];
                    end
                    2'd2: vp_width_r  <= write_value[8:0];
                    2'd3: vp_height_r <= write_value[8:0];
                endcase
            end

            // --- Palette writes (only when not busy) ---
            if (write_trigger && !rend_busy && is_palette)
                palette[pal_idx] <= write_value[15:0];

            // --- Renderer FSM ---
            case (rstate)
                R_IDLE: begin
                    if (flush_trigger) begin
                        if (!oled_initialized) begin
                            rstate <= R_INIT_POWER;
                            delay_cnt <= DELAY_20MS;
                            ctl_pmoden <= 1'b1;
                        end else begin
                            rstate <= R_SET_WINDOW;
                            init_cmd_idx <= 30; // window commands start at idx 30
                        end
                    end
                end

                // --- OLED init sequence ---
                R_INIT_POWER: begin
                    if (delay_cnt > 0)
                        delay_cnt <= delay_cnt - 1;
                    else begin
                        ctl_res <= 1'b0; // assert reset
                        delay_cnt <= DELAY_1MS;
                        rstate <= R_INIT_RESET_HI;
                    end
                end

                R_INIT_RESET_HI: begin
                    if (delay_cnt > 0)
                        delay_cnt <= delay_cnt - 1;
                    else begin
                        ctl_res <= 1'b1; // deassert reset
                        delay_cnt <= DELAY_1MS;
                        rstate <= R_INIT_RESET_LO;
                    end
                end

                R_INIT_RESET_LO: begin
                    if (delay_cnt > 0)
                        delay_cnt <= delay_cnt - 1;
                    else begin
                        ctl_cs <= 1'b1;
                        ctl_dc <= 1'b0; // command mode
                        init_cmd_idx <= 0;
                        rstate <= R_INIT_CMD;
                    end
                end

                R_INIT_CMD: begin
                    if (!spi_busy && !spi_trigger) begin
                        if (init_cmd_idx < 30) begin
                            spi_data <= init_cmds[init_cmd_idx];
                            spi_trigger <= 1'b1;
                            init_cmd_idx <= init_cmd_idx + 1;
                        end else begin
                            // Init commands done, enable Vcc
                            ctl_vccen <= 1'b1;
                            delay_cnt <= DELAY_100MS;
                            rstate <= R_INIT_VCCEN;
                        end
                    end
                end

                R_INIT_VCCEN: begin
                    if (delay_cnt > 0)
                        delay_cnt <= delay_cnt - 1;
                    else begin
                        // Send Display ON
                        ctl_dc <= 1'b0;
                        spi_data <= 8'hAF;
                        spi_trigger <= 1'b1;
                        rstate <= R_INIT_DISPLAY_ON;
                    end
                end

                R_INIT_DISPLAY_ON: begin
                    if (spi_done) begin
                        oled_initialized <= 1'b1;
                        // Now send window commands and start pixel stream
                        init_cmd_idx <= 30;
                        rstate <= R_SET_WINDOW;
                    end
                end

                // --- Set window (before each frame) ---
                R_SET_WINDOW: begin
                    if (!spi_busy && !spi_trigger) begin
                        if (init_cmd_idx < INIT_CMD_COUNT) begin
                            ctl_dc <= 1'b0; // command mode
                            spi_data <= init_cmds[init_cmd_idx];
                            spi_trigger <= 1'b1;
                            init_cmd_idx <= init_cmd_idx + 1;
                        end else begin
                            // Window set, start pixel output
                            ctl_dc <= 1'b1; // data mode
                            scr_x <= 0;
                            scr_y <= 0;
                            rstate <= R_PIXEL_ADDR;
                        end
                    end
                end

                // --- Pixel loop ---
                R_PIXEL_ADDR: begin
                    // Compute BRAM address for (scr_x, scr_y)
                    if (scr_x < offset_x || scr_x >= (offset_x + disp_w) ||
                        scr_y < offset_y || scr_y >= (offset_y + disp_h)) begin
                        // Border pixel = black
                        cur_pixel <= 16'h0000;
                        rstate <= R_PIXEL_SEND_HI;
                    end else begin
                        // bx, by в координатах viewport
                        // pixel_linear = (by << stride_shift) + bx
                        if (mode_r) begin
                            // PAL256: 1 byte per pixel
                            // byte_addr = pixel_linear
                            // word_addr = byte_addr >> 2
                            // Сохраняем byte_addr в pixel_addr_r, word_addr в bram_addr_b
                            pixel_addr_r <=
                                (((scr_y - offset_y) << scale_shift) << stride_shift) +
                                ((scr_x - offset_x) << scale_shift);
                        end else begin
                            // RGB565: 2 bytes per pixel
                            // halfword_addr = pixel_linear
                            // word_addr = halfword_addr >> 1
                            pixel_addr_r <=
                                (((scr_y - offset_y) << scale_shift) << stride_shift) +
                                ((scr_x - offset_x) << scale_shift);
                        end
                        rstate <= R_PIXEL_READ;
                    end
                end

                R_PIXEL_READ: begin
                    // Set BRAM address based on mode (1 cycle for address, 1 for data)
                    if (mode_r)
                        bram_addr_b <= pixel_addr_r[BRAM_ADDR_W+1:2]; // byte addr >> 2
                    else
                        bram_addr_b <= pixel_addr_r[BRAM_ADDR_W:1];   // halfword addr >> 1
                    rstate <= R_PIXEL_LOOKUP;
                end

                R_PIXEL_LOOKUP: begin
                    // BRAM data ready (1 cycle latency from addr set)
                    if (mode_r) begin
                        // PAL256: extract byte by position, lookup palette
                        case (pixel_addr_r[1:0])
                            2'd0: cur_pixel <= palette[bram_dout_b[ 7: 0]];
                            2'd1: cur_pixel <= palette[bram_dout_b[15: 8]];
                            2'd2: cur_pixel <= palette[bram_dout_b[23:16]];
                            2'd3: cur_pixel <= palette[bram_dout_b[31:24]];
                        endcase
                    end else begin
                        // RGB565: extract halfword
                        if (pixel_addr_r[0])
                            cur_pixel <= bram_dout_b[31:16];
                        else
                            cur_pixel <= bram_dout_b[15:0];
                    end
                    rstate <= R_PIXEL_SEND_HI;
                end

                R_PIXEL_SEND_HI: begin
                    if (!spi_busy && !spi_trigger) begin
                        spi_data <= cur_pixel[15:8];
                        spi_trigger <= 1'b1;
                        rstate <= R_PIXEL_SEND_LO;
                    end
                end

                R_PIXEL_SEND_LO: begin
                    if (spi_done) begin
                        spi_data <= cur_pixel[7:0];
                        spi_trigger <= 1'b1;
                        rstate <= R_PIXEL_NEXT;
                    end
                end

                R_PIXEL_NEXT: begin
                    if (spi_done) begin
                        if (scr_x == SCREEN_W - 1) begin
                            scr_x <= 0;
                            if (scr_y == SCREEN_H - 1)
                                rstate <= R_DONE;
                            else begin
                                scr_y <= scr_y + 1;
                                rstate <= R_PIXEL_ADDR;
                            end
                        end else begin
                            scr_x <= scr_x + 1;
                            rstate <= R_PIXEL_ADDR;
                        end
                    end
                end

                R_DONE: begin
                    rstate <= R_IDLE;
                end
            endcase
        end
    end

endmodule
