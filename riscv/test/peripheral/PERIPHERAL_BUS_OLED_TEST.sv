module PERIPHERAL_BUS_OLED_TEST();
    reg [28:0] address;
    reg read_trigger = 0, write_trigger = 0;
    reg [31:0] write_value = 0;
    reg [3:0] mask = 4'hF;

    wire [31:0] read_value;
    wire controller_ready;

    // MC stub
    wire [27:0] mc_address;
    wire mc_read_trigger, mc_write_trigger;
    wire [31:0] mc_write_value;
    wire [3:0] mc_mask;
    reg [31:0] mc_read_value = 32'hAAAA_AAAA;
    reg mc_controller_ready = 1;

    // UART stub
    wire [27:0] io_address;
    wire io_read_trigger, io_write_trigger;
    wire [31:0] io_write_value;
    wire [3:0] io_mask;
    reg [31:0] io_read_value = 32'hBBBB_BBBB;
    reg io_controller_ready = 1;

    // OLED stub
    wire [27:0] oled_address;
    wire oled_read_trigger, oled_write_trigger;
    wire [31:0] oled_write_value;
    wire [3:0] oled_mask;
    reg [31:0] oled_read_value = 32'hCCCC_CCCC;
    reg oled_controller_ready = 1;

    PERIPHERAL_BUS dut (
        .address(address),
        .read_trigger(read_trigger),
        .write_trigger(write_trigger),
        .write_value(write_value),
        .mask(mask),
        .read_value(read_value),
        .controller_ready(controller_ready),

        .mc_address(mc_address),
        .mc_read_trigger(mc_read_trigger),
        .mc_write_trigger(mc_write_trigger),
        .mc_write_value(mc_write_value),
        .mc_mask(mc_mask),
        .mc_read_value(mc_read_value),
        .mc_controller_ready(mc_controller_ready),

        .io_address(io_address),
        .io_read_trigger(io_read_trigger),
        .io_write_trigger(io_write_trigger),
        .io_write_value(io_write_value),
        .io_mask(io_mask),
        .io_read_value(io_read_value),
        .io_controller_ready(io_controller_ready),

        .oled_address(oled_address),
        .oled_read_trigger(oled_read_trigger),
        .oled_write_trigger(oled_write_trigger),
        .oled_write_value(oled_write_value),
        .oled_mask(oled_mask),
        .oled_read_value(oled_read_value),
        .oled_controller_ready(oled_controller_ready)
    );

    integer errors = 0;

    initial begin
        // T1: Memory (addr[28]=0)
        address = 29'h0000000; read_trigger = 1; #1;
        if (mc_read_trigger !== 1 || io_read_trigger !== 0 || oled_read_trigger !== 0 ||
            read_value !== 32'hAAAAAAAA || controller_ready !== 1) begin
            $display("T1 FAIL: MC routing"); errors=errors+1;
        end else $display("T1 PASS: MC routing");
        read_trigger = 0;

        // T2: MC not ready propagates
        mc_controller_ready = 0; address = 29'h0000010; #1;
        if (controller_ready !== 0) begin $display("T2 FAIL: MC not ready"); errors=errors+1; end
        else $display("T2 PASS: MC not ready");
        mc_controller_ready = 1;

        // T3: UART (addr[28]=1, addr[16]=0)
        address = 29'h10000000; read_trigger = 1; #1;
        if (mc_read_trigger !== 0 || io_read_trigger !== 1 || oled_read_trigger !== 0 ||
            read_value !== 32'hBBBBBBBB || controller_ready !== 1) begin
            $display("T3 FAIL: UART routing"); errors=errors+1;
        end else $display("T3 PASS: UART routing");
        read_trigger = 0;

        // T4: OLED (addr[28]=1, addr[16]=1)
        address = 29'h10010000; read_trigger = 1; #1;
        if (mc_read_trigger !== 0 || io_read_trigger !== 0 || oled_read_trigger !== 1 ||
            read_value !== 32'hCCCCCCCC || controller_ready !== 1) begin
            $display("T4 FAIL: OLED routing"); errors=errors+1;
        end else $display("T4 PASS: OLED routing");
        read_trigger = 0;

        // T5: OLED not ready doesn't affect MC
        oled_controller_ready = 0; address = 29'h0000000; #1;
        if (controller_ready !== 1) begin $display("T5 FAIL: MC should be ready"); errors=errors+1; end
        else $display("T5 PASS: MC ready while OLED busy");
        oled_controller_ready = 1;

        // T6: UART not ready doesn't affect OLED
        io_controller_ready = 0; address = 29'h10010000; #1;
        if (controller_ready !== 1) begin $display("T6 FAIL: OLED should be ready"); errors=errors+1; end
        else $display("T6 PASS: OLED ready while UART busy");
        io_controller_ready = 1;

        // T7: Write trigger routing to MC
        address = 29'h0000100; write_trigger = 1; #1;
        if (mc_write_trigger !== 1 || io_write_trigger !== 0 || oled_write_trigger !== 0) begin
            $display("T7 FAIL: MC write"); errors=errors+1;
        end else $display("T7 PASS: MC write routing");
        write_trigger = 0;

        // T8: Write trigger routing to OLED
        address = 29'h10010004; write_trigger = 1; #1;
        if (mc_write_trigger !== 0 || io_write_trigger !== 0 || oled_write_trigger !== 1) begin
            $display("T8 FAIL: OLED write"); errors=errors+1;
        end else $display("T8 PASS: OLED write routing");
        write_trigger = 0;

        #1;
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d TESTS FAILED", errors);
        $finish;
    end
endmodule
