/*
 * test_blitter.c — поэтапный тест hardware blitter (column + span).
 *
 * Тест 1: Прямая запись/чтение SCRATCHPAD (без blitter)
 * Тест 2: CMD=1 (column) — записать текстуру в DDR, blitter column, проверить результат
 * Тест 3: CMD=2 (span)   — записать flat текстуру в DDR, blitter span, проверить результат
 * Тест 4: Сравнить span blitter с программным вычислением
 *
 * Вывод через UART — смотрим логи.
 */
#include "runtime.h"

/* --- Hardware defines --- */
#define SCRATCH_BASE      0x10040000U
#define BLIT_BASE         (SCRATCH_BASE + 0x20000U)

#define BLIT_CMD          (*(volatile unsigned int *)(BLIT_BASE + 0x00))
#define BLIT_STATUS       (*(volatile unsigned int *)(BLIT_BASE + 0x04))
#define BLIT_SRC_ADDR     (*(volatile unsigned int *)(BLIT_BASE + 0x08))
#define BLIT_SRC_FRAC     (*(volatile unsigned int *)(BLIT_BASE + 0x0C))
#define BLIT_SRC_STEP     (*(volatile unsigned int *)(BLIT_BASE + 0x10))
#define BLIT_SRC_MASK     (*(volatile unsigned int *)(BLIT_BASE + 0x14))
#define BLIT_DST_OFFSET   (*(volatile unsigned int *)(BLIT_BASE + 0x18))
#define BLIT_DST_STEP     (*(volatile unsigned int *)(BLIT_BASE + 0x1C))
#define BLIT_COUNT        (*(volatile unsigned int *)(BLIT_BASE + 0x20))
#define BLIT_CMAP_OFFSET  (*(volatile unsigned int *)(BLIT_BASE + 0x24))
#define BLIT_SRC_YFRAC    (*(volatile unsigned int *)(BLIT_BASE + 0x28))
#define BLIT_SRC_YSTEP    (*(volatile unsigned int *)(BLIT_BASE + 0x2C))
#define BLIT_SRC_SHIFT    (*(volatile unsigned int *)(BLIT_BASE + 0x30))

#define SP(off)  (*(volatile unsigned char *)(SCRATCH_BASE + (off)))
#define SP32(off) (*(volatile unsigned int *)(SCRATCH_BASE + (off)))

/* DDR area for test textures — use 0x00008000 (32KB), well within ROM/RAM gap */
#define TEX_DDR_BASE   0x00008000U
#define TEX_DDR(off)   (*(volatile unsigned char *)(TEX_DDR_BASE + (off)))
#define TEX_DDR32(off) (*(volatile unsigned int  *)(TEX_DDR_BASE + (off)))

/* Identity colormap: index N → value N (at offset 0x1000 in scratchpad) */
#define CMAP_OFFSET  0x1000U

static void setup_identity_colormap(void) {
    /* Write 256 bytes: cmap[i] = i */
    for (int i = 0; i < 256; i += 4) {
        unsigned int val = (unsigned int)i
                         | ((unsigned int)(i+1) << 8)
                         | ((unsigned int)(i+2) << 16)
                         | ((unsigned int)(i+3) << 24);
        SP32(CMAP_OFFSET + i) = val;
    }
}

static void wait_blit(void) {
    /* CPU stalls while blitter_active, but poll STATUS just in case */
    while (BLIT_STATUS & 1);
}

