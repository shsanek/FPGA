/*
 * test_alu.c — покрытие всех R-type и I-type ALU инструкций RV32I.
 *
 * R-type (funct3 + funct7):  ADD SUB SLL SLT SLTU XOR SRL SRA OR AND
 * I-type (funct3):           ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI
 *
 * Значения скрываем через noinline-функции — компилятор не знает их на этапе
 * компиляции и вынужден генерировать реальные ALU-инструкции.
 */
#include "../common/check.h"

/* Возвращает аргумент как есть; компилятор не может подставить значение. */
__attribute__((noinline)) static int       I(int x)          { return x; }
__attribute__((noinline)) static unsigned  U(unsigned int x)  { return x; }

int test_alu_run(void);
#ifndef NO_MAIN
int main(void) { return test_alu_run(); }
#endif
int test_alu_run(void) {
    int       a, b;
    unsigned  ua, ub;

    /* ------------------------------------------------------------------ */
    /* ADD / SUB                                                            */
    /* ------------------------------------------------------------------ */
    a = I(10);  b = I(3);
    CHECK_EQ(a + b,  13,         "ADD  10+3");
    CHECK_EQ(a - b,  7,          "SUB  10-3");
    CHECK_EQ(I(-1) + I(1), 0,   "ADD  -1+1=0  (wrap)");
    CHECK_EQ(I(0)  - I(1), -1,  "SUB  0-1=-1");
    /* Переполнение: INT_MAX + 1 = INT_MIN (unsigned cast, no UB) */
    CHECK_EQ((unsigned int)I(0x7FFFFFFF) + 1u, 0x80000000u, "ADD overflow");

    /* ------------------------------------------------------------------ */
    /* SLL — логический сдвиг влево                                        */
    /* ------------------------------------------------------------------ */
    CHECK_EQ(U(1) << U(0),   1u,          "SLL  1<<0");
    CHECK_EQ(U(1) << U(1),   2u,          "SLL  1<<1");
    CHECK_EQ(U(1) << U(31),  0x80000000u, "SLL  1<<31");
    CHECK_EQ(U(0xFF) << U(8), 0xFF00u,    "SLL  0xFF<<8");
    CHECK_EQ(U(0xAB) << U(16), 0x00AB0000u, "SLL  0xAB<<16");

    /* ------------------------------------------------------------------ */
    /* SRL — логический сдвиг вправо (заполняет 0)                        */
    /* ------------------------------------------------------------------ */
    CHECK_EQ(U(0x80000000u) >> U(1),  0x40000000u, "SRL  0x80000000>>1");
    CHECK_EQ(U(0xFFFFFFFFu) >> U(31), 1u,           "SRL  0xFFFFFFFF>>31");
    CHECK_EQ(U(0xFF) >> U(4),         0x0Fu,         "SRL  0xFF>>4");
    CHECK_EQ(U(1)   >> U(0),          1u,            "SRL  1>>0");

    /* ------------------------------------------------------------------ */
    /* SRA — арифметический сдвиг вправо (сохраняет знак)                 */
    /* ------------------------------------------------------------------ */
    CHECK_EQ(I(-4)  >> I(1),  -2,  "SRA  -4>>1=-2");
    CHECK_EQ(I(-1)  >> I(31), -1,  "SRA  -1>>31=-1");
    CHECK_EQ(I(-256)>> I(4),  -16, "SRA  -256>>4=-16");
    CHECK_EQ(I(16)  >> I(2),  4,   "SRA  16>>2=4  (positive)");

    /* ------------------------------------------------------------------ */
    /* SLT — signed less-than: (a < b) ? 1 : 0                            */
    /* ------------------------------------------------------------------ */
    CHECK_EQ(I(-1)  < I(0),  1, "SLT  -1<0");
    CHECK_EQ(I(-1)  < I(1),  1, "SLT  -1<1");
    CHECK_EQ(I(1)   < I(0),  0, "SLT  1<0=0");
    CHECK_EQ(I(0)   < I(0),  0, "SLT  0<0=0");
    CHECK_EQ(I(-2)  < I(-1), 1, "SLT  -2<-1");

    /* ------------------------------------------------------------------ */
    /* SLTU — unsigned less-than                                           */
    /* ------------------------------------------------------------------ */
    /* 0xFFFFFFFF как unsigned > 0, но как signed = -1 < 0 */
    CHECK_EQ(U(0xFFFFFFFFu) > U(0u), 1u, "SLTU 0xFFFFFFFF > 0 unsigned");
    CHECK_EQ(U(0u) < U(0xFFFFFFFFu), 1u, "SLTU 0 < 0xFFFFFFFF unsigned");
    CHECK_EQ(U(5u) < U(10u),         1u, "SLTU 5<10");
    CHECK_EQ(U(10u)< U(5u),          0u, "SLTU 10<5=0");

    /* ------------------------------------------------------------------ */
    /* XOR / OR / AND                                                      */
    /* ------------------------------------------------------------------ */
    ua = U(0xAAAAAAAAu);  ub = U(0x55555555u);
    CHECK_EQ(ua ^ ub, 0xFFFFFFFFu, "XOR  0xAA...^0x55...=0xFF...");
    CHECK_EQ(ua ^ ua, 0u,           "XOR  a^a=0");
    CHECK_EQ(ua | ub, 0xFFFFFFFFu, "OR   0xAA...|0x55...=0xFF...");
    CHECK_EQ(U(0u)  | ua, ua,       "OR   0|a=a");
    CHECK_EQ(ua & ub, 0u,           "AND  0xAA...&0x55...=0");
    CHECK_EQ(U(0xFFFFFFFFu) & ua, ua, "AND  0xFF...&a=a");
    CHECK_EQ(U(0xF0u) & U(0xFFu),  0xF0u, "AND  0xF0&0xFF=0xF0");

    /* ------------------------------------------------------------------ */
    /* ADDI — immediate добавление (12-bit signed, -2048..2047)            */
    /* ------------------------------------------------------------------ */
    a = I(0);
    CHECK_EQ(a + 1,     1,    "ADDI 0+1");
    CHECK_EQ(a + (-1),  -1,   "ADDI 0+(-1)");
    CHECK_EQ(a + 2047,  2047, "ADDI 0+2047 (max positive imm)");
    CHECK_EQ(a + (-2048), -2048, "ADDI 0+(-2048) (max negative imm)");
    a = I(100);
    CHECK_EQ(a + 0, 100, "ADDI +0 (no-op)");

    /* ------------------------------------------------------------------ */
    /* SLTI — signed immediate compare                                     */
    /* ------------------------------------------------------------------ */
    a = I(-1);
    CHECK((a < 0),  "SLTI -1<0");
    CHECK((a < 1),  "SLTI -1<1");
    CHECK(!(a < -2), "SLTI -1 not < -2");

    /* ------------------------------------------------------------------ */
    /* SLTIU — unsigned immediate compare                                  */
    /* ------------------------------------------------------------------ */
    ua = U(0u);
    CHECK((ua < 1u), "SLTIU 0<1");
    CHECK(!(ua < 0u), "SLTIU 0 not < 0");

    /* ------------------------------------------------------------------ */
    /* XORI / ORI / ANDI                                                   */
    /* ------------------------------------------------------------------ */
    ua = U(0xFFFF0000u);
    CHECK_EQ(ua ^ 0xFFFFFFFFu, 0x0000FFFFu, "XORI 0xFFFF0000^-1=0x0000FFFF");
    CHECK_EQ(ua | 0x0000FFFFu, 0xFFFFFFFFu, "ORI  0xFFFF0000|0x0000FFFF");
    CHECK_EQ(ua & 0xFF000000u, 0xFF000000u, "ANDI mask upper byte");

    /* ------------------------------------------------------------------ */
    /* SLLI / SRLI / SRAI — immediate shifts                               */
    /* ------------------------------------------------------------------ */
    ua = U(1u);
    CHECK_EQ(ua << 0,  1u,          "SLLI 1<<0");
    CHECK_EQ(ua << 15, 0x8000u,     "SLLI 1<<15");
    CHECK_EQ(ua << 31, 0x80000000u, "SLLI 1<<31");

    ua = U(0x80000000u);
    CHECK_EQ(ua >> 1,  0x40000000u, "SRLI 0x80000000>>1");
    CHECK_EQ(ua >> 31, 1u,           "SRLI 0x80000000>>31=1");

    a = I(-1024);
    CHECK_EQ(a >> 2,  -256, "SRAI -1024>>2=-256");
    CHECK_EQ(a >> 10, -1,   "SRAI -1024>>10=-1");

    DONE();
    return 0;
}
