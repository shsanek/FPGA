#pragma once

void console_init(void);

void console_putchar(char c);
char console_getchar(void);
int  console_getchar_nowait(void);

void console_puts(const char *p);
int  console_printf(const char *fmt, ...);

/* 2-byte keyboard protocol: returns DOOM key code, -1 if none */
int  console_read_event(int *is_press);
