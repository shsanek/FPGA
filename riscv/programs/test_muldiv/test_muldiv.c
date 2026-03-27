/*
 * test_muldiv.c — тесты софтверного умножения и деления (rv32i без M-extension).
 *
 * GCC генерирует вызовы __mulsi3, __divsi3, __udivsi3, __modsi3, __umodsi3
 * из libgcc. Проверяем корректность на граничных случаях.
 */
#include "../common/check.h"

__attribute__((noinline)) static int       I(int x)         { return x; }
__attribute__((noinline)) static unsigned   U(unsigned x)    { return x; }

int test_muldiv_run(void);
#ifndef NO_MAIN
int main(void) { return test_muldiv_run(); }
#endif
int test_muldiv_run(void) {

    /* ================================================================ */
    /* Умножение (signed)                                                */
    /* ================================================================ */
    CHECK_EQ(I(3) * I(7),     21,          "MUL 3*7=21");
    CHECK_EQ(I(0) * I(12345), 0,           "MUL 0*x=0");
    CHECK_EQ(I(1) * I(-1),    -1,          "MUL 1*(-1)=-1");
    CHECK_EQ(I(-1) * I(-1),   1,           "MUL (-1)*(-1)=1");
    CHECK_EQ(I(100) * I(100), 10000,       "MUL 100*100=10000");
    CHECK_EQ(I(-5) * I(6),    -30,         "MUL (-5)*6=-30");
    CHECK_EQ(I(256) * I(256), 65536,       "MUL 256*256=65536");
    CHECK_EQ(I(1000) * I(1000), 1000000,   "MUL 1000*1000=1M");
    CHECK_EQ(I(0x7FFF) * I(2), 0xFFFE,     "MUL 32767*2=65534");
    CHECK_EQ(I(12345) * I(6789), (int)83810205u, "MUL 12345*6789");

    /* Переполнение (wrap) */
    CHECK_EQ((unsigned)I(0x10000) * (unsigned)I(0x10000), 0u,
             "MUL overflow 64K*64K=0 (low32)");
    CHECK_EQ((unsigned)I(0xFFFF) * (unsigned)I(0xFFFF), 0xFFFE0001u,
             "MUL 0xFFFF*0xFFFF");

    /* ================================================================ */
    /* Умножение (unsigned)                                              */
    /* ================================================================ */
    CHECK_EQ(U(3) * U(7),     21u,         "UMUL 3*7=21");
    CHECK_EQ(U(0x80000000u) * U(2), 0u,    "UMUL 2G*2=0 (overflow)");
    CHECK_EQ(U(0xFFFFFFFFu) * U(1), 0xFFFFFFFFu, "UMUL MAX*1=MAX");

    /* ================================================================ */
    /* Деление (signed)                                                  */
    /* ================================================================ */
    CHECK_EQ(I(21) / I(7),    3,           "DIV 21/7=3");
    CHECK_EQ(I(100) / I(10),  10,          "DIV 100/10=10");
    CHECK_EQ(I(7) / I(2),     3,           "DIV 7/2=3 (truncate)");
    CHECK_EQ(I(-7) / I(2),    -3,          "DIV (-7)/2=-3");
    CHECK_EQ(I(7) / I(-2),    -3,          "DIV 7/(-2)=-3");
    CHECK_EQ(I(-7) / I(-2),   3,           "DIV (-7)/(-2)=3");
    CHECK_EQ(I(0) / I(5),     0,           "DIV 0/5=0");
    CHECK_EQ(I(1) / I(1),     1,           "DIV 1/1=1");
    CHECK_EQ(I(1000000) / I(1000), 1000,   "DIV 1M/1K=1K");
    CHECK_EQ(I(0x7FFFFFFF) / I(1), 0x7FFFFFFF, "DIV INTMAX/1=INTMAX");
    CHECK_EQ(I(0x7FFFFFFF) / I(2), 0x3FFFFFFF,  "DIV INTMAX/2");

    /* ================================================================ */
    /* Деление (unsigned)                                                */
    /* ================================================================ */
    CHECK_EQ(U(21) / U(7),    3u,          "UDIV 21/7=3");
    CHECK_EQ(U(0xFFFFFFFFu) / U(1), 0xFFFFFFFFu, "UDIV MAX/1=MAX");
    CHECK_EQ(U(0xFFFFFFFFu) / U(2), 0x7FFFFFFFu, "UDIV MAX/2");
    CHECK_EQ(U(0x80000000u) / U(2), 0x40000000u, "UDIV 2G/2=1G");
    CHECK_EQ(U(100) / U(3),   33u,         "UDIV 100/3=33");

    /* ================================================================ */
    /* Остаток от деления (signed)                                       */
    /* ================================================================ */
    CHECK_EQ(I(7) % I(3),     1,           "MOD 7%%3=1");
    CHECK_EQ(I(10) % I(5),    0,           "MOD 10%%5=0");
    CHECK_EQ(I(-7) % I(3),    -1,          "MOD (-7)%%3=-1");
    CHECK_EQ(I(7) % I(-3),    1,           "MOD 7%%(-3)=1");
    CHECK_EQ(I(-7) % I(-3),   -1,          "MOD (-7)%%(-3)=-1");
    CHECK_EQ(I(0) % I(7),     0,           "MOD 0%%7=0");
    CHECK_EQ(I(123456) % I(1000), 456,     "MOD 123456%%1000=456");

    /* ================================================================ */
    /* Остаток от деления (unsigned)                                     */
    /* ================================================================ */
    CHECK_EQ(U(7) % U(3),     1u,          "UMOD 7%%3=1");
    CHECK_EQ(U(0xFFFFFFFFu) % U(2), 1u,    "UMOD MAX%%2=1");
    CHECK_EQ(U(0xFFFFFFFFu) % U(10), 5u,   "UMOD MAX%%10=5");
    CHECK_EQ(U(100) % U(7),   2u,          "UMOD 100%%7=2");

    /* ================================================================ */
    /* Комбинированные: (a*b)/c, a*b+c*d                                */
    /* ================================================================ */
    CHECK_EQ((I(6) * I(7)) / I(3), 14,     "COMBO (6*7)/3=14");
    CHECK_EQ(I(3) * I(5) + I(4) * I(7), 43, "COMBO 3*5+4*7=43");
    CHECK_EQ((I(1000) * I(1000)) / I(100), 10000, "COMBO 1M/100=10K");
    CHECK_EQ((I(255) * I(256)) % I(1000), 280, "COMBO (255*256)%%1000=280");

    /* Степени двойки через умножение */
    int p = I(1);
    for (int i = 0; i < 30; i++) p = p * I(2);
    CHECK_EQ(p, 1 << 30, "MUL power-of-2 loop: 2^30");

    DONE();
    return 0;
}
