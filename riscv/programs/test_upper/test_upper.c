/*
 * test_upper.c — покрытие LUI и AUIPC инструкций RV32I.
 *
 * LUI   — загружает 20-битный immediate в старшие биты регистра,
 *          младшие 12 бит = 0.  Используется GCC для:
 *           - констант ≥ 2048 (0x800)
 *           - адресов глобальных переменных в паре с ADDI/LOAD/STORE
 *
 * AUIPC — прибавляет 20-битный immediate (<<12) к PC.
 *          Используется GCC для:
 *           - PC-relative загрузки адреса глобальных переменных
 *           - PC-relative JAL на расстояния > 1 МБ (не актуально здесь)
 *
 * Глобали в .bss (нет инициализаторов → no VMA gap issue).
 * Значения присваиваются в main() через AUIPC+STORE.
 */
#include "../common/check.h"

/* BSS globals — нет инициализаторов → нет .data → нет 64KB дыры в binary */
static unsigned int g_a;
static unsigned int g_b;
static unsigned int g_c;
static unsigned int g_d;
static          int g_neg;

/* Массив — доступ к концу требует LUI для вычисления адреса */
static unsigned int g_arr[64];   /* 256 байт */

/* noinline чтобы компилятор не свернул в константы */
__attribute__((noinline))
static unsigned int load_large_const_1(void) { return 0x80000000u; }
__attribute__((noinline))
static unsigned int load_large_const_2(void) { return 0xFFFF0000u; }
__attribute__((noinline))
static unsigned int load_large_const_3(void) { return 0xABCDE000u; }

/* Константа с проблемным знаковым расширением ADDI: имм[11]=1 */
__attribute__((noinline))
static unsigned int load_tricky_1(void) { return 0x00000800u; }
__attribute__((noinline))
static unsigned int load_tricky_2(void) { return 0x12345800u; }
__attribute__((noinline))
static unsigned int load_tricky_3(void) { return 0xFFFFFFFFu; }

int test_upper_run(void);
#ifndef NO_MAIN
int main(void) { return test_upper_run(); }
#endif
int test_upper_run(void) {
    /* ================================================================== */
    /* Тест 1: LUI — чистые 20-битные верхние части                       */
    /* ================================================================== */
    CHECK_EQ(load_large_const_1(), 0x80000000u, "LUI 0x80000000");
    CHECK_EQ(load_large_const_2(), 0xFFFF0000u, "LUI 0xFFFF0000");
    CHECK_EQ(load_large_const_3(), 0xABCDE000u, "LUI 0xABCDE000");

    /* ================================================================== */
    /* Тест 2: LUI + ADDI — произвольные 32-битные константы              */
    /* ================================================================== */
    {
        volatile unsigned int v;
        v = 0x12345678u;
        CHECK_EQ(v, 0x12345678u, "LUI+ADDI 0x12345678");
        v = 0xDEADBEEFu;
        CHECK_EQ(v, 0xDEADBEEFu, "LUI+ADDI 0xDEADBEEF");
        v = 0x00001234u;
        CHECK_EQ(v, 0x00001234u, "LUI+ADDI 0x00001234 (small upper)");
    }

    /* ================================================================== */
    /* Тест 3: граничный случай — ADDI с отрицательным immediate          */
    /* ================================================================== */
    CHECK_EQ(load_tricky_1(), 0x00000800u, "LUI+ADDI tricky 0x800");
    CHECK_EQ(load_tricky_2(), 0x12345800u, "LUI+ADDI tricky 0x12345800");
    CHECK_EQ(load_tricky_3(), 0xFFFFFFFFu, "LUI+ADDI tricky -1");

    /* ================================================================== */
    /* Тест 4: AUIPC — глобальные переменные (PC-relative address)        */
    /* GCC: auipc x, %pcrel_hi(g_a) / sw x, %pcrel_lo(g_a)(x)           */
    /* ================================================================== */
    g_a   = 0xDEADBEEFu;
    g_b   = 0x12345678u;
    g_c   = 0xFFFFFFFFu;
    g_d   = 0x00000001u;
    g_neg = -42;

    CHECK_EQ(g_a,   0xDEADBEEFu,          "AUIPC read g_a");
    CHECK_EQ(g_b,   0x12345678u,          "AUIPC read g_b");
    CHECK_EQ(g_c,   0xFFFFFFFFu,          "AUIPC read g_c");
    CHECK_EQ(g_d,   0x00000001u,          "AUIPC read g_d");
    CHECK_EQ((unsigned int)g_neg, (unsigned int)-42, "AUIPC read g_neg");

    /* Запись через AUIPC-адрес и чтение обратно */
    g_a = 0x11111111u;
    CHECK_EQ(g_a, 0x11111111u, "AUIPC write+read g_a");

    /* ================================================================== */
    /* Тест 5: Массив с большими смещениями                               */
    /* Доступ к g_arr[63] требует LUI для вычисления адреса               */
    /* ================================================================== */
    g_arr[0]  = 0xAAAAAAAAu;
    g_arr[31] = 0xBBBBBBBBu;
    g_arr[63] = 0xCCCCCCCCu;

    CHECK_EQ(g_arr[0],  0xAAAAAAAAu, "AUIPC+LUI arr[0]");
    CHECK_EQ(g_arr[31], 0xBBBBBBBBu, "AUIPC+LUI arr[31]");
    CHECK_EQ(g_arr[63], 0xCCCCCCCCu, "AUIPC+LUI arr[63]");

    /* Проверяем что запись в arr[63] не затронула arr[0] и arr[31] */
    CHECK_EQ(g_arr[0],  0xAAAAAAAAu, "arr[0] intact after arr[63] write");
    CHECK_EQ(g_arr[31], 0xBBBBBBBBu, "arr[31] intact after arr[63] write");

    DONE();
    return 0;
}
