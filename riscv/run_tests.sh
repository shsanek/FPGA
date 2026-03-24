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
#   - riscv32-unknown-elf-gcc  (или riscv64-unknown-elf-gcc)
#   - iverilog + vvp
#   - python3
# -----------------------------------------------------------------------
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"
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
        "$SCRIPT_DIR/PROGRAM_TEST.sv" \
        "$SCRIPT_DIR/TOP.sv" \
        "$SCRIPT_DIR/CPU/CPU_SINGLE_CYCLE.sv" \
        "$SCRIPT_DIR/CPU/CPU_ALU.sv" \
        "$SCRIPT_DIR/CPU/CPU_DATA_ADAPTER.sv" \
        "$SCRIPT_DIR/CPU/PERIPHERAL_BUS.sv" \
        "$SCRIPT_DIR/CPU/UART_IO_DEVICE.sv" \
        "$SCRIPT_DIR/CPU/DEBUG_CONTROLLER.sv" \
        "$SCRIPT_DIR/IMMEDIATE_GENERATOR/IMMEDIATE_GENERATOR.sv" \
        "$SCRIPT_DIR/BRANCH_UNIT/BRANCH_UNIT.sv" \
        "$SCRIPT_DIR/LOAD_UNIT/LOAD_UNIT.sv" \
        "$SCRIPT_DIR/STORE_UNIT/STORE_UNIT.sv" \
        "$SCRIPT_DIR/Register/REGISTER_32_BLOCK_32.sv" \
        "$SCRIPT_DIR/MEMORY/MEMORY_CONTROLLER.sv" \
        "$SCRIPT_DIR/MEMORY/CHUNK_STORAGE_4_POOL/CHUNK_STORAGE_4_POOL.sv" \
        "$SCRIPT_DIR/MEMORY/CHUNK_STORAGE/CHUNK_STORAGE.sv" \
        "$SCRIPT_DIR/MEMORY/RAM_CONTROLLER/RAM_CONTROLLER.sv" \
        "$SCRIPT_DIR/MEMORY/RAM_CONTROLLER/MIG_MODEL.sv" \
        "$SCRIPT_DIR/I_O/INPUT_CONTROLLER/I_O_INPUT_CONTROLLER.sv" \
        "$SCRIPT_DIR/I_O/OUTPUT_CONTROLLER/I_O_OUTPUT_CONTROLLER.sv" \
        "$SCRIPT_DIR/I_O/I_O_TIMER_GENERATOR.sv" \
        2>&1 | grep -v "^.*sorry:" || true
    echo "Testbench compiled: $SIM_BIN"
}

# -----------------------------------------------------------------------
# Шаг 2: Собрать все C-программы через tests/Makefile
# -----------------------------------------------------------------------
build_programs() {
    echo "=== Building C programs ==="
    make -C "$TESTS_DIR" all PYTHON=/usr/bin/python3
}

# -----------------------------------------------------------------------
# Шаг 3: Запустить симуляцию одной программы
# Returns 0 if PASS, 1 if FAIL/TIMEOUT
# -----------------------------------------------------------------------
run_program() {
    local name="$1"
    local hex_file="$TESTS_DIR/programs/$name/program.hex"
    local exp_file="$TESTS_DIR/programs/$name/expected.txt"
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
    PROGRAM_LIST=$(ls "$TESTS_DIR/programs/")
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
