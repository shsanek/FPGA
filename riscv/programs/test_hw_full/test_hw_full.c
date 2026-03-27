/*
 * test_hw_full.c — полный аппаратный тест CPU для BOOT.BIN.
 *
 * Подробные логи каждого теста. ALU, MUL/DIV, Memory, Branch, Jump.
 */
#include "../common/runtime.h"

static int errors = 0;
static int total = 0;

static void ok(const char *name) {
    total++;
}

static void chk(const char *name, unsigned got, unsigned expected) {
    total++;
    if (got != expected) {
        puts("FAIL: ");
        puts(name);
        puts("  got="); print_hex(got);
        puts("  exp="); print_hex(expected);
        putchar('\n');
        errors++;
    }
}

__attribute__((noinline)) static int I(int x) { return x; }
__attribute__((noinline)) static unsigned U(unsigned x) { return x; }

/* ---- inline asm helpers for M-extension ---- */
static int hw_mul(int a, int b) { int r; __asm__ volatile("mul %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }
static int hw_mulh(int a, int b) { int r; __asm__ volatile("mulh %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }
static unsigned hw_mulhu(unsigned a, unsigned b) { unsigned r; __asm__ volatile("mulhu %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }
static int hw_mulhsu(int a, unsigned b) { int r; __asm__ volatile("mulhsu %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }
static int hw_div(int a, int b) { int r; __asm__ volatile("div %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }
static unsigned hw_divu(unsigned a, unsigned b) { unsigned r; __asm__ volatile("divu %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }
static int hw_rem(int a, int b) { int r; __asm__ volatile("rem %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }
static unsigned hw_remu(unsigned a, unsigned b) { unsigned r; __asm__ volatile("remu %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }

/* ---- ALU R-type ---- */
static void test_alu(void) {
    puts("--- ALU R-type ---");

    puts(" ADD:");
    chk("10+3", I(10)+I(3), 13);
    chk("-1+1", I(-1)+I(1), 0);
    chk("0x7FFFFFFF+1", (unsigned)I(0x7FFFFFFF)+1u, 0x80000000u);
    chk("0+0", I(0)+I(0), 0);
    chk("MAX+MAX", (unsigned)I(0x7FFFFFFF)+(unsigned)I(0x7FFFFFFF), 0xFFFFFFFEu);

    puts(" SUB:");
    chk("10-3", I(10)-I(3), 7);
    chk("0-1", I(0)-I(1), (unsigned)-1);
    chk("3-10", I(3)-I(10), (unsigned)-7);
    chk("MIN-1", (unsigned)I(0x80000000)-1u, 0x7FFFFFFFu);

    puts(" AND:");
    chk("0xFF00&0x0FF0", I(0xFF00)&I(0x0FF0), 0x0F00);
    chk("0&-1", I(0)&I(-1), 0);
    chk("-1&-1", I(-1)&I(-1), (unsigned)-1);

    puts(" OR:");
    chk("0xFF00|0x00FF", I(0xFF00)|I(0x00FF), 0xFFFF);
    chk("0|0", I(0)|I(0), 0);
    chk("0xA|0x5", I(0xA)|I(0x5), 0xF);

    puts(" XOR:");
    chk("0xFF^0xFF", I(0xFF)^I(0xFF), 0);
    chk("0xA^0x5", I(0xA)^I(0x5), 0xF);
    chk("-1^0", I(-1)^I(0), (unsigned)-1);

    puts(" SLL:");
    chk("1<<0", I(1)<<I(0), 1);
    chk("1<<31", I(1)<<I(31), 0x80000000u);
    chk("0xFF<<8", I(0xFF)<<I(8), 0xFF00);
    chk("1<<16", I(1)<<I(16), 0x10000);

    puts(" SRL:");
    chk("0x80000000>>31", U(0x80000000u)>>I(31), 1);
    chk("0xFFFFFFFF>>16", U(0xFFFFFFFF)>>I(16), 0xFFFF);
    chk("0x100>>4", U(0x100)>>I(4), 0x10);

    puts(" SRA:");
    chk("-1024>>2", I(-1024)>>I(2), (unsigned)-256);
    chk("-1>>10", I(-1)>>I(10), (unsigned)-1);
    chk("0x7FFFFFFF>>1", I(0x7FFFFFFF)>>I(1), 0x3FFFFFFF);

    puts(" SLT:");
    chk("1<2", (unsigned)(I(1)<I(2)), 1);
    chk("2<1", (unsigned)(I(2)<I(1)), 0);
    chk("-1<0", (unsigned)(I(-1)<I(0)), 1);
    chk("0<-1", (unsigned)(I(0)<I(-1)), 0);

    puts(" SLTU:");
    chk("1<u2", (unsigned)(U(1)<U(2)), 1);
    chk("0xFFFFFFFF<u0", (unsigned)(U(0xFFFFFFFF)<U(0)), 0);
    chk("0<u0xFFFFFFFF", (unsigned)(U(0)<U(0xFFFFFFFF)), 1);
}

/* ---- ALU I-type ---- */
static void test_alu_imm(void) {
    puts("--- ALU I-type ---");

    puts(" ADDI:");
    chk("x+0", I(42)+0, 42);
    chk("x+(-1)", I(10)+(-1), 9);
    chk("0+2047", I(0)+2047, 2047);

    puts(" ANDI:");
    chk("0xFF&0x0F", I(0xFF)&0x0F, 0x0F);

    puts(" ORI:");
    chk("0xF0|0x0F", I(0xF0)|0x0F, 0xFF);

    puts(" XORI:");
    chk("0xFF^0x0F", I(0xFF)^0x0F, 0xF0);

    puts(" SLLI:");
    chk("1<<5", I(1)<<5, 32);

    puts(" SRLI:");
    chk("256>>4", U(256)>>4, 16);

    puts(" SRAI:");
    chk("-128>>2", I(-128)>>2, (unsigned)-32);

    puts(" SLTI:");
    chk("0<1", (unsigned)(I(0)<1), 1);
    chk("1<0", (unsigned)(I(1)<0), 0);
    chk("-1<0", (unsigned)(I(-1)<0), 1);
}

/* ---- MUL/DIV (M-extension) ---- */
static void test_muldiv(void) {
    puts("--- MUL/DIV ---");

    puts(" MUL:");
    chk("3*7", hw_mul(3,7), 21);
    chk("0*X", hw_mul(0,999), 0);
    chk("-1*-1", hw_mul(-1,-1), 1);
    chk("100*100", hw_mul(100,100), 10000);
    chk("-5*6", hw_mul(-5,6), (unsigned)-30);
    chk("0xFFFF*0xFFFF", hw_mul(0xFFFF,0xFFFF), 0xFFFE0001u);
    chk("0x10000*0x10000", hw_mul(0x10000,0x10000), 0);
    chk("12345*6789", hw_mul(12345,6789), 83810205u);

    puts(" MULH:");
    chk("1*1h", hw_mulh(1,1), 0);
    chk("0x10000*0x10000h", hw_mulh(0x10000,0x10000), 1);
    chk("-1*1h", hw_mulh(-1,1), (unsigned)-1);
    chk("-1*-1h", hw_mulh(-1,-1), 0);
    chk("0x40000000*4h", hw_mulh(0x40000000,4), 1);

    puts(" MULHU:");
    chk("MAX*2hu", hw_mulhu(0xFFFFFFFFu,2), 1);
    chk("MAX*MAXhu", hw_mulhu(0xFFFFFFFFu,0xFFFFFFFFu), 0xFFFFFFFEu);

    puts(" MULHSU:");
    chk("-1*1hsu", hw_mulhsu(-1,1), (unsigned)-1);
    chk("1*MAXhsu", hw_mulhsu(1,0xFFFFFFFFu), 0);

    puts(" DIV:");
    chk("21/7", hw_div(21,7), 3);
    chk("7/2", hw_div(7,2), 3);
    chk("-7/2", hw_div(-7,2), (unsigned)-3);
    chk("7/-2", hw_div(7,-2), (unsigned)-3);
    chk("-7/-2", hw_div(-7,-2), 3);
    chk("0/5", hw_div(0,5), 0);
    chk("1/0", hw_div(1,0), (unsigned)-1);
    chk("MIN/-1", hw_div((int)0x80000000,-1), 0x80000000u);
    chk("1M/1K", hw_div(1000000,1000), 1000);

    puts(" DIVU:");
    chk("21/7u", hw_divu(21,7), 3);
    chk("MAX/1u", hw_divu(0xFFFFFFFFu,1), 0xFFFFFFFFu);
    chk("MAX/2u", hw_divu(0xFFFFFFFFu,2), 0x7FFFFFFFu);
    chk("100/3u", hw_divu(100,3), 33);
    chk("1/0u", hw_divu(1,0), 0xFFFFFFFFu);

    puts(" REM:");
    chk("7%3", hw_rem(7,3), 1);
    chk("-7%3", hw_rem(-7,3), (unsigned)-1);
    chk("7%-3", hw_rem(7,-3), 1);
    chk("0%7", hw_rem(0,7), 0);
    chk("5%0", hw_rem(5,0), 5);
    chk("MIN%-1", hw_rem((int)0x80000000,-1), 0);
    chk("123456%1000", hw_rem(123456,1000), 456);

    puts(" REMU:");
    chk("7%3u", hw_remu(7,3), 1);
    chk("MAX%2u", hw_remu(0xFFFFFFFFu,2), 1);
    chk("MAX%10u", hw_remu(0xFFFFFFFFu,10), 5);
    chk("5%0u", hw_remu(5,0), 5);
}

/* ---- Memory load/store ---- */
static volatile unsigned char membuf[64];

static void test_memory(void) {
    puts("--- MEMORY ---");

    /* Clear */
    for (int i = 0; i < 64; i++) membuf[i] = 0;

    puts(" SW/LW:");
    *(volatile unsigned int *)(membuf+0) = 0xDEADBEEF;
    chk("sw/lw", *(volatile unsigned int *)(membuf+0), 0xDEADBEEFu);
    *(volatile unsigned int *)(membuf+4) = 0x12345678;
    chk("sw/lw[4]", *(volatile unsigned int *)(membuf+4), 0x12345678u);
    /* Verify first word untouched */
    chk("sw/lw[0] intact", *(volatile unsigned int *)(membuf+0), 0xDEADBEEFu);

    puts(" SH/LH/LHU:");
    *(volatile unsigned short *)(membuf+8) = 0xABCD;
    chk("sh/lhu", *(volatile unsigned short *)(membuf+8), 0xABCD);
    *(volatile unsigned short *)(membuf+10) = 0x1234;
    chk("sh/lhu[10]", *(volatile unsigned short *)(membuf+10), 0x1234);
    /* Signed halfword */
    *(volatile unsigned short *)(membuf+12) = 0xFF80;
    chk("lh sign", (unsigned)(*(volatile short *)(membuf+12)), (unsigned)(short)0xFF80);

    puts(" SB/LB/LBU:");
    *(volatile unsigned char *)(membuf+16) = 0xAB;
    chk("sb/lbu", *(volatile unsigned char *)(membuf+16), 0xAB);
    *(volatile unsigned char *)(membuf+17) = 0xCD;
    chk("sb/lbu[17]", *(volatile unsigned char *)(membuf+17), 0xCD);
    /* Signed byte */
    *(volatile unsigned char *)(membuf+18) = 0x80;
    chk("lb sign", (unsigned)(*(volatile signed char *)(membuf+18)), (unsigned)(signed char)0x80);

    puts(" Byte assembly:");
    *(volatile unsigned char *)(membuf+20) = 0x78;
    *(volatile unsigned char *)(membuf+21) = 0x56;
    *(volatile unsigned char *)(membuf+22) = 0x34;
    *(volatile unsigned char *)(membuf+23) = 0x12;
    chk("4xSB->LW", *(volatile unsigned int *)(membuf+20), 0x12345678u);

    puts(" Word disassembly:");
    *(volatile unsigned int *)(membuf+24) = 0xAABBCCDD;
    chk("LW->LBU[0]", *(volatile unsigned char *)(membuf+24), 0xDD);
    chk("LW->LBU[1]", *(volatile unsigned char *)(membuf+25), 0xCC);
    chk("LW->LBU[2]", *(volatile unsigned char *)(membuf+26), 0xBB);
    chk("LW->LBU[3]", *(volatile unsigned char *)(membuf+27), 0xAA);

    puts(" SB overwrite:");
    *(volatile unsigned int *)(membuf+28) = 0x11223344;
    *(volatile unsigned char *)(membuf+29) = 0xFF;
    chk("SB overwrite byte1", *(volatile unsigned int *)(membuf+28), 0x1122FF44u);
}

/* ---- Branches ---- */
static void test_branch(void) {
    puts("--- BRANCH ---");

    puts(" BEQ:");
    chk("5==5", (unsigned)(I(5)==I(5)), 1);
    chk("5==6", (unsigned)(I(5)==I(6)), 0);

    puts(" BNE:");
    chk("5!=6", (unsigned)(I(5)!=I(6)), 1);
    chk("5!=5", (unsigned)(I(5)!=I(5)), 0);

    puts(" BLT:");
    chk("-1<0", (unsigned)(I(-1)<I(0)), 1);
    chk("0<-1", (unsigned)(I(0)<I(-1)), 0);
    chk("MIN<MAX", (unsigned)(I(0x80000000)<I(0x7FFFFFFF)), 1);

    puts(" BGE:");
    chk("0>=-1", (unsigned)(I(0)>=I(-1)), 1);
    chk("5>=5", (unsigned)(I(5)>=I(5)), 1);
    chk("-1>=0", (unsigned)(I(-1)>=I(0)), 0);

    puts(" BLTU:");
    chk("0<u1", (unsigned)(U(0)<U(1)), 1);
    chk("0xFFFFFFFF<u0", (unsigned)(U(0xFFFFFFFF)<U(0)), 0);

    puts(" BGEU:");
    chk("1>=u0", (unsigned)(U(1)>=U(0)), 1);
    chk("0>=u0", (unsigned)(U(0)>=U(0)), 1);

    puts(" Loop:");
    int sum = 0;
    for (int i = 1; i <= 100; i++) sum += i;
    chk("sum1..100", (unsigned)sum, 5050);
}

/* ---- Jumps ---- */
__attribute__((noinline)) static int square(int x) { return x * x; }
__attribute__((noinline)) static int fact(int n) { return n <= 1 ? 1 : n * fact(n-1); }

static void test_jump(void) {
    puts("--- JUMP ---");

    puts(" JAL (function call):");
    chk("square(7)", (unsigned)square(7), 49);
    chk("square(0)", (unsigned)square(0), 0);
    chk("square(-3)", (unsigned)square(-3), 9);

    puts(" JAL (recursion):");
    chk("fact(1)", (unsigned)fact(1), 1);
    chk("fact(5)", (unsigned)fact(5), 120);
    chk("fact(10)", (unsigned)fact(10), 3628800);

    puts(" JALR (function pointer):");
    int (*fn)(int) = square;
    chk("fnptr square(6)", (unsigned)fn(6), 36);
    fn = fact;
    chk("fnptr fact(7)", (unsigned)fn(7), 5040);
}

/* ---- LUI/AUIPC ---- */
static unsigned g_big;

static void test_upper(void) {
    puts("--- LUI/AUIPC ---");

    g_big = 0x12345000;
    chk("LUI 0x12345000", g_big, 0x12345000u);

    g_big = 0x12345000 + 0x678;
    chk("LUI+ADDI", g_big, 0x12345678u);

    unsigned arr[4];
    arr[0] = 0xAAAAAAAA;
    arr[3] = 0xBBBBBBBB;
    chk("arr[0]", arr[0], 0xAAAAAAAAu);
    chk("arr[3]", arr[3], 0xBBBBBBBBu);
}

/* ---- Fibonacci (stress test) ---- */
__attribute__((noinline)) static int fib(int n) {
    if (n <= 1) return n;
    return fib(n-1) + fib(n-2);
}

static void test_fib(void) {
    puts("--- FIB ---");
    chk("fib(0)", (unsigned)fib(0), 0);
    chk("fib(1)", (unsigned)fib(1), 1);
    chk("fib(5)", (unsigned)fib(5), 5);
    chk("fib(10)", (unsigned)fib(10), 55);
    chk("fib(15)", (unsigned)fib(15), 610);
    chk("fib(20)", (unsigned)fib(20), 6765);
}

/* ---- Main ---- */
int main(void) {
    puts("=== FULL HW TEST ===\n");

    test_alu();
    puts(" ALU OK\n");

    test_alu_imm();
    puts(" ALU-I OK\n");

    test_muldiv();
    puts(" MUL/DIV OK\n");

    test_memory();
    puts(" MEM OK\n");

    test_branch();
    puts(" BRANCH OK\n");

    test_jump();
    puts(" JUMP OK\n");

    test_upper();
    puts(" UPPER OK\n");

    test_fib();
    puts(" FIB OK\n");

    putchar('\n');
    puts("Total: "); print_int(total); puts(" tests\n");
    if (errors == 0) {
        puts("=== ALL PASSED ===");
    } else {
        puts("FAILURES: "); print_int(errors); putchar('\n');
    }
    return errors;
}
