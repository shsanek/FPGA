# -----------------------------------------------------------------------
# RV32I bare-metal test programs
# -----------------------------------------------------------------------
# Requires riscv32-unknown-elf-gcc (or riscv64-unknown-elf-gcc with -march=rv32i)
# Install on macOS:
#   brew tap riscv-software-src/riscv
#   brew install riscv-gnu-toolchain --HEAD
# -----------------------------------------------------------------------

CC       := riscv64-elf-gcc
OBJCOPY  := riscv64-elf-objcopy
COMMON   := $(CURDIR)/common
CFLAGS   := -march=rv32i -mabi=ilp32 -O2 -Wall \
            -ffreestanding -nostdlib -nostartfiles \
            -I$(COMMON)
LDFLAGS  := -T$(COMMON)/linker.ld -Wl,--gc-sections
LDLIBS   := -lgcc

RUNTIME  := $(COMMON)/crt0.s $(COMMON)/runtime.c

PROGRAMS := $(sort $(filter-out common/,$(dir $(wildcard */))))
HEXFILES := $(patsubst %/,%/program.hex,$(PROGRAMS))

.PHONY: all clean

all: $(HEXFILES)
	@echo "Built: $(HEXFILES)"

# Generic rule: programs/<name>/program.hex from programs/<name>/<name>.c
PYTHON   := $(shell which python3 2>/dev/null || echo /usr/bin/python3)

%/program.hex: %/program.elf
	$(OBJCOPY) -O binary $< $(patsubst %.hex,%.bin,$@)
	$(PYTHON) $(CURDIR)/bin2hex.py $(patsubst %.hex,%.bin,$@) $@

%/program.elf: %/*.c $(RUNTIME) $(COMMON)/linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(RUNTIME) $< $(LDLIBS)

clean:
	rm -f */program.elf */program.bin */program.hex
