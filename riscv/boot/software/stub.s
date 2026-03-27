/* stub.s — минимальная программа-заглушка для FLASH_LOADER.
 *
 * Бесконечный цикл (1 инструкция, 4 байта).
 * Используется:
 *   1. Debug-only режим — CPU крутит цикл, управление через UART debug
 *   2. Мок для тестов — FLASH_LOADER загружает заглушку, debug грузит программу
 *
 * Сборка:
 *   riscv64-elf-as -march=rv32i -mabi=ilp32 -o stub.o stub.s
 *   riscv64-elf-objcopy -O binary stub.o stub.bin
 *   python3 prepend_header.py stub.bin stub_with_header.bin
 */
    .section .text
    .globl _start
_start:
    j _start    /* 0x0000006f — бесконечный цикл */
