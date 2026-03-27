// SD I/O Device — memory-mapped контроллер PmodMicroSD (SPI mode).
//
// Адресное пространство (биты [3:2] адреса):
//   offset 0x00  DATA     (W) — отправить байт по SPI (блокирует bus)
//                          (R) — последний принятый байт (MISO)
//   offset 0x04  CONTROL  (W/R) — bit 0 = CS (1 = CS_N active low)
//   offset 0x08  STATUS   (R) — {29'b0, card_detect, spi_busy, 0}
//   offset 0x0C  DIVIDER  (W/R) — SPI clock делитель
//
// Full-duplex: запись в DATA отправляет байт по MOSI и одновременно
// принимает байт по MISO. Результат доступен при чтении DATA.
module SD_IO_DEVICE (
    input  wire        clk,
    input  wire        reset,

    // Bus interface
    input  wire [27:0] address,
    input  wire        read_trigger,
    input  wire        write_trigger,
    input  wire [31:0] write_value,
    input  wire [3:0]  mask,
    output wire [31:0] read_value,
    output wire        controller_ready,

    // SPI
    output wire        sd_sck,
    output wire        sd_mosi,
    input  wire        sd_miso,
    output wire        sd_cs_n,    // chip select (active low)

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
    logic        cs_r;         // CS state (1=active)
    logic [7:0]  rx_data_r;    // last received byte
    logic [7:0]  tx_data_r;    // last sent byte

    localparam [15:0] DEFAULT_DIVIDER = 16'd101; // ~400 kHz for SD init

    wire [1:0] reg_sel = address[3:2];
    localparam REG_DATA    = 2'd0;
    localparam REG_CONTROL = 2'd1;
    localparam REG_STATUS  = 2'd2;
    localparam REG_DIVIDER = 2'd3;

    // ---------------------------------------------------------------
    // CS pin
    // ---------------------------------------------------------------
    assign sd_cs_n = ~cs_r;

    // ---------------------------------------------------------------
    // Комбинационное чтение
    // ---------------------------------------------------------------
    reg [31:0] rdata;
    always_comb begin
        case (reg_sel)
            REG_DATA:    rdata = {24'b0, rx_data_r};
            REG_CONTROL: rdata = {31'b0, cs_r};
            REG_STATUS:  rdata = {29'b0, ~sd_cd_n, spi_busy, 1'b0};
            REG_DIVIDER: rdata = {16'b0, divider_r};
            default:     rdata = 32'b0;
        endcase
    end
    assign read_value = rdata;

    // ---------------------------------------------------------------
    // controller_ready
    // ---------------------------------------------------------------
    assign controller_ready = !spi_busy;

    // ---------------------------------------------------------------
    // Latch rx_data when SPI done
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        spi_trigger <= 1'b0;

        if (reset) begin
            cs_r      <= 1'b0;
            rx_data_r <= 8'hFF;
            tx_data_r <= 8'h00;
            divider_r <= DEFAULT_DIVIDER;
        end else begin
            // Latch MISO result
            if (spi_done)
                rx_data_r <= spi_rx;

            if (write_trigger) begin
                case (reg_sel)
                    REG_DATA: begin
                        tx_data_r   <= write_value[7:0];
                        spi_data    <= write_value[7:0];
                        spi_trigger <= 1'b1;
                    end
                    REG_CONTROL: begin
                        cs_r <= write_value[0];
                    end
                    REG_DIVIDER: begin
                        divider_r <= write_value[15:0];
                    end
                    default: ;
                endcase
            end
        end
    end

endmodule
