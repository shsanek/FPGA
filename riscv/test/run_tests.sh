#!/usr/bin/env bash
# -----------------------------------------------------------------------
# run_tests.sh — сборка + симуляция + сравнение всех C-программ
#
# Использование:
#   ./run_tests.sh                  # запустить все тесты
#   ./run_tests.sh hello            # запустить только тест hello
#   ./run_tests.sh --build-only     # только скомпилировать, без симуляции
#   ./run_tests.sh --sim-only hello # только симуляция (пропустить компиляцию)
#
# Требования:
#   - riscv64-elf-gcc (или riscv-none-elf-gcc)
#   - iverilog + vvp
#   - python3
# -----------------------------------------------------------------------
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RISCV_DIR="$(dirname "$SCRIPT_DIR")"
RTL_DIR="$RISCV_DIR/rtl"
PROGRAMS_DIR="$RISCV_DIR/programs"
WORK_DIR="/tmp/riscv_tests"
SIM_BIN="$WORK_DIR/program_test"

BUILD_ONLY=0
SIM_ONLY=0
FILTER=""

for arg in "$@"; do
    case "$arg" in
        --build-only) BUILD_ONLY=1 ;;
        --sim-only)   SIM_ONLY=1   ;;
        -*)           echo "Unknown flag: $arg"; exit 1 ;;
        *)            FILTER="$arg" ;;
    esac
done

mkdir -p "$WORK_DIR"

# -----------------------------------------------------------------------
# Шаг 1: Компилируем тестбенч один раз
# -----------------------------------------------------------------------
compile_testbench() {
    echo "=== Compiling simulation testbench ==="
    iverilog -g2012 -o "$SIM_BIN" \
        "$SCRIPT_DIR/integration/PROGRAM_TEST.sv" \
        "$RTL_DIR/TOP.sv" \
        "$RTL_DIR/BASE_TYPE.sv" \
        "$RTL_DIR/core/CPU_SINGLE_CYCLE.sv" \
        "$RTL_DIR/core/CPU_ALU.sv" \
        "$RTL_DIR/core/CPU_DATA_ADAPTER.sv" \
        "$RTL_DIR/core/CPU_PIPELINE_ADAPTER.sv" \
        "$RTL_DIR/core/OP_0110011.sv" \
        "$RTL_DIR/core/OP_0010011.sv" \
        "$RTL_DIR/core/REGISTER_32_BLOCK_32.sv" \
        "$RTL_DIR/core/IMMEDIATE_GENERATOR.sv" \
        "$RTL_DIR/core/BRANCH_UNIT.sv" \
        "$RTL_DIR/core/LOAD_UNIT.sv" \
        "$RTL_DIR/core/STORE_UNIT.sv" \
        "$RTL_DIR/peripheral/PERIPHERAL_BUS.sv" \
        "$RTL_DIR/peripheral/UART_IO_DEVICE.sv" \
        "$RTL_DIR/peripheral/OLED_IO_DEVICE.sv" \
        "$RTL_DIR/peripheral/SD_IO_DEVICE.sv" \
        "$RTL_DIR/peripheral/SPI_MASTER.sv" \
        "$RTL_DIR/peripheral/FLASH_LOADER.sv" \
        "$RTL_DIR/debug/DEBUG_CONTROLLER.sv" \
        "$RTL_DIR/memory/MEMORY_CONTROLLER.sv" \
        "$RTL_DIR/memory/CHUNK_STORAGE_4_POOL.sv" \
        "$RTL_DIR/memory/CHUNK_STORAGE.sv" \
        "$RTL_DIR/memory/RAM_CONTROLLER.sv" \
        "$RTL_DIR/memory/MIG_MODEL.sv" \
        "$RTL_DIR/uart/I_O_INPUT_CONTROLLER.sv" \
        "$RTL_DIR/uart/I_O_OUTPUT_CONTROLLER.sv" \
        "$RTL_DIR/uart/I_O_TIMER_GENERATOR.sv" \
        "$RTL_DIR/uart/SIMPLE_UART_RX.sv" \
        "$RTL_DIR/uart/UART_FIFO.sv" \
        "$RTL_DIR/uart/VALUE_STORAGE.sv" \
        "$SCRIPT_DIR/peripheral/SPI_FLASH_STUB.sv" \
        2>&1 | grep -v "^.*sorry:" || true
    echo "Testbench compiled: $SIM_BIN"
}

# -----------------------------------------------------------------------
# Шаг 2: Собрать все C-программы через programs/Makefile
# -----------------------------------------------------------------------
build_programs() {
    echo "=== Building C programs ==="
    make -C "$PROGRAMS_DIR" all PYTHON=/usr/bin/python3
}

# -----------------------------------------------------------------------
# Шаг 3: Запустить симуляцию одной программы
# Returns 0 if PASS, 1 if FAIL/TIMEOUT
# -----------------------------------------------------------------------
run_program() {
    local name="$1"
    local hex_file="$PROGRAMS_DIR/$name/program.hex"
    local exp_file="$PROGRAMS_DIR/$name/expected.txt"
    local out_file="$WORK_DIR/${name}.out"

    if [ ! -f "$hex_file" ]; then
        echo "  [SKIP] $name: no program.hex (compile first)"
        return 0
    fi

    printf "  %-20s " "$name"

    # Запуск симуляции
    vvp "$SIM_BIN" \
        "+HEX_FILE=$hex_file" \
        "+OUT_FILE=$out_file" \
        "+TIMEOUT=10000000" \
        > "$WORK_DIR/${name}.log" 2>&1

    local exit_code=$?

    # Читаем статус из лога
    if grep -q "HARD TIMEOUT\|PROGRAM_TEST TIMEOUT" "$WORK_DIR/${name}.log"; then
        echo "TIMEOUT"
        echo "    Log: $WORK_DIR/${name}.log"
        return 1
    fi

    # Сравниваем вывод с ожидаемым
    if [ -f "$exp_file" ]; then
        if diff -q "$exp_file" "$out_file" > /dev/null 2>&1; then
            local cycles
            cycles=$(grep "PROGRAM_TEST OK" "$WORK_DIR/${name}.log" | grep -oE '[0-9]+ cycles' | head -1)
            echo "PASS  ($cycles)"
            return 0
        else
            echo "FAIL  (output mismatch)"
            echo "    Expected ($exp_file):"
            sed 's/^/      /' "$exp_file"
            echo "    Got ($out_file):"
            sed 's/^/      /' "$out_file"
            return 1
        fi
    else
        echo "OK    (no expected.txt, output saved to $out_file)"
        cat "$out_file"
        return 0
    fi
}

# -----------------------------------------------------------------------
# Главная логика
# -----------------------------------------------------------------------
PASS=0
FAIL=0
SKIP=0

if [ "$SIM_ONLY" -eq 0 ]; then
    build_programs
fi

if [ "$BUILD_ONLY" -eq 1 ]; then
    echo "Build done."
    exit 0
fi

compile_testbench

echo ""
echo "=== Running program tests ==="

# Список тестов: либо фильтр, либо все папки в programs/
if [ -n "$FILTER" ]; then
    PROGRAM_LIST="$FILTER"
else
    PROGRAM_LIST=$(ls "$PROGRAMS_DIR" | grep -v common | grep -v Makefile | grep -v bin2hex | grep -v program | grep -v test_oled | grep -v test_sd)
fi

for prog in $PROGRAM_LIST; do
    if run_program "$prog"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ]
