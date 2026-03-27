#ifndef _STDLIB_H
#define _STDLIB_H

#include <stddef.h>

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1

void *malloc(size_t size);
void *calloc(size_t nmemb, size_t size);
void *realloc(void *ptr, size_t size);
void free(void *ptr);
void abort(void);
void exit(int status);
int atoi(const char *nptr);
long atol(const char *nptr);
int abs(int j);
long labs(long j);
void qsort(void *base, size_t nmemb, size_t size, int (*compar)(const void *, const void *));

#endif
