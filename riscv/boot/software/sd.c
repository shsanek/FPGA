/* SD card SPI driver — extracted from test_sd.c (read-only). */
#include "sd.h"

#define SD_DATA    (*(volatile unsigned int *)0x10020000U)
#define SD_CONTROL (*(volatile unsigned int *)0x10020004U)
#define SD_STATUS  (*(volatile unsigned int *)0x10020008U)
#define SD_DIVIDER (*(volatile unsigned int *)0x1002000CU)

#define UART_TX    (*(volatile unsigned int *)0x10000000U)

static int is_sdhc;

static void delay(volatile unsigned int n) {
    while (n--) __asm__ volatile("");
}

static void spi_wait(void) {
    while (SD_STATUS & 0x2) ;
}

static unsigned char spi_xfer(unsigned char tx) {
    spi_wait();
    SD_DATA = tx;
    spi_wait();
    return (unsigned char)SD_DATA;
}

static void boot_putc(int c) { UART_TX = (unsigned int)(unsigned char)c; }

static void boot_puts(const char *s) {
    while (*s) boot_putc(*s++);
    boot_putc('\n');
}

static unsigned char sd_cmd(unsigned char cmd, unsigned int arg, unsigned char crc) {
    spi_xfer(0x40 | cmd);
    spi_xfer((arg >> 24) & 0xFF);
    spi_xfer((arg >> 16) & 0xFF);
    spi_xfer((arg >>  8) & 0xFF);
    spi_xfer(arg & 0xFF);
    spi_xfer(crc);
    unsigned char r;
    for (int i = 0; i < 10; i++) {
        r = spi_xfer(0xFF);
        if (!(r & 0x80)) return r;
    }
    return r;
}

static unsigned char sd_acmd(unsigned char cmd, unsigned int arg) {
    sd_cmd(55, 0, 0xFF);
    return sd_cmd(cmd, arg, 0xFF);
}

int sd_init(void) {
    is_sdhc = 0;
    SD_DIVIDER = 101;   /* ~400 kHz */
    SD_CONTROL = 0;     /* CS off */
    for (int i = 0; i < 10; i++) spi_xfer(0xFF);

    SD_CONTROL = 1;     /* CS on */
    delay(1000);

    unsigned char r = sd_cmd(0, 0, 0x95);
    if (r != 0x01) { boot_puts("CMD0 fail"); return -1; }

    r = sd_cmd(8, 0x000001AA, 0x87);
    if (r == 0x01) {
        spi_xfer(0xFF); spi_xfer(0xFF); spi_xfer(0xFF);
        unsigned char check = spi_xfer(0xFF);
        if (check != 0xAA) { boot_puts("CMD8 fail"); return -2; }
    }

    for (int retry = 0; retry < 1000; retry++) {
        r = sd_acmd(41, 0x40000000);
        if (r == 0x00) break;
        delay(10000);
    }
    if (r != 0x00) { boot_puts("ACMD41 fail"); return -3; }

    r = sd_cmd(58, 0, 0xFF);
    if (r == 0x00) {
        unsigned char ocr3 = spi_xfer(0xFF);
        spi_xfer(0xFF); spi_xfer(0xFF); spi_xfer(0xFF);
        if (ocr3 & 0x40) {
            is_sdhc = 1;
        } else {
            sd_cmd(16, 512, 0xFF);
        }
    }

    SD_DIVIDER = 3;     /* ~10 MHz (81.25 / 8) */
    return 0;
}

int sd_read_block(unsigned int block_addr, unsigned char *buf) {
    unsigned int addr = is_sdhc ? block_addr : (block_addr * 512);
    unsigned char r = sd_cmd(17, addr, 0xFF);
    if (r != 0x00) return -1;

    for (int i = 0; i < 10000; i++) {
        r = spi_xfer(0xFF);
        if (r == 0xFE) break;
    }
    if (r != 0xFE) return -2;

    for (int i = 0; i < 512; i++)
        buf[i] = spi_xfer(0xFF);

    spi_xfer(0xFF); spi_xfer(0xFF); /* CRC */
    return 0;
}
