module MEMORY_CONTROLLER#(
    parameter CHUNK_PART = 128,
    parameter DATA_SIZE = 32,
    parameter MASK_SIZE = DATA_SIZE / 8,
    parameter ADDRESS_SIZE = 28
)(
    input wire clk,
    input wire reset,

    // RAM

    // COMMON
    input logic ram_controller_ready,

    // WRITE
    output logic ram_write_trigger,
    output logic[CHUNK_PART - 1: 0] ram_write_value,
    output logic[ADDRESS_SIZE - 1:0] ram_write_address,

    // READ
    output logic ram_read_trigger,
    input wire[CHUNK_PART - 1: 0] ram_read_value,
    output logic[ADDRESS_SIZE - 1:0] ram_read_address,
    input wire ram_read_value_ready,

    // INTERFACE
    // COMMON
    output wire controller_ready,
    input wire[ADDRESS_SIZE - 1:0] address,
    input wire[MASK_SIZE - 1: 0] mask,

    // WRITE
    input wire write_trigger,
    input wire[DATA_SIZE-1: 0] write_value,

    // READ
    input wire read_trigger,
    output wire[DATA_SIZE-1: 0] read_value,
    output wire contains_address,

    // DEBUG — приоритет над CPU
    input  wire                    dbg_read_trigger,
    input  wire                    dbg_write_trigger,
    input  wire [ADDRESS_SIZE-1:0] dbg_address,
    input  wire [DATA_SIZE-1:0]    dbg_write_data,
    input  wire [MASK_SIZE-1:0]    dbg_mask,
    output wire [DATA_SIZE-1:0]    dbg_read_data,
    output wire                    dbg_ready
);
    wire[ADDRESS_SIZE - 1:0] save_address;
    wire[CHUNK_PART - 1: 0] save_data;
    wire save_need_flag;

    logic[CHUNK_PART - 1: 0] new_data;
    logic[ADDRESS_SIZE - 1:0] new_address;
    logic new_data_save;

    wire internal_contains_address;

    logic internal_write_trigger;
    logic[ADDRESS_SIZE - 1:0] internal_address;
    logic[MASK_SIZE - 1:0] internal_mask;
    logic[DATA_SIZE - 1:0] internal_write_data;

    // dirty-evict tracking
    logic had_dirty_evict;

    typedef enum logic [2:0] {
        MEMORY_CONTROLLER_STATE_NORMAL,
        MEMORY_CONTROLLER_STATE_WATING,
        MEMORY_CONTROLLER_STATE_SAVE_DATA,
        MEMORY_CONTROLLER_STATE_WRITE_DATA,
        MEMORY_CONTROLLER_STATE_WAIT_DIRTY
    } MEMORY_CONTROLLER_STATE;

    MEMORY_CONTROLLER_STATE internal_state;

    // ---------------------------------------------------------------
    // Debug mux — debug имеет приоритет над CPU
    // ---------------------------------------------------------------
    logic dbg_active;      // идёт debug-операция
    logic dbg_done_cycle;  // MC прошёл хотя бы 1 такт после захвата

    wire eff_write_trigger = dbg_active ? dbg_write_trigger : write_trigger;
    wire eff_read_trigger  = dbg_active ? dbg_read_trigger  : read_trigger;
    wire [ADDRESS_SIZE-1:0] eff_address    = dbg_active ? dbg_address    : address;
    wire [MASK_SIZE-1:0]    eff_mask       = dbg_active ? dbg_mask       : mask;
    wire [DATA_SIZE-1:0]    eff_write_value= dbg_active ? dbg_write_data : write_value;

    // controller_ready для CPU скрыт пока отладчик занят
    wire cpu_controller_ready = ((internal_state == MEMORY_CONTROLLER_STATE_NORMAL) && ram_controller_ready && !dbg_active);

    // dbg_ready — 1 такт после завершения debug-операции
    logic dbg_ready_r;
    assign dbg_ready    = dbg_ready_r;
    assign dbg_read_data = read_value;  // read_value — комбинационный из кэша

    wire output_write_trigger;
    wire[ADDRESS_SIZE - 1:0] output_address;
    wire[MASK_SIZE - 1:0] output_mask;
    wire[DATA_SIZE - 1:0] output_write_value;

    assign output_write_trigger = (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) ? internal_write_trigger : eff_write_trigger;
    assign output_address       = (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) ? internal_address       : eff_address;
    assign output_mask          = (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) ? internal_mask          : eff_mask;
    assign output_write_value   = (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) ? internal_write_data    : eff_write_value;

    assign contains_address  = internal_contains_address;
    assign controller_ready  = cpu_controller_ready;

    // LRU order_tick: age cache entries while controller is busy
    wire order_tick = (internal_state != MEMORY_CONTROLLER_STATE_NORMAL);

    always_ff @(posedge clk) begin
        if (reset) begin
            internal_write_trigger <= 0;
            internal_state         <= MEMORY_CONTROLLER_STATE_NORMAL;
            new_data_save          <= 0;
            ram_write_trigger      <= 0;
            ram_read_trigger       <= 0;
            had_dirty_evict        <= 0;
            dbg_active             <= 0;
            dbg_done_cycle         <= 0;
            dbg_ready_r            <= 0;
        end else begin
            dbg_ready_r <= 0;  // default: pulse only 1 такт

            // Захватить debug-запрос (приоритет над CPU)
            if (!dbg_active && (dbg_read_trigger || dbg_write_trigger) &&
                (internal_state == MEMORY_CONTROLLER_STATE_NORMAL) && ram_controller_ready) begin
                dbg_active     <= 1;
                dbg_done_cycle <= 0;
            end
            if (dbg_active && !dbg_done_cycle) begin
                dbg_done_cycle <= 1;  // следующий такт после захвата
            end

            // Debug-операция завершена когда контроллер вернулся в NORMAL+ready
            // после обработки (dbg_done_cycle = такт после захвата)
            if (dbg_active && dbg_done_cycle &&
                (internal_state == MEMORY_CONTROLLER_STATE_NORMAL) && ram_controller_ready) begin
                dbg_active  <= 0;
                dbg_ready_r <= 1;
            end

            if (internal_state == MEMORY_CONTROLLER_STATE_SAVE_DATA) begin
                new_data_save     <= 0;
                ram_write_trigger <= 0;   // clear the 1-cycle write pulse sent in WATING
                if (had_dirty_evict)
                    internal_state <= MEMORY_CONTROLLER_STATE_WAIT_DIRTY;
                else if (internal_write_trigger)
                    internal_state <= MEMORY_CONTROLLER_STATE_WRITE_DATA;
                else
                    internal_state <= MEMORY_CONTROLLER_STATE_NORMAL;

            end else if (internal_state == MEMORY_CONTROLLER_STATE_WRITE_DATA) begin
                internal_write_trigger <= 0;
                internal_state <= MEMORY_CONTROLLER_STATE_NORMAL;

            end else if (internal_state == MEMORY_CONTROLLER_STATE_WAIT_DIRTY) begin
                // Wait until RAM controller finishes the dirty writeback.
                // In real HW: ram_controller_ready drops after write trigger, then returns high.
                // In stub tests where ready is always 1, we exit in 1 cycle (write was a pulse).
                if (ram_controller_ready) begin
                    had_dirty_evict <= 0;
                    if (internal_write_trigger)
                        internal_state <= MEMORY_CONTROLLER_STATE_WRITE_DATA;
                    else
                        internal_state <= MEMORY_CONTROLLER_STATE_NORMAL;
                end

            end else if (internal_state == MEMORY_CONTROLLER_STATE_NORMAL && ram_controller_ready) begin
                if ((!internal_contains_address) && (eff_read_trigger || eff_write_trigger)) begin
                    // Cache miss — сохранить запрос, подгрузить из RAM
                    internal_write_trigger <= eff_write_trigger;
                    internal_address       <= eff_address;
                    internal_mask          <= eff_mask;
                    internal_write_data    <= eff_write_value;

                    ram_read_trigger  <= 1;
                    ram_read_address  <= { eff_address[ADDRESS_SIZE-1:4], 4'b0000 };
                    internal_state    <= MEMORY_CONTROLLER_STATE_WATING;
                end

            end else if (internal_state == MEMORY_CONTROLLER_STATE_WATING) begin
                ram_read_trigger <= 0;
                if (ram_read_value_ready) begin
                    // Data arrived from RAM. NOW select victim and capture its dirty state
                    // before new_data_save evicts it into that slot.
                    if (save_need_flag) begin
                        ram_write_trigger <= 1;
                        ram_write_value   <= save_data;
                        ram_write_address <= save_address;
                        had_dirty_evict   <= 1;
                    end
                    new_address   <= ram_read_address;
                    new_data      <= ram_read_value;
                    new_data_save <= 1;
                    internal_state <= MEMORY_CONTROLLER_STATE_SAVE_DATA;
                end
            end
        end
    end

    CHUNK_STORAGE_4_POOL #(
        .CHUNK_PART(CHUNK_PART),
        .DATA_SIZE(DATA_SIZE),
        .MASK_SIZE(MASK_SIZE),
        .ADDRESS_SIZE(ADDRESS_SIZE)
    ) storage_pool (
        .clk                   (clk),
        .reset                 (reset),
        .address               (output_address),
        .mask                  (output_mask),

        // WRITE
        .write_trigger         (output_write_trigger),
        .write_value           (output_write_value),

        // READ
        .read_trigger          (read_trigger),
        .read_value            (read_value),
        .contains_address      (internal_contains_address),

        // SAVE
        .save_address          (save_address),
        .save_data             (save_data),
        .save_need_flag        (save_need_flag),

        .order_tick            (order_tick),

        // NEW DATA
        .new_data              (new_data),
        .new_address           (new_address),
        .new_data_save         (new_data_save)
    );

endmodule
