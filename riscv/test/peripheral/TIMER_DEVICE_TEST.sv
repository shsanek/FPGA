module TIMER_DEVICE_TEST();
    logic        clk, reset;
    logic [27:0] address;
    logic        read_trigger;
    wire  [31:0] read_value;
    wire         controller_ready;

    int error = 0;

    TIMER_DEVICE #(.CLOCK_FREQ(100_000)) dut (
        .clk              (clk),
        .reset            (reset),
        .address          (address),
        .read_trigger     (read_trigger),
        .read_value       (read_value),
        .controller_ready (controller_ready)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    task read_reg(input [3:0] offset, output [31:0] val);
        @(posedge clk);
        address = {24'd0, offset};
        read_trigger = 1;
        @(posedge clk);
        read_trigger = 0;
        #1;
        val = read_value;
    endtask

    reg [31:0] cyc_lo, cyc_hi, ms, us_lo, cyc_lo2;

    initial begin
        $dumpfile("TIMER_DEVICE_TEST.vcd");
        $dumpvars(0, TIMER_DEVICE_TEST);

        reset = 1; read_trigger = 0; address = 0;
        #20; reset = 0;

        // controller_ready должен быть 1
        assert(controller_ready === 1'b1) else begin
            $display("FAIL: controller_ready != 1");
            error++;
        end

        // Прогоним 200 тактов (~2 мс при CLOCK_FREQ=100)
        repeat(200) @(posedge clk);

        // Читаем CYCLE_LO
        read_reg(4'h0, cyc_lo);
        $display("CYCLE_LO = %0d", cyc_lo);
        assert(cyc_lo > 200) else begin
            $display("FAIL: cycle_lo too small: %0d", cyc_lo);
            error++;
        end

        // CYCLE_HI (snapshot)
        read_reg(4'h4, cyc_hi);
        $display("CYCLE_HI = %0d", cyc_hi);
        assert(cyc_hi === 32'd0) else begin
            $display("FAIL: cycle_hi should be 0 at this point");
            error++;
        end

        // TIME_MS — при CLOCK_FREQ=100, 100 cycles = 1ms, 200+ cycles = 2+ ms
        read_reg(4'h8, ms);
        $display("TIME_MS  = %0d", ms);
        assert(ms >= 2) else begin
            $display("FAIL: ms too small: %0d", ms);
            error++;
        end

        // TIME_US
        read_reg(4'hC, us_lo);
        $display("TIME_US  = %0d", us_lo);

        // Проверяем что счётчик растёт
        repeat(50) @(posedge clk);
        read_reg(4'h0, cyc_lo2);
        assert(cyc_lo2 > cyc_lo) else begin
            $display("FAIL: counter not incrementing");
            error++;
        end
        $display("CYCLE_LO after 50 more clocks = %0d (delta=%0d)", cyc_lo2, cyc_lo2 - cyc_lo);

        if (error == 0)
            $display("ALL TIMER TESTS PASSED");
        else
            $display("TIMER TEST FAILED with %0d errors", error);
        $finish;
    end
endmodule
