/* SD card + FAT32 — unified API. */
#include "sdcard.h"
#include "uart.h"

/* ---- SD hardware registers ---- */
#define SD_DATA    (*(volatile unsigned int *)0x40020000U)
#define SD_CONTROL (*(volatile unsigned int *)0x40020004U)
#define SD_STATUS  (*(volatile unsigned int *)0x40020008U)
#define SD_DIVIDER (*(volatile unsigned int *)0x4002000CU)

static int is_sdhc;

static void delay(volatile unsigned int n) {
    while (n--) __asm__ volatile("");
}

static void spi_wait(void) {
    while (SD_STATUS & 0x2) ;
}

static unsigned char spi_xfer(unsigned char tx) {
    spi_wait();
    SD_DATA = tx;
    spi_wait();
    return (unsigned char)SD_DATA;
}

static unsigned char sd_cmd(unsigned char cmd, unsigned int arg, unsigned char crc) {
    spi_xfer(0x40 | cmd);
    spi_xfer((arg >> 24) & 0xFF);
    spi_xfer((arg >> 16) & 0xFF);
    spi_xfer((arg >>  8) & 0xFF);
    spi_xfer(arg & 0xFF);
    spi_xfer(crc);
    unsigned char r;
    for (int i = 0; i < 10; i++) {
        r = spi_xfer(0xFF);
        if (!(r & 0x80)) return r;
    }
    return r;
}

static unsigned char sd_acmd(unsigned char cmd, unsigned int arg) {
    sd_cmd(55, 0, 0xFF);
    return sd_cmd(cmd, arg, 0xFF);
}

int sd_init(void) {
    is_sdhc = 0;
    SD_DIVIDER = 101;
    SD_CONTROL = 0;
    for (int i = 0; i < 10; i++) spi_xfer(0xFF);
    SD_CONTROL = 1;
    delay(1000);

    if (sd_cmd(0, 0, 0x95) != 0x01) return -1;

    unsigned char r = sd_cmd(8, 0x000001AA, 0x87);
    if (r == 0x01) {
        spi_xfer(0xFF); spi_xfer(0xFF); spi_xfer(0xFF);
        if (spi_xfer(0xFF) != 0xAA) return -2;
    }

    for (int i = 0; i < 1000; i++) {
        if (sd_acmd(41, 0x40000000) == 0x00) break;
        delay(10000);
        if (i == 999) return -3;
    }

    r = sd_cmd(58, 0, 0xFF);
    if (r == 0x00) {
        unsigned char ocr3 = spi_xfer(0xFF);
        spi_xfer(0xFF); spi_xfer(0xFF); spi_xfer(0xFF);
        if (ocr3 & 0x40) is_sdhc = 1;
        else sd_cmd(16, 512, 0xFF);
    }

    SD_DIVIDER = 7;
    return 0;
}

int sd_read_block(unsigned int block, unsigned char *buf) {
    unsigned int addr = is_sdhc ? block : (block * 512);
    if (sd_cmd(17, addr, 0xFF) != 0x00) return -1;
    unsigned char r;
    for (int i = 0; i < 100000; i++) {
        r = spi_xfer(0xFF);
        if (r == 0xFE) break;
    }
    if (r != 0xFE) return -2;
    for (int i = 0; i < 512; i++) buf[i] = spi_xfer(0xFF);
    spi_xfer(0xFF); spi_xfer(0xFF);
    return 0;
}

int sd_write_block(unsigned int block, const unsigned char *buf) {
    unsigned int addr = is_sdhc ? block : (block * 512);
    if (sd_cmd(24, addr, 0xFF) != 0x00) return -1;
    spi_xfer(0xFF);
    spi_xfer(0xFE);
    for (int i = 0; i < 512; i++) spi_xfer(buf[i]);
    spi_xfer(0xFF); spi_xfer(0xFF);
    unsigned char r = spi_xfer(0xFF);
    if ((r & 0x1F) != 0x05) return -2;
    for (int i = 0; i < 100000; i++)
        if (spi_xfer(0xFF) != 0x00) break;
    return 0;
}

/* ==================================================================== */
/* FAT32                                                                 */
/* ==================================================================== */

static unsigned char sector_buf[512];

static unsigned int rd16(const unsigned char *p) { return p[0] | (p[1] << 8); }
static unsigned int rd32(const unsigned char *p) {
    return p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24);
}

/* Geometry (cached after fat32_init) */
static unsigned int part_lba;
static unsigned int spc;              /* sectors per cluster */
static unsigned int fat_lba;
static unsigned int data_lba;
static unsigned int root_cluster;
static int fat32_ready = 0;

static fat32_file_t files[FAT32_MAX_OPEN];

static unsigned int cluster_to_lba(unsigned int c) {
    return data_lba + (c - 2) * spc;
}

static unsigned int fat_next(unsigned int cluster) {
    unsigned int off = cluster * 4;
    unsigned int sec = fat_lba + (off / 512);
    unsigned int idx = off % 512;
    if (sd_read_block(sec, sector_buf) != 0) return 0x0FFFFFFF;
    return rd32(&sector_buf[idx]) & 0x0FFFFFFF;
}

