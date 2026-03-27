/*
 * boot_tests.c — объединённый тест всех ISA-подсистем для BOOT.BIN.
 *
 * Запускает: hello, fib, sum, test_alu, test_branch, test_jump, test_mem, test_upper.
 * Выводит результат каждого набора и итоговый счёт.
 *
 * Сборка:
 *   cd riscv/boot/tools
 *   make boot BOOT_SRC=../../programs/boot_tests/boot_tests.c
 *   → BOOT.BIN → скопировать на SD карту
 */
#include "../common/runtime.h"

/* check.h использует static g_failed — нужен сброс между тестами */
extern int g_failed;

/* Объявления функций из отдельных тест-файлов */
int hello_run(void);
int fib_run(void);
int sum_run(void);
int test_alu_run(void);
int test_branch_run(void);
int test_jump_run(void);
int test_mem_run(void);
int test_upper_run(void);
int test_oled_run(void);

static int run_suite(const char *name, int (*fn)(void)) {
    puts("--- ");
    puts(name);
    g_failed = 0;
    fn();
    if (g_failed) {
        puts("  FAIL");
        return 1;
    }
    puts("  OK");
    return 0;
}

int main(void) {
    int fail = 0;

    puts("=== BOOT TESTS ===");

    /* hello/fib/sum не используют g_failed, просто выводят */
    puts("--- hello");
    hello_run();
    puts("  OK");

    puts("--- fib");
    fib_run();
    puts("  OK");

    puts("--- sum");
    sum_run();
    puts("  OK");

    /* ISA тесты — используют CHECK_EQ / g_failed */
    fail += run_suite("test_alu",    test_alu_run);
    fail += run_suite("test_branch", test_branch_run);
    fail += run_suite("test_jump",   test_jump_run);
    fail += run_suite("test_mem",    test_mem_run);
    fail += run_suite("test_upper",  test_upper_run);

    /* Hardware тесты */
    puts("--- test_oled");
    test_oled_run();
    puts("  OK");

    puts("");
    if (fail == 0) {
        puts("=== ALL 9 TESTS PASSED ===");
    } else {
        puts("=== FAILURES: ");
        print_int(fail);
        puts(" ===");
    }

    return fail;
}
