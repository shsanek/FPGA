// SD I/O Device — memory-mapped контроллер PmodMicroSD (SPI mode).
//
// Адресное пространство (биты [3:2] адреса):
//   offset 0x00  DATA     (W) — отправить байт по SPI (в TX FIFO, не блокирует bus)
//                          (R) — последний принятый байт (MISO), блокирует пока FIFO+SPI не завершатся
//   offset 0x04  CONTROL  (W/R) — bit 0 = CS (1 = CS_N active low)
//   offset 0x08  STATUS   (R) — {29'b0, card_detect, spi_busy, 0}
//                                spi_busy = 1 когда FIFO не пуст ИЛИ SPI transfer в процессе
//   offset 0x0C  DIVIDER  (W/R) — SPI clock делитель
//
// Full-duplex: запись в DATA ставит байт в TX FIFO. Внутренний FSM
// кормит SPI_MASTER из FIFO. Каждый transfer принимает байт по MISO.
// Чтение DATA возвращает последний принятый байт (после завершения всех transfer).

module SD_IO_DEVICE (
    input  wire        clk,
    input  wire        reset,

    // Bus interface
    input  wire [27:0] address,
    input  wire        read_trigger,
    input  wire        write_trigger,
    input  wire [31:0] write_value,
    input  wire [3:0]  mask,
    output reg  [31:0] read_value,
    output wire        controller_ready,
    output reg         read_valid,

    // SPI
    output wire        sd_sck,
    output wire        sd_mosi,
    input  wire        sd_miso,
    output wire        sd_cs_n,

    // Card detect (active low: 0 = card inserted)
    input  wire        sd_cd_n
);
    // ---------------------------------------------------------------
    // SPI Master (full-duplex)
    // ---------------------------------------------------------------
    logic [7:0]  spi_data;
    logic        spi_trigger;
    wire         spi_busy;
    wire         spi_done;
    wire  [7:0]  spi_rx;
    logic [15:0] divider_r;

    SPI_MASTER #(.DATA_WIDTH(8)) spi (
        .clk(clk), .reset(reset),
        .data(spi_data),
        .trigger(spi_trigger),
        .divider(divider_r),
        .busy(spi_busy),
        .done(spi_done),
        .sck(sd_sck),
        .mosi(sd_mosi),
        .miso(sd_miso),
        .rx_data(spi_rx)
    );

    // ---------------------------------------------------------------
    // Регистры
    // ---------------------------------------------------------------
    logic        cs_r;
    logic [7:0]  rx_data_r;

    localparam [15:0] DEFAULT_DIVIDER = 16'd101;

    wire [1:0] reg_sel = address[3:2];
    localparam REG_DATA    = 2'd0;
    localparam REG_CONTROL = 2'd1;
    localparam REG_STATUS  = 2'd2;
    localparam REG_DIVIDER = 2'd3;

    // ---------------------------------------------------------------
    // TX FIFO (4 deep)
    // ---------------------------------------------------------------
    wire [7:0] fifo_rd_data;
    wire       fifo_empty, fifo_full;
    reg        fifo_rd_en;

    UART_FIFO #(.DEPTH(4), .WIDTH(8)) tx_fifo (
        .clk(clk), .reset(reset),
        .wr_data(write_value[7:0]),
        .wr_en(write_trigger && (reg_sel == REG_DATA) && !fifo_full),
        .full(fifo_full),
        .rd_data(fifo_rd_data),
        .rd_en(fifo_rd_en),
        .empty(fifo_empty)
    );

    assign sd_cs_n = ~cs_r;

    // SPI active = FIFO has data OR SPI transferring
    wire spi_active = !fifo_empty || spi_busy;

    // ---------------------------------------------------------------
    // Read pending (1-cycle read latency)
    // ---------------------------------------------------------------
    reg read_pending;

    // ---------------------------------------------------------------
    // controller_ready:
    //   Write DATA: blocked only when FIFO full
    //   Read DATA: blocked while SPI active (FIFO not empty OR SPI busy)
    //   Read pending: blocked until read_valid pulses
    //   All other registers: always ready
    // ---------------------------------------------------------------
    wire writing_data = write_trigger && (reg_sel == REG_DATA);
    wire reading_data = read_trigger  && (reg_sel == REG_DATA);

    assign controller_ready = read_pending ? 1'b0 :
                              writing_data ? !fifo_full :
                              reading_data ? !spi_active :
                              1'b1;

    // ---------------------------------------------------------------
    // FIFO → SPI feeder FSM
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        spi_trigger <= 1'b0;
        fifo_rd_en  <= 1'b0;

        if (reset) begin
            cs_r      <= 1'b0;
            rx_data_r <= 8'hFF;
            divider_r <= DEFAULT_DIVIDER;
            read_pending <= 0;
            read_valid   <= 0;
            read_value   <= 32'b0;
        end else begin
            read_valid <= 0;

            // --- Read pipeline ---
            if (read_trigger && controller_ready && !read_pending) begin
                read_pending <= 1;
                case (reg_sel)
                    REG_DATA:    read_value <= {24'b0, rx_data_r};
                    REG_CONTROL: read_value <= {31'b0, cs_r};
                    REG_STATUS:  read_value <= {29'b0, ~sd_cd_n, spi_active, 1'b0};
                    REG_DIVIDER: read_value <= {16'b0, divider_r};
                    default:     read_value <= 32'b0;
                endcase
            end
            if (read_pending) begin
                read_valid   <= 1;
                read_pending <= 0;
            end

            // Latch MISO result
            if (spi_done)
                rx_data_r <= spi_rx;

            // Feed SPI from FIFO when SPI is idle
            if (!spi_busy && !fifo_empty && !fifo_rd_en) begin
                fifo_rd_en  <= 1'b1;
            end

            // After FIFO read, start SPI transfer
            if (fifo_rd_en) begin
                spi_data    <= fifo_rd_data;
                spi_trigger <= 1'b1;
            end

            // Register writes (non-DATA)
            if (write_trigger) begin
                case (reg_sel)
                    REG_CONTROL: cs_r      <= write_value[0];
                    REG_DIVIDER: divider_r <= write_value[15:0];
                    default: ;
                endcase
            end
        end
    end

endmodule