int fat32_init(void) {
    fat32_ready = 0;
    for (int i = 0; i < FAT32_MAX_OPEN; i++) files[i].active = 0;

    if (sd_read_block(0, sector_buf) != 0) return -1;
    if (sector_buf[510] != 0x55 || sector_buf[511] != 0xAA) return -2;

    int found = 0;
    for (int i = 0; i < 4; i++) {
        unsigned char *e = &sector_buf[446 + i * 16];
        if (e[4] == 0x0B || e[4] == 0x0C) {
            part_lba = rd32(&e[8]);
            found = 1;
            break;
        }
    }
    if (!found) return -3;

    if (sd_read_block(part_lba, sector_buf) != 0) return -4;
    if (rd16(&sector_buf[0x0B]) != 512) return -5;

    spc           = sector_buf[0x0D];
    fat_lba       = part_lba + rd16(&sector_buf[0x0E]);
    data_lba      = fat_lba + sector_buf[0x10] * rd32(&sector_buf[0x24]);
    root_cluster  = rd32(&sector_buf[0x2C]);

    fat32_ready = 1;
    return 0;
}

int fat32_open(const char *name83) {
    if (!fat32_ready) return -1;

    /* Find free slot */
    int slot = -1;
    for (int i = 0; i < FAT32_MAX_OPEN; i++) {
        if (!files[i].active) { slot = i; break; }
    }
    if (slot < 0) return -2;  /* no free slots */

    /* Search root directory */
    unsigned int cluster = root_cluster;
    while (cluster < 0x0FFFFFF8) {
        unsigned int lba = cluster_to_lba(cluster);
        for (unsigned int s = 0; s < spc; s++) {
            if (sd_read_block(lba + s, sector_buf) != 0) return -3;
            for (int e = 0; e < 16; e++) {
                unsigned char *ent = &sector_buf[e * 32];
                if (ent[0] == 0x00) return -4;   /* end of dir */
                if (ent[0] == 0xE5) continue;
                if (ent[0x0B] & 0x0F) continue;  /* LFN */
                if (ent[0x0B] & 0x08) continue;  /* volume label */

                int match = 1;
                for (int i = 0; i < 11; i++) {
                    if (ent[i] != (unsigned char)name83[i]) { match = 0; break; }
                }
                if (match) {
                    files[slot].active        = 1;
                    files[slot].start_cluster = (rd16(&ent[0x14]) << 16) | rd16(&ent[0x1A]);
                    files[slot].file_size     = rd32(&ent[0x1C]);
                    files[slot].position      = 0;
                    files[slot].cur_cluster   = files[slot].start_cluster;
                    files[slot].cluster_offset = 0;
                    return slot;
                }
            }
        }
        cluster = fat_next(cluster);
    }
    return -4;  /* not found */
}

int fat32_read(int handle, unsigned char *buf, int count) {
    if (handle < 0 || handle >= FAT32_MAX_OPEN || !files[handle].active) return -1;
    fat32_file_t *f = &files[handle];

    int total = 0;
    unsigned int bytes_per_cluster = spc * 512;

    while (total < count && f->position < f->file_size) {
        /* Which sector within current cluster? */
        unsigned int sec_in_cluster = f->cluster_offset / 512;
        unsigned int byte_in_sector = f->cluster_offset % 512;
        unsigned int lba = cluster_to_lba(f->cur_cluster) + sec_in_cluster;

        int rc = sd_read_block(lba, sector_buf);
        if (rc != 0) {
            uart_puts("fat32_read: sd_read_block failed");
            uart_write(" lba="); uart_print_hex(lba);
            uart_write(" cluster="); uart_print_hex(f->cur_cluster);
            uart_write(" pos="); uart_print_uint(f->position);
            uart_write(" rc="); uart_print_int(rc);
            uart_putc('\n');
            return -2;
        }

        /* Copy bytes from sector_buf */
        while (byte_in_sector < 512 && total < count && f->position < f->file_size) {
            buf[total++] = sector_buf[byte_in_sector++];
            f->position++;
            f->cluster_offset++;
        }

        /* End of cluster? Follow chain */
        if (f->cluster_offset >= bytes_per_cluster) {
            unsigned int next = fat_next(f->cur_cluster);
            if (next >= 0x0FFFFFF8) {
                uart_puts("fat32_read: chain ended early");
                uart_write(" cluster="); uart_print_hex(f->cur_cluster);
                uart_write(" pos="); uart_print_uint(f->position);
                uart_putc('\n');
                break;
            }
            f->cur_cluster = next;
            f->cluster_offset = 0;
        }
    }
    return total;
}

int fat32_seek(int handle, unsigned int position) {
    if (handle < 0 || handle >= FAT32_MAX_OPEN || !files[handle].active) return -1;
    fat32_file_t *f = &files[handle];

    if (position > f->file_size) position = f->file_size;

    unsigned int bytes_per_cluster = spc * 512;

    /* Restart from beginning of file */
    f->cur_cluster = f->start_cluster;
    f->cluster_offset = 0;
    f->position = 0;

    /* Walk cluster chain to target position */
    unsigned int clusters_to_skip = position / bytes_per_cluster;
    for (unsigned int i = 0; i < clusters_to_skip; i++) {
        f->cur_cluster = fat_next(f->cur_cluster);
        if (f->cur_cluster >= 0x0FFFFFF8) return -2;
    }

    f->cluster_offset = position % bytes_per_cluster;
    f->position = position;
    return 0;
}

int fat32_size(int handle) {
    if (handle < 0 || handle >= FAT32_MAX_OPEN || !files[handle].active) return -1;
    return (int)files[handle].file_size;
}

void fat32_close(int handle) {
    if (handle >= 0 && handle < FAT32_MAX_OPEN)
        files[handle].active = 0;
}

int fat32_load(const char *name83, unsigned char *dst) {
    int h = fat32_open(name83);
    if (h < 0) return h;
    int sz = fat32_size(h);
    int rd = fat32_read(h, dst, sz);
    fat32_close(h);
    return rd;
}
