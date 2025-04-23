module RAM_CONTROLLER_TEST();

  // Параметры
  localparam CHUNK_PART   = 128;
  localparam ADDRESS_SIZE = 28;

  // Тактовые сигналы
  reg clk;
  reg mig_ui_clk;

  // Интерфейс контроллера
  wire                    controller_ready;
  wire [3:0]              error;
  wire [2:0]              led0;

  // Интерфейс записи
  reg                     write_trigger;
  reg  [CHUNK_PART-1:0]   write_value;
  reg  [ADDRESS_SIZE-1:0] write_address;

  // Интерфейс чтения
  reg                     read_trigger;
  reg  [ADDRESS_SIZE-1:0] read_address;
  wire [CHUNK_PART-1:0]   read_value;
  wire                    read_value_ready;

  // Сигналы MIG
  wire [ADDRESS_SIZE-1:0]    mig_app_addr;
  wire [2:0]                 mig_app_cmd;
  wire                       mig_app_en;
  wire [CHUNK_PART-1:0]      mig_app_wdf_data;
  wire                       mig_app_wdf_end;
  wire [(CHUNK_PART/8)-1:0]  mig_app_wdf_mask;
  wire                       mig_app_wdf_wren;

  reg                        mig_app_wdf_rdy;
  reg  [CHUNK_PART-1:0]      mig_app_rd_data;
  reg                        mig_app_rd_data_valid;
  reg                        mig_app_rd_data_end;
  reg                        mig_app_rdy;
  reg                        mig_init_calib_complete;

  // Сборники результатов
  integer                    read_count;
  reg  [CHUNK_PART-1:0]      read_captured;
  integer                    write_count;
  reg  [CHUNK_PART-1:0]      write_captured;
  reg                         test_error;

  // Инстанцируем DUT
  RAM_CONTROLLER #(
    .CHUNK_PART(CHUNK_PART),
    .ADDRESS_SIZE(ADDRESS_SIZE)
  ) dut (
    .clk(clk),
    // COMMON
    .controller_ready(controller_ready),
    .error(error),
    // WRITE
    .write_trigger(write_trigger),
    .write_value(write_value),
    .write_address(write_address),
    // READ
    .read_trigger(read_trigger),
    .read_value(read_value),
    .read_address(read_address),
    .read_value_ready(read_value_ready),
    .led0(led0),
    // MIG
    .mig_app_addr(mig_app_addr),
    .mig_app_cmd(mig_app_cmd),
    .mig_app_en(mig_app_en),
    .mig_app_wdf_data(mig_app_wdf_data),
    .mig_app_wdf_end(mig_app_wdf_end),
    .mig_app_wdf_mask(mig_app_wdf_mask),
    .mig_app_wdf_wren(mig_app_wdf_wren),
    .mig_app_wdf_rdy(mig_app_wdf_rdy),
    .mig_app_rd_data(mig_app_rd_data),
    .mig_app_rd_data_end(mig_app_rd_data_end),
    .mig_app_rd_data_valid(mig_app_rd_data_valid),
    .mig_app_rdy(mig_app_rdy),
    .mig_ui_clk(mig_ui_clk),
    .mig_init_calib_complete(mig_init_calib_complete)
  );

  // Генерация тактов
  initial begin clk = 0; forever #5 clk = ~clk; end
  initial begin mig_ui_clk = 0; forever #4 mig_ui_clk = ~mig_ui_clk; end

  // Инициализация сигналов
  initial begin
    write_trigger           = 0;
    write_value             = {CHUNK_PART{1'b0}};
    write_address           = 0;
    read_trigger            = 0;
    read_address            = 0;

    mig_app_wdf_rdy         = 1;
    mig_app_rd_data         = 0;
    mig_app_rd_data_valid   = 0;
    mig_app_rd_data_end     = 0;
    mig_app_rdy             = 1;
    mig_init_calib_complete = 1;

    read_count   = 0;
    write_count  = 0;
    test_error   = 0;
  end

  // Эмуляция реакции MIG на burst-чтение одного такта
  reg mig_read_busy;
  reg mig_write_busy;
  integer read_beat;
  integer write_beat;
  always @(posedge mig_ui_clk) begin
// --- Burst-чтение ---
    if (mig_read_busy) begin
      mig_app_rd_data       <= 128'h0123456789ABCDEF_FEDCBA9876543210;
      mig_app_rd_data_valid <= 1;
      mig_app_rd_data_end   <= 1;
      mig_read_busy         <= 0;
    end else if (mig_app_en && mig_app_cmd == 3'b001) begin
      mig_read_busy <= 1;
    end else begin
      mig_app_rd_data_valid <= 0;
      mig_app_rd_data_end   <= 0;
    end

    if (mig_write_busy) begin
      mig_app_wdf_rdy <= 1;
      if (mig_app_wdf_wren == 1) begin
        mig_write_busy <= 0;
      end
    end else if (mig_app_en && mig_app_cmd == 3'b000) begin
      mig_write_busy <= 1;
      mig_app_wdf_rdy <= 0;
    end else begin
      mig_app_wdf_rdy <= 0;
    end
  end

  always @(posedge clk) begin
    if (read_value_ready) begin
      read_count    <= read_count + 1;
      read_captured <= read_value;
    end
  end

  // Захват данных, посылаемых на запись, в домене mig_ui_clk
  always @(posedge mig_ui_clk) begin
    if (mig_app_wdf_wren && mig_app_wdf_end) begin
      write_count    <= write_count + 1;
      write_captured <= mig_app_wdf_data;
    end
  end

  // Основной тест
  initial begin
    $dumpfile("RAM_CONTROLLER_TEST.vcd");
    $dumpvars(0, RAM_CONTROLLER_TEST);

    // --- ТЕСТ ЧТЕНИЯ ---
    #65;
    read_address = 28'd42;
    read_trigger = 1;
    #10;
    read_trigger = 0;
    // ждём реакции
    #200;
    if (read_count != 1)             test_error = 1;
    if (read_captured != 128'h0123456789ABCDEF_FEDCBA9876543210) test_error = 1;

    // --- ТЕСТ ЗАПИСИ ---
    #20;
    write_address = 28'd84;
    write_value   = 128'hDEADBEEF_DEADBEEF_FEEDFACE_FEEDFACE;
    write_trigger = 1;
    #10;
    write_trigger = 0;

    #200;
    if (write_count != 1)            test_error = 1;
    if (write_captured != 128'hDEADBEEF_DEADBEEF_FEEDFACE_FEEDFACE) test_error = 1;

    // --- Итог ---
    if (!test_error)
      $display("ALL 128-BIT TESTS PASSED");
    else
      $display("128-BIT TESTS FAILED");

    $finish;
  end

endmodule
