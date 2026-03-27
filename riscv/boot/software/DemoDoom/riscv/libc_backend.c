/*
 * libc_backend.c — минимальный libc для DOOM.
 * Файлы читаются с SD карты через FAT32 (наша шина 0x10020000).
 * Консоль через UART (0x10000000).
 */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "config.h"
#include "console.h"

/* ---- Heap ---- */

extern uint8_t _heap_start;
static void *heap_end = 0;

static void heap_init(void) {
    if (!heap_end) heap_end = &_heap_start;
}
static unsigned int alloc_cnt = 0;

void *_sbrk(intptr_t increment) {
    heap_init();
    increment = (increment + 3) & ~3;
    heap_end = (void*)((((uint32_t)heap_end) + 3) & ~3);
    void *rv = heap_end;
    heap_end += increment;
    return rv;
}

/* Bump allocator с отслеживанием размера (для realloc).
 * Каждый блок: [size_t old_size][user data...] */
void *malloc(size_t size) {
    if (size == 0) return (void*)0;
    size = (size + 7) & ~7;
    size_t *hdr = (size_t *)_sbrk(size + sizeof(size_t));
    *hdr = size;
    void *p = hdr + 1;
    if (alloc_cnt < 20 || size > 4096) {
        console_printf("[malloc] #%u size=%u -> %08x\n", alloc_cnt, (unsigned)size, (unsigned)(uint32_t)p);
    }
    alloc_cnt++;
    return p;
}

void *calloc(size_t nmemb, size_t size) {
    size_t total = nmemb * size;
    void *p = malloc(total);
    if (p) memset(p, 0, total);
    return p;
}

void *realloc(void *ptr, size_t new_size) {
    void *p = malloc(new_size);
    if (p && ptr) {
        size_t old_size = *((size_t *)ptr - 1);
        size_t copy = old_size < new_size ? old_size : new_size;
        memcpy(p, ptr, copy);
    }
    return p;
}

void free(void *ptr) {
    (void)ptr;
}

/* ---- SD SPI (0x10020000) ---- */

#define SD_DATA    (*(volatile unsigned int *)0x10020000U)
#define SD_CONTROL (*(volatile unsigned int *)0x10020004U)
#define SD_STATUS  (*(volatile unsigned int *)0x10020008U)
#define SD_DIVIDER (*(volatile unsigned int *)0x1002000CU)

static int sd_sdhc = 0;
static int sd_ok   = 0;

static void sd_delay(volatile unsigned int n) { while (n--) __asm__ volatile(""); }
static void sd_wait(void) { while (SD_STATUS & 0x2); }
static unsigned char sd_xfer(unsigned char tx) { sd_wait(); SD_DATA = tx; sd_wait(); return (unsigned char)SD_DATA; }

static unsigned char sd_cmd(unsigned char c, unsigned int a, unsigned char crc) {
    sd_xfer(0x40|c); sd_xfer((a>>24)&0xFF); sd_xfer((a>>16)&0xFF); sd_xfer((a>>8)&0xFF); sd_xfer(a&0xFF); sd_xfer(crc);
    unsigned char r;
    for (int i=0;i<10;i++) { r=sd_xfer(0xFF); if (!(r&0x80)) return r; }
    return r;
}

static int sd_read_block(unsigned int blk, unsigned char *buf) {
    unsigned int addr = sd_sdhc ? blk : (blk*512);
    if (sd_cmd(17, addr, 0xFF) != 0x00) return -1;
    unsigned char r;
    for (int i=0;i<10000;i++) { r=sd_xfer(0xFF); if(r==0xFE) break; }
    if (r!=0xFE) return -2;
    for (int i=0;i<512;i++) buf[i]=sd_xfer(0xFF);
    sd_xfer(0xFF); sd_xfer(0xFF);
    return 0;
}

