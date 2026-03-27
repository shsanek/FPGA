#pragma once
#include "runtime.h"

static int g_failed = 0;

static void chk_fail(const char *msg) {
    puts(msg);
    g_failed = 1;
}

/* CHECK(expr, "name") — prints "FAIL: name" if expr is false */
#define CHECK(expr, msg) \
    do { if (!(expr)) chk_fail("FAIL: " msg); } while (0)

/* CHECK_EQ(a, b, "name") — checks a == b, prints hex values on failure */
#define CHECK_EQ(a, b, msg) \
    do { \
        unsigned int _a = (unsigned int)(a); \
        unsigned int _b = (unsigned int)(b); \
        if (_a != _b) { \
            chk_fail("FAIL: " msg); \
            puts("  got:      0x"); print_hex(_a); print_nl(); \
            puts("  expected: 0x"); print_hex(_b); print_nl(); \
        } \
    } while (0)

#define DONE() do { if (!g_failed) puts("ALL OK"); } while (0)
