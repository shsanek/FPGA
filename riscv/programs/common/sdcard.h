#ifndef SDCARD_H
#define SDCARD_H

/* SD card + FAT32 API.
 * SD через SD_IO_DEVICE (0x10020000), SPI mode.
 * FAT32: open/read/close + write (TODO).
 */

/* ---- Low-level SD ---- */
int  sd_init(void);                     /* CMD0..CMD58, returns 0 on success */
int  sd_read_block(unsigned int block, unsigned char *buf);   /* 512 bytes */
int  sd_write_block(unsigned int block, const unsigned char *buf);

/* ---- FAT32 filesystem ---- */

#define FAT32_MAX_OPEN  4               /* макс. одновременно открытых файлов */
#define FAT32_NAME_LEN  11              /* 8.3 format без точки */

typedef struct {
    int            active;              /* slot занят */
    unsigned int   start_cluster;       /* первый кластер файла */
    unsigned int   file_size;           /* размер в байтах */
    unsigned int   position;            /* текущая позиция чтения */
    unsigned int   cur_cluster;         /* текущий кластер */
    unsigned int   cluster_offset;      /* смещение внутри кластера (байты) */
} fat32_file_t;

int  fat32_init(void);                  /* MBR → BPB → geometry */
int  fat32_open(const char *name83);    /* найти файл, вернуть handle (0..3) или <0 */
int  fat32_read(int handle, unsigned char *buf, int count);  /* прочитать count байт */
int  fat32_size(int handle);            /* размер файла */
int  fat32_seek(int handle, unsigned int position);  /* seek к позиции */
void fat32_close(int handle);

/* Загрузить весь файл в память (удобный wrapper) */
int  fat32_load(const char *name83, unsigned char *dst);  /* → size или <0 */

#endif
