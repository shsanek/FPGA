#include "../common/runtime.h"

int sum_run(void);
#ifndef NO_MAIN
int main(void) { return sum_run(); }
#endif
int sum_run(void) {
    int s = 0;
    for (int i = 1; i <= 100; i++) s += i;
    print_int(s);
    putchar('\n');
    return 0;
}
