# Makefile for Stage 1 bootloader
#
# Targets:
#   make stage1      — build stage1.bin (raw binary)
#   make stage1_hdr  — build stage1_with_header.bin (for write_cfgmem)
#   make boot        — build BOOT.BIN from a test program (set BOOT_SRC)
#   make clean

CROSS    ?= riscv-none-elf-
CC        = $(CROSS)gcc
OBJCOPY   = $(CROSS)objcopy
SIZE      = $(CROSS)size

CFLAGS    = -march=rv32i -mabi=ilp32 -O2 -ffreestanding -nostdlib -nostartfiles -Wall
COMMON   = ../../programs/common

SW_DIR   = ../software
SRC      = $(SW_DIR)/stage1.c $(SW_DIR)/sd.c $(SW_DIR)/fat32.c
CRT0     = $(COMMON)/crt0.s
RUNTIME  = $(COMMON)/runtime.c

AS        = $(CROSS)as

.PHONY: stage1 stage1_hdr stub stub_hdr boot clean

# ---- Stage 1 (for QSPI flash, loads at 0x07F00000) ----

stage1: stage1.bin
	$(SIZE) stage1.elf

stage1.elf: $(CRT0) $(RUNTIME) $(SRC) stage1.ld
	$(CC) $(CFLAGS) -T stage1.ld $(CRT0) $(RUNTIME) $(SRC) -lgcc -o $@

stage1.bin: stage1.elf
	$(OBJCOPY) -O binary $< $@

stage1_hdr: stage1.bin
	python3 prepend_header.py stage1.bin stage1_with_header.bin

# ---- Stub (заглушка — бесконечный цикл, для debug-only и тестов) ----

stub: stub.bin

stub.o: $(SW_DIR)/stub.s
	$(AS) -march=rv32i -mabi=ilp32 -o $@ $<

stub.bin: stub.o
	$(OBJCOPY) -O binary $< $@

stub_hdr: stub.bin
	python3 prepend_header.py stub.bin stub_with_header.bin 0x00000000

# ---- BOOT.BIN (for SD card, loads at 0x00000000) ----

PROG_DIR = ../../programs

# boot_tests — все тесты в одном бинарнике
BOOT_TESTS_SRC = $(PROG_DIR)/boot_tests/boot_tests.c \
    $(PROG_DIR)/hello/hello.c \
    $(PROG_DIR)/fib/fib.c \
    $(PROG_DIR)/sum/sum.c \
    $(PROG_DIR)/test_alu/test_alu.c \
    $(PROG_DIR)/test_branch/test_branch.c \
    $(PROG_DIR)/test_jump/test_jump.c \
    $(PROG_DIR)/test_mem/test_mem.c \
    $(PROG_DIR)/test_upper/test_upper.c \
    $(PROG_DIR)/test_oled/test_oled.c \
    $(COMMON)/oled.c

boot: BOOT.BIN

boot.elf: $(CRT0) $(RUNTIME) $(BOOT_TESTS_SRC) $(COMMON)/linker.ld
	$(CC) $(CFLAGS) -DNO_MAIN -I$(COMMON) -T $(COMMON)/linker.ld $(CRT0) $(RUNTIME) $(BOOT_TESTS_SRC) -lgcc -o $@

BOOT.BIN: boot.elf
	$(OBJCOPY) -O binary $< $@
	$(SIZE) boot.elf

# ---- Clean ----

clean:
	rm -f *.elf *.bin *.o
