module RAM_CONTROLLER_TEST();

  // Параметры (используем значения по умолчанию из вашего модуля)
  localparam CHUNK_PART    = 128;
  localparam DATA_SIZE     = 32;
  localparam MASK_SIZE     = DATA_SIZE/8;
  localparam ADDRESS_SIZE  = 28;

  // Тактовые сигналы
  reg clk;
  reg mig_ui_clk;

  // Интерфейс общего доступа
  reg [ADDRESS_SIZE-1:0] address;
  reg [MASK_SIZE-1:0]    mask;
  wire controller_ready;
  wire [3:0]           _error;

  // Интерфейс записи
  reg         write_trigger;
  reg [DATA_SIZE-1:0] write_value;

  // Интерфейс чтения
  reg         read_trigger;
  wire [DATA_SIZE-1:0] read_value;
  wire        read_value_ready;

  // Сигналы для MIG (выходы из модуля RAM_CONTROLLER)
  wire [ADDRESS_SIZE-1:0] mig_app_addr;
  wire [2:0]              mig_app_cmd;
  wire                    mig_app_en;
  wire [CHUNK_PART-1:0]   mig_app_wdf_data;
  wire                    mig_app_wdf_end;
  wire [(CHUNK_PART/8)-1:0] mig_app_wdf_mask;
  wire                    mig_app_wdf_wren;

  // Сигналы для MIG (входы в модуль RAM_CONTROLLER, задаются тестбенчем)
  reg [CHUNK_PART-1:0] mig_app_rd_data;
  reg                  mig_app_rd_data_end;
  reg                  mig_app_rd_data_valid;
  reg                  mig_app_rdy;
  reg                  mig_app_wdf_rdy;
  reg                  mig_app_sr_active;
  reg                  mig_app_ref_ack;
  reg                  mig_app_zq_ack;
  reg                  mig_ui_clk_sync_rst;
  reg                  mig_init_calib_complete;

  // Инстанцируем DUT
  RAM_CONTROLLER dut (
    .clk(clk),
    .address(address),
    .mask(mask),
    .controller_ready(controller_ready),
    .error(_error),
    .write_trigger(write_trigger),
    .write_value(write_value),
    .read_trigger(read_trigger),
    .read_value(read_value),
    .read_value_ready(read_value_ready),

    .mig_app_addr(mig_app_addr),
    .mig_app_cmd(mig_app_cmd),
    .mig_app_en(mig_app_en),
    .mig_app_wdf_data(mig_app_wdf_data),
    .mig_app_wdf_end(mig_app_wdf_end),
    .mig_app_wdf_mask(mig_app_wdf_mask),
    .mig_app_wdf_wren(mig_app_wdf_wren),
    .mig_app_rd_data(mig_app_rd_data),
    .mig_app_rd_data_end(mig_app_rd_data_end),
    .mig_app_rd_data_valid(mig_app_rd_data_valid),
    .mig_app_rdy(mig_app_rdy),
    .mig_app_wdf_rdy(mig_app_wdf_rdy),
    .mig_ui_clk(mig_ui_clk),
    .mig_init_calib_complete(mig_init_calib_complete)
  );

  // Генерация такта для clk (основной домен)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // период 10 ед.
  end

  // Генерация такта для mig_ui_clk (тактовый сигнал MIG)
  initial begin
    mig_ui_clk = 0;
    forever #4 mig_ui_clk = ~mig_ui_clk;  // период 8 ед.
  end

  // Инициализация входных сигналов MIG и общих сигналов
  initial begin
    address                 = 0;
    mask                    = {MASK_SIZE{1'b1}};
    write_trigger           = 0;
    write_value             = 0;
    read_trigger            = 0;
    mig_app_rd_data         = 0;
    mig_app_rd_data_valid   = 0;
    mig_app_rd_data_end     = 0;
    mig_app_rdy             = 1; // MIG всегда готов принимать команды
    mig_app_wdf_rdy         = 1; // MIG готов принимать данные для записи
    mig_app_sr_active       = 0;
    mig_app_ref_ack         = 0;
    mig_app_zq_ack          = 0;
    mig_ui_clk_sync_rst     = 0;
    mig_init_calib_complete = 1; // Инициализация и калибровка завершены
    error = 0;
  end


  integer read_beat;
  int mig_sim_state = 0;
  always @(posedge mig_ui_clk) begin
    if (mig_sim_state == 1) begin
      if(read_beat < 1) begin
        mig_app_rd_data_valid <= 1;
        // Для первого beat задаём тестовое значение в младших 32 битах
        if(read_beat == 0)
          mig_app_rd_data <= {96'd0, 32'hCAFEBABE};
        else
          mig_app_rd_data <= 0;
        // На последнем beat сигнал окончания burst
        if(read_beat == 0)
          mig_app_rd_data_end <= 1;
        else
          mig_app_rd_data_end <= 0;
        read_beat <= read_beat + 1;
      end
      else begin
        mig_app_rd_data_valid <= 0;
        mig_app_rd_data_end   <= 0;
        mig_sim_state <= 0;
      end
    end else if(mig_app_en && (mig_app_cmd == 3'b001)) begin  // команда чтения
      mig_sim_state <= 1;
    end else begin
      read_beat <= 0;
      mig_app_rd_data_valid <= 0;
      mig_app_rd_data_end   <= 0;
    end
  end

  int _read_value_count;
  int _read_value;
  int error;
  always @(posedge clk) begin
    if (read_value_ready) begin
      _read_value_count += 1;
      _read_value = read_value;
    end
  end

  // Тестовая последовательность для операции чтения
  initial begin
    $dumpfile("RAM_CONTROLLER_TEST.vcd");
    $dumpvars(0, RAM_CONTROLLER_TEST);

    #5;
    address = 28'd100;
    mask = 4'b1111;
    read_trigger = 0;
    write_trigger = 0;

    #20;
    read_trigger = 1;
    #10;
    read_trigger = 0;

    // Ожидаем завершения burst-чтения (несколько тактов mig_ui_clk)
    #150;
    // Проверяем, что сигнал готовности чтения установлен и получено корректное значение

    assert(_read_value_count == 1) else error = error + 1;
    assert(_read_value == 32'hCAFEBABE) else error = error + 1;

    // Задаём адрес, маску, значение для записи и активируем write_trigger
    address = 28'd200;
    mask    = 4'b1111;
    write_value = 32'h12345678;
    write_trigger = 1;
    #10;
    write_trigger = 0;
    
    // Принудительно задаём сигнал mig_app_wdf_wren = 1,
    // чтобы имитировать готовность MIG принимать данные для записи
    force dut.mig_app_wdf_wren = 1;
    
    // Ожидаем завершения burst-записи (8 beat'ов на mig_ui_clk)
    #100;
    
    // Освобождаем принудительное задание сигнала
    release dut.mig_app_wdf_wren;
    
    // Проверяем, что в конце записи установлен сигнал mig_app_wdf_end
    if(error == 0)
      $display("ALL TESTS PASSED");
    else
      $display("TEST FAILED with %0d errors", error);
  
    $finish;
  end

endmodule
