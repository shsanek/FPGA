// Minimal UART test: sends 'H' once per second + echoes received bytes
// Use this to verify UART TX/RX pins work
module UART_LOOPBACK_TEST (
    input  wire        sys_clk_i,
    output wire        uart_tx,
    input  wire        uart_rx,
    output wire [3:0]  led
);

    wire clk;
    wire locked;

    // Use clk_wiz for consistent clock
    clk_wiz_0 u_clk_wiz (
        .clk_in1  (sys_clk_i),
        .clk_out1 (),
        .clk_out2 (clk),       // 81.25 MHz
        .clk_out3 (),
        .locked   (locked),
        .reset    (1'b0)
    );

    wire reset = ~locked;

    // UART TX - simple shift register
    localparam BIT_PERIOD = 81_250_000 / 115_200;  // ~705

    reg [9:0]  tx_shift;       // start + 8 data + stop
    reg [9:0]  tx_timer;
    reg [3:0]  tx_bit_cnt;
    reg        tx_busy;
    reg        tx_out;

    // Heartbeat counter - send 'H' every ~1 second
    reg [26:0] sec_cnt;
    reg        send_trigger;

    // RX byte counter for LED
    reg [7:0]  rx_byte_cnt;

    assign uart_tx = tx_out;
    assign led[0] = sec_cnt[25];    // heartbeat
    assign led[1] = locked;
    assign led[2] = tx_busy;
    assign led[3] = uart_rx;        // raw RX line (should be HIGH idle)

    always @(posedge clk) begin
        if (reset) begin
            tx_shift <= 10'h3FF;
            tx_timer <= 0;
            tx_bit_cnt <= 0;
            tx_busy <= 0;
            tx_out <= 1;
            sec_cnt <= 0;
            send_trigger <= 0;
            rx_byte_cnt <= 0;
        end else begin
            send_trigger <= 0;
            sec_cnt <= sec_cnt + 1;

            // Trigger every ~1 second
            if (sec_cnt == 27'd81_250_000) begin
                sec_cnt <= 0;
                if (!tx_busy)
                    send_trigger <= 1;
            end

            // TX state machine
            if (send_trigger && !tx_busy) begin
                tx_shift <= {1'b1, 8'h48, 1'b0}; // stop + 'H' + start
                tx_timer <= BIT_PERIOD;
                tx_bit_cnt <= 10;
                tx_busy <= 1;
                tx_out <= 0; // start bit
            end else if (tx_busy) begin
                if (tx_timer == 0) begin
                    tx_timer <= BIT_PERIOD;
                    tx_out <= tx_shift[0];
                    tx_shift <= {1'b1, tx_shift[9:1]};
                    tx_bit_cnt <= tx_bit_cnt - 1;
                    if (tx_bit_cnt == 0) begin
                        tx_busy <= 0;
                        tx_out <= 1;
                    end
                end else begin
                    tx_timer <= tx_timer - 1;
                end
            end
        end
    end

endmodule
