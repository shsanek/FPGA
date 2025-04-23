module RAM_CONTROLLER #(
    parameter CHUNK_PART = 128,
    parameter ADDRESS_SIZE = 28,
    parameter CHUNK_COUNT = 4
)
(
    input wire clk,

    // COMMON
    output logic controller_ready,
    output logic[3:0] error,

    // WRITE
    input wire write_trigger,
    input wire[CHUNK_PART - 1: 0] write_value,
    input wire[ADDRESS_SIZE - 1:0] write_address,

    // READ
    input wire read_trigger,
    output wire[CHUNK_PART - 1: 0] read_value,
    input wire[ADDRESS_SIZE - 1:0] read_address,
    output wire read_value_ready,
    output logic[2:0] led0,

    // MIG INTERFACE
    output logic [ADDRESS_SIZE - 1:0]       mig_app_addr,
    output logic [2:0]                      mig_app_cmd,
    output logic                            mig_app_en,

    output logic [CHUNK_PART - 1:0]         mig_app_wdf_data,
    output logic                            mig_app_wdf_end,
    output wire [(CHUNK_PART / 8 - 1):0]    mig_app_wdf_mask,
    output logic                            mig_app_wdf_wren,
    input  wire                             mig_app_wdf_rdy,

    input  wire [CHUNK_PART - 1:0]          mig_app_rd_data,
    input  wire                             mig_app_rd_data_end,
    input  wire                             mig_app_rd_data_valid,

    input  wire                             mig_app_rdy,

    input  wire                             mig_ui_clk,
    input  wire                             mig_init_calib_complete
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
    
    SYNC_CONTROLLER_STATE controll_ui_clk_state;

    logic[ADDRESS_SIZE - 1:0] internal_write_address;
    logic[ADDRESS_SIZE - 1:0] internal_read_address;

    logic[3:0] internal_error;

    logic[CHUNK_PART - 1: 0] internal_write_value;
    logic internal_write_trigger;

    logic internal_read_trigger;
    logic[CHUNK_PART - 1: 0] internal_read_value;
    logic internal_read_value_ready;
    logic internal_read_value_ready2;

    assign read_value_ready =   internal_read_value_ready2;
    assign read_value =         internal_output_value;

    RAM_CONTROLLER_STATE ram_state;

    logic[CHUNK_PART - 1: 0] internal_output_value;

    initial begin
        controll_ui_clk_state = SYNC_CONTROLLER_ACTIVE_CONTROLL;
        controll_clk_state = SYNC_CONTROLLER_NOT_CONTOLL;
        
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


        if (controll_clk_state == SYNC_CONTROLLER_ACTIVE_CONTROLL) begin
            controller_ready <= !(write_trigger || read_trigger) && (internal_error == 0);
            
            internal_read_value_ready2 <= internal_read_value_ready;
            internal_read_value_ready <= read_trigger;
            internal_read_address <= read_address;

            internal_write_address <= write_address;
            internal_write_trigger <= write_trigger;
            internal_write_value <= write_value;
            internal_read_trigger <= read_trigger;

            error <= internal_error;
            
            if (write_trigger || read_trigger) begin
                controll_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
            end
        end else if (
            controll_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL && 
            controll_ui_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL
        ) begin
            controll_clk_state <= SYNC_CONTROLLER_NOT_CONTOLL;
        end else if (
            controll_ui_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL &&
            controll_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin
            controll_clk_state <= SYNC_CONTROLLER_WILL_START_CONTROLL;
        end else if (
            controll_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL &&
            controll_ui_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin 
            controll_clk_state <= SYNC_CONTROLLER_ACTIVE_CONTROLL;
        end
    end

    initial begin 
        ram_state = RAM_CONTROLLER_STATE_INIT;
        skip_write = 0;
        mig_app_wdf_wren = 0;
    end

    assign mig_app_wdf_mask = 16'b0000000000000000;
    logic skip_write;
 
    always_ff @(posedge mig_ui_clk) begin
        if (controll_ui_clk_state == SYNC_CONTROLLER_ACTIVE_CONTROLL) begin
            if (ram_state == RAM_CONTROLLER_STATE_INIT) begin
                if (mig_init_calib_complete) begin
                    ram_state <= RAM_CONTROLLER_STATE_WATING;
                    controll_ui_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
                end
            end else if (ram_state == RAM_CONTROLLER_STATE_WATING) begin 
                if (mig_app_rdy && mig_init_calib_complete) begin
                    if (internal_write_trigger && !skip_write) begin
                        mig_app_en <= 1;
                        mig_app_cmd <= 3'b000;
                        mig_app_addr <= internal_write_address;
                        mig_app_wdf_data <= internal_write_value;
                       
                        ram_state <= RAM_CONTROLLER_STATE_WRITE;
                    end else if (internal_read_trigger) begin
                        mig_app_en <= 1;
                        mig_app_cmd <= 1;
                        mig_app_addr <= internal_read_address;
                        ram_state <= RAM_CONTROLLER_STATE_READ;
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
                    internal_output_value <= mig_app_rd_data;
                    skip_write <= 0;

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
                    if (internal_read_trigger) begin
                        skip_write <= 1;
                    end else begin 
                        controll_ui_clk_state <= SYNC_CONTROLLER_WILL_STOP_CONTROLL;
                    end
                end
            end
        end else if (
            controll_ui_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL && 
            controll_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL
        ) begin
            mig_app_en <= 0;
            controll_ui_clk_state <= SYNC_CONTROLLER_NOT_CONTOLL;
        end else if (
            controll_clk_state == SYNC_CONTROLLER_WILL_STOP_CONTROLL &&
            controll_ui_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin
            controll_ui_clk_state <= SYNC_CONTROLLER_WILL_START_CONTROLL;
        end else if (
            controll_ui_clk_state == SYNC_CONTROLLER_WILL_START_CONTROLL &&
            controll_clk_state == SYNC_CONTROLLER_NOT_CONTOLL
        ) begin 
            controll_ui_clk_state <= SYNC_CONTROLLER_ACTIVE_CONTROLL;
        end
    end

endmodule