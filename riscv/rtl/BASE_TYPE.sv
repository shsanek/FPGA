package types_pkg;

typedef struct packed {
    logic [6:0] funct7;
    logic [4:0] rs2;
    logic [4:0] rs1;
    logic [2:0] funct3;
    logic [4:0] rd;
    logic [6:0] opcode;
} R_TYPE;

typedef struct packed {
    logic [6:0] funct7;
    logic [2:0] funct3;

    logic [31:0] rs1;
    logic [31:0] rs2;
} R_TYPE_ALU32_INPUT;

typedef enum logic [2:0] {
    READ_COMMAND,
    READ_REGISTER,
    RUN_COMMAND,
    WATING_MEMORY,
    SAVE_IN_REGISTER,
    ERROR
} PROCESSOR_STATE;

// Тип доступа к памяти через MEMORY_CONTROLLER
typedef enum logic [1:0] {
    BUS_BASE_MEM         = 2'b00,  // DDR через 4-pool D-cache
    BUS_STREAM           = 2'b01,  // DDR через 1-entry stream cache (блиттер)
    BUS_CODE_CACHE_CORE1 = 2'b10   // DDR через I-cache (read-only BRAM)
    // 2'b11 — зарезервировано
} BUS_MEM_TYPE;

endpackage;