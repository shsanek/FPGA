/*
 * test_mem.c — покрытие всех Load/Store инструкций RV32I.
 *
 * Stores: SW SH SB
 * Loads:  LW LH LHU LB LBU
 *
 * Дополнительно тестируем:
 *  - все 4 байтовых смещения (byte_offset = 0..3)
 *  - оба halfword-смещения (byte_offset = 0, 2)
 *  - знаковое расширение (LB, LH) vs нулевое (LBU, LHU)
 *  - наложение: SW → SB → LW  (перетирание одного байта в слове)
 *  - сборка слова из 4 SB-ов → LW
 *  - граница 16-байтовой строки кэша (смещение 12 / 16)
 *  - соседние слова не затирают друг друга
 *
 * Буфер живёт в BSS (RAM через MEMORY_CONTROLLER). Адреса полностью
 * runtime — компилятор не может соптимизировать load/store.
 */
#include "../common/check.h"

/* 64-байтный буфер в .bss (инициализирован нулём в crt0.s) */
static volatile unsigned char buf[64];

/* Вспомогательные макросы для типизированного доступа без UB */
#define WP(off)  ((volatile unsigned int  *)(buf + (off)))
#define HP(off)  ((volatile unsigned short *)(buf + (off)))
#define SHP(off) ((volatile signed short   *)(buf + (off)))
#define BP(off)  ((volatile unsigned char  *)(buf + (off)))
#define SBP(off) ((volatile signed char    *)(buf + (off)))

