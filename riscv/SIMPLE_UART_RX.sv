// Simple reliable UART RX receiver.
// 2-FF synchronizer + oversample at BIT_PERIOD, sample at mid-bit.
// Produces 1-cycle pulse on rx_valid with rx_data.
module SIMPLE_UART_RX #(
    parameter CLOCK_FREQ = 81_250_000,
    parameter BAUD_RATE  = 115_200
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       rx,           // raw UART RX pin

    output reg  [7:0] rx_data,
    output reg        rx_valid      // 1-cycle pulse
);
    localparam BIT_PERIOD = CLOCK_FREQ / BAUD_RATE;
    localparam HALF_BIT   = BIT_PERIOD / 2;
    localparam CTR_BITS   = $clog2(BIT_PERIOD + 1);

    // 2-FF synchronizer
    reg rx_s1, rx_s2;
    always @(posedge clk) begin
        rx_s1 <= rx;
        rx_s2 <= rx_s1;
    end

    // State
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]          state;
    reg [CTR_BITS-1:0] counter;
    reg [2:0]          bit_idx;
    reg [7:0]          shift;

    always @(posedge clk) begin
        if (reset) begin
            state    <= S_IDLE;
            counter  <= 0;
            bit_idx  <= 0;
            shift    <= 0;
            rx_data  <= 0;
            rx_valid <= 0;
        end else begin
            rx_valid <= 0;

            case (state)
                S_IDLE: begin
                    if (rx_s2 == 0) begin
                        // Start bit detected, wait half bit to sample mid-start
                        counter <= HALF_BIT - 1;
                        state   <= S_START;
                    end
                end

                S_START: begin
                    if (counter == 0) begin
                        if (rx_s2 == 0) begin
                            // Valid start bit at mid-point, start receiving data
                            counter <= BIT_PERIOD - 1;
                            bit_idx <= 0;
                            state   <= S_DATA;
                        end else begin
                            // False start, go back to idle
                            state <= S_IDLE;
                        end
                    end else begin
                        counter <= counter - 1;
                    end
                end

                S_DATA: begin
                    if (counter == 0) begin
                        shift[bit_idx] <= rx_s2;  // LSB first
                        if (bit_idx == 7) begin
                            counter <= BIT_PERIOD - 1;
                            state   <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                            counter <= BIT_PERIOD - 1;
                        end
                    end else begin
                        counter <= counter - 1;
                    end
                end

                S_STOP: begin
                    if (counter == 0) begin
                        if (rx_s2 == 1) begin
                            // Valid stop bit
                            rx_data  <= shift;
                            rx_valid <= 1;
                        end
                        // Either way, return to idle
                        state <= S_IDLE;
                    end else begin
                        counter <= counter - 1;
                    end
                end
            endcase
        end
    end

endmodule
