// FLASH_LOADER — аппаратный загрузчик программы из QSPI flash в DDR.
//
// При старте (reset):
//   1. Стопорит CPU (bus_request=1)
//   2. Ждёт готовности DDR (ddr_ready)
//   3. Читает из SPI flash по адресу FLASH_OFFSET:
//      - 4 байта magic     (LE) — должно быть 0xB007C0DE
//      - 4 байта size      (LE) — размер данных в байтах (кратно 4)
//      - 4 байта load_addr (LE) — адрес загрузки в DDR
//   4. Читает size байт и записывает в DDR начиная с load_addr
//   5. Устанавливает PC=load_addr, снимает bus_request
//   6. Переходит в DONE — неактивен до следующего reset
//
// Если magic не совпадает — переходит в DONE без загрузки.
// SPI flash команда 0x03 (READ) + 24-bit адрес, затем потоковое чтение.
module FLASH_LOADER #(
    parameter ADDRESS_SIZE  = 28,
    parameter DATA_SIZE     = 32,
    parameter FLASH_OFFSET  = 24'h300000,
    parameter SPI_DIVIDER   = 7
)(
    input  wire clk,
    input  wire reset,

    input  wire ddr_ready,

    output wire bus_request,
    input  wire bus_granted,

    output wire [ADDRESS_SIZE-1:0] mc_address,
    output wire                    mc_write_trigger,
    output wire [DATA_SIZE-1:0]    mc_write_data,
    output wire [DATA_SIZE/8-1:0]  mc_write_mask,
    input  wire                    mc_ready,

    output wire        set_pc,
    output wire [31:0] new_pc,

    output wire flash_cs_n,
    output wire flash_sck,
    output wire flash_mosi,
    input  wire flash_miso,

    output wire active
);
    localparam [31:0] MAGIC = 32'hB007C0DE;

    // ---------------------------------------------------------------
    // FSM states
    // ---------------------------------------------------------------
    typedef enum logic [3:0] {
        S_WAIT_DDR,
        S_CS_ON,
        S_SPI_XFER,       // универсальное состояние SPI transfer
        S_ASSEMBLE,       // собрать принятый байт в word
        S_WRITE_DDR,
        S_SET_PC,
        S_DONE
    } state_t;

    state_t state;
    state_t after_spi;    // куда вернуться после SPI transfer

    // ---------------------------------------------------------------
    // SPI Master
    // ---------------------------------------------------------------
    logic [7:0]  spi_tx_data;
    logic        spi_trigger_r;
    wire         spi_busy;
    wire         spi_done;
    wire  [7:0]  spi_rx;

    SPI_MASTER #(.DATA_WIDTH(8)) spi (
        .clk     (clk),
        .reset   (reset),
        .data    (spi_tx_data),
        .trigger (spi_trigger_r),
        .divider (SPI_DIVIDER[15:0]),
        .busy    (spi_busy),
        .done    (spi_done),
        .sck     (flash_sck),
        .mosi    (flash_mosi),
        .miso    (flash_miso),
        .rx_data (spi_rx)
    );

    // ---------------------------------------------------------------
    // Внутренние регистры
    // ---------------------------------------------------------------
    logic        cs_r;
    logic [31:0] saved_magic;
    logic [31:0] saved_size;
    logic [31:0] saved_load_addr;
    logic [31:0] word_buf;
    logic [1:0]  byte_idx;          // 0-3 внутри 32-bit word
    logic [3:0]  cmd_seq;           // счётчик для cmd+addr последовательности
    logic [ADDRESS_SIZE-1:0] ddr_addr;
    logic [31:0] bytes_remaining;

    logic        bus_request_r;
    logic        mc_wr_r;
    logic        set_pc_r;

    // Фаза чтения header: 0-11 = байты magic(0-3) + size(4-7) + load_addr(8-11)
    logic [3:0]  header_idx;

    // ---------------------------------------------------------------
    // Outputs
    // ---------------------------------------------------------------
    assign flash_cs_n      = ~cs_r;
    assign bus_request     = bus_request_r;
    assign mc_address      = ddr_addr;
    assign mc_write_trigger = mc_wr_r;
    assign mc_write_data   = word_buf;
    assign mc_write_mask   = {(DATA_SIZE/8){1'b1}};
    assign set_pc          = set_pc_r;
    assign new_pc          = saved_load_addr;
    assign active          = (state != S_DONE);

    // ---------------------------------------------------------------
    // CMD+ADDR sequence: 0x03, addr[23:16], addr[15:8], addr[7:0]
    // ---------------------------------------------------------------
    logic [7:0] cmd_bytes [0:3];
    assign cmd_bytes[0] = 8'h03;
    assign cmd_bytes[1] = FLASH_OFFSET[23:16];
    assign cmd_bytes[2] = FLASH_OFFSET[15:8];
    assign cmd_bytes[3] = FLASH_OFFSET[7:0];

    // ---------------------------------------------------------------
    // SPI transfer helper
    // Вызов: установить spi_tx_data, state <= S_SPI_XFER, after_spi <= next
    // SPI_XFER: trigger → wait done → jump to after_spi
    // ---------------------------------------------------------------

    // ---------------------------------------------------------------
    // Main FSM
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            state           <= S_WAIT_DDR;
            after_spi       <= S_DONE;
            cs_r            <= 1'b0;
            spi_trigger_r   <= 1'b0;
            spi_tx_data     <= 8'h00;
            saved_magic     <= 32'b0;
            saved_size      <= 32'b0;
            saved_load_addr <= 32'b0;
            word_buf        <= 32'b0;
            byte_idx        <= 2'b0;
            cmd_seq         <= 4'b0;
            header_idx      <= 4'b0;
            ddr_addr        <= '0;
            bytes_remaining <= 32'b0;
            bus_request_r   <= 1'b1;
            mc_wr_r         <= 1'b0;
            set_pc_r        <= 1'b0;
        end else begin
            spi_trigger_r <= 1'b0;
            set_pc_r      <= 1'b0;

            case (state)
                // --------------------------------------------------
                S_WAIT_DDR: begin
                    if (ddr_ready) begin
                        cs_r    <= 1'b1;      // CS active
                        state   <= S_CS_ON;
                    end
                end

                // --------------------------------------------------
                // Один такт задержки после CS on перед SPI
                S_CS_ON: begin
                    cmd_seq     <= 4'd0;
                    spi_tx_data <= cmd_bytes[0];
                    spi_trigger_r <= 1'b1;
                    state       <= S_SPI_XFER;
                    after_spi   <= S_CS_ON;    // вернёмся сюда для следующего байта cmd
                end

                // --------------------------------------------------
                // Универсальный SPI transfer: ждём done
                S_SPI_XFER: begin
                    if (spi_done) begin
                        if (after_spi == S_CS_ON) begin
                            // Отправляем cmd+addr последовательность
                            cmd_seq <= cmd_seq + 1;
                            if (cmd_seq == 4'd3) begin
                                // Все 4 байта (cmd + 3 addr) отправлены
                                // Начинаем читать header
                                header_idx  <= 4'd0;
                                byte_idx    <= 2'd0;
                                spi_tx_data <= 8'hFF;
                                spi_trigger_r <= 1'b1;
                                after_spi   <= S_ASSEMBLE;
                            end else begin
                                spi_tx_data   <= cmd_bytes[cmd_seq + 1];
                                spi_trigger_r <= 1'b1;
                                // after_spi stays S_CS_ON
                            end
                        end else if (after_spi == S_ASSEMBLE) begin
                            state <= S_ASSEMBLE;
                        end
                    end
                end

                // --------------------------------------------------
                // Собираем принятый байт в word (header или data)
                S_ASSEMBLE: begin
                    // Записываем байт в нужную позицию word_buf
                    case (byte_idx)
                        2'd0: word_buf[7:0]   <= spi_rx;
                        2'd1: word_buf[15:8]  <= spi_rx;
                        2'd2: word_buf[23:16] <= spi_rx;
                        2'd3: word_buf[31:24] <= spi_rx;
                    endcase

                    if (header_idx < 4'd12) begin
                        // ---- Фаза чтения header (12 байт: magic+size+load_addr) ----
                        header_idx <= header_idx + 1;

                        if (byte_idx == 2'd3) begin
                            byte_idx <= 2'd0;
                            if (header_idx == 4'd3) begin
                                // Magic word complete
                                saved_magic <= {spi_rx, word_buf[23:0]};
                            end else if (header_idx == 4'd7) begin
                                // Size word complete
                                saved_size <= {spi_rx, word_buf[23:0]};
                            end
                        end else begin
                            byte_idx <= byte_idx + 1;
                        end

                        if (header_idx == 4'd11) begin
                            // Load_addr word complete, verify and start
                            saved_load_addr <= {spi_rx, word_buf[23:0]};
                            bytes_remaining <= saved_size;
                            ddr_addr        <= {spi_rx, word_buf[23:0]};
                            byte_idx        <= 2'd0;
                            word_buf        <= 32'b0;

                            if (saved_magic != MAGIC) begin
                                // Bad magic — abort
                                cs_r  <= 1'b0;
                                state <= S_DONE;
                                bus_request_r <= 1'b0;
                            end else if (saved_size == 32'b0) begin
                                // Zero size — nothing to load
                                cs_r  <= 1'b0;
                                state <= S_SET_PC;
                            end else begin
                                // Start reading payload
                                spi_tx_data   <= 8'hFF;
                                spi_trigger_r <= 1'b1;
                                state         <= S_SPI_XFER;
                                after_spi     <= S_ASSEMBLE;
                            end
                        end else begin
                            // Continue reading header
                            spi_tx_data   <= 8'hFF;
                            spi_trigger_r <= 1'b1;
                            state         <= S_SPI_XFER;
                            after_spi     <= S_ASSEMBLE;
                        end

                    end else begin
                        // ---- Фаза чтения payload ----
                        bytes_remaining <= bytes_remaining - 1;

                        if (byte_idx == 2'd3 || bytes_remaining == 32'd1) begin
                            // Word complete or last byte → write to DDR
                            byte_idx <= 2'd0;
                            // Финализируем word_buf с последним байтом
                            case (byte_idx)
                                2'd0: word_buf[7:0]   <= spi_rx;
                                2'd1: word_buf[15:8]  <= spi_rx;
                                2'd2: word_buf[23:16] <= spi_rx;
                                2'd3: word_buf[31:24] <= spi_rx;
                            endcase
                            state <= S_WRITE_DDR;
                        end else begin
                            byte_idx <= byte_idx + 1;
                            // Continue reading
                            spi_tx_data   <= 8'hFF;
                            spi_trigger_r <= 1'b1;
                            state         <= S_SPI_XFER;
                            after_spi     <= S_ASSEMBLE;
                        end
                    end
                end

                // --------------------------------------------------
                S_WRITE_DDR: begin
                    mc_wr_r <= 1'b1;
                    if (mc_ready) begin
                        mc_wr_r  <= 1'b0;
                        ddr_addr <= ddr_addr + ADDRESS_SIZE'(4);
                        word_buf <= 32'b0;

                        if (bytes_remaining == 32'd0) begin
                            state <= S_SET_PC;
                        end else begin
                            // Continue reading payload
                            spi_tx_data   <= 8'hFF;
                            spi_trigger_r <= 1'b1;
                            state         <= S_SPI_XFER;
                            after_spi     <= S_ASSEMBLE;
                        end
                    end
                end

                // --------------------------------------------------
                S_SET_PC: begin
                    cs_r          <= 1'b0;
                    set_pc_r      <= 1'b1;
                    bus_request_r <= 1'b0;
                    state         <= S_DONE;
                end

                // --------------------------------------------------
                S_DONE: begin
                    // Неактивен до reset
                end
            endcase
        end
    end

endmodule
