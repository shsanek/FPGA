/*
 * test_sd.c — запись "Hello SD card!\n" в блок 0 microSD (raw SPI mode).
 *
 * Протокол:
 *   1. Init: 80 тактов с CS=high, CMD0, CMD8, ACMD41, CMD58
 *   2. Write block 0: CMD24, data token 0xFE, 512 байт, dummy CRC
 *   3. Read block 0: CMD17, ждём 0xFE, читаем 512 байт
 *   4. Сравниваем и выводим результат через UART
 */
#include "../../runtime.h"

/* ---- SD регистры ---- */
#define SD_DATA    (*(volatile unsigned int *)0x08020000U)
#define SD_CONTROL (*(volatile unsigned int *)0x08020004U)
#define SD_STATUS  (*(volatile unsigned int *)0x08020008U)
#define SD_DIVIDER (*(volatile unsigned int *)0x0802000CU)

#define SD_CS_ON   1
#define SD_CS_OFF  0

/* ---- Delay ---- */
static void delay(volatile unsigned int n) {
    while (n--) __asm__ volatile("");
}

/* ---- SPI helpers ---- */
static void spi_wait(void) {
    while (SD_STATUS & 0x2) ;
}

/* Send byte, return received byte */
static unsigned char spi_xfer(unsigned char tx) {
    spi_wait();
    SD_DATA = tx;
    spi_wait();
    return (unsigned char)SD_DATA;
}

/* ---- SD commands ---- */

/* Send SD command (6 bytes), return R1 response */
static unsigned char sd_cmd(unsigned char cmd, unsigned int arg, unsigned char crc) {
    spi_xfer(0x40 | cmd);
    spi_xfer((arg >> 24) & 0xFF);
    spi_xfer((arg >> 16) & 0xFF);
    spi_xfer((arg >>  8) & 0xFF);
    spi_xfer(arg & 0xFF);
    spi_xfer(crc);

    /* Wait for response (bit7=0) */
    unsigned char r;
    for (int i = 0; i < 10; i++) {
        r = spi_xfer(0xFF);
        if (!(r & 0x80)) return r;
    }
    return r;
}

/* Send ACMD (CMD55 + CMDx) */
static unsigned char sd_acmd(unsigned char cmd, unsigned int arg) {
    sd_cmd(55, 0, 0xFF);
    return sd_cmd(cmd, arg, 0xFF);
}

/* ---- SD init ---- */
static int sd_init(void) {
    /* Slow clock for init (~400 kHz) */
    SD_DIVIDER = 101;

    /* CS off, send >=74 clocks (10 bytes of 0xFF) */
    SD_CONTROL = SD_CS_OFF;
    for (int i = 0; i < 10; i++) spi_xfer(0xFF);

    /* CS on */
    SD_CONTROL = SD_CS_ON;
    delay(1000);

    /* CMD0: GO_IDLE_STATE */
    unsigned char r = sd_cmd(0, 0, 0x95);
    if (r != 0x01) {
        puts("CMD0 fail");
        print_hex(r);
        print_nl();
        return -1;
    }
    puts("CMD0 OK");

    /* CMD8: SEND_IF_COND (voltage check, required for SDv2) */
    r = sd_cmd(8, 0x000001AA, 0x87);
    if (r == 0x01) {
        /* SDv2: read 4 bytes of R7 response */
        spi_xfer(0xFF);
        spi_xfer(0xFF);
        spi_xfer(0xFF);
        unsigned char check = spi_xfer(0xFF);
        if (check != 0xAA) {
            puts("CMD8 check fail");
            return -2;
        }
        puts("CMD8 OK (SDv2)");
    } else {
        puts("CMD8 skip (SDv1)");
    }

    /* ACMD41: SD_SEND_OP_COND (init card) */
    for (int retry = 0; retry < 1000; retry++) {
        r = sd_acmd(41, 0x40000000);
        if (r == 0x00) break;
        delay(10000);
    }
    if (r != 0x00) {
        puts("ACMD41 fail");
        print_hex(r);
        print_nl();
        return -3;
    }
    puts("ACMD41 OK");

    /* CMD58: READ_OCR (check SDHC) */
    r = sd_cmd(58, 0, 0xFF);
    if (r == 0x00) {
        unsigned char ocr3 = spi_xfer(0xFF);
        spi_xfer(0xFF);
        spi_xfer(0xFF);
        spi_xfer(0xFF);
        if (ocr3 & 0x40) {
            puts("SDHC card");
        } else {
            puts("SDSC card");
            /* Set block size to 512 for SDSC */
            sd_cmd(16, 512, 0xFF);
        }
    }

    /* Switch to fast clock (~5 MHz) */
    SD_DIVIDER = 7;
    puts("SD init done");
    return 0;
}

