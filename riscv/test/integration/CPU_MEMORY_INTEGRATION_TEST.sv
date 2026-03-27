// Интеграционный тест: CPU_SINGLE_CYCLE + CPU_DATA_ADAPTER + MEMORY_CONTROLLER + MIG_MODEL
//
// Инструкции — ROM (комбинационный).
// Данные     — MEMORY_CONTROLLER → RAM_CONTROLLER → MIG_MODEL (DDR симуляция).
//
// Программа:
//   addi x1, x0, 42     → x1 = 42
//   sw   x1, 0(x0)      → mem[0] = 42  (через MEMORY_CONTROLLER)
//   lw   x2, 0(x0)      → x2 = 42      (через MEMORY_CONTROLLER, cache hit)
//   addi x3, x2, 10     → x3 = 52      (проверяем что LW вернул верное значение)
//   sw   x3, 4(x0)      → mem[4] = 52
//   lw   x4, 4(x0)      → x4 = 52
//   jal  x0, 0          → infinite loop
module CPU_MEMORY_INTEGRATION_TEST();
    // Параметры
    localparam CHUNK_PART   = 128;
    localparam ADDRESS_SIZE = 28;
    localparam DATA_SIZE    = 32;
    localparam MASK_SIZE    = DATA_SIZE / 8;

    // Тактовые
    logic clk     = 0;
    logic mig_clk = 0;
    initial forever #5  clk     = ~clk;
    initial forever #4  mig_clk = ~mig_clk;  // 125 MHz

    logic reset;
    int   error = 0;

    // ---------------------------------------------------------------
    // ROM — инструкции (комбинационное чтение)
    // ---------------------------------------------------------------
    wire  [31:0] instr_addr;
    logic [31:0] rom [0:255];
    wire  [31:0] instr_data = rom[instr_addr[9:2]];

    initial begin
        for (int i = 0; i < 256; i++) rom[i] = 32'h00000013; // NOP
        //  Адрес  Инструкция
        rom[0] = 32'h02A00093; // addi x1, x0, 42
        rom[1] = 32'h00102023; // sw   x1, 0(x0)
        rom[2] = 32'h00002103; // lw   x2, 0(x0)
        rom[3] = 32'h00A10193; // addi x3, x2, 10
        rom[4] = 32'h00302223; // sw   x3, 4(x0)
        rom[5] = 32'h00402203; // lw   x4, 4(x0)  — lw x4, 4(x0): 000000000100_00000_010_00100_0000011 = 0x00402203
        rom[6] = 32'h0000006F; // jal  x0, 0
    end

    // ---------------------------------------------------------------
    // CPU_DATA_ADAPTER → MEMORY_CONTROLLER сигналы
    // ---------------------------------------------------------------
    wire        mem_read_en, mem_write_en;
    wire [31:0] mem_addr, mem_write_data, mem_read_data;
    wire [3:0]  mem_byte_mask;
    wire        mem_stall;

    wire [27:0] mc_address;
    wire        mc_read_trigger, mc_write_trigger;
    wire [31:0] mc_write_value, mc_read_value;
    wire [3:0]  mc_mask;
    wire        mc_controller_ready, mc_contains_address;

    // ---------------------------------------------------------------
    // CPU
    // ---------------------------------------------------------------
    CPU_SINGLE_CYCLE #(.DEBUG_ENABLE(0)) cpu (
        .clk            (clk),
        .reset          (reset),
        .mem_stall      (mem_stall),
        .instr_stall    (1'b0),
        .instr_addr     (instr_addr),
        .instr_data     (instr_data),
        .mem_read_en    (mem_read_en),
        .mem_write_en   (mem_write_en),
        .mem_addr       (mem_addr),
        .mem_write_data (mem_write_data),
        .mem_byte_mask  (mem_byte_mask),
        .mem_read_data  (mem_read_data),
        .dbg_halt       (1'b0),
        .dbg_step       (1'b0),
        .dbg_set_pc     (1'b0),
        .dbg_new_pc     (32'b0),
        .dbg_is_halted  (),
        .dbg_current_pc (),
        .dbg_current_instr()
    );

    // ---------------------------------------------------------------
    // Адаптер данных
    // ---------------------------------------------------------------
    CPU_DATA_ADAPTER adapter (
        .clk             (clk),
        .reset           (reset),
        .mem_read_en     (mem_read_en),
        .mem_write_en    (mem_write_en),
        .mem_addr        (mem_addr),
        .mem_write_data  (mem_write_data),
        .mem_byte_mask   (mem_byte_mask),
        .mem_read_data   (mem_read_data),
        .stall           (mem_stall),
        .mc_address      (mc_address),
        .mc_read_trigger (mc_read_trigger),
        .mc_write_trigger(mc_write_trigger),
        .mc_write_value  (mc_write_value),
        .mc_mask         (mc_mask),
        .mc_read_value   (mc_read_value),
        .mc_controller_ready(mc_controller_ready)
    );

    // ---------------------------------------------------------------
    // MEMORY_CONTROLLER → RAM_CONTROLLER сигналы
    // ---------------------------------------------------------------
    wire        ram_controller_ready;
    wire        ram_write_trigger;
    wire [CHUNK_PART-1:0]   ram_write_value;
    wire [ADDRESS_SIZE-1:0] ram_write_address;
    wire        ram_read_trigger;
    wire [CHUNK_PART-1:0]   ram_read_value;
    wire [ADDRESS_SIZE-1:0] ram_read_address;
    wire        ram_read_value_ready;

    // ---------------------------------------------------------------
    // MEMORY_CONTROLLER
    // ---------------------------------------------------------------
    MEMORY_CONTROLLER #(
        .CHUNK_PART  (CHUNK_PART),
        .DATA_SIZE   (DATA_SIZE),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) mem_ctrl (
        .clk                (clk),
        .reset              (reset),
        .ram_controller_ready(ram_controller_ready),
        .ram_write_trigger  (ram_write_trigger),
        .ram_write_value    (ram_write_value),
        .ram_write_address  (ram_write_address),
        .ram_read_trigger   (ram_read_trigger),
        .ram_read_value     (ram_read_value),
        .ram_read_address   (ram_read_address),
        .ram_read_value_ready(ram_read_value_ready),
        .controller_ready   (mc_controller_ready),
        .address            (mc_address),
        .mask               (mc_mask),
        .write_trigger      (mc_write_trigger),
        .write_value        (mc_write_value),
        .read_trigger       (mc_read_trigger),
        .read_value         (mc_read_value),
        .contains_address   (mc_contains_address),
        .dbg_read_trigger   (1'b0),
        .dbg_write_trigger  (1'b0),
        .dbg_address        (28'b0),
        .dbg_write_data     (32'b0),
        .dbg_mask           (4'b0),
        .dbg_read_data      (),
        .dbg_ready          ()
    );

    // ---------------------------------------------------------------
    // MIG-интерфейс
    // ---------------------------------------------------------------
    wire [ADDRESS_SIZE-1:0] mig_app_addr;
    wire [2:0]              mig_app_cmd;
    wire                    mig_app_en;
    wire [CHUNK_PART-1:0]   mig_app_wdf_data;
    wire                    mig_app_wdf_wren;
    wire                    mig_app_wdf_end;
    wire [(CHUNK_PART/8-1):0] mig_app_wdf_mask;
    wire                    mig_app_wdf_rdy;
    wire [CHUNK_PART-1:0]   mig_app_rd_data;
    wire                    mig_app_rd_data_valid;
    wire                    mig_app_rd_data_end;
    wire                    mig_app_rdy;
    wire                    mig_init_calib_complete;

    // ---------------------------------------------------------------
    // RAM_CONTROLLER
    // ---------------------------------------------------------------
    RAM_CONTROLLER #(
        .CHUNK_PART  (CHUNK_PART),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) ram_ctrl (
        .clk                    (clk),
        .reset                  (reset),
        .controller_ready       (ram_controller_ready),
        .error                  (),
        .write_trigger          (ram_write_trigger),
        .write_value            (ram_write_value),
        .write_address          (ram_write_address),
        .read_trigger           (ram_read_trigger),
        .read_value             (ram_read_value),
        .read_address           (ram_read_address),
        .read_value_ready       (ram_read_value_ready),
        .led0                   (),
        .mig_app_addr           (mig_app_addr),
        .mig_app_cmd            (mig_app_cmd),
        .mig_app_en             (mig_app_en),
        .mig_app_wdf_data       (mig_app_wdf_data),
        .mig_app_wdf_end        (mig_app_wdf_end),
        .mig_app_wdf_mask       (mig_app_wdf_mask),
        .mig_app_wdf_wren       (mig_app_wdf_wren),
        .mig_app_wdf_rdy        (mig_app_wdf_rdy),
        .mig_app_rd_data        (mig_app_rd_data),
        .mig_app_rd_data_end    (mig_app_rd_data_end),
        .mig_app_rd_data_valid  (mig_app_rd_data_valid),
        .mig_app_rdy            (mig_app_rdy),
        .mig_ui_clk             (mig_clk),
        .mig_init_calib_complete(mig_init_calib_complete)
    );

    // ---------------------------------------------------------------
    // MIG_MODEL
    // ---------------------------------------------------------------
    MIG_MODEL #(
        .CHUNK_PART  (CHUNK_PART),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) mig (
        .mig_ui_clk             (mig_clk),
        .mig_init_calib_complete(mig_init_calib_complete),
        .mig_app_rdy            (mig_app_rdy),
        .mig_app_en             (mig_app_en),
        .mig_app_cmd            (mig_app_cmd),
        .mig_app_addr           (mig_app_addr),
        .mig_app_wdf_data       (mig_app_wdf_data),
        .mig_app_wdf_wren       (mig_app_wdf_wren),
        .mig_app_wdf_end        (mig_app_wdf_end),
        .mig_app_wdf_rdy        (mig_app_wdf_rdy),
        .mig_app_rd_data        (mig_app_rd_data),
        .mig_app_rd_data_valid  (mig_app_rd_data_valid),
        .mig_app_rd_data_end    (mig_app_rd_data_end)
    );

    // ---------------------------------------------------------------
    // Тест
    // ---------------------------------------------------------------
    // Аварийный таймаут
    initial begin
        #500000;
        $display("TIMEOUT at t=%0t mc_ready=%b ram_ready=%b", $time, mc_controller_ready, ram_controller_ready);
        $finish;
    end

    initial begin
        // Assert reset briefly, then release and wait for memory to initialize
        reset = 1;
        repeat(5) @(posedge clk);
        #1;
        reset = 0;

        $display("Waiting for mc_controller_ready...");
        begin : wait_init
            integer n;
            n = 0;
            while (mc_controller_ready !== 1'b1 && n < 2000) begin
                @(posedge clk); n = n + 1;
            end
        end
        $display("mc_controller_ready=%b after init", mc_controller_ready);

        // Wait for program execution after memory system is ready
        // Each SW/LW takes ~50 cycles (CDC + MIG), 7 instructions x 50 = 350
        repeat(1000) @(posedge clk); #1;

        // Проверяем регистры
        assert(cpu.regfile.reg_values[1] === 32'd42) else begin
            $display("FAIL x1: got %0d", cpu.regfile.reg_values[1]); error = error + 1;
        end
        assert(cpu.regfile.reg_values[2] === 32'd42) else begin
            $display("FAIL x2 (LW): got %0d", cpu.regfile.reg_values[2]); error = error + 1;
        end
        assert(cpu.regfile.reg_values[3] === 32'd52) else begin
            $display("FAIL x3 (ADDI after LW): got %0d", cpu.regfile.reg_values[3]); error = error + 1;
        end
        assert(cpu.regfile.reg_values[4] === 32'd52) else begin
            $display("FAIL x4 (LW x4): got %0d", cpu.regfile.reg_values[4]); error = error + 1;
        end

        if (error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);

        $finish;
    end
endmodule
