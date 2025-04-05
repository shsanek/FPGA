module VALUE_STORAGE_TEST();
    logic clk;

    logic[3:0] buttons;

    logic io_input_trigger;
    logic[7:0] io_input_value;

    logic io_read_ready_trigger; 

    wire[7:0] io_output_value;
    wire io_output_trigger;

    logic[3:0] leds;

    int error = 0;

    VALUE_STORAGE dut (
        .clk(clk),
        .buttons(buttons),
        .io_input_trigger(io_input_trigger),
        .io_input_value(io_input_value),
        .io_read_ready_trigger(io_read_ready_trigger),
        .io_output_value(io_output_value),
        .io_output_trigger(io_output_trigger),
        .leds(leds)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("VALUE_STORAGE.vcd");
        $dumpvars(0, VALUE_STORAGE_TEST);

        #5


        buttons = 4'd0;

        io_input_trigger = 1'b0;
        io_input_value = 8'd0;

        io_read_ready_trigger = 1'b1;

        #10
        assert(io_output_value ===  8'd0 && io_output_trigger === 1'b0) else error = error + 1;

        buttons = 4'b0001;
        #20
        assert(io_output_value ===  8'd1 && io_output_trigger === 1'b0) else error = error + 1;

        buttons = 4'b0000;
        #10
        assert(io_output_value ===  8'd1 && io_output_trigger === 1'b0) else error = error + 1;

        buttons = 4'b0010;
        #20
        assert(io_output_value ===  8'd2 && io_output_trigger === 1'b0) else error = error + 1;

        buttons = 4'b0000;
        #10
        assert(io_output_value ===  8'd2 && io_output_trigger === 1'b0) else error = error + 1;

        buttons = 4'b0100;
        #10
        assert(io_output_value ===  8'd0 && io_output_trigger === 1'b0) else error = error + 1;

        buttons = 4'b0001;
        #10
        assert(io_output_value ===  8'd0 && io_output_trigger === 1'b0) else error = error + 1;

        buttons = 4'b0000;
        #10
        assert(io_output_value ===  8'd0 && io_output_trigger === 1'b0) else error = error + 1;

        io_input_trigger = 1'b1;
        io_input_value = 8'd22;
        #10
        assert(io_output_value ===  8'd22 && io_output_trigger === 1'b0) else error = error + 1;

        io_input_trigger = 1'b0;
        io_input_value = 8'd40;
        #10
        assert(io_output_value ===  8'd22 && io_output_trigger === 1'b0) else error = error + 1;

        buttons = 4'b1000;
        io_read_ready_trigger = 1'b0;
        #10
        assert(io_output_value ===  8'd22 && io_output_trigger === 1'b1) else error = error + 1;

        buttons = 4'b0000;
        #10
        assert(io_output_value ===  8'd22 && io_output_trigger === 1'b0) else error = error + 1;

        buttons = 4'b0010;
        #20
        assert(io_output_value ===  8'd22 && io_output_trigger === 1'b0) else error = error + 1;

        io_read_ready_trigger = 1'b1;
        #10
        assert(io_output_value ===  8'd22 && io_output_trigger === 1'b0) else error = error + 1;

        buttons = 4'b0000;
        #10
        assert(io_output_value ===  8'd22 && io_output_trigger === 1'b0) else error = error + 1;

        buttons = 4'b0100;
        #10
        assert(io_output_value ===  8'd0 && io_output_trigger === 1'b0) else error = error + 1;

        #10
        if(error == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED with %0d errors", error);
            
        $finish;
    end

endmodule