/* ---- Write single block (512 bytes) ---- */
static int sd_write_block(unsigned int block_addr, const unsigned char *buf) {
    unsigned char r = sd_cmd(24, block_addr, 0xFF);
    if (r != 0x00) {
        puts("CMD24 fail");
        print_hex(r);
        print_nl();
        return -1;
    }

    /* Spacer byte */
    spi_xfer(0xFF);

    /* Data token */
    spi_xfer(0xFE);

    /* 512 bytes of data */
    for (int i = 0; i < 512; i++) {
        spi_xfer(buf[i]);
    }

    /* Dummy CRC */
    spi_xfer(0xFF);
    spi_xfer(0xFF);

    /* Data response: xxx00101 = accepted */
    r = spi_xfer(0xFF);
    if ((r & 0x1F) != 0x05) {
        puts("Write rejected");
        print_hex(r);
        print_nl();
        return -2;
    }

    /* Wait for card busy (MISO=0) */
    for (int i = 0; i < 100000; i++) {
        if (spi_xfer(0xFF) != 0x00) break;
    }

    return 0;
}

/* ---- Read single block (512 bytes) ---- */
static int sd_read_block(unsigned int block_addr, unsigned char *buf) {
    unsigned char r = sd_cmd(17, block_addr, 0xFF);
    if (r != 0x00) {
        puts("CMD17 fail");
        print_hex(r);
        print_nl();
        return -1;
    }

    /* Wait for data token 0xFE */
    for (int i = 0; i < 10000; i++) {
        r = spi_xfer(0xFF);
        if (r == 0xFE) break;
    }
    if (r != 0xFE) {
        puts("No data token");
        return -2;
    }

    /* Read 512 bytes */
    for (int i = 0; i < 512; i++) {
        buf[i] = spi_xfer(0xFF);
    }

    /* Discard CRC */
    spi_xfer(0xFF);
    spi_xfer(0xFF);

    return 0;
}

/* ---- Main ---- */
static unsigned char wbuf[512];
static unsigned char rbuf[512];

int main(void) {
    puts("SD test start");

    /* Check card detect */
    if (!(SD_STATUS & 0x04)) {
        puts("No card!");
        return 1;
    }
    puts("Card detected");

    if (sd_init() != 0) {
        puts("Init failed");
        return 1;
    }

    /* Prepare write buffer: "Hello SD card!\n" + zeros */
    const char *msg = "Hello SD card!\n";
    for (int i = 0; i < 512; i++) wbuf[i] = 0;
    for (int i = 0; msg[i]; i++) wbuf[i] = msg[i];

    /* Write block 0 */
    puts("Writing block 0...");
    if (sd_write_block(0, wbuf) != 0) {
        puts("Write failed");
        return 1;
    }
    puts("Write OK");

    /* Read back block 0 */
    puts("Reading block 0...");
    for (int i = 0; i < 512; i++) rbuf[i] = 0xFF;
    if (sd_read_block(0, rbuf) != 0) {
        puts("Read failed");
        return 1;
    }
    puts("Read OK");

    /* Compare */
    int match = 1;
    for (int i = 0; i < 512; i++) {
        if (wbuf[i] != rbuf[i]) {
            match = 0;
            break;
        }
    }

    /* Print what we read */
    puts("Data:");
    for (int i = 0; rbuf[i] && i < 64; i++) {
        putchar(rbuf[i]);
    }

    if (match) {
        puts("VERIFY OK");
    } else {
        puts("VERIFY FAIL");
    }

    /* CS off */
    SD_CONTROL = SD_CS_OFF;

    return 0;
}
