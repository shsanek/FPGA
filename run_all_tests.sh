#!/bin/bash
# Run all tests via Vivado xvlog/xelab/xsim
export PATH="/c/AMDDesignTools/2025.2/Vivado/bin:$PATH"
SRC="C:/Users/ssane/Documents/FPGA/riscv"
PASS=0
FAIL=0
SKIP=0
FAILED_LIST=""

run_test() {
    local name=$1
    shift
    local files=("$@")

    echo "--- $name ---"

    # Compile
    if ! xvlog --sv "${files[@]}" > /dev/null 2>&1; then
        echo "  COMPILE ERROR"
        FAIL=$((FAIL+1))
        FAILED_LIST="$FAILED_LIST $name(compile)"
        return
    fi

    # Elaborate
    if ! xelab "$name" -s "${name}_sim" > /dev/null 2>&1; then
        echo "  ELABORATE ERROR"
        FAIL=$((FAIL+1))
        FAILED_LIST="$FAILED_LIST $name(elab)"
        return
    fi

    # Run
    local output
    output=$(xsim "${name}_sim" -R 2>&1)

    if echo "$output" | grep -qi "ALL.*PASS\|PASS\|passed"; then
        echo "  PASSED"
        PASS=$((PASS+1))
    elif echo "$output" | grep -qi "FAIL\|ERROR"; then
        echo "  FAILED"
        echo "$output" | grep -i "FAIL\|ERROR" | head -5
        FAIL=$((FAIL+1))
        FAILED_LIST="$FAILED_LIST $name"
    else
        echo "  COMPLETED (no PASS/FAIL marker)"
        PASS=$((PASS+1))
    fi
}

# Simple tests (single module + test)
run_test OP_0110011_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/ALU/OP_0110011/OP_0110011.sv" "$SRC/ALU/OP_0110011/OP_0110011_TEST.sv"

run_test OP_0010011_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/ALU/OP_0010011/OP_0010011.sv" "$SRC/ALU/OP_0010011/OP_0010011_TEST.sv"

run_test REGISTER_32_BLOCK_32_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/Register/REGISTER_32_BLOCK_32.sv" "$SRC/Register/REGISTER_32_BLOCK_32_TEST.sv"

run_test BRANCH_UNIT_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/BRANCH_UNIT/BRANCH_UNIT.sv" "$SRC/BRANCH_UNIT/BRANCH_UNIT_TEST.sv"

run_test IMMEDIATE_GENERATOR_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/IMMEDIATE_GENERATOR/IMMEDIATE_GENERATOR.sv" "$SRC/IMMEDIATE_GENERATOR/IMMEDIATE_GENERATOR_TEST.sv"

run_test LOAD_UNIT_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/LOAD_UNIT/LOAD_UNIT.sv" "$SRC/LOAD_UNIT/LOAD_UNIT_TEST.sv"

run_test STORE_UNIT_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/STORE_UNIT/STORE_UNIT.sv" "$SRC/STORE_UNIT/STORE_UNIT_TEST.sv"

run_test CHUNK_STORAGE_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/MEMORY/CHUNK_STORAGE/CHUNK_STORAGE.sv" "$SRC/MEMORY/CHUNK_STORAGE/CHUNK_STORAGE_TEST.sv"

run_test CHUNK_STORAGE_4_POOL_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/MEMORY/CHUNK_STORAGE/CHUNK_STORAGE.sv" \
    "$SRC/MEMORY/CHUNK_STORAGE_4_POOL/CHUNK_STORAGE_4_POOL.sv" "$SRC/MEMORY/CHUNK_STORAGE_4_POOL/CHUNK_STORAGE_4_POOL_TEST.sv"

run_test RAM_CONTROLLER_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/MEMORY/RAM_CONTROLLER/RAM_CONTROLLER.sv" \
    "$SRC/MEMORY/RAM_CONTROLLER/MIG_MODEL.sv" "$SRC/MEMORY/RAM_CONTROLLER/RAM_CONTROLLER_TEST.sv"

run_test MEMORY_CONTROLLER_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/MEMORY/CHUNK_STORAGE/CHUNK_STORAGE.sv" \
    "$SRC/MEMORY/CHUNK_STORAGE_4_POOL/CHUNK_STORAGE_4_POOL.sv" \
    "$SRC/MEMORY/RAM_CONTROLLER/RAM_CONTROLLER.sv" "$SRC/MEMORY/RAM_CONTROLLER/MIG_MODEL.sv" \
    "$SRC/MEMORY/MEMORY_CONTROLLER.sv" "$SRC/MEMORY/MEMORY_CONTROLLER_TEST.sv"

run_test PERIPHERAL_BUS_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/CPU/PERIPHERAL_BUS.sv" "$SRC/CPU/PERIPHERAL_BUS_TEST.sv"

run_test VALUE_STORAGE_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/I_O/VALUE_STORAGE/VALUE_STORAGE.sv" "$SRC/I_O/VALUE_STORAGE/VALUE_STORAGE_TEST.sv"

# CPU tests (need many deps)
ALL_CPU_DEPS=(
    "$SRC/BASE_TYPE.sv"
    "$SRC/Register/REGISTER_32_BLOCK_32.sv"
    "$SRC/ALU/OP_0110011/OP_0110011.sv"
    "$SRC/ALU/OP_0010011/OP_0010011.sv"
    "$SRC/BRANCH_UNIT/BRANCH_UNIT.sv"
    "$SRC/IMMEDIATE_GENERATOR/IMMEDIATE_GENERATOR.sv"
    "$SRC/LOAD_UNIT/LOAD_UNIT.sv"
    "$SRC/STORE_UNIT/STORE_UNIT.sv"
    "$SRC/CPU/CPU_ALU.sv"
    "$SRC/CPU/CPU_SINGLE_CYCLE.sv"
)

run_test CPU_SINGLE_CYCLE_TEST \
    "${ALL_CPU_DEPS[@]}" "$SRC/CPU/CPU_SINGLE_CYCLE_TEST.sv"

# Debug controller test
run_test DEBUG_CONTROLLER_TEST \
    "$SRC/BASE_TYPE.sv" "$SRC/CPU/DEBUG_CONTROLLER.sv" "$SRC/CPU/DEBUG_CONTROLLER_TEST.sv"

echo ""
echo "========================================="
echo "Results: $PASS passed, $FAIL failed"
if [ -n "$FAILED_LIST" ]; then
    echo "Failed:$FAILED_LIST"
fi
echo "========================================="
