/*
 * test_muldiv_hw.c — тест аппаратного MUL/DIV (rv32im M-extension).
 *
 * Использует inline asm чтобы гарантировать генерацию реальных MUL/DIV/REM инструкций.
 * Для запуска на железе как BOOT.BIN.
 */
#include "../common/runtime.h"

static int errors = 0;

static void check(const char *name, int got, int expected) {
    if (got != expected) {
        puts("FAIL: ");
        puts(name);
        puts("  got="); print_hex((unsigned)got);
        puts("  exp="); print_hex((unsigned)expected);
        putchar('\n');
        errors++;
    }
}

/* ---- MUL: rd = (rs1 * rs2)[31:0] ---- */
static int hw_mul(int a, int b) {
    int r;
    __asm__ volatile("mul %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

/* ---- MULH: rd = (rs1 * rs2)[63:32] (signed×signed) ---- */
static int hw_mulh(int a, int b) {
    int r;
    __asm__ volatile("mulh %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

/* ---- MULHU: rd = (rs1 * rs2)[63:32] (unsigned×unsigned) ---- */
static unsigned hw_mulhu(unsigned a, unsigned b) {
    unsigned r;
    __asm__ volatile("mulhu %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

/* ---- MULHSU: rd = (rs1 * rs2)[63:32] (signed×unsigned) ---- */
static int hw_mulhsu(int a, unsigned b) {
    int r;
    __asm__ volatile("mulhsu %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

/* ---- DIV: signed division ---- */
static int hw_div(int a, int b) {
    int r;
    __asm__ volatile("div %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

/* ---- DIVU: unsigned division ---- */
static unsigned hw_divu(unsigned a, unsigned b) {
    unsigned r;
    __asm__ volatile("divu %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

/* ---- REM: signed remainder ---- */
static int hw_rem(int a, int b) {
    int r;
    __asm__ volatile("rem %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

/* ---- REMU: unsigned remainder ---- */
static unsigned hw_remu(unsigned a, unsigned b) {
    unsigned r;
    __asm__ volatile("remu %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));
    return r;
}

int main(void) {
    puts("=== MUL/DIV HW TEST ===");

    /* ---- MUL ---- */
    puts("MUL:");
    check("3*7",        hw_mul(3, 7),       21);
    check("0*123",      hw_mul(0, 123),     0);
    check("1*(-1)",     hw_mul(1, -1),      -1);
    check("(-1)*(-1)",  hw_mul(-1, -1),     1);
    check("100*100",    hw_mul(100, 100),    10000);
    check("(-5)*6",     hw_mul(-5, 6),      -30);
    check("256*256",    hw_mul(256, 256),    65536);
    check("0x1000*0x1000", hw_mul(0x1000, 0x1000), 0x1000000);
    check("0xFFFF*0xFFFF", hw_mul(0xFFFF, 0xFFFF), (int)0xFFFE0001u);
    check("0x10000*0x10000", hw_mul(0x10000, 0x10000), 0); /* overflow low32=0 */

    /* ---- MULH (signed high) ---- */
    puts("MULH:");
    check("1*1",        hw_mulh(1, 1),      0);
    check("0x10000*0x10000", hw_mulh(0x10000, 0x10000), 1);
    check("(-1)*(-1)",  hw_mulh(-1, -1),    0);
    check("(-1)*1",     hw_mulh(-1, 1),     -1);
    check("0x7FFFFFFF*2", hw_mulh(0x7FFFFFFF, 2), 0);
    check("0x40000000*4", hw_mulh(0x40000000, 4), 1);

    /* ---- MULHU (unsigned high) ---- */
    puts("MULHU:");
    check("1*1",        hw_mulhu(1, 1),     0);
    check("0xFFFFFFFF*2", hw_mulhu(0xFFFFFFFFu, 2), 1);
    check("0xFFFFFFFF*0xFFFFFFFF", hw_mulhu(0xFFFFFFFFu, 0xFFFFFFFFu), 0xFFFFFFFEu);
    check("0x80000000*2", hw_mulhu(0x80000000u, 2), 1);

    /* ---- MULHSU (signed*unsigned high) ---- */
    puts("MULHSU:");
    check("1*1",        hw_mulhsu(1, 1),    0);
    check("(-1)*1",     hw_mulhsu(-1, 1),   -1);
    check("(-1)*0xFFFFFFFF", hw_mulhsu(-1, 0xFFFFFFFFu), -1);
    check("1*0xFFFFFFFF", hw_mulhsu(1, 0xFFFFFFFFu), 0);

    /* ---- DIV ---- */
    puts("DIV:");
    check("21/7",       hw_div(21, 7),      3);
    check("100/10",     hw_div(100, 10),    10);
    check("7/2",        hw_div(7, 2),       3);
    check("(-7)/2",     hw_div(-7, 2),      -3);
    check("7/(-2)",     hw_div(7, -2),      -3);
    check("(-7)/(-2)",  hw_div(-7, -2),     3);
    check("0/5",        hw_div(0, 5),       0);
    check("1000000/1000", hw_div(1000000, 1000), 1000);
    /* div by zero → -1 (RISC-V spec) */
    check("1/0",        hw_div(1, 0),       -1);
    /* overflow: INT_MIN / -1 → INT_MIN (RISC-V spec) */
    check("INT_MIN/(-1)", hw_div((int)0x80000000, -1), (int)0x80000000);

    /* ---- DIVU ---- */
    puts("DIVU:");
    check("21/7",       hw_divu(21, 7),     3);
    check("0xFFFFFFFF/1", hw_divu(0xFFFFFFFFu, 1), 0xFFFFFFFFu);
    check("0xFFFFFFFF/2", hw_divu(0xFFFFFFFFu, 2), 0x7FFFFFFFu);
    check("100/3",      hw_divu(100, 3),    33);
    /* divu by zero → 0xFFFFFFFF (RISC-V spec) */
    check("1/0",        hw_divu(1, 0),      0xFFFFFFFFu);

    /* ---- REM ---- */
    puts("REM:");
    check("7%3",        hw_rem(7, 3),       1);
    check("(-7)%3",     hw_rem(-7, 3),      -1);
    check("7%(-3)",     hw_rem(7, -3),      1);
    check("(-7)%(-3)",  hw_rem(-7, -3),     -1);
    check("0%7",        hw_rem(0, 7),       0);
    check("123456%1000", hw_rem(123456, 1000), 456);
    /* rem by zero → dividend (RISC-V spec) */
    check("5%0",        hw_rem(5, 0),       5);
    /* overflow: INT_MIN % -1 → 0 (RISC-V spec) */
    check("INT_MIN%(-1)", hw_rem((int)0x80000000, -1), 0);

    /* ---- REMU ---- */
    puts("REMU:");
    check("7%3",        hw_remu(7, 3),      1);
    check("0xFFFFFFFF%2", hw_remu(0xFFFFFFFFu, 2), 1);
    check("0xFFFFFFFF%10", hw_remu(0xFFFFFFFFu, 10), 5);
    check("100%7",      hw_remu(100, 7),    2);
    /* remu by zero → dividend (RISC-V spec) */
    check("5%0",        hw_remu(5, 0),      5);

    /* ---- Summary ---- */
    putchar('\n');
    if (errors == 0) {
        puts("=== ALL MUL/DIV HW TESTS PASSED ===");
    } else {
        puts("=== FAILURES: ");
        print_int(errors);
        puts(" ===");
    }
    return errors;
}