static int sd_init_card(void) {
    if (sd_ok) return 0;
    SD_DIVIDER=101; SD_CONTROL=0;
    for(int i=0;i<10;i++) sd_xfer(0xFF);
    SD_CONTROL=1; sd_delay(1000);
    if(sd_cmd(0,0,0x95)!=0x01) return -1;
    unsigned char r=sd_cmd(8,0x1AA,0x87);
    if(r==0x01){sd_xfer(0xFF);sd_xfer(0xFF);sd_xfer(0xFF);if(sd_xfer(0xFF)!=0xAA)return -2;}
    for(int i=0;i<1000;i++){if(sd_cmd(55,0,0xFF),sd_cmd(41,0x40000000,0xFF)==0)break;sd_delay(10000);if(i==999)return -3;}
    r=sd_cmd(58,0,0xFF);
    if(r==0){unsigned char o=sd_xfer(0xFF);sd_xfer(0xFF);sd_xfer(0xFF);sd_xfer(0xFF);if(o&0x40)sd_sdhc=1;else sd_cmd(16,512,0xFF);}
    SD_DIVIDER=7; sd_ok=1; return 0;
}

/* ---- FAT32 ---- */

static unsigned char fbuf[512];
static unsigned int f_plba, f_spc, f_flba, f_dlba, f_root;
static int f_ok = 0;

static unsigned int r16(const unsigned char *p){return p[0]|(p[1]<<8);}
static unsigned int r32(const unsigned char *p){return p[0]|(p[1]<<8)|(p[2]<<16)|(p[3]<<24);}
static unsigned int c2lba(unsigned int c){return f_dlba+(c-2)*f_spc;}
static unsigned int fnext(unsigned int c){unsigned int o=c*4;if(sd_read_block(f_flba+(o/512),fbuf))return 0x0FFFFFFF;return r32(&fbuf[o%512])&0x0FFFFFFF;}

static int fat_init(void) {
    if(f_ok) return 0;
    if(sd_init_card()) return -1;
    if(sd_read_block(0,fbuf)) return -2;
    if(fbuf[510]!=0x55||fbuf[511]!=0xAA) return -3;
    int found=0;
    for(int i=0;i<4;i++){unsigned char*e=&fbuf[446+i*16];if(e[4]==0x0B||e[4]==0x0C){f_plba=r32(&e[8]);found=1;break;}}
    if(!found) return -4;
    if(sd_read_block(f_plba,fbuf)) return -5;
    f_spc=fbuf[0x0D]; f_flba=f_plba+r16(&fbuf[0x0E]); f_dlba=f_flba+fbuf[0x10]*r32(&fbuf[0x24]); f_root=r32(&fbuf[0x2C]);
    f_ok=1; return 0;
}

static int fat_find(const char *name, unsigned int *cl, unsigned int *sz) {
    if(fat_init()) return -1;
    /* "doomu.wad" → "DOOMU   WAD" */
    char n83[11]; memset(n83,' ',11);
    int dot=-1; for(int i=0;name[i];i++) if(name[i]=='.'){dot=i;break;}
    int nl=dot>=0?dot:(int)strlen(name); if(nl>8)nl=8;
    for(int i=0;i<nl;i++){char c=name[i];if(c>='a'&&c<='z')c-=32;n83[i]=c;}
    if(dot>=0){const char*ext=&name[dot+1];for(int i=0;i<3&&ext[i];i++){char c=ext[i];if(c>='a'&&c<='z')c-=32;n83[8+i]=c;}}

    unsigned int cluster=f_root;
    while(cluster<0x0FFFFFF8){
        unsigned int lba=c2lba(cluster);
        for(unsigned int s=0;s<f_spc;s++){
            if(sd_read_block(lba+s,fbuf)) return -2;
            for(int e=0;e<16;e++){
                unsigned char*ent=&fbuf[e*32];
                if(ent[0]==0x00) return -3;
                if(ent[0]==0xE5||ent[0x0B]&0x0F||ent[0x0B]&0x08) continue;
                int m=1; for(int i=0;i<11;i++) if(ent[i]!=(unsigned char)n83[i]){m=0;break;}
                if(m){*cl=(r16(&ent[0x14])<<16)|r16(&ent[0x1A]);*sz=r32(&ent[0x1C]);return 0;}
            }
        }
        cluster=fnext(cluster);
    }
    return -3;
}

/* ---- File descriptors ---- */

static unsigned int read_log_cnt = 0;

