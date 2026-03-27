/*
 * test_branch.c — покрытие всех 6 условных переходов RV32I.
 *
 * BEQ  BNE  BLT  BGE  BLTU  BGEU
 *
 * Каждый переход тестируется в двух случаях: taken и not-taken.
 * Ключевые граничные случаи:
 *   BLT/BGE  — знаковое сравнение (0x80000000 < 0x7FFFFFFF как signed)
 *   BLTU/BGEU — беззнаковое (0xFFFFFFFF > 0 и 0x80000000 > 0x7FFFFFFF)
 *
 * volatile переменные — компилятор не знает значений на этапе компиляции
 * и вынужден генерировать реальные ветвления.
 *
 * Также тестируем: цикл (backward branch), вложенные условия, JALR при
 * возврате из функции.
 */
#include "../common/check.h"

/* ---------- вспомогательный инструментарий ----------------------------- */

/* Считаем количество taken/not-taken переходов чтобы убедиться,
   что оба пути действительно исполнились. */
static volatile int cnt_taken = 0;
static volatile int cnt_notaken = 0;

static void taken(void)   { cnt_taken++;   }
static void notaken(void) { cnt_notaken++; }

/* Branch wrapper: проходит через taken(), если condition истинно */
#define BR_TAKEN(cond, name)  \
    do { \
        cnt_taken = 0; cnt_notaken = 0; \
        if (cond) taken(); else notaken(); \
        CHECK(cnt_taken   == 1, name " taken");   \
        CHECK(cnt_notaken == 0, name " taken: notaken=0"); \
    } while(0)

#define BR_NOTAKEN(cond, name)  \
    do { \
        cnt_taken = 0; cnt_notaken = 0; \
        if (cond) taken(); else notaken(); \
        CHECK(cnt_taken   == 0, name " not-taken: taken=0"); \
        CHECK(cnt_notaken == 1, name " not-taken"); \
    } while(0)

int test_branch_run(void);
#ifndef NO_MAIN
int main(void) { return test_branch_run(); }
#endif
int test_branch_run(void) {
    volatile int  sa = 0, sb = 0;
    volatile unsigned int ua = 0, ub = 0;

    /* ================================================================== */
    /* BEQ — branch if equal                                               */
    /* ================================================================== */
    sa = 5;  sb = 5;   BR_TAKEN  (sa == sb,  "BEQ");
    sa = 5;  sb = 6;   BR_NOTAKEN(sa == sb,  "BEQ");
    sa = -1; sb = -1;  BR_TAKEN  (sa == sb,  "BEQ negative");
    sa = 0;  sb = 0;   BR_TAKEN  (sa == sb,  "BEQ zero");

    /* ================================================================== */
    /* BNE — branch if not equal                                           */
    /* ================================================================== */
    sa = 5;  sb = 6;   BR_TAKEN  (sa != sb,  "BNE");
    sa = 5;  sb = 5;   BR_NOTAKEN(sa != sb,  "BNE");
    sa = -1; sb = 1;   BR_TAKEN  (sa != sb,  "BNE signed");

    /* ================================================================== */
    /* BLT — branch if less (signed)                                       */
    /* ================================================================== */
    sa = -1; sb = 0;   BR_TAKEN  (sa < sb,   "BLT -1<0");
    sa = -1; sb = 1;   BR_TAKEN  (sa < sb,   "BLT -1<1");
    sa = 1;  sb = -1;  BR_NOTAKEN(sa < sb,   "BLT 1<-1=F");
    sa = 0;  sb = 0;   BR_NOTAKEN(sa < sb,   "BLT 0<0=F");
    /* INT_MIN < INT_MAX signed */
    sa = (int)0x80000000u;  sb = 0x7FFFFFFF;
    BR_TAKEN  (sa < sb,                      "BLT INT_MIN<INT_MAX");
    /* 0x80000000 > 0x7FFFFFFF signed → NOT taken */
    BR_NOTAKEN(sb < sa,                      "BLT INT_MAX<INT_MIN=F");

    /* ================================================================== */
    /* BGE — branch if greater or equal (signed)                           */
    /* ================================================================== */
    sa = 0;  sb = 0;   BR_TAKEN  (sa >= sb,  "BGE 0>=0");
    sa = 1;  sb = 0;   BR_TAKEN  (sa >= sb,  "BGE 1>=0");
    sa = 0;  sb = 1;   BR_NOTAKEN(sa >= sb,  "BGE 0>=1=F");
    sa = -1; sb = 0;   BR_NOTAKEN(sa >= sb,  "BGE -1>=0=F");
    sa = -1; sb = -1;  BR_TAKEN  (sa >= sb,  "BGE -1>=-1");

    /* ================================================================== */
    /* BLTU — branch if less (unsigned)                                    */
    /* ================================================================== */
    ua = 0u;           ub = 0xFFFFFFFFu;
    BR_TAKEN  ((int)(ua < ub),             "BLTU 0<0xFFFFFFFF");
    BR_NOTAKEN((int)(ub < ua),             "BLTU 0xFFFFFFFF<0=F");
    ua = 0x7FFFFFFFu;  ub = 0x80000000u;
    BR_TAKEN  ((int)(ua < ub),             "BLTU 0x7FFFFFFF<0x80000000");
    /* signed: 0x80000000 < 0x7FFFFFFF, unsigned: reversed */
    BR_NOTAKEN((int)(ub < ua),             "BLTU 0x80000000<0x7FFFFFFF=F");

    /* ================================================================== */
    /* BGEU — branch if greater or equal (unsigned)                        */
    /* ================================================================== */
    ua = 0xFFFFFFFFu;  ub = 0u;
    BR_TAKEN  ((int)(ua >= ub),            "BGEU 0xFFFFFFFF>=0");
    BR_NOTAKEN((int)(ub >= ua),            "BGEU 0>=0xFFFFFFFF=F");
    ua = 5u;           ub = 5u;
    BR_TAKEN  ((int)(ua >= ub),            "BGEU 5>=5");

    /* ================================================================== */
    /* Цикл с backward branch (BNE / BLT)                                  */
    /* ================================================================== */
    {
        volatile int sum = 0;
        volatile int i;
        /* Сумма 1..10 = 55 */
        for (i = 1; i <= 10; i++) sum += i;
        CHECK_EQ(sum, 55, "loop BNE backward: sum 1..10=55");
    }
    {
        /* Вложенный цикл — 3×3 итерации */
        volatile int cnt = 0;
        volatile int r, c;
        for (r = 0; r < 3; r++)
            for (c = 0; c < 3; c++)
                cnt++;
        CHECK_EQ(cnt, 9, "nested loop: 3×3=9");
    }

    /* ================================================================== */
    /* Цепочка условий (if / else-if / else)                              */
    /* ================================================================== */
    {
        volatile int v = 42;
        int result = 0;
        if      (v < 0)   result = -1;
        else if (v == 42) result = 42;
        else              result = 1;
        CHECK_EQ(result, 42, "if-elseif-else: v=42");
    }

    DONE();
    return 0;
}
