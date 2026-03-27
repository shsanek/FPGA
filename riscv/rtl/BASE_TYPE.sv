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

endpackage;