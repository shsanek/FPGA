// OLED I/O Device — memory-mapped контроллер PmodOLEDrgb (SSD1331).
//
// Адресное пространство (биты [3:2] адреса):
//   offset 0x00  DATA     (W) — отправить байт по SPI (блокирует bus пока SPI busy)
//   offset 0x04  CONTROL  (W/R) — управление пинами:
//                  bit 0 = CS     (chip select, active low — инвертировать в pin!)
//                  bit 1 = DC     (0=command, 1=data)
//                  bit 2 = RES    (reset, active low — инвертировать в pin!)
//                  bit 3 = VCCEN  (OLED Vcc enable)
//                  bit 4 = PMODEN (module power enable)
//   offset 0x08  STATUS   (R) — {30'b0, spi_busy, 1'b0}
//   offset 0x0C  DIVIDER  (W/R) — SPI clock делитель (полупериод SCK в тактах clk)
//
// При записи в DATA:
//   - Данные загружаются в SPI_MASTER
//   - controller_ready=0 пока SPI передаёт байт
//   - После завершения controller_ready=1
//
// CONTROL регистр: CPU управляет CS/DC/RES/VCCEN/PMODEN напрямую.
// Init sequence (power-on, reset, команды SSD1331) выполняет CPU-программа.
module OLED_IO_DEVICE (
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

    // SPI выходы
    output wire        oled_sck,
    output wire        oled_mosi,

    // Управляющие пины (active-high в регистре; инверсию делает верхний модуль)
    output wire        oled_cs_n,    // chip select (active low)
    output wire        oled_dc,      // data/command
    output wire        oled_res_n,   // reset (active low)
    output wire        oled_vccen,   // OLED Vcc enable
    output wire        oled_pmoden   // module power enable
);
    // ---------------------------------------------------------------
    // SPI Master
    // ---------------------------------------------------------------
    logic [7:0]  spi_data;
    logic        spi_trigger;
    wire         spi_busy;
    wire         spi_done;
    logic [15:0] divider_r;

    SPI_MASTER #(.DATA_WIDTH(8)) spi (
        .clk(clk), .reset(reset),
        .data(spi_data),
        .trigger(spi_trigger),
        .divider(divider_r),
        .busy(spi_busy),
        .done(spi_done),
        .sck(oled_sck),
        .mosi(oled_mosi),
        .miso(1'b1),
        .rx_data()
    );

    // ---------------------------------------------------------------
    // Регистры
    // ---------------------------------------------------------------
    logic [4:0]  control_r;  // {PMODEN, VCCEN, RES, DC, CS}
    logic [7:0]  data_r;     // последний отправленный байт

    localparam [15:0] DEFAULT_DIVIDER = 16'd7; // 81.25MHz / (2*(7+1)) ≈ 5 MHz

    // Выбор регистра
    wire [1:0] reg_sel = address[3:2];
    localparam REG_DATA    = 2'd0;
    localparam REG_CONTROL = 2'd1;
    localparam REG_STATUS  = 2'd2;
    localparam REG_DIVIDER = 2'd3;

    // ---------------------------------------------------------------
    // Управляющие пины
    // ---------------------------------------------------------------
    assign oled_cs_n   = ~control_r[0]; // инверсия: регистр 1 = CS active
    assign oled_dc     =  control_r[1];
    assign oled_res_n  = ~control_r[2]; // инверсия: регистр 1 = reset active
    assign oled_vccen  =  control_r[3];
    assign oled_pmoden =  control_r[4];

    // ---------------------------------------------------------------
    // Комбинационное чтение
    // ---------------------------------------------------------------
    reg [31:0] rdata;
    always_comb begin
        case (reg_sel)
            REG_DATA:    rdata = {24'b0, data_r};
            REG_CONTROL: rdata = {27'b0, control_r};
            REG_STATUS:  rdata = {30'b0, spi_busy, 1'b0};
            REG_DIVIDER: rdata = {16'b0, divider_r};
            default:     rdata = 32'b0;
        endcase
    end
    assign read_value = rdata;

    // ---------------------------------------------------------------
    // controller_ready: bus свободен когда SPI не занят
    // ---------------------------------------------------------------
    assign controller_ready = !spi_busy;

    // ---------------------------------------------------------------
    // Последовательная логика
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        spi_trigger <= 1'b0; // default: single-cycle pulse

        if (reset) begin
            control_r   <= 5'b00000;   // всё выключено
            data_r      <= 8'h00;
            divider_r   <= DEFAULT_DIVIDER;
        end else begin
            if (write_trigger) begin
                case (reg_sel)
                    REG_DATA: begin
                        data_r      <= write_value[7:0];
                        spi_data    <= write_value[7:0];
                        spi_trigger <= 1'b1;
                    end
                    REG_CONTROL: begin
                        control_r <= write_value[4:0];
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
