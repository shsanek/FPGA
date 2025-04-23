module CHUNK_STORAGE_4_POOL_TEST;

  // Параметры
  localparam CHUNK_PART    = 128;
  localparam DATA_SIZE     = 32;
  localparam MASK_SIZE     = DATA_SIZE/8;
  localparam ADDRESS_SIZE  = 28;

  // Тактовый сигнал
  reg clk;
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Интерфейсы DUT
  reg  [ADDRESS_SIZE-1:0] address;
  reg  [MASK_SIZE-1:0]    mask;
  reg                     write_trigger;
  reg  [DATA_SIZE-1:0]    write_value;
  reg                     read_trigger;
  wire                    contains_address;
  wire [DATA_SIZE-1:0]    read_value;

  reg  [ADDRESS_SIZE-1:0] command_address;
  wire                    contains_command_address;
  wire [DATA_SIZE-1:0]    read_command;

  wire [ADDRESS_SIZE-1:0] save_address;
  wire [CHUNK_PART-1:0]   save_data;
  wire                    save_need_flag;

  wire [15:0]             order_index;

  reg  [CHUNK_PART-1:0]   new_data;
  reg  [ADDRESS_SIZE-1:0] new_address;
  reg                     new_data_save;

  // Счётчик ошибок
  int error = 0;

  // Ожидаемый вектор данных после маскированной записи
  logic [CHUNK_PART-1:0] expected_data;

  // Инстанцируем обёртку
  CHUNK_STORAGE_4_POOL #(
    .CHUNK_PART   (CHUNK_PART),
    .DATA_SIZE    (DATA_SIZE),
    .MASK_SIZE    (MASK_SIZE),
    .ADDRESS_SIZE (ADDRESS_SIZE)
  ) dut (
    .clk                      (clk),
    .address                  (address),
    .mask                     (mask),
    .write_trigger            (write_trigger),
    .write_value              (write_value),
    .command_address          (command_address),
    .read_command             (read_command),
    .contains_command_address (contains_command_address),
    .read_trigger             (read_trigger),
    .read_value               (read_value),
    .contains_address         (contains_address),
    .save_address             (save_address),
    .save_data                (save_data),
    .save_need_flag           (save_need_flag),
    .order_index              (order_index),
    .new_data                 (new_data),
    .new_address              (new_address),
    .new_data_save            (new_data_save)
  );

  initial begin
    $dumpfile("CHUNK_STORAGE_4_POOL_TEST.vcd");
    $dumpvars(0, CHUNK_STORAGE_4_POOL_TEST);
    @(posedge clk);

    // --- 1) Инициализация ---
    address       = 0;
    mask          = {MASK_SIZE{1'b1}};
    write_trigger = 0;
    write_value   = 0;
    read_trigger  = 0;
    command_address = 0;
    new_data      = 0;
    new_address   = 0;
    new_data_save = 0;
    #0;

    // --- 2) Загрузка нового чанка ---
    new_address   = 28'h0A5000F;
    new_data      = {
      32'hDEAD_BEEF,
      32'hCAFE_BABE,
      32'h1234_5678,
      32'h8765_4321
    };
    new_data_save = 1;
    #10;
    new_data_save = 0;
    #10;

    // --- 2) Загрузка нового чанка ---
    new_address   = 28'h0A50020;
    new_data      = {
      32'h12345678,
      32'h12345678,
      32'h12345678,
      32'h12345678
    };
    new_data_save = 1;
    #10;
    new_data_save = 0;
    #10;

    new_address   = 28'h0A50040;
    new_data      = {
      32'hDEAD_BEEF,
      32'hCAFE_BABE,
      32'h1234_5678,
      32'h8765_4321
    };
    new_data_save = 1;
    #10;
    new_data_save = 0;
    #10;

    new_address   = 28'h0A50060;
    new_data      = {
      32'h12345678,
      32'h12345678,
      32'h12345678,
      32'h12345678
    };
    new_data_save = 1;
    #10;
    new_data_save = 0;
    #10;

    new_address   = 28'h0A50060;
    new_data_save = 1;
    #10;
    new_data_save = 0;
    #10;

    new_address   = 28'h0A50060;
    new_data_save = 1;
    #10;
    new_data_save = 0;
    #10;

    new_address   = 28'h0A50060;
    new_data_save = 1;
    #10;
    new_data_save = 0;
    #10;

    new_address   = 28'h0A50060;
    new_data_save = 1;
    #10;
    new_data_save = 0;
    #10;

    if (save_need_flag !== 1'b0)                      error = error + 1;
    #10;
    if (save_address !== {new_address[27:4],4'b0000}) error = error + 2;
    #10;
    if (save_data !== new_data)               error = error + 3;
    #10;


    // --- 3) Чтение без изменений ---
    address      = {new_address[27:4],4'b0000};
    read_trigger = 1;
    #10;
    read_trigger = 0;
    #10;

    if (contains_address      !== 1'b1)               error = error + 1;
    if (read_value            !== 32'h12345678)       error = error + 1;

    command_address = {new_address[27:4],4'b1000};
    #10;

    if (contains_command_address !== 1'b1)  error = error + 1;
    if (read_command !== 32'h12345678)     error = error + 1;

    // --- 4) Маскированная запись в слово с индексом 1 ---
    address       = {new_address[27:4],4'b0100};
    mask          = 4'b0101;         // обновить байты 0 и 2
    write_value   = 32'hA1B2_C3D4;
    write_trigger = 1;
    #10;
    write_trigger = 0;
    #10;

    if (save_need_flag !== 1'b1)                      error = error + 1;
    if (save_address   !== {new_address[27:4],4'b0000}) error = error + 1;

    // Формируем ожидаемый 128‑битный вектор {d3,d2,d1,d0}
    expected_data = {
      32'h12345678,    // chunk_data3
      32'h12345678,    // chunk_data2
      32'h12B256D4,    // chunk_data1 после маскированной записи
      32'h12345678     // chunk_data0
    };
    if (save_data !== expected_data)                  error = error + 1;

    // --- Итоговый отчёт ---
    if (error == 0)
      $display("ALL TESTS PASSED");
    else
      $display("TEST FAILED with %0d errors", error);

    $finish;
  end

endmodule
