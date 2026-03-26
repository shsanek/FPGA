// SPI Master — сдвиговый регистр с настраиваемым делителем тактовой частоты.
//
// Параметры:
//   DATA_WIDTH — ширина данных (по умолчанию 8 бит)
//
// Протокол: SPI Mode 0 (CPOL=0, CPHA=0)
//   - SCK idle = 0
//   - Data sampled on rising edge of SCK
//   - Data shifted out on falling edge of SCK
//   - MSB first
//
// Использование:
//   1. Установить divider (кол-во тактов clk на полупериод SCK)
//   2. Подать data + trigger=1 на один такт
//   3. Дождаться done=1 (busy=0)
//   4. Прочитать rx_data (принятые данные по MISO)
module SPI_MASTER #(
    parameter DATA_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  reset,

    // Управление
    input  wire [DATA_WIDTH-1:0] data,
    input  wire                  trigger,
    input  wire [15:0]           divider,  // полупериод SCK в тактах clk

    // Статус
    output wire                  busy,
    output wire                  done,     // импульс 1 такт по завершении

    // SPI
    output wire                  sck,
    output wire                  mosi,
    input  wire                  miso,     // данные от slave
    output wire [DATA_WIDTH-1:0] rx_data   // принятый байт (valid при done=1)
);
    localparam BIT_CNT_W = $clog2(DATA_WIDTH + 1);

    typedef enum logic [1:0] {
        S_IDLE,
        S_SHIFT,
        S_DONE
    } state_t;

    state_t                 state;
    logic [DATA_WIDTH-1:0]  shift_reg;
    logic [DATA_WIDTH-1:0]  rx_shift;   // MISO receive shift register
    logic [BIT_CNT_W-1:0]  bit_cnt;    // сколько бит осталось
    logic [15:0]            clk_cnt;    // счётчик делителя
    logic                   sck_r;      // текущее значение SCK

    assign busy    = (state != S_IDLE);
    assign done    = (state == S_DONE);
    assign sck     = sck_r;
    assign mosi    = shift_reg[DATA_WIDTH-1]; // MSB
    assign rx_data = rx_shift;

    always_ff @(posedge clk) begin
        if (reset) begin
            state     <= S_IDLE;
            shift_reg <= '0;
            rx_shift  <= '0;
            bit_cnt   <= '0;
            clk_cnt   <= '0;
            sck_r     <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    sck_r <= 1'b0;
                    if (trigger) begin
                        shift_reg <= data;
                        bit_cnt   <= DATA_WIDTH[BIT_CNT_W-1:0];
                        clk_cnt   <= '0;
                        state     <= S_SHIFT;
                    end
                end

                S_SHIFT: begin
                    if (clk_cnt < divider) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= '0;
                        if (!sck_r) begin
                            // Rising edge — sample MISO, slave samples MOSI
                            sck_r    <= 1'b1;
                            rx_shift <= {rx_shift[DATA_WIDTH-2:0], miso};
                        end else begin
                            // Falling edge — shift next bit
                            sck_r   <= 1'b0;
                            bit_cnt <= bit_cnt - 1'b1;
                            if (bit_cnt == 1) begin
                                // Последний бит отправлен
                                state <= S_DONE;
                            end else begin
                                shift_reg <= {shift_reg[DATA_WIDTH-2:0], 1'b0};
                            end
                        end
                    end
                end

                S_DONE: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
