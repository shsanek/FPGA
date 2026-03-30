// TIMER_DEVICE — счётчик тактов и времени с момента запуска
//
// Адресная карта (внутри слота 0x803_0000):
//   0x0  CYCLE_LO   (R)  — нижние 32 бита счётчика тактов
//   0x4  CYCLE_HI   (R)  — верхние 32 бита счётчика тактов
//   0x8  TIME_MS    (R)  — миллисекунды с момента запуска (32 бита, ~49 дней)
//   0xC  TIME_US_LO (R)  — микросекунды с момента запуска, нижние 32 бита
//
// Атомарное чтение: при чтении CYCLE_LO верхняя часть защёлкивается в snapshot.
module TIMER_DEVICE #(
    parameter CLOCK_FREQ = 81_250_000
)(
    input  wire        clk,
    input  wire        reset,

    input  wire [27:0] address,
    input  wire        read_trigger,

    output reg  [31:0] read_value,
    output wire        controller_ready,
    output reg         read_valid
);

    // read_pending: 1 cycle read latency
    reg read_pending;

    assign controller_ready = !read_pending;

    // 64-битный счётчик тактов
    logic [63:0] cycle_count;

    always_ff @(posedge clk) begin
        if (reset)
            cycle_count <= 64'd0;
        else
            cycle_count <= cycle_count + 64'd1;
    end

    // Snapshot верхних 32 бит — защёлкивается при чтении CYCLE_LO
    logic [31:0] cycle_hi_snapshot;

    // Миллисекунды
    localparam CYCLES_PER_MS = CLOCK_FREQ / 1000;
    logic [31:0] ms_counter;
    logic [31:0] ms_divider;

    always_ff @(posedge clk) begin
        if (reset) begin
            ms_counter <= 32'd0;
            ms_divider <= 32'd0;
        end else begin
            if (ms_divider >= CYCLES_PER_MS - 1) begin
                ms_divider <= 32'd0;
                ms_counter <= ms_counter + 32'd1;
            end else begin
                ms_divider <= ms_divider + 32'd1;
            end
        end
    end

    // Микросекунды
    localparam CYCLES_PER_US = CLOCK_FREQ / 1_000_000;
    logic [31:0] us_counter;
    logic [31:0] us_divider;

    always_ff @(posedge clk) begin
        if (reset) begin
            us_counter <= 32'd0;
            us_divider <= 32'd0;
        end else begin
            if (us_divider >= CYCLES_PER_US - 1) begin
                us_divider <= 32'd0;
                us_counter <= us_counter + 32'd1;
            end else begin
                us_divider <= us_divider + 32'd1;
            end
        end
    end

    // Read pipeline: latch data + snapshot, then pulse read_valid
    always_ff @(posedge clk) begin
        if (reset) begin
            read_pending <= 0;
            read_valid   <= 0;
            read_value   <= 32'd0;
        end else begin
            read_valid <= 0;

            if (read_trigger && !read_pending) begin
                read_pending <= 1;
                // Latch value and snapshot
                case (address[3:0])
                    4'h0: begin
                        read_value <= cycle_count[31:0];
                        cycle_hi_snapshot <= cycle_count[63:32];
                    end
                    4'h4:    read_value <= cycle_hi_snapshot;
                    4'h8:    read_value <= ms_counter;
                    4'hC:    read_value <= us_counter;
                    default: read_value <= 32'd0;
                endcase
            end

            if (read_pending) begin
                read_valid   <= 1;
                read_pending <= 0;
            end
        end
    end

endmodule
