MEMORY
{
    RAM (xrw) : ORIGIN = 0x0, LENGTH = 0x900000  /* 9 МБ, измените по необходимости */
}
ENTRY(_start)
SECTIONS {
    /* Установка вершины стека в конце области RAM */
    __stacktop = ORIGIN(RAM) + LENGTH(RAM);
    
    .text :
    {
        . = ALIGN(4);
        *(.text.start)
        *(.text)
        *(.text*)
        *(.rodata)
        *(.rodata*)
        *(.srodata)
        *(.srodata*)
        . = ALIGN(4);
        _etext = .;
        _sidata = _etext;  /* Данные уже находятся в RAM */
    } >RAM
    
    .data : AT ( _sidata )
    {
        . = ALIGN(4);
        _sdata = .;
        _ram_start = .;
        . = ALIGN(4);
        *(.data)
        *(.data*)
        *(.sdata)
        *(.sdata*)
        . = ALIGN(4);
        _edata = .;
    } >RAM
    
    .bss :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss)
        *(.bss*)
        *(.sbss)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } >RAM
    
    .heap :
    {
        . = ALIGN(4);
        _heap_start = .;
    } >RAM
}
