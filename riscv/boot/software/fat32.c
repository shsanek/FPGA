/* Minimal FAT32 reader for bootloader. */
#include "fat32.h"
#include "sd.h"

#define UART_TX (*(volatile unsigned int *)0x08000000U)

static void boot_putc(int c) { UART_TX = (unsigned int)(unsigned char)c; }
static void boot_puts(const char *s) {
    while (*s) boot_putc(*s++);
    boot_putc('\n');
}
static void boot_hex(unsigned int n) {
    const char *h = "0123456789abcdef";
    for (int s = 28; s >= 0; s -= 4) boot_putc(h[(n >> s) & 0xF]);
}

/* ---- Read helpers ---- */
static unsigned char buf[512];

static unsigned int rd16(const unsigned char *p) {
    return p[0] | (p[1] << 8);
}
static unsigned int rd32(const unsigned char *p) {
    return p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24);
}

/* ---- Progress callback ---- */
static fat32_progress_fn progress_cb = 0;

void fat32_set_progress(fat32_progress_fn fn) {
    progress_cb = fn;
}

/* ---- FAT32 geometry (cached after init) ---- */
static unsigned int part_lba;           /* partition start sector */
static unsigned int sectors_per_cluster;
static unsigned int reserved_sectors;
static unsigned int num_fats;
static unsigned int fat_size;           /* sectors per FAT */
static unsigned int root_cluster;
static unsigned int fat_lba;            /* first FAT sector */
static unsigned int data_lba;           /* first data sector */

/* Convert cluster number to first sector */
static unsigned int cluster_to_lba(unsigned int cluster) {
    return data_lba + (cluster - 2) * sectors_per_cluster;
}

/* Read one FAT entry (next cluster in chain) */
static unsigned int fat_next(unsigned int cluster) {
    unsigned int fat_offset = cluster * 4;
    unsigned int fat_sector = fat_lba + (fat_offset / 512);
    unsigned int fat_index  = fat_offset % 512;

    if (sd_read_block(fat_sector, buf) != 0) return 0x0FFFFFFF;
    return rd32(&buf[fat_index]) & 0x0FFFFFFF;
}

int fat32_init(void) {
    /* Read MBR (sector 0) */
    if (sd_read_block(0, buf) != 0) {
        boot_puts("MBR read fail");
        return -1;
    }

    /* Check MBR signature */
    if (buf[510] != 0x55 || buf[511] != 0xAA) {
        boot_puts("No MBR sig");
        return -2;
    }

    /* Find first FAT32 partition (type 0x0B or 0x0C) */
    int found = 0;
    for (int i = 0; i < 4; i++) {
        unsigned char *entry = &buf[446 + i * 16];
        unsigned char ptype = entry[4];
        if (ptype == 0x0B || ptype == 0x0C) {
            part_lba = rd32(&entry[8]);
            found = 1;
            break;
        }
    }
    if (!found) {
        boot_puts("No FAT32 part");
        return -3;
    }

    /* Read BPB (first sector of partition) */
    if (sd_read_block(part_lba, buf) != 0) {
        boot_puts("BPB read fail");
        return -4;
    }

    /* Parse BPB */
    unsigned int bytes_per_sector = rd16(&buf[0x0B]);
    if (bytes_per_sector != 512) {
        boot_puts("Bad sector size");
        return -5;
    }

    sectors_per_cluster = buf[0x0D];
    reserved_sectors    = rd16(&buf[0x0E]);
    num_fats            = buf[0x10];
    fat_size            = rd32(&buf[0x24]);
    root_cluster        = rd32(&buf[0x2C]);

    fat_lba  = part_lba + reserved_sectors;
    data_lba = fat_lba + num_fats * fat_size;

    boot_puts("FAT32 OK");
    return 0;
}

int fat32_load(const char *name83, unsigned char *dst) {
    /* Search root directory for file */
    unsigned int cluster = root_cluster;
    int file_found = 0;
    unsigned int file_cluster = 0;
    unsigned int file_size = 0;

    while (cluster < 0x0FFFFFF8) {
        unsigned int lba = cluster_to_lba(cluster);
        for (unsigned int s = 0; s < sectors_per_cluster; s++) {
            if (sd_read_block(lba + s, buf) != 0) {
                boot_puts("Dir read fail");
                return -1;
            }

            for (int e = 0; e < 16; e++) { /* 16 entries per sector */
                unsigned char *ent = &buf[e * 32];

                if (ent[0] == 0x00) goto dir_end;  /* no more entries */
                if (ent[0] == 0xE5) continue;       /* deleted */
                if (ent[0x0B] & 0x0F) continue;     /* LFN entry */
                if (ent[0x0B] & 0x08) continue;     /* volume label */

                /* Compare 8.3 name (11 bytes) */
                int match = 1;
                for (int i = 0; i < 11; i++) {
                    if (ent[i] != (unsigned char)name83[i]) {
                        match = 0;
                        break;
                    }
                }

                if (match) {
                    file_cluster = (rd16(&ent[0x14]) << 16) | rd16(&ent[0x1A]);
                    file_size    = rd32(&ent[0x1C]);
                    file_found   = 1;
                    goto dir_end;
                }
            }
        }
        cluster = fat_next(cluster);
    }

dir_end:
    if (!file_found) {
        boot_puts("File not found");
        return -2;
    }

    boot_puts("Loading...");
    boot_hex(file_size);
    boot_puts(" bytes");

    /* Read file data following cluster chain */
    unsigned int bytes_loaded = 0;
    cluster = file_cluster;

    while (cluster < 0x0FFFFFF8 && bytes_loaded < file_size) {
        unsigned int lba = cluster_to_lba(cluster);
        for (unsigned int s = 0; s < sectors_per_cluster; s++) {
            if (bytes_loaded >= file_size) break;

            if (sd_read_block(lba + s, buf) != 0) {
                boot_puts("Data read fail");
                return -3;
            }

            unsigned int chunk = file_size - bytes_loaded;
            if (chunk > 512) chunk = 512;

            for (unsigned int i = 0; i < chunk; i++)
                dst[bytes_loaded + i] = buf[i];

            bytes_loaded += chunk;

            if (progress_cb)
                progress_cb(bytes_loaded, file_size);
        }
        cluster = fat_next(cluster);
    }

    return (int)file_size;
}
