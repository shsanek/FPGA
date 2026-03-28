/*
 * libc_mini.c — minimal libc for bare-metal DOOM (no newlib)
 */

#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "mini-printf.h"
#include "console.h"

/* ---- errno ---- */
int errno;

/* ---- FILE stubs ---- */
struct _FILE { int fd; };
typedef struct _FILE FILE;

static FILE _stdin_f  = { 0 };
static FILE _stdout_f = { 1 };
static FILE _stderr_f = { 2 };

FILE *stdin  = &_stdin_f;
FILE *stdout = &_stdout_f;
FILE *stderr = &_stderr_f;

/* ---- memory: memcpy, memset, memmove, memcmp ---- */

void *memcpy(void *dest, const void *src, size_t n)
{
    unsigned char *d = dest;
    const unsigned char *s = src;
    while (n--) *d++ = *s++;
    return dest;
}

void *memmove(void *dest, const void *src, size_t n)
{
    unsigned char *d = dest;
    const unsigned char *s = src;
    if (d < s) {
        while (n--) *d++ = *s++;
    } else {
        d += n; s += n;
        while (n--) *--d = *--s;
    }
    return dest;
}

void *memset(void *s, int c, size_t n)
{
    unsigned char *p = s;
    while (n--) *p++ = (unsigned char)c;
    return s;
}

int memcmp(const void *s1, const void *s2, size_t n)
{
    const unsigned char *a = s1, *b = s2;
    while (n--) {
        if (*a != *b) return *a - *b;
        a++; b++;
    }
    return 0;
}

/* ---- string ---- */

size_t strlen(const char *s)
{
    size_t len = 0;
    while (s[len]) len++;
    return len;
}

char *strcpy(char *dest, const char *src)
{
    char *d = dest;
    while ((*d++ = *src++));
    return dest;
}

char *strncpy(char *dest, const char *src, size_t n)
{
    size_t i;
    for (i = 0; i < n && src[i]; i++)
        dest[i] = src[i];
    for (; i < n; i++)
        dest[i] = '\0';
    return dest;
}

int strcmp(const char *s1, const char *s2)
{
    while (*s1 && *s1 == *s2) { s1++; s2++; }
    return *(unsigned char *)s1 - *(unsigned char *)s2;
}

int strncmp(const char *s1, const char *s2, size_t n)
{
    while (n && *s1 && *s1 == *s2) { s1++; s2++; n--; }
    return n ? *(unsigned char *)s1 - *(unsigned char *)s2 : 0;
}

static inline int _tolower(int c)
{
    return (c >= 'A' && c <= 'Z') ? c + 32 : c;
}

int strcasecmp(const char *s1, const char *s2)
{
    while (*s1 && _tolower(*s1) == _tolower(*s2)) { s1++; s2++; }
    return _tolower(*(unsigned char *)s1) - _tolower(*(unsigned char *)s2);
}

int strncasecmp(const char *s1, const char *s2, size_t n)
{
    while (n && *s1 && _tolower(*s1) == _tolower(*s2)) { s1++; s2++; n--; }
    return n ? _tolower(*(unsigned char *)s1) - _tolower(*(unsigned char *)s2) : 0;
}

char *strcat(char *dest, const char *src)
{
    char *d = dest;
    while (*d) d++;
    while ((*d++ = *src++));
    return dest;
}

char *strchr(const char *s, int c)
{
    while (*s) {
        if (*s == (char)c) return (char *)s;
        s++;
    }
    return (c == 0) ? (char *)s : NULL;
}

char *strrchr(const char *s, int c)
{
    const char *last = NULL;
    while (*s) {
        if (*s == (char)c) last = s;
        s++;
    }
    if (c == 0) return (char *)s;
    return (char *)last;
}

char *strstr(const char *haystack, const char *needle)
{
    size_t nlen = strlen(needle);
    if (!nlen) return (char *)haystack;
    while (*haystack) {
        if (!strncmp(haystack, needle, nlen)) return (char *)haystack;
        haystack++;
    }
    return NULL;
}

/* ---- malloc/free via _sbrk from libc_backend.c ---- */

extern void *_sbrk(intptr_t increment);

/* Simple bump allocator — free is a no-op, good enough for DOOM */
void *malloc(size_t size)
{
    if (size == 0) return NULL;
    size = (size + 3) & ~3; /* align */
    return _sbrk(size);
}

void *calloc(size_t nmemb, size_t size)
{
    size_t total = nmemb * size;
    void *p = malloc(total);
    if (p) memset(p, 0, total);
    return p;
}

void *realloc(void *ptr, size_t size)
{
    /* DOOM's z_zone handles its own memory; realloc is rarely called */
    void *p = malloc(size);
    if (p && ptr) memcpy(p, ptr, size); /* may over-read, but OK for DOOM */
    return p;
}

void free(void *ptr)
{
    (void)ptr; /* bump allocator — no free */
}

/* ---- abs ---- */

int abs(int j) { return j < 0 ? -j : j; }

