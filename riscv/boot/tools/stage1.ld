/*
 * Linker script for Stage 1 bootloader.
 * FLASH_LOADER загружает этот код в верхнюю часть DDR (0x07F00000).
 * Stage 1 грузит BOOT.BIN по адресу 0x00000000 — стандартные программы работают без перелинковки.
 */
ENTRY(_start)

MEMORY {
    ROM (rx)  : ORIGIN = 0x07F00000, LENGTH = 16K
    RAM (rwx) : ORIGIN = 0x07F10000, LENGTH = 64K
}

SECTIONS {
    .text : {
        KEEP(*(.text.crt0))
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > ROM

    _text_end = LOADADDR(.text) + SIZEOF(.text);

    .data : AT(_text_end) {
        _data_lma   = LOADADDR(.data);
        _data_start = .;
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
        _data_end = .;
    } > RAM

    .bss : {
        _bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > RAM

    _stack_top = ORIGIN(RAM) + LENGTH(RAM);

    /DISCARD/ : {
        *(.eh_frame*)
        *(.comment)
    }
}
