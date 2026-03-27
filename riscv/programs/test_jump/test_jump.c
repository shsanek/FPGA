/*
 * test_jump.c — покрытие JAL и JALR инструкций RV32I.
 *
 * JAL  — прямой вызов функции (PC-relative, ±1 МБ)
 * JALR — косвенный переход (rs1 + imm); используется при:
 *         - возврате из функции (ret = jalr x0, ra, 0)
 *         - вызове через указатель на функцию
 *         - хвостовом вызове через указатель
 *
 * Тесты:
 *   1. Прямой вызов функции, возврат значения
 *   2. Рекурсия — факториал (глубокое использование стека и ret)
 *   3. Взаимная рекурсия — even/odd (два JAL, каждый вызывает другой)
 *   4. Указатель на функцию — JALR через register
 *   5. Массив указателей на функции — JALR с разными адресами
 *   6. Хвостовой вызов через указатель
 */
#include "../common/check.h"

/* ------------------------------------------------------------------ */
/* 1. Простая функция                                                  */
/* ------------------------------------------------------------------ */
__attribute__((noinline)) static int square(int x) { return x * x; }

/* ------------------------------------------------------------------ */
/* 2. Рекурсия: факториал                                              */
/* ------------------------------------------------------------------ */
__attribute__((noinline)) static int fact(int n) {
    if (n <= 1) return 1;
    return n * fact(n - 1);
}

/* ------------------------------------------------------------------ */
/* 3. Взаимная рекурсия                                                */
/* ------------------------------------------------------------------ */
static int is_even(int n);
static int is_odd(int n);

__attribute__((noinline)) static int is_even(int n) {
    if (n == 0) return 1;
    return is_odd(n - 1);
}
__attribute__((noinline)) static int is_odd(int n) {
    if (n == 0) return 0;
    return is_even(n - 1);
}

/* ------------------------------------------------------------------ */
/* 4-5. Указатели на функции (JALR)                                   */
/* ------------------------------------------------------------------ */
typedef int (*int_fn)(int);

__attribute__((noinline)) static int apply(int_fn fn, int x) {
    return fn(x);   /* JALR через регистр */
}

__attribute__((noinline)) static int double_val(int x) { return x * 2; }
__attribute__((noinline)) static int negate(int x)     { return -x;    }
__attribute__((noinline)) static int identity(int x)   { return x;     }

/* ------------------------------------------------------------------ */
/* 6. Вызов через массив указателей                                    */
/* ------------------------------------------------------------------ */
static int call_table(int_fn tbl[], int idx, int arg) {
    return tbl[idx](arg);  /* JALR через load + register */
}

int main(void) {
    /* 1. Прямой вызов */
    CHECK_EQ(square(0),  0,  "JAL square(0)");
    CHECK_EQ(square(5),  25, "JAL square(5)");
    CHECK_EQ(square(-3), 9,  "JAL square(-3)");
    CHECK_EQ(square(10), 100,"JAL square(10)");

    /* 2. Рекурсивный факториал (стек глубиной N) */
    CHECK_EQ(fact(1),  1,    "JAL/ret fact(1)");
    CHECK_EQ(fact(5),  120,  "JAL/ret fact(5)");
    CHECK_EQ(fact(10), 3628800, "JAL/ret fact(10)");

    /* 3. Взаимная рекурсия */
    CHECK(is_even(0),        "mutual-rec even(0)=T");
    CHECK(!is_even(1),       "mutual-rec even(1)=F");
    CHECK(is_odd(1),         "mutual-rec odd(1)=T");
    CHECK(!is_odd(0),        "mutual-rec odd(0)=F");
    CHECK(is_even(10),       "mutual-rec even(10)=T");
    CHECK(is_odd(7),         "mutual-rec odd(7)=T");

    /* 4. Вызов через указатель (JALR через регистр) */
    CHECK_EQ(apply(square,     7),  49,  "JALR ptr square(7)");
    CHECK_EQ(apply(double_val, 6),  12,  "JALR ptr double(6)");
    CHECK_EQ(apply(negate,     5),  -5,  "JALR ptr negate(5)");
    CHECK_EQ(apply(identity,   42), 42,  "JALR ptr identity(42)");

    /* 5. Таблица указателей (JALR после load) */
    int_fn tbl[3] = { identity, double_val, negate };
    CHECK_EQ(call_table(tbl, 0, 10), 10,  "JALR tbl[0]=identity");
    CHECK_EQ(call_table(tbl, 1, 10), 20,  "JALR tbl[1]=double");
    CHECK_EQ(call_table(tbl, 2, 10), -10, "JALR tbl[2]=negate");

    /* 6. Вложенные вызовы — проверяем сохранение ra на стеке */
    CHECK_EQ(apply(square, apply(double_val, 3)), 36, "nested JALR: square(double(3))=36");
    CHECK_EQ(fact(fact(1)), 1, "nested JAL: fact(fact(1))=1");

    DONE();
    return 0;
}