#define NUM_FDS 16
static struct {
    enum {FD_NONE=0,FD_STDIO=1,FD_FAT=2} type;
    unsigned int cstart, ccur, fsize, off;
} fds[NUM_FDS] = {[0]={.type=FD_STDIO},[1]={.type=FD_STDIO},[2]={.type=FD_STDIO}};

int _open(const char *path, int flags) {
    unsigned int cl,sz;
    if(fat_find(path,&cl,&sz)){errno=ENOENT;return -1;}
    int fd; for(fd=3;fd<NUM_FDS&&fds[fd].type!=FD_NONE;fd++);
    if(fd==NUM_FDS){errno=ENOMEM;return -1;}
    fds[fd]=(typeof(fds[0])){.type=FD_FAT,.cstart=cl,.ccur=cl,.fsize=sz,.off=0};
    console_printf("Opened: %s fd=%d size=%u\n",path,fd,sz);
    read_log_cnt = 0;  /* reset чтобы логировать reads после open */
    return fd;
}

ssize_t _read(int fd, void *buf, size_t n) {
    if(fd<0||fd>=NUM_FDS||fds[fd].type!=FD_FAT){errno=EINVAL;return -1;}
    if(fds[fd].off+n>fds[fd].fsize) n=fds[fd].fsize-fds[fd].off;
    read_log_cnt++;
    unsigned int bpc=f_spc*512; size_t tot=0;
    int sectors_read = 0;
    while(tot<n){
        unsigned int co=fds[fd].off%bpc;
        unsigned int lba = c2lba(fds[fd].ccur)+co/512;
        if(sd_read_block(lba, fbuf)) {
            console_printf("[read] SD FAIL lba=%u sec#%d\n", lba, sectors_read);
            return -1;
        }
        sectors_read++;
        (void)sectors_read;
        unsigned int bi=co%512;
        while(bi<512&&tot<n){((unsigned char*)buf)[tot++]=fbuf[bi++];fds[fd].off++;}
        if(fds[fd].off%bpc==0&&tot<n) fds[fd].ccur=fnext(fds[fd].ccur);
    }
    return tot;
}

ssize_t _write(int fd, const void *buf, size_t n) {
    const unsigned char *c=buf; for(size_t i=0;i<n;i++) console_putchar(*c++); return n;
}

int _close(int fd) {
    if(fd<0||fd>=NUM_FDS){errno=EINVAL;return -1;}
    fds[fd].type=FD_NONE; return 0;
}

off_t _lseek(int fd, off_t offset, int whence) {
    if(fd<0||fd>=NUM_FDS||fds[fd].type!=FD_FAT){errno=EINVAL;return -1;}
    size_t noff;
    switch(whence){case SEEK_SET:noff=offset;break;case SEEK_CUR:noff=fds[fd].off+offset;break;case SEEK_END:noff=fds[fd].fsize+offset;break;default:errno=EINVAL;return -1;}
    if(noff>fds[fd].fsize){errno=EINVAL;return -1;}
    unsigned int bpc=f_spc*512;

    if (noff == fds[fd].off) {
        /* Seek to same position — no-op */
        return noff;
    }

    unsigned int new_ci = noff / bpc;
    unsigned int cur_ci = fds[fd].off / bpc;

    if (noff >= fds[fd].off && new_ci >= cur_ci) {
        /* Forward seek — продолжаем с текущего кластера */
        for (unsigned int i = cur_ci; i < new_ci; i++)
            fds[fd].ccur = fnext(fds[fd].ccur);
    } else {
        /* Backward seek — перемотка с начала */
        fds[fd].ccur = fds[fd].cstart;
        for (unsigned int i = 0; i < new_ci; i++)
            fds[fd].ccur = fnext(fds[fd].ccur);
    }

    fds[fd].off = noff;
    return noff;
}

int _stat(const char *f, struct stat *s){return -1;}
int _fstat(int fd, struct stat *s){return -1;}
int _isatty(int fd){errno=0;return fd==1||fd==2;}
int access(const char *path, int mode) {
    unsigned int cl,sz;
    if(fat_find(path,&cl,&sz)){errno=ENOENT;return -1;}
    if(mode&~(R_OK|F_OK)){errno=EACCES;return -1;}
    return 0;
}
