#include "../common/runtime.h"

int hello_run(void);
#ifndef NO_MAIN
int main(void) { return hello_run(); }
#endif
int hello_run(void) {
    puts("Hello, RISC-V!");
    return 0;
}
