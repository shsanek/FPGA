/*
 * Stage 1 bootloader — загружает BOOT.BIN с SD карты (FAT32) в DDR.
 *
 * Загрузка: FLASH_LOADER кладёт этот код в DDR по адресу 0x00000000.
 * Работа:
 *   1. Инициализация SD карты
 *   2. Чтение FAT32, поиск BOOT.BIN
 *   3. Загрузка файла по адресу LOAD_ADDR (0x00100000 = 1 МБ)
 *   4. Переход на LOAD_ADDR
 *
 * BOOT.BIN должен быть скомпилирован с ORIGIN = 0x00100000.
 */
#include "sd.h"
#include "fat32.h"

#define UART_TX  (*(volatile unsigned int *)0x08000000U)
#define SD_STATUS (*(volatile unsigned int *)0x08020008U)

/* OLED registers */
#define OLED_DATA    (*(volatile unsigned int *)0x08010000U)
#define OLED_CONTROL (*(volatile unsigned int *)0x08010004U)
#define OLED_STATUS  (*(volatile unsigned int *)0x08010008U)
#define OLED_DIVIDER (*(volatile unsigned int *)0x0801000CU)

#define CTL_CS     (1 << 0)
#define CTL_DC     (1 << 1)
#define CTL_RES    (1 << 2)
#define CTL_VCCEN  (1 << 3)
#define CTL_PMODEN (1 << 4)

#define LOAD_ADDR 0x00000000U

static void boot_putc(int c) { UART_TX = (unsigned int)(unsigned char)c; }
static void boot_puts(const char *s) {
    while (*s) boot_putc(*s++);
    boot_putc('\n');
}
static void boot_hex(unsigned int n) {
    const char *h = "0123456789abcdef";
    for (int s = 28; s >= 0; s -= 4) boot_putc(h[(n >> s) & 0xF]);
}

/* ---- OLED helpers ---- */
static void delay(volatile unsigned int n) {
    while (n--) __asm__ volatile("");
}
#define DELAY_1MS   81250
#define DELAY_20MS  (20 * DELAY_1MS)
#define DELAY_100MS (100 * DELAY_1MS)

static void spi_wait(void) { while (OLED_STATUS & 0x2); }
static void oled_cmd(unsigned char c) { spi_wait(); OLED_DATA = c; }
static void oled_data(unsigned char d) { spi_wait(); OLED_DATA = d; }

static void oled_init(void) {
    OLED_CONTROL = CTL_PMODEN;
    delay(DELAY_20MS);
    OLED_CONTROL = CTL_PMODEN | CTL_RES;
    delay(DELAY_1MS);
    OLED_CONTROL = CTL_PMODEN;
    delay(DELAY_1MS);
    OLED_CONTROL = CTL_PMODEN | CTL_CS;

    oled_cmd(0xAE); oled_cmd(0xA0); oled_cmd(0x72);
    oled_cmd(0xA1); oled_cmd(0x00);
    oled_cmd(0xA2); oled_cmd(0x00);
    oled_cmd(0xA4);
    oled_cmd(0xA8); oled_cmd(0x3F);
    oled_cmd(0xAD); oled_cmd(0x8E);
    oled_cmd(0xB0); oled_cmd(0x0B);
    oled_cmd(0xB1); oled_cmd(0x31);
    oled_cmd(0xB3); oled_cmd(0xF0);
    oled_cmd(0x8A); oled_cmd(0x64);
    oled_cmd(0x8B); oled_cmd(0x78);
    oled_cmd(0x8C); oled_cmd(0x64);
    oled_cmd(0xBB); oled_cmd(0x3A);
    oled_cmd(0xBE); oled_cmd(0x3E);
    oled_cmd(0x87); oled_cmd(0x06);
    oled_cmd(0x81); oled_cmd(0x91);
    oled_cmd(0x82); oled_cmd(0x50);
    oled_cmd(0x83); oled_cmd(0x7D);
    spi_wait();

    OLED_CONTROL = CTL_PMODEN | CTL_VCCEN | CTL_CS;
    delay(DELAY_100MS);
    oled_cmd(0xAF);
    spi_wait();
}

static void oled_fill_blue(void) {
    /* Set window 0,0 → 95,63 */
    oled_cmd(0x15); oled_cmd(0); oled_cmd(95);
    oled_cmd(0x75); oled_cmd(0); oled_cmd(63);
    spi_wait();
    /* Data mode */
    unsigned int ctl = OLED_CONTROL;
    OLED_CONTROL = ctl | CTL_DC | CTL_CS;
    /* RGB565 blue = 0x001F → hi=0x00, lo=0x1F */
    for (int i = 0; i < 96 * 64; i++) {
        oled_data(0x00);
        oled_data(0x1F);
    }
    spi_wait();
}

static void oled_fill_red(void) {
    oled_cmd(0x15); oled_cmd(0); oled_cmd(95);
    oled_cmd(0x75); oled_cmd(0); oled_cmd(63);
    spi_wait();
    unsigned int ctl = OLED_CONTROL;
    OLED_CONTROL = ctl | CTL_DC | CTL_CS;
    /* RGB565 red = 0xF800 → hi=0xF8, lo=0x00 */
    for (int i = 0; i < 96 * 64; i++) {
        oled_data(0xF8);
        oled_data(0x00);
    }
    spi_wait();
}

static void halt_red(const char *msg) {
    boot_puts(msg);
    oled_init();
    oled_fill_red();
    while (1) __asm__ volatile("");
}

int main(void) {
    boot_puts("Stage1: boot");

    /* Init OLED → blue screen (alive indicator) */
    oled_init();
    oled_fill_blue();
    boot_puts("OLED blue");

    /* Check card detect */
    if (!(SD_STATUS & 0x04)) {
        halt_red("No SD card");
    }

    /* Init SD */
    if (sd_init() != 0) {
        halt_red("SD init fail");
    }
    boot_puts("SD OK");

    /* Init FAT32 */
    if (fat32_init() != 0) {
        halt_red("FAT32 fail");
    }
    boot_puts("FAT32 OK");

    /* Load BOOT.BIN to LOAD_ADDR */
    /*  8.3 name: "BOOT    BIN" (8 chars name + 3 chars ext, space-padded) */
    int size = fat32_load("BOOT    BIN", (unsigned char *)LOAD_ADDR);
    if (size <= 0) {
        halt_red("BOOT.BIN not found");
    }

    boot_puts("Loaded ");
    boot_hex((unsigned int)size);
    boot_puts(" bytes");

    boot_puts("Jumping to ");
    boot_hex(LOAD_ADDR);
    boot_putc('\n');

    /* Jump to loaded program */
    ((void (*)(void))LOAD_ADDR)();

    /* Should not reach here */
    return 0;
}