int main(void) {
    int errors = 0;

    puts("=== BLITTER TEST ===");

    /* ---- Test 1: SCRATCHPAD direct R/W ---- */
    puts("T1: scratchpad direct R/W");
    SP(0x2000) = 0xAB;
    SP(0x2001) = 0xCD;
    unsigned char v0 = SP(0x2000);
    unsigned char v1 = SP(0x2001);
    if (v0 != 0xAB || v1 != 0xCD) {
        puts("  FAIL: sp read/write");
        puts("  got: 0x"); print_hex(v0); puts(" 0x"); print_hex(v1); print_nl();
        errors++;
    } else {
        puts("  OK");
    }

    /* ---- Setup ---- */
    setup_identity_colormap();
    puts("T1b: verify colormap");
    unsigned char cm0 = SP(CMAP_OFFSET + 0);
    unsigned char cm42 = SP(CMAP_OFFSET + 42);
    unsigned char cm255 = SP(CMAP_OFFSET + 255);
    if (cm0 != 0 || cm42 != 42 || cm255 != 255) {
        puts("  FAIL: colormap");
        puts("  cm[0]="); print_uint(cm0);
        puts(" cm[42]="); print_uint(cm42);
        puts(" cm[255]="); print_uint(cm255);
        print_nl();
        errors++;
    } else {
        puts("  OK");
    }

    /* ---- Test 2: DDR write/readback ---- */
    puts("T2a: DDR write+readback");

    TEX_DDR(0) = 10; TEX_DDR(1) = 20; TEX_DDR(2) = 30; TEX_DDR(3) = 40;
    TEX_DDR(4) = 50; TEX_DDR(5) = 60; TEX_DDR(6) = 70; TEX_DDR(7) = 80;

    /* Readback immediately */
    unsigned char d0 = TEX_DDR(0), d1 = TEX_DDR(1), d2 = TEX_DDR(2), d3 = TEX_DDR(3);
    if (d0 != 10 || d1 != 20 || d2 != 30 || d3 != 40) {
        puts("  FAIL DDR readback: ");
        print_uint(d0); putchar(' '); print_uint(d1); putchar(' ');
        print_uint(d2); putchar(' '); print_uint(d3); print_nl();
        errors++;
    } else {
        puts("  OK");
    }

    /* ---- Test 2b: Column blit with status check ---- */
    puts("T2b: column blit (CMD=1)");

    unsigned int st_before = BLIT_STATUS;
    puts("  status before CMD: "); print_hex(st_before); print_nl();

    /* Clear destination area in scratchpad */
    for (int i = 0; i < 32; i++)
        SP(0x3000 + i) = 0xEE;  /* sentinel */

    /* Blit: read 4 texels from DDR, write to scratchpad offset 0x3000, step=1 */
    BLIT_SRC_ADDR   = TEX_DDR_BASE;
    BLIT_SRC_FRAC   = 0 << 16;     /* start at texel 0, fixed 16.16 */
    BLIT_SRC_STEP   = 1 << 16;     /* step = 1.0 texel per pixel */
    BLIT_SRC_MASK   = 127;         /* wrap mask */
    BLIT_DST_OFFSET = 0x3000;      /* byte offset in scratchpad */
    BLIT_DST_STEP   = 1;           /* +1 byte per pixel */
    BLIT_COUNT      = 4;
    BLIT_CMAP_OFFSET = SCRATCH_BASE + CMAP_OFFSET; /* identity colormap */
    BLIT_CMD        = 1;           /* CMD_COLUMN → go! */

    /* Check status right after CMD (CPU should stall until blitter done) */
    unsigned int st_after = BLIT_STATUS;
    puts("  status after CMD: "); print_hex(st_after); print_nl();

    wait_blit();

    /* Check results — also dump raw bytes */
    unsigned char expected_col[4] = {10, 20, 30, 40};
    int col_ok = 1;
    puts("  dst bytes: ");
    for (int i = 0; i < 8; i++) {
        print_hex(SP(0x3000 + i)); putchar(' ');
    }
    print_nl();
    for (int i = 0; i < 4; i++) {
        unsigned char got = SP(0x3000 + i);
        if (got != expected_col[i]) {
            puts("  FAIL pixel ");
            print_int(i);
            puts(": got="); print_uint(got);
            puts(" exp="); print_uint(expected_col[i]);
            print_nl();
            col_ok = 0;
            errors++;
        }
    }
    if (col_ok) puts("  OK");

    /* ---- Test 3: CMD=2 (span) — simple case ---- */
    puts("T3: span blit (CMD=2) simple");

    /* Write a 8x8 flat texture in DDR at offset 64 (so different address) */
    /* Using 8x8 with shift=3 for simplicity, mask=7 */
    for (int y = 0; y < 8; y++)
        for (int x = 0; x < 8; x++)
            TEX_DDR(64 + y * 8 + x) = (unsigned char)(y * 8 + x + 1); /* values 1..64 */

    /* Clear destination */
    for (int i = 0; i < 32; i++)
        SP(0x4000 + i) = 0;

    /* Blit span: read 4 texels from row 0 (x=0,1,2,3) */
    BLIT_SRC_ADDR   = TEX_DDR_BASE + 64;
    BLIT_SRC_FRAC   = 0;           /* xfrac = 0.0 */
    BLIT_SRC_STEP   = 1 << 16;     /* xstep = 1.0 per pixel */
    BLIT_SRC_MASK   = 7;           /* 8-wide texture, but mask is for full idx? no... */
    BLIT_SRC_YFRAC  = 0;           /* yfrac = 0.0 */
    BLIT_SRC_YSTEP  = 0;           /* no Y movement */
    BLIT_SRC_SHIFT  = 3;           /* log2(8) = 3 */
    BLIT_DST_OFFSET = 0x4000;
    BLIT_DST_STEP   = 1;
    BLIT_COUNT      = 4;
    BLIT_CMAP_OFFSET = SCRATCH_BASE + CMAP_OFFSET;
    BLIT_CMD        = 2;           /* CMD_SPAN → go! */
    wait_blit();

    /* Expected: texels at (0,0),(1,0),(2,0),(3,0) = 1,2,3,4 */
    unsigned char expected_span[4] = {1, 2, 3, 4};
    int span_ok = 1;
    for (int i = 0; i < 4; i++) {
        unsigned char got = SP(0x4000 + i);
        if (got != expected_span[i]) {
            puts("  FAIL pixel ");
            print_int(i);
            puts(": got="); print_uint(got);
            puts(" exp="); print_uint(expected_span[i]);
            print_nl();
            span_ok = 0;
            errors++;
        }
    }
    if (span_ok) puts("  OK");

    /* ---- Test 4: CMD=2 (span) with Y movement ---- */
    puts("T4: span blit with Y step");

    /* Clear destination */
    for (int i = 0; i < 32; i++)
        SP(0x5000 + i) = 0;

    /* Blit span: x fixed at 0, y steps 0→1→2→3 */
    BLIT_SRC_ADDR   = TEX_DDR_BASE + 64;
    BLIT_SRC_FRAC   = 0;           /* xfrac = 0 */
    BLIT_SRC_STEP   = 0;           /* xstep = 0 (no X movement) */
    BLIT_SRC_MASK   = 7;
    BLIT_SRC_YFRAC  = 0;           /* yfrac = 0 */
    BLIT_SRC_YSTEP  = 1 << 16;     /* ystep = 1.0 per pixel */
    BLIT_SRC_SHIFT  = 3;
    BLIT_DST_OFFSET = 0x5000;
    BLIT_DST_STEP   = 1;
    BLIT_COUNT      = 4;
    BLIT_CMAP_OFFSET = SCRATCH_BASE + CMAP_OFFSET;
    BLIT_CMD        = 2;
    wait_blit();

    /* Expected: texels at (0,0),(0,1),(0,2),(0,3) = row*8+col+1 = 1,9,17,25 */
    unsigned char expected_ystep[4] = {1, 9, 17, 25};
    int ystep_ok = 1;
    for (int i = 0; i < 4; i++) {
        unsigned char got = SP(0x5000 + i);
        if (got != expected_ystep[i]) {
            puts("  FAIL pixel ");
            print_int(i);
            puts(": got="); print_uint(got);
            puts(" exp="); print_uint(expected_ystep[i]);
            print_nl();
            ystep_ok = 0;
            errors++;
        }
    }
    if (ystep_ok) puts("  OK");

    /* ---- Test 5: CMD=2 (span) with negative frac (DOOM-like) ---- */
    puts("T5: span blit negative coords");

    for (int i = 0; i < 32; i++)
        SP(0x6000 + i) = 0;

    /* Use 64x64 texture like DOOM */
    /* Write 64x64 flat: pixel[y][x] = (y*64+x) & 0xFF */
    for (int i = 0; i < 4096; i += 4) {
        unsigned int val = (unsigned int)(i & 0xFF)
                         | ((unsigned int)((i+1) & 0xFF) << 8)
                         | ((unsigned int)((i+2) & 0xFF) << 16)
                         | ((unsigned int)((i+3) & 0xFF) << 24);
        TEX_DDR32(256 + i) = val;
    }

    /* xfrac = -3.0 = 0xFFFD0000, yfrac = -2.0 = 0xFFFE0000 */
    /* With mask=63, effective x = (-3)&63 = 61, y = (-2)&63 = 62 */
    /* tex_idx = 62*64 + 61 = 4029 */
    /* pixel value = 4029 & 0xFF = 0xBD = 189 */
    BLIT_SRC_ADDR   = TEX_DDR_BASE + 256;
    BLIT_SRC_FRAC   = 0xFFFD0000U; /* xfrac = -3.0 */
    BLIT_SRC_STEP   = 1 << 16;     /* xstep = +1.0 */
    BLIT_SRC_MASK   = 63;
    BLIT_SRC_YFRAC  = 0xFFFE0000U; /* yfrac = -2.0 */
    BLIT_SRC_YSTEP  = 0;           /* no Y movement */
    BLIT_SRC_SHIFT  = 6;
    BLIT_DST_OFFSET = 0x6000;
    BLIT_DST_STEP   = 1;
    BLIT_COUNT      = 4;
    BLIT_CMAP_OFFSET = SCRATCH_BASE + CMAP_OFFSET;
    BLIT_CMD        = 2;
    wait_blit();

    /* Compute expected manually:
     * px0: x=(-3)&63=61, y=(-2)&63=62 → idx=62*64+61=4029 → 4029&0xFF = 189
     * px1: x=(-2)&63=62, y=62         → idx=62*64+62=4030 → 4030&0xFF = 190
     * px2: x=(-1)&63=63, y=62         → idx=62*64+63=4031 → 4031&0xFF = 191
     * px3: x=(0)&63=0,   y=62         → idx=62*64+0 =3968 → 3968&0xFF = 128
     */
    unsigned char expected_neg[4] = {189, 190, 191, 128};
    int neg_ok = 1;
    for (int i = 0; i < 4; i++) {
        unsigned char got = SP(0x6000 + i);
        if (got != expected_neg[i]) {
            puts("  FAIL pixel ");
            print_int(i);
            puts(": got="); print_uint(got);
            puts(" exp="); print_uint(expected_neg[i]);
            print_nl();
            neg_ok = 0;
            errors++;
        }
    }
    if (neg_ok) puts("  OK");

    /* ---- Test 6: Fractional steps (DOOM-like sub-texel stepping) ---- */
    puts("T6: span fractional steps");

    /* Reuse 8x8 texture from T3 at TEX_DDR_BASE+64, values 1..64 */
    for (int i = 0; i < 32; i++) SP(0x7000 + i) = 0;

    /* xstep = 0.5 (0x8000), ystep = 0.25 (0x4000), shift=3, mask=7 */
    /* Pixel 0: x=0>>16=0 & 7=0, y=0>>16=0 & 7=0 → idx=0*8+0=0 → val=1 */
    /* Pixel 1: x=0x8000>>16=0, y=0x4000>>16=0   → idx=0   → val=1 */
    /* Pixel 2: x=0x10000>>16=1, y=0x8000>>16=0   → idx=1   → val=2 */
    /* Pixel 3: x=0x18000>>16=1, y=0xC000>>16=0   → idx=1   → val=2 */
    /* Pixel 4: x=0x20000>>16=2, y=0x10000>>16=1  → idx=1*8+2=10 → val=11 */
    /* Pixel 5: x=0x28000>>16=2, y=0x14000>>16=1  → idx=10  → val=11 */
    /* Pixel 6: x=0x30000>>16=3, y=0x18000>>16=1  → idx=11  → val=12 */
    /* Pixel 7: x=0x38000>>16=3, y=0x1C000>>16=1  → idx=11  → val=12 */
    BLIT_SRC_ADDR   = TEX_DDR_BASE + 64;
    BLIT_SRC_FRAC   = 0;
    BLIT_SRC_STEP   = 0x8000;      /* xstep = 0.5 */
    BLIT_SRC_MASK   = 7;
    BLIT_SRC_YFRAC  = 0;
    BLIT_SRC_YSTEP  = 0x4000;      /* ystep = 0.25 */
    BLIT_SRC_SHIFT  = 3;
    BLIT_DST_OFFSET = 0x7000;
    BLIT_DST_STEP   = 1;
    BLIT_COUNT      = 8;
    BLIT_CMAP_OFFSET = SCRATCH_BASE + CMAP_OFFSET;
    BLIT_CMD        = 2;
    wait_blit();

    unsigned char expected_frac[8] = {1, 1, 2, 2, 11, 11, 12, 12};
    int frac_ok = 1;
    for (int i = 0; i < 8; i++) {
        unsigned char got = SP(0x7000 + i);
        if (got != expected_frac[i]) {
            puts("  FAIL pixel ");
            print_int(i);
            puts(": got="); print_uint(got);
            puts(" exp="); print_uint(expected_frac[i]);
            print_nl();
            frac_ok = 0;
            errors++;
        }
    }
    if (frac_ok) puts("  OK");

    /* ---- Test 7: Long span (64 pixels, full flat row) ---- */
    puts("T7: long span 64px");

    /* Use 64x64 texture at TEX_DDR_BASE+256 from T5 */
    /* pixel[y][x] = (y*64+x) & 0xFF */
    for (int i = 0; i < 80; i++) SP(0x8000 + i) = 0;

    /* Span along row 3: x steps 0..63, y fixed at 3 */
    BLIT_SRC_ADDR   = TEX_DDR_BASE + 256;
    BLIT_SRC_FRAC   = 0;
    BLIT_SRC_STEP   = 1 << 16;
    BLIT_SRC_MASK   = 63;
    BLIT_SRC_YFRAC  = 3 << 16;
    BLIT_SRC_YSTEP  = 0;
    BLIT_SRC_SHIFT  = 6;
    BLIT_DST_OFFSET = 0x8000;
    BLIT_DST_STEP   = 1;
    BLIT_COUNT      = 64;
    BLIT_CMAP_OFFSET = SCRATCH_BASE + CMAP_OFFSET;
    BLIT_CMD        = 2;
    wait_blit();

    /* Expected: tex[3][0..63] = (3*64+x)&0xFF = 192..255 */
    int long_ok = 1;
    for (int i = 0; i < 64; i++) {
        unsigned char got = SP(0x8000 + i);
        unsigned char exp = (unsigned char)((3 * 64 + i) & 0xFF);
        if (got != exp) {
            puts("  FAIL pixel ");
            print_int(i);
            puts(": got="); print_uint(got);
            puts(" exp="); print_uint(exp);
            print_nl();
            long_ok = 0;
            errors++;
            if (errors > 10) { puts("  (too many errors, stopping)"); break; }
        }
    }
    if (long_ok) puts("  OK");

    /* ---- Test 8: Non-identity colormap ---- */
    puts("T8: non-identity colormap");

    /* Write a colormap where cmap[i] = 255-i */
    for (int i = 0; i < 256; i += 4) {
        unsigned int val = (unsigned int)(255 - i)
                         | ((unsigned int)(255 - (i+1)) << 8)
                         | ((unsigned int)(255 - (i+2)) << 16)
                         | ((unsigned int)(255 - (i+3)) << 24);
        SP32(0x2000 + i) = val;
    }

    for (int i = 0; i < 16; i++) SP(0x9000 + i) = 0;

    /* Column blit: texels 10,20,30,40 through inverted colormap → 245,235,225,215 */
    BLIT_SRC_ADDR   = TEX_DDR_BASE;  /* same column texture from T2 */
    BLIT_SRC_FRAC   = 0;
    BLIT_SRC_STEP   = 1 << 16;
    BLIT_SRC_MASK   = 127;
    BLIT_DST_OFFSET = 0x9000;
    BLIT_DST_STEP   = 1;
    BLIT_COUNT      = 4;
    BLIT_CMAP_OFFSET = SCRATCH_BASE + 0x2000;  /* inverted colormap */
    BLIT_CMD        = 1;
    wait_blit();

    unsigned char expected_cmap[4] = {245, 235, 225, 215};
    int cmap_ok = 1;
    for (int i = 0; i < 4; i++) {
        unsigned char got = SP(0x9000 + i);
        if (got != expected_cmap[i]) {
            puts("  FAIL pixel ");
            print_int(i);
            puts(": got="); print_uint(got);
            puts(" exp="); print_uint(expected_cmap[i]);
            print_nl();
            cmap_ok = 0;
            errors++;
        }
    }
    if (cmap_ok) puts("  OK");

    /* ---- Test 9: Back-to-back blits (column then span) ---- */
    puts("T9: back-to-back column+span");

    for (int i = 0; i < 32; i++) SP(0xA000 + i) = 0;
    for (int i = 0; i < 32; i++) SP(0xA100 + i) = 0;

    /* Restore identity colormap */
    setup_identity_colormap();

    /* Column blit: 4 texels → 0xA000 */
    BLIT_SRC_ADDR   = TEX_DDR_BASE;
    BLIT_SRC_FRAC   = 0;
    BLIT_SRC_STEP   = 1 << 16;
    BLIT_SRC_MASK   = 127;
    BLIT_DST_OFFSET = 0xA000;
    BLIT_DST_STEP   = 1;
    BLIT_COUNT      = 4;
    BLIT_CMAP_OFFSET = SCRATCH_BASE + CMAP_OFFSET;
    BLIT_CMD        = 1;
    wait_blit();

    /* Immediately: span blit 4 texels → 0xA100 */
    BLIT_SRC_ADDR   = TEX_DDR_BASE + 64;
    BLIT_SRC_FRAC   = 0;
    BLIT_SRC_STEP   = 1 << 16;
    BLIT_SRC_MASK   = 7;
    BLIT_SRC_YFRAC  = 0;
    BLIT_SRC_YSTEP  = 0;
    BLIT_SRC_SHIFT  = 3;
    BLIT_DST_OFFSET = 0xA100;
    BLIT_DST_STEP   = 1;
    BLIT_COUNT      = 4;
    BLIT_CMAP_OFFSET = SCRATCH_BASE + CMAP_OFFSET;
    BLIT_CMD        = 2;
    wait_blit();

    int b2b_ok = 1;
    /* Check column result */
    for (int i = 0; i < 4; i++) {
        unsigned char got = SP(0xA000 + i);
        if (got != expected_col[i]) {
            puts("  FAIL col pixel ");
            print_int(i);
            puts(": got="); print_uint(got);
            puts(" exp="); print_uint(expected_col[i]);
            print_nl();
            b2b_ok = 0; errors++;
        }
    }
    /* Check span result */
    for (int i = 0; i < 4; i++) {
        unsigned char got = SP(0xA100 + i);
        if (got != expected_span[i]) {
            puts("  FAIL span pixel ");
            print_int(i);
            puts(": got="); print_uint(got);
            puts(" exp="); print_uint(expected_span[i]);
            print_nl();
            b2b_ok = 0; errors++;
        }
    }
    if (b2b_ok) puts("  OK");

    /* ---- Test 10: Span with wrapping (x crosses 64 boundary) ---- */
    puts("T10: span wrap-around");

    for (int i = 0; i < 16; i++) SP(0xB000 + i) = 0;

    /* Start at x=62, step +1, 4 pixels → x=62,63,0,1 (wraps via mask=63) */
    /* y fixed at 0 → tex_idx = 62,63,0,1 → values (62+1),(63+1),(0+1),(1+1) = 63,64,1,2 */
    /* But 64 & 0xFF = 64 */
    BLIT_SRC_ADDR   = TEX_DDR_BASE + 256;
    BLIT_SRC_FRAC   = 62 << 16;
    BLIT_SRC_STEP   = 1 << 16;
    BLIT_SRC_MASK   = 63;
    BLIT_SRC_YFRAC  = 0;
    BLIT_SRC_YSTEP  = 0;
    BLIT_SRC_SHIFT  = 6;
    BLIT_DST_OFFSET = 0xB000;
    BLIT_DST_STEP   = 1;
    BLIT_COUNT      = 4;
    BLIT_CMAP_OFFSET = SCRATCH_BASE + CMAP_OFFSET;
    BLIT_CMD        = 2;
    wait_blit();

    /* tex[0][62]=62&0xFF=62, tex[0][63]=63, tex[0][0]=0, tex[0][1]=1 */
    unsigned char expected_wrap[4] = {62, 63, 0, 1};
    int wrap_ok = 1;
    for (int i = 0; i < 4; i++) {
        unsigned char got = SP(0xB000 + i);
        if (got != expected_wrap[i]) {
            puts("  FAIL pixel ");
            print_int(i);
            puts(": got="); print_uint(got);
            puts(" exp="); print_uint(expected_wrap[i]);
            print_nl();
            wrap_ok = 0; errors++;
        }
    }
    if (wrap_ok) puts("  OK");

    /* ---- Test 11: Large DOOM-like span (320px, random-ish steps) ---- */
    puts("T11: DOOM-like 320px span");

    /* Use 64x64 texture, simulate a DOOM floor span across full screen width */
    /* xfrac=0x000A3000, xstep=0x0000C800 (~0.78), yfrac=0x00053000, ystep=0x00006400 (~0.39) */
    for (int i = 0; i < 320; i++) SP(0xC000 + i) = 0xFF; /* fill with sentinel */

    BLIT_SRC_ADDR   = TEX_DDR_BASE + 256;
    BLIT_SRC_FRAC   = 0x000A3000U;
    BLIT_SRC_STEP   = 0x0000C800U;
    BLIT_SRC_MASK   = 63;
    BLIT_SRC_YFRAC  = 0x00053000U;
    BLIT_SRC_YSTEP  = 0x00006400U;
    BLIT_SRC_SHIFT  = 6;
    BLIT_DST_OFFSET = 0xC000;
    BLIT_DST_STEP   = 1;
    BLIT_COUNT      = 320;
    BLIT_CMAP_OFFSET = SCRATCH_BASE + CMAP_OFFSET;
    BLIT_CMD        = 2;
    wait_blit();

    /* Verify by software computation */
    unsigned int xf = 0x000A3000U;
    unsigned int yf = 0x00053000U;
    int doom_ok = 1;
    int doom_errs = 0;
    for (int i = 0; i < 320; i++) {
        unsigned int ym = (yf >> (16 - 6)) & (63 << 6);
        unsigned int xm = (xf >> 16) & 63;
        unsigned int idx = ym + xm;
        unsigned char exp = (unsigned char)(idx & 0xFF);
        unsigned char got = SP(0xC000 + i);
        if (got != exp) {
            if (doom_errs < 5) {
                puts("  FAIL pixel ");
                print_int(i);
                puts(": got="); print_uint(got);
                puts(" exp="); print_uint(exp);
                puts(" xf=0x"); print_hex(xf);
                puts(" yf=0x"); print_hex(yf);
                print_nl();
            }
            doom_ok = 0; doom_errs++; errors++;
        }
        xf += 0x0000C800U;
        yf += 0x00006400U;
    }
    if (!doom_ok && doom_errs > 5) {
        puts("  ... "); print_int(doom_errs); puts(" errors total"); print_nl();
    }
    if (doom_ok) puts("  OK");

    /* ---- Summary ---- */
    print_nl();
    if (errors == 0)
        puts("ALL TESTS PASSED");
    else {
        puts("ERRORS: "); print_int(errors); print_nl();
    }

    return 0;
}
