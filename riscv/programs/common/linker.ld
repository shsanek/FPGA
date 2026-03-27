/*
 * Linker script for bare-metal RV32I.
 *
 * Instruction memory (ROM): 0x00000000 – 0x00003FFF  (16 KB, 4096 words)
 * Data memory     (RAM):    0x00010000 – 0x0001FFFF  (64 KB via MEMORY_CONTROLLER)
 *
 * Note: instruction fetch and data access use separate CPU ports (Harvard-like),
 * so ROM and RAM address spaces are independent even though bit27=0 for both.
 */

ENTRY(_start)

MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
    RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 64K
}

SECTIONS {
    /* ---- code + read-only data go to ROM ---- */
    .text : {
        KEEP(*(.text.crt0))
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > ROM

    _text_end = LOADADDR(.text) + SIZEOF(.text);

    /* ---- initialised data: loaded from ROM, runs in RAM ---- */
    .data : AT(_text_end) {
        _data_lma   = LOADADDR(.data);
        _data_start = .;
        *(.data*)
        . = ALIGN(4);
        _data_end = .;
    } > RAM

    /* ---- zero-initialised data ---- */
    .bss : {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > RAM

    /* ---- stack grows downward from top of RAM ---- */
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
