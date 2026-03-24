#include "../../runtime.h"

int main(void) {
    int s = 0;
    for (int i = 1; i <= 100; i++) s += i;
    print_int(s);
    putchar('\n');
    return 0;
}
