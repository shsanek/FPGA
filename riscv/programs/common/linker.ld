/*
 * Linker script for bare-metal RV32I.
 *
 * Code (ROM): 0x00000000 – 0x0000FFFF  (64 KB)
 * Data (RAM): 0x00010000 – 0x0001FFFF  (64 KB via MEMORY_CONTROLLER)
 *
 * Von Neumann — всё в DDR, разделение чисто логическое.
 */

ENTRY(_start)

MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
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
        *(.sdata*)
        . = ALIGN(4);
        _data_end = .;
    } > RAM

    /* ---- zero-initialised data ---- */
    .bss : {
        _bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > RAM

    /* ---- stack grows downward from top of RAM ---- */
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