int test_mem_run(void);
#ifndef NO_MAIN
int main(void) { return test_mem_run(); }
#endif
int test_mem_run(void) {

    /* ================================================================== */
    /* SW + LW                                                             */
    /* ================================================================== */
    *WP(0)  = 0xDEADBEEFu;
    CHECK_EQ(*WP(0),  0xDEADBEEFu, "SW+LW basic");

    *WP(4)  = 0x00000000u;
    CHECK_EQ(*WP(4),  0x00000000u, "SW zero");

    *WP(8)  = 0x7FFFFFFFu;
    CHECK_EQ(*WP(8),  0x7FFFFFFFu, "SW INT_MAX");

    *WP(12) = 0x80000000u;
    CHECK_EQ(*WP(12), 0x80000000u, "SW INT_MIN");

    /* ================================================================== */
    /* SH + LHU / LH — halfword смещение 0                                */
    /* ================================================================== */
    *WP(16) = 0u;                   /* очищаем */
    *HP(16) = 0x4EEFu;             /* bit15=0 → положительное signed short */
    CHECK_EQ(*HP(16), 0x4EEFu,  "SH+LHU off=0");
    CHECK_EQ((unsigned)*SHP(16), 0x4EEFu, "LH+  off=0 pos value");

    /* Знаковое расширение: 0x8000 → -32768 */
    *HP(16) = 0x8000u;
    CHECK_EQ(*HP(16),  0x8000u,  "LHU  sign bit, unsigned");
    CHECK_EQ(*SHP(16), (short)-32768, "LH   sign extend 0x8000=-32768");

    /* Верхняя часть слова не тронута (LHU/LH только нижние 16 бит) */
    *WP(16) = 0xABCD0000u;
    *HP(16) = 0x1234u;             /* перезаписываем нижнее halfword */
    CHECK_EQ(*WP(16), 0xABCD1234u, "SH lower, upper preserved");

    /* ================================================================== */
    /* SH + LHU / LH — halfword смещение 2                                */
    /* ================================================================== */
    *WP(20) = 0u;
    *HP(22) = 0xCAFEu;
    CHECK_EQ(*HP(22), 0xCAFEu,   "SH+LHU off=2");
    CHECK_EQ(*WP(20), 0xCAFE0000u, "SH off=2 → correct word position");

    *HP(22) = 0xFF00u;
    CHECK_EQ(*SHP(22), (short)0xFF00u, "LH  off=2 sign extend 0xFF00");

    /* ================================================================== */
    /* SB + LBU / LB — все 4 байтовых смещения                            */
    /* ================================================================== */
    *WP(24) = 0u;
    *BP(24) = 0x11u;  *BP(25) = 0x22u;  *BP(26) = 0x33u;  *BP(27) = 0x44u;

    CHECK_EQ(*BP(24), 0x11u, "SB+LBU off=0");
    CHECK_EQ(*BP(25), 0x22u, "SB+LBU off=1");
    CHECK_EQ(*BP(26), 0x33u, "SB+LBU off=2");
    CHECK_EQ(*BP(27), 0x44u, "SB+LBU off=3");
    /* Little-endian: LW видит 0x44332211 */
    CHECK_EQ(*WP(24), 0x44332211u, "SB×4 → LW little-endian");

    /* Знаковое расширение LB: 0xFF → -1, 0x7F → 127, 0x80 → -128 */
    *BP(28) = 0xFFu;
    CHECK_EQ((int)*SBP(28), -1,   "LB sign extend 0xFF");
    *BP(28) = 0x7Fu;
    CHECK_EQ((int)*SBP(28), 127,  "LB sign extend 0x7F=127");
    *BP(28) = 0x80u;
    CHECK_EQ((int)*SBP(28), -128, "LB sign extend 0x80=-128");
    *BP(28) = 0x80u;
    CHECK_EQ(*BP(28), 0x80u,      "LBU 0x80 unsigned=128");

    /* ================================================================== */
    /* Наложение: SW → SB перетирает 1 байт                               */
    /* Проверяем все 4 позиции                                             */
    /* ================================================================== */
    /* little-endian: SW 0x12345678:
       buf+0=0x78, buf+1=0x56, buf+2=0x34, buf+3=0x12             */

    *WP(32) = 0x12345678u;
    *BP(32) = 0xAAu;               /* заменяем байт 0 */
    CHECK_EQ(*WP(32), 0x123456AAu, "SW+SB overwrite byte 0");

    *WP(32) = 0x12345678u;
    *BP(33) = 0xBBu;               /* заменяем байт 1 */
    CHECK_EQ(*WP(32), 0x1234BB78u, "SW+SB overwrite byte 1");

    *WP(32) = 0x12345678u;
    *BP(34) = 0xCCu;               /* заменяем байт 2 */
    CHECK_EQ(*WP(32), 0x12CC5678u, "SW+SB overwrite byte 2");

    *WP(32) = 0x12345678u;
    *BP(35) = 0xDDu;               /* заменяем байт 3 */
    CHECK_EQ(*WP(32), 0xDD345678u, "SW+SB overwrite byte 3");

    /* ================================================================== */
    /* Наложение: SH перетирает halfword в слове                           */
    /* ================================================================== */
    *WP(36) = 0xFFFFFFFFu;
    *HP(36) = 0x0000u;             /* нижнее halfword → 0 */
    CHECK_EQ(*WP(36), 0xFFFF0000u, "SW+SH overwrite low halfword");

    *WP(36) = 0xFFFFFFFFu;
    *HP(38) = 0x0000u;             /* верхнее halfword → 0 */
    CHECK_EQ(*WP(36), 0x0000FFFFu, "SW+SH overwrite high halfword");

    /* ================================================================== */
    /* Граница 16-байтной строки кэша (смещение 44 / 48 от начала buf).   */
    /* buf начинается с 0x00010000.                                        */
    /* Строка кэша 2: байты [32..47], строка 3: байты [48..63].           */
    /* ================================================================== */
    *WP(44) = 0xAABBCCDDu;  /* последнее слово в строке кэша */
    *WP(48) = 0x11223344u;  /* первое слово следующей строки  */
    CHECK_EQ(*WP(44), 0xAABBCCDDu, "cache boundary: word at -4");
    CHECK_EQ(*WP(48), 0x11223344u, "cache boundary: word at +0");
    /* Убеждаемся что строки не влияют друг на друга */
    *BP(47) = 0xFFu;
    CHECK_EQ(*WP(44), 0xFFBBCCDDu, "cache boundary SB at end of line");
    CHECK_EQ(*WP(48), 0x11223344u,    "cache boundary next line intact");

    /* ================================================================== */
    /* Соседние слова не затирают друг друга                               */
    /* ================================================================== */
    *WP(52) = 0xAAAAAAAAu;
    *WP(56) = 0xBBBBBBBBu;
    *WP(60) = 0xCCCCCCCCu;
    *WP(52) = 0xAAAAAAAAu;  /* запись ещё раз — проверяем стабильность */
    CHECK_EQ(*WP(52), 0xAAAAAAAAu, "adjacent words no corrupt [0]");
    CHECK_EQ(*WP(56), 0xBBBBBBBBu, "adjacent words no corrupt [1]");
    CHECK_EQ(*WP(60), 0xCCCCCCCCu, "adjacent words no corrupt [2]");

    DONE();
    return 0;
}
