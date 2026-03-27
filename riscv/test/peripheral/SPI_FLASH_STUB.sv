// SPI_FLASH_STUB — мок SPI flash для тестов.
//
// Отдаёт stub-программу (j _start = 0x0000006f) с header:
//   magic=0xB007C0DE, size=4, load_addr=0x00000000
//
// Протокол: после cmd(0x03) + addr(3B) отдаёт байты из flash_data[].
// SPI Mode 0: MISO меняется на falling edge SCK.
module SPI_FLASH_STUB (
    input  wire cs_n,
    input  wire sck,
    input  wire mosi,
    output reg  miso
);
    // Header (12 bytes) + stub (4 bytes) = 16 bytes
    // Magic:     0xB007C0DE → DE C0 07 B0
    // Size:      4          → 04 00 00 00
    // Load_addr: 0x00000000 → 00 00 00 00
    // Stub:      j _start   → 6F 00 00 00
    localparam FLASH_SIZE = 16;
    logic [7:0] flash_data [0:FLASH_SIZE-1];

    initial begin
        // Header: magic
        flash_data[0]  = 8'hDE;
        flash_data[1]  = 8'hC0;
        flash_data[2]  = 8'h07;
        flash_data[3]  = 8'hB0;
        // Header: size = 4
        flash_data[4]  = 8'h04;
        flash_data[5]  = 8'h00;
        flash_data[6]  = 8'h00;
        flash_data[7]  = 8'h00;
        // Header: load_addr = 0x00000000
        flash_data[8]  = 8'h00;
        flash_data[9]  = 8'h00;
        flash_data[10] = 8'h00;
        flash_data[11] = 8'h00;
        // Payload: j _start (0x0000006f)
        flash_data[12] = 8'h6F;
        flash_data[13] = 8'h00;
        flash_data[14] = 8'h00;
        flash_data[15] = 8'h00;
    end

    // SPI state
    integer bit_cnt = 0;
    integer phase = 0;        // 0=cmd+addr (32 bits), 1=data
    integer read_idx = 0;
    integer out_bit = 7;
    logic [7:0] out_byte;

    // MISO: shift out on falling edge SCK
    always @(negedge sck or posedge cs_n) begin
        if (cs_n) begin
            bit_cnt   <= 0;
            phase     <= 0;
            read_idx  <= 0;
            out_bit   <= 7;
            miso      <= 1'b1;
        end else begin
            if (phase == 0) begin
                bit_cnt <= bit_cnt + 1;
                if (bit_cnt == 31) begin
                    phase    <= 1;
                    out_byte <= flash_data[0];
                    out_bit  <= 7;
                    miso     <= flash_data[0][7];
                end
            end else begin
                if (out_bit == 0) begin
                    read_idx <= read_idx + 1;
                    if (read_idx + 1 < FLASH_SIZE) begin
                        out_byte <= flash_data[read_idx + 1];
                        miso     <= flash_data[read_idx + 1][7];
                    end else begin
                        miso <= 1'b1;
                    end
                    out_bit <= 7;
                end else begin
                    out_bit <= out_bit - 1;
                    miso    <= out_byte[out_bit - 1];
                end
            end
        end
    end

endmodule