/* ---- printf family (via mini_vsnprintf) ---- */

static char _printf_buf[256];

/* vsnprintf/snprintf are handled by mini-printf.h macros */

int sprintf(char *str, const char *fmt, ...)
{
    va_list va;
    va_start(va, fmt);
    int ret = mini_vsnprintf(str, 1024, fmt, va);
    va_end(va);
    return ret;
}

int printf(const char *fmt, ...)
{
    va_list va;
    va_start(va, fmt);
    int ret = mini_vsnprintf(_printf_buf, sizeof(_printf_buf), fmt, va);
    va_end(va);
    console_puts(_printf_buf);
    return ret;
}

int fprintf(FILE *stream, const char *fmt, ...)
{
    (void)stream;
    va_list va;
    va_start(va, fmt);
    int ret = mini_vsnprintf(_printf_buf, sizeof(_printf_buf), fmt, va);
    va_end(va);
    console_puts(_printf_buf);
    return ret;
}

int vfprintf(FILE *stream, const char *fmt, va_list ap)
{
    (void)stream;
    int ret = mini_vsnprintf(_printf_buf, sizeof(_printf_buf), fmt, ap);
    console_puts(_printf_buf);
    return ret;
}

int puts(const char *s)
{
    console_puts(s);
    console_putchar('\n');
    return 0;
}

int putchar(int c)
{
    console_putchar((char)c);
    return c;
}

/* ---- abort / exit ---- */

void abort(void)
{
    console_puts("\n!!! ABORT !!!\n");
    while (1) {}
}

void exit(int status)
{
    printf("\n!!! EXIT(%d) !!!\n", status);
    while (1) {}
}

/* ---- sscanf stub ---- */

int sscanf(const char *str, const char *fmt, ...)
{
    printf("[STUB] sscanf(\"%s\", \"%s\")\n", str, fmt);
    abort();
    return 0;
}

int fscanf(FILE *stream, const char *fmt, ...)
{
    (void)stream;
    printf("[STUB] fscanf(fmt=\"%s\")\n", fmt);
    abort();
    return 0;
}

/* ---- FILE operations (via _open/_read/_write/_close/_lseek from libc_backend.c) ---- */

extern int _open(const char *pathname, int flags);
extern ssize_t _read(int fd, void *buf, size_t nbyte);
extern ssize_t _write(int fd, const void *buf, size_t nbyte);
extern int _close(int fd);
extern off_t _lseek(int fd, off_t offset, int whence);
extern int _stat(const char *filename, struct stat *statbuf);
extern int _fstat(int fd, struct stat *statbuf);

/* Simple fd-based FILE pool */
#define MAX_FILES 16
static FILE _files[MAX_FILES];
static int _files_used[MAX_FILES];

FILE *fopen(const char *path, const char *mode)
{
    (void)mode;
    int fd = _open(path, 0);
    if (fd < 0) return NULL;
    for (int i = 0; i < MAX_FILES; i++) {
        if (!_files_used[i]) {
            _files_used[i] = 1;
            _files[i].fd = fd;
            return &_files[i];
        }
    }
    _close(fd);
    return NULL;
}

int fclose(FILE *stream)
{
    if (!stream) return -1;
    int ret = _close(stream->fd);
    for (int i = 0; i < MAX_FILES; i++) {
        if (&_files[i] == stream) { _files_used[i] = 0; break; }
    }
    return ret;
}

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    if (!stream) return 0;
    ssize_t r = _read(stream->fd, ptr, size * nmemb);
    return (r > 0) ? (size_t)r / size : 0;
}

size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream)
{
    if (!stream) return 0;
    ssize_t r = _write(stream->fd, ptr, size * nmemb);
    return (r > 0) ? (size_t)r / size : 0;
}

int fseek(FILE *stream, long offset, int whence)
{
    if (!stream) return -1;
    return (_lseek(stream->fd, offset, whence) < 0) ? -1 : 0;
}

long ftell(FILE *stream)
{
    if (!stream) return -1;
    return _lseek(stream->fd, 0, 1); /* SEEK_CUR */
}

void rewind(FILE *stream) { fseek(stream, 0, 0); }
int feof(FILE *stream) { (void)stream; return 0; }
int ferror(FILE *stream) { (void)stream; return 0; }
int fflush(FILE *stream) { (void)stream; return 0; }
void setbuf(FILE *stream, char *buf) { (void)stream; (void)buf; }

/* non-underscore wrappers for syscalls */
int open(const char *pathname, int flags, ...) { return _open(pathname, flags); }
int close(int fd) { return _close(fd); }
ssize_t read(int fd, void *buf, size_t count) { return _read(fd, buf, count); }
ssize_t write(int fd, const void *buf, size_t count) { return _write(fd, buf, count); }
off_t lseek(int fd, off_t offset, int whence) { return _lseek(fd, offset, whence); }
int stat(const char *path, struct stat *buf) { return _stat(path, buf); }
int fstat(int fd, struct stat *buf) { return _fstat(fd, buf); }
