module REG_tb();

    logic clk=0;
    logic reset_trigger;
    logic write_trigger;
    logic [7:0] value;
    logic [7:0] current_value;

    int error=0;

    bf_register dut(clk, reset_trigger, write_trigger, value, current_value); // device under test i.e. the gate we want to test

    initial begin
        $dumpfile("reg.vcd");
        $dumpvars(0, REG_tb);
            
        reset_trigger=0; write_trigger=1; value = 8'b100; #10;
        assert(current_value===8'b100) else error=1;
            
        reset_trigger=0; write_trigger=0; value = 8'b110; #10;
        assert(current_value===8'b100) else error=1;
        
        reset_trigger=1; write_trigger=0; value = 8'b100; #10;
        assert(current_value===8'b0) else error=1;
            
        reset_trigger=0; write_trigger=1; value = 8'b100; #10;
        assert(current_value===8'b100) else error=1;
    end

    initial begin
        for (int i = 0; i < 60; i = i + 1) begin
            #5 clk = ~clk;
        end
    end
    
endmodule

module NAND_tb();

    logic a, b, y;
    int error=0;

    NAND dut(a, b, y); // device under test i.e. the gate we want to test

    initial begin
        $dumpfile("nand.vcd");
        $dumpvars(0, NAND_tb);
            
        a=0; b=0;   #10;
        assert(y===1) else error=1;
            
        b=1;        #10;
        assert(y===1) else error=1;
            
        a=1; b=0;   #10;
        assert(y===1) else error=1;
            
        b=1;        #10;
        assert(y===0) else error=1;
    end
    
    always@(a, b, y, error) begin
        if(!error) begin 
            $display("Time=%Dt inputs:a=%b\t b=%b\t output:y=%b", $time, a, b, y);            
        end else begin
            $error("Test fail at time=%Dt inputs:a=%b\t b=%b\t output:y=%b", $time, a, b, y);
            error=0;      
        end
    end
    
endmodule

module bf_command_runner_tb();

    // Объявление сигналов для тестирования
    logic clk = 0;
    logic run_trigger;
    logic [2:0] current_command;
    logic [7:0] current_value;
    logic [15:0] command_addr;
    logic [15:0] cell_addr;
    logic [7:0] new_value;
    logic        write_trigger;
    
    int error = 0;

    // Инстанцирование устройства под тестированием (DUT)
    bf_command_runner dut(
        .clk(clk),
        .run_trigger(run_trigger),
        .current_command(current_command),
        .current_value(current_value),
        .command_addr(command_addr),
        .cell_addr(cell_addr),
        .new_value(new_value),
        .write_trigger(write_trigger)
    );
    
    // Тестовая последовательность
    initial begin
        $dumpfile("bf_command_runner.vcd");
        $dumpvars(0, bf_command_runner_tb);
        
        // Начальная инициализация сигналов
        run_trigger = 0;
        current_command = 3'b000;
        current_value = 8'd0;
        #10;
        
        // Тест 1: Команда 3'b000 (инкремент значения)
        // Ожидается: new_value = current_value + 1, write_trigger = 1
        run_trigger = 1;
        current_command = 3'b000;
        current_value = 8'd10;
        #10;
        assert(new_value === 16'd11) else begin
            $display("Ошибка: для 3'b000 ожидалось new_value = 11, получено %0d", new_value);
            error = error + 1;
        end
        assert(write_trigger === 1) else begin
            $display("Ошибка: для 3'b000 ожидалось write_trigger = 1, получено %0d", write_trigger);
            error = error + 1;
        end
        
        // Тест 2: Команда 3'b001 (декремент значения)
        // Ожидается: new_value = current_value - 1, write_trigger = 1
        current_command = 3'b001;
        current_value = 8'd20;
        #10;
        assert(new_value === 16'd19) else begin
            $display("Ошибка: для 3'b001 ожидалось new_value = 19, получено %0d", new_value);
            error = error + 1;
        end
        assert(write_trigger === 1) else begin
            $display("Ошибка: для 3'b001 ожидалось write_trigger = 1, получено %0d", write_trigger);
            error = error + 1;
        end
        
        // Тест 3: Команда 3'b010 (переход, если значение равно 0)
        // Ожидается: переход в состояние SEARCH_NEXT, запись не инициируется (write_trigger = 0)
        current_command = 3'b010;
        current_value = 8'd0;
        #10;
        assert(write_trigger === 0) else begin
            $display("Ошибка: для 3'b010 ожидалось write_trigger = 0, получено %0d", write_trigger);
            error = error + 1;
        end
        
        // Тест 4: Команда 3'b011 (переход назад, если значение не равно 0)
        // Ожидается: переход в состояние SEARCH_BACK, запись не инициируется (write_trigger = 0)
        current_command = 3'b011;
        current_value = 8'd5;
        #10;
        assert(write_trigger === 0) else begin
            $display("Ошибка: для 3'b011 ожидалось write_trigger = 0, получено %0d", write_trigger);
            error = error + 1;
        end
        
        // Тест 5: Команда 3'b100 (сдвиг адреса ячейки вправо)
        // Ожидается: увеличение cell_addr
        current_command = 3'b100;
        #10;
        assert(cell_addr === 16'd1) else begin
            $display("Ошибка: для 3'b100 ожидалось cell_addr = 1, получено %0d", cell_addr);
            error = error + 1;
        end
        
        // Тест 6: Команда 3'b101 (сдвиг адреса ячейки влево)
        // Ожидается: уменьшение cell_addr
        current_command = 3'b101;
        #10;
        assert(cell_addr === 16'd0) else begin
            $display("Ошибка: для 3'b101 ожидалось cell_addr = 0, получено %0d", cell_addr);
            error = error + 1;
        end
        
        if(error == 0) begin
            $display("Все тесты пройдены успешно.");
        end else begin
            $display("Обнаружено %0d ошибок.", error);
        end
        $finish;
    end

    // Генерация тактового сигнала: переключение каждые 5 единиц времени
    always begin
        #5 clk = ~clk;
    end

endmodule
