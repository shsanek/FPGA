#ifndef _UNISTD_H
#define _UNISTD_H

#include <stddef.h>
#include <sys/types.h>

#define R_OK 4
#define W_OK 2
#define X_OK 1
#define F_OK 0

int access(const char *pathname, int mode);
int close(int fd);
ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
off_t lseek(int fd, off_t offset, int whence);
void *sbrk(intptr_t increment);
int usleep(unsigned int usec);

#endif
