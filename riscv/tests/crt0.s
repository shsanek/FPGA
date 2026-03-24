/* Minimal startup for bare-metal RV32I */

    .section .text.crt0,"ax"
    .globl _start
_start:
    .option norelax

    /* Set stack pointer */
    la      sp, _stack_top

    /* Copy .data from ROM (LMA) to RAM (VMA) */
    la      a0, _data_lma
    la      a1, _data_start
    la      a2, _data_end
.Lcopy_data:
    bge     a1, a2, .Lzero_bss
    lw      t0, 0(a0)
    sw      t0, 0(a1)
    addi    a0, a0, 4
    addi    a1, a1, 4
    j       .Lcopy_data

    /* Zero .bss */
.Lzero_bss:
    la      a0, _bss_start
    la      a1, _bss_end
.Lbss_loop:
    bge     a0, a1, .Lcall_main
    sw      zero, 0(a0)
    addi    a0, a0, 4
    j       .Lbss_loop

.Lcall_main:
    call    main

    /* Fall-through: EBREAK halts CPU (signals test end) */
    ebreak
    j       .   /* safety loop */
