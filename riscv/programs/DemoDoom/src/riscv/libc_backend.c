/*
 * libc_backend.c — File I/O backend for DOOM on Arty A7.
 * WAD files are read from SD card via FAT32.
 */

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdint.h>

#include "config.h"
#include "console.h"

/* SD card + FAT32 API */
extern int  sd_init(void);
extern int  fat32_init(void);
extern int  fat32_open(const char *name83);
extern int  fat32_read(int handle, unsigned char *buf, int count);
extern int  fat32_size(int handle);
extern int  fat32_seek(int handle, unsigned int position);
extern void fat32_close(int handle);


/* HEAP handling (bump allocator) */

extern uint8_t _heap_start;
static void *heap_end = &_heap_start;

void *
_sbrk(intptr_t increment)
{
    increment = (increment + 3) & ~3;
    heap_end = (void *)((((uint32_t)heap_end) + 3) & ~3);
    void *rv = heap_end;
    heap_end += increment;
    return rv;
}


/* File handling — WAD loaded entirely into RAM */

#define NUM_FDS 16

static struct {
    enum {
        FD_NONE  = 0,
        FD_STDIO = 1,
        FD_RAM   = 2,
    } type;
    uint8_t *data;         /* pointer to file data in RAM */
    size_t   file_size;
    size_t   offset;
} fds[NUM_FDS] = {
    [0] = { .type = FD_STDIO },
    [1] = { .type = FD_STDIO },
    [2] = { .type = FD_STDIO },
};

static int name_to_83(const char *path, char *name83);

/* WAD file preloaded into RAM by doom_load_wad() */
static uint8_t *wad_ram = NULL;
static size_t   wad_size = 0;

/* Call from i_main.c after FAT32 init, before D_DoomMain */
void doom_load_wad(const char *filename)
{
    char name83[11];
    name_to_83(filename, name83);

    int h = fat32_open(name83);
    if (h < 0) {
        console_printf("doom_load_wad: not found: %s\n", filename);
        return;
    }

    wad_size = (size_t)fat32_size(h);
    console_printf("Loading %s (%d bytes) into RAM...\n", filename, (int)wad_size);

    /* Allocate from heap */
    wad_ram = (uint8_t *)_sbrk((intptr_t)wad_size);

    /* Read entire file */
    int total = 0;
    int next_report = 1 << 21; /* 2MB */
    int chunk;
    while (total < (int)wad_size) {
        chunk = (int)wad_size - total;
        if (chunk > 512) chunk = 512;
        int rd = fat32_read(h, wad_ram + total, chunk);
        if (rd <= 0) {
            console_printf("\nREAD FAIL: rc=%d at %d/%d\n", rd, total, (int)wad_size);
            break;
        }
        total += rd;
        if (total >= next_report) {
            console_printf("  %dMB\n", next_report >> 20);
            next_report += 1 << 21;
        }
    }
    console_printf("WAD: %d/%d bytes\n", total, (int)wad_size);

    fat32_close(h);
}

/* Convert "doomu.wad" to FAT32 8.3 format "DOOMU   WAD" */
static int
name_to_83(const char *path, char *name83)
{
    /* Find just the filename part (skip any path) */
    const char *p = path;
    const char *last_slash = path;
    while (*p) {
        if (*p == '/') last_slash = p + 1;
        p++;
    }
    path = last_slash;

    /* Find dot */
    const char *dot = NULL;
    for (p = path; *p; p++) {
        if (*p == '.') dot = p;
    }

    /* Fill name part (8 chars, uppercase, space-padded) */
    int i = 0;
    for (p = path; *p && p != dot && i < 8; p++, i++) {
        char c = *p;
        if (c >= 'a' && c <= 'z') c -= 32;
        name83[i] = c;
    }
    while (i < 8) name83[i++] = ' ';

    /* Fill extension (3 chars) */
    if (dot) {
        dot++;
        for (int j = 0; j < 3 && dot[j]; j++) {
            char c = dot[j];
            if (c >= 'a' && c <= 'z') c -= 32;
            name83[i++] = c;
        }
    }
    while (i < 11) name83[i++] = ' ';

    return 0;
}

int
_open(const char *pathname, int flags)
{
    /* Only the WAD file is available */
    if (!wad_ram || !strstr(pathname, ".wad")) {
        console_printf("_open: not found: %s\n", pathname);
        errno = ENOENT;
        return -1;
    }

    /* Find free FD */
    int fd;
    for (fd = 3; fd < NUM_FDS && fds[fd].type != FD_NONE; fd++) ;
    if (fd == NUM_FDS) {
        errno = ENOMEM;
        return -1;
    }

    fds[fd].type = FD_RAM;
    fds[fd].data = wad_ram;
    fds[fd].file_size = wad_size;
    fds[fd].offset = 0;

    console_printf("Opened: %s as fd=%d (size=%d, RAM)\n",
                   pathname, fd, (int)fds[fd].file_size);
    return fd;
}

ssize_t
_read(int fd, void *buf, size_t nbyte)
{
    if (fd < 0 || fd >= NUM_FDS || fds[fd].type != FD_RAM) {
        errno = EINVAL;
        return -1;
    }

    if (fds[fd].offset + nbyte > fds[fd].file_size)
        nbyte = fds[fd].file_size - fds[fd].offset;

    memcpy(buf, fds[fd].data + fds[fd].offset, nbyte);
    fds[fd].offset += nbyte;

    return (ssize_t)nbyte;
}

ssize_t
_write(int fd, const void *buf, size_t nbyte)
{
    const unsigned char *c = buf;
    for (size_t i = 0; i < nbyte; i++)
        console_putchar(*c++);
    return nbyte;
}

int
_close(int fd)
{
    if (fd < 0 || fd >= NUM_FDS) {
        errno = EINVAL;
        return -1;
    }

    fds[fd].type = FD_NONE;
    return 0;
}

off_t
_lseek(int fd, off_t offset, int whence)
{
    if (fd < 0 || fd >= NUM_FDS || fds[fd].type != FD_RAM) {
        errno = EINVAL;
        return -1;
    }

    size_t new_offset;
    switch (whence) {
    case SEEK_SET:
        new_offset = offset;
        break;
    case SEEK_CUR:
        new_offset = fds[fd].offset + offset;
        break;
    case SEEK_END:
        new_offset = fds[fd].file_size - offset;
        break;
    default:
        errno = EINVAL;
        return -1;
    }

    if (new_offset > fds[fd].file_size) {
        errno = EINVAL;
        return -1;
    }

    fds[fd].offset = new_offset;
    return new_offset;
}

int
_stat(const char *filename, struct stat *statbuf)
{
    console_printf("[STUB] _stat(filename=\"%s\")\n", filename);
    return -1;
}

int
_fstat(int fd, struct stat *statbuf)
{
    console_printf("[STUB] _fstat(fd=%d)\n", fd);
    return -1;
}

int
_isatty(int fd)
{
    errno = 0;
    return (fd == 1) || (fd == 2);
}

int
access(const char *pathname, int mode)
{
    /* If WAD is loaded, any WAD-like filename is "accessible" */
    (void)mode;
    if (wad_ram)
        return 0;
    errno = ENOENT;
    return -1;
}
