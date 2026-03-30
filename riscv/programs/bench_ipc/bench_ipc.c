/*
 * IPC Benchmark — realistic instruction mix.
 *
 * Target: ~500+ instructions per iteration.
 * Mix: ~50% ALU, ~20% LOAD/STORE, ~15% BRANCH, ~10% JUMP (call/ret), ~5% LUI
 *
 * Runs ITERATIONS times. First pass = cold cache, subsequent = warm.
 * Result in x10 (a0) for verification.
 */

#define N 32
#ifndef ITERATIONS
#define ITERATIONS 10
#endif

static volatile int arr[N];
static volatile int result;

static int __attribute__((noinline)) sum_array(volatile int *a, int n) {
    int s = 0;
    for (int i = 0; i < n; i++)
        s += a[i];
    return s;
}

static int __attribute__((noinline)) find_minmax(volatile int *a, int n,
                                                  volatile int *out_min,
                                                  volatile int *out_max) {
    int mn = a[0], mx = a[0];
    for (int i = 1; i < n; i++) {
        int v = a[i];
        if (v < mn) mn = v;
        if (v > mx) mx = v;
    }
    *out_min = mn;
    *out_max = mx;
    return mx - mn;
}

static void __attribute__((noinline)) transform(volatile int *a, int n) {
    for (int i = 0; i < n; i++) {
        int v = a[i];
        int t = (v << 2) - v;       /* v*3 */
        t = t + 7;
        t = t ^ (v >> 1);
        t = t & 0xFFFF;
        a[i] = t;
    }
}

static int __attribute__((noinline)) bubble_pass(volatile int *a, int n) {
    int swapped = 0;
    for (int i = 0; i < n - 1; i++) {
        if (a[i] > a[i + 1]) {
            int tmp = a[i];
            a[i] = a[i + 1];
            a[i + 1] = tmp;
            swapped = 1;
        }
    }
    return swapped;
}

static void __attribute__((noinline)) prefix_sum(volatile int *a, int n) {
    for (int i = 1; i < n; i++)
        a[i] += a[i - 1];
}

static int __attribute__((noinline)) count_positive(volatile int *a, int n) {
    int c = 0;
    for (int i = 0; i < n; i++)
        if (a[i] > 0) c++;
    return c;
}

static void __attribute__((noinline)) fill(volatile int *a, int n, int seed) {
    for (int i = 0; i < n; i++)
        a[i] = (seed + i * 7) ^ (i << 3);
}

int main(void) {
    int total = 0;

    for (int iter = 0; iter < ITERATIONS; iter++) {
        volatile int mn, mx;

        fill(arr, N, iter * 13);
        total += sum_array(arr, N);
        total += find_minmax(arr, N, &mn, &mx);

        transform(arr, N);

        bubble_pass(arr, N);
        bubble_pass(arr, N);
        bubble_pass(arr, N);

        prefix_sum(arr, N);
        total += count_positive(arr, N);
    }

    result = total;
    return total;
}
