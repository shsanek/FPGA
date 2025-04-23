module RAM_CONTROLLER #(
    parameter CHUNK_PART = 128,
    parameter DATA_SIZE = 32,
    parameter MASK_SIZE = DATA_SIZE / 8,
    parameter ADDRESS_SIZE = 28,
    parameter CHUNK_COUNT = 4
)
(
    input wire clk,

    // COMMON
    input wire[ADDRESS_SIZE - 1:0] address,
    input wire[MASK_SIZE - 1: 0] mask,
    output logic controller_ready,
    output logic[3:0] error,

    // WRITE
    input wire write_trigger,
    input wire[DATA_SIZE-1: 0] write_value,

    // READ
    input wire read_trigger,
    output wire[DATA_SIZE-1: 0] read_value,
    output wire read_value_ready,
    output logic[2:0] led0,

    // MIG INTERFACE
    output wire [ADDRESS_SIZE-1:0] mig_app_addr,
    output logic [2:0]              mig_app_cmd,
    output logic                    mig_app_en,

    output logic [CHUNK_PART - 1:0]          mig_app_wdf_data,
    output logic                  mig_app_wdf_end,
    output wire [(CHUNK_PART / 8 - 1):0]           mig_app_wdf_mask,
    output logic                  mig_app_wdf_wren,
    input  wire                  mig_app_wdf_rdy,

    input  wire [CHUNK_PART - 1:0]          mig_app_rd_data,
    input  wire                  mig_app_rd_data_end,
    input  wire                  mig_app_rd_data_valid,

    input  wire                  mig_app_rdy,

    input  wire                  mig_ui_clk,
    input  wire                  mig_init_calib_complete
);

    typedef enum logic [1:0] {
        SYNC_CONTROLLER_ACTIVE_CONTROLL,
        SYNC_CONTROLLER_WILL_START_CONTROLL,
        SYNC_CONTROLLER_WILL_STOP_CONTROLL,
        SYNC_CONTROLLER_NOT_CONTOLL
    } SYNC_CONTROLLER_STATE;

    typedef enum logic [1:0] {
        RAM_CONTROLLER_STATE_WATING,
        RAM_CONTROLLER_STATE_READ,
        RAM_CONTROLLER_STATE_WRITE,
        RAM_CONTROLLER_STATE_INIT
    } RAM_CONTROLLER_STATE; 

    SYNC_CONTROLLER_STATE controll_clk_state;
    SYNC_CONTROLLER_STATE _controll_clk_state;
    
    SYNC_CONTROLLER_STATE _controll_ui_clk_state;
    SYNC_CONTROLLER_STATE controll_ui_clk_state;

    logic[ADDRESS_SIZE - 1:0] internal_address;
    logic[MASK_SIZE - 1: 0] internal_mask;
    logic[3:0] internal_error;
    logic[DATA_SIZE-1: 0] internal_write_value;
    logic internal_read_trigger;
    logic internal_write_trigger;
    logic[DATA_SIZE-1: 0] internal_read_value;
    logic internal_read_value_ready;

    RAM_CONTROLLER_STATE ram_state;

    logic[3: 0] internal_chunk_part_index;
    logic[CHUNK_PART-1: 0] internal_output_value;
    
    logic internal_read_value_ready2;
    assign read_value_ready = internal_read_value_ready2;
    assign read_value = internal_output_value[31:0];

    initial begin
        controll_ui_clk_state = SYNC_CONTROLLER_ACTIVE_CONTROLL;
        controll_clk_state = SYNC_CONTROLLER_NOT_CONTOLL;
        
        internal_address = 0;
        internal_mask = 0;
        controller_ready = 1;
        internal_error = 0;
        internal_write_trigger = 0;
        internal_write_value = 0;
        internal_read_trigger = 0;
        internal_read_value = 0;
        internal_read_value_ready2 = 0;
        internal_read_value_ready = 0;
    end

    always_ff @(posedge clk) begin
        led0[1] <= mig_init_calib_complete;
        led0[0] <= !mig_init_calib_complete;
        led0[2] <= !controll_clk_state == SYNC_CONTROLLER_ACTIVE_CONTROLL;
        _controll_ui_clk_state <= controll_ui_clk_state;
        if (controll_clk_state == SYNC_CONTROLLER_ACTIVE_CONTROLL) begin
            controller_ready <= !(write_trigger || read_trigger) && (internal_error == 0);
            
            internal_read_value_ready2 <= internal_read_value_ready;
            internal_read_value_ready <= read_trigger;

            internal_address <= address;
            internal_mask <= mask;

            internal_write_trigger <= write_trigger;
            internal_write_value <= write_value;
            internal_read_trigger <= read_trigger;

            error <= internal_error;
            
            if (write_trigger || read_trigger) begin
                controll_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
            end
        end else if (
            controll_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL && 
            _controll_ui_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL
        ) begin
            controll_clk_state <= SYNC_CONTROLLER_NOT_CONTOLL;
        end else if (
            _controll_ui_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL &&
            controll_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin
            controll_clk_state <= SYNC_CONTROLLER_WILL_START_CONTROLL;
        end else if (
            controll_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL &&
            _controll_ui_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin 
            controll_clk_state <= SYNC_CONTROLLER_ACTIVE_CONTROLL;
        end
    end

    initial begin 
        ram_state = RAM_CONTROLLER_STATE_INIT;
        internal_mask = ~0;
        internal_chunk_part_index = 0;
    end

    assign mig_app_addr = internal_address;
    assign mig_app_wdf_mask = 16'b0000000000000000;
 
    always_ff @(posedge mig_ui_clk) begin
        _controll_clk_state <= controll_clk_state;

        if (controll_ui_clk_state == SYNC_CONTROLLER_ACTIVE_CONTROLL) begin
            if (ram_state == RAM_CONTROLLER_STATE_INIT) begin
                if (mig_init_calib_complete) begin
                    ram_state <= RAM_CONTROLLER_STATE_WATING;
                    controll_ui_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
                end
            end else if (ram_state == RAM_CONTROLLER_STATE_WATING) begin 
                if (mig_app_rdy && mig_init_calib_complete) begin

                    if (internal_read_trigger) begin
                        mig_app_en <= 1;
                        mig_app_cmd <= 1;
                        
                        ram_state <= RAM_CONTROLLER_STATE_READ;
                    end else if (internal_write_trigger) begin
                        mig_app_en <= 1;
                        mig_app_cmd <= 3'b000;

                        mig_app_wdf_data[31:0] <= internal_write_value;
                       
                        ram_state <= RAM_CONTROLLER_STATE_WRITE;
                    end else begin 
                        internal_error <= 1;
                        controll_ui_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
                    end
                end
            end else if (ram_state == RAM_CONTROLLER_STATE_READ) begin
                if (mig_app_rdy) begin
                    mig_app_en <= 0;
                end
                if (mig_app_rd_data_valid) begin
                    internal_output_value <= mig_app_rd_data[31:0];

                    ram_state <= RAM_CONTROLLER_STATE_WATING;
                    controll_ui_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
                end
            end else if (ram_state == RAM_CONTROLLER_STATE_WRITE) begin
                if (mig_app_rdy) begin
                    mig_app_en <= 0;
                end
                if (!mig_app_en && !mig_app_wdf_wren && mig_app_wdf_rdy) begin
                    mig_app_wdf_wren <= 1;
                    mig_app_wdf_end <= 1;
                end else if (mig_app_wdf_wren) begin
                    mig_app_wdf_wren <= 0;
                    mig_app_wdf_end <= 0;
                    ram_state <= RAM_CONTROLLER_STATE_WATING;
                    controll_ui_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
                end
            end
        end else if (
            controll_ui_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL && 
            _controll_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL
        ) begin
            mig_app_en <= 0;
            controll_ui_clk_state <= SYNC_CONTROLLER_NOT_CONTOLL;
        end else if (
            _controll_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL &&
            controll_ui_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin
            controll_ui_clk_state <= SYNC_CONTROLLER_WILL_START_CONTROLL;
        end else if (
            controll_ui_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL &&
            _controll_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin 
            controll_ui_clk_state <= SYNC_CONTROLLER_ACTIVE_CONTROLL;
        end
    end

endmodule