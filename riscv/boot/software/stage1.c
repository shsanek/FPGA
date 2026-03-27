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

int main(void) {
    boot_puts("Stage1: boot");

    /* Check card detect */
    if (!(SD_STATUS & 0x04)) {
        boot_puts("No SD card");
        boot_puts("Halting");
        return 1;
    }

    /* Init SD */
    if (sd_init() != 0) {
        boot_puts("SD init fail");
        return 1;
    }
    boot_puts("SD OK");

    /* Init FAT32 */
    if (fat32_init() != 0) {
        boot_puts("FAT32 fail");
        return 1;
    }

    /* Load BOOT.BIN to LOAD_ADDR */
    /*  8.3 name: "BOOT    BIN" (8 chars name + 3 chars ext, space-padded) */
    int size = fat32_load("BOOT    BIN", (unsigned char *)LOAD_ADDR);
    if (size <= 0) {
        boot_puts("Load fail");
        return 1;
    }

    boot_puts("Jumping to ");
    boot_hex(LOAD_ADDR);
    boot_putc('\n');

    /* Jump to loaded program */
    ((void (*)(void))LOAD_ADDR)();

    /* Should not reach here */
    return 0;
}
