#ifndef _SYS_STAT_H
#define _SYS_STAT_H

#include <sys/types.h>

struct stat {
    mode_t st_mode;
    off_t  st_size;
};

int stat(const char *path, struct stat *buf);
int fstat(int fd, struct stat *buf);

#endif
