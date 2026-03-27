#include "../common/runtime.h"

static int fib(int n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

int fib_run(void);
#ifndef NO_MAIN
int main(void) { return fib_run(); }
#endif
int fib_run(void) {
    for (int i = 0; i < 10; i++) {
        print_int(fib(i));
        putchar('\n');
    }
    return 0;
}
