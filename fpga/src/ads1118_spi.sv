// ads1118_spi.sv — SPI master for the ADS1118, mode 1 (CPOL=0, CPHA=1).
//
// Mode 1: SCLK idles low. Both sides change data on the RISING edge and
// sample on the FALLING edge. So this master drives MOSI on rising edges
// and captures MISO on falling edges.
//
// One 16-bit transaction per `start` pulse:
//   CS low -> wait SETUP -> 16 SCLK cycles (shift CFG out, data in) -> CS high
//
// CFG = 0xC36B decodes as:
//   [15]    SS=1      start a single-shot conversion
//   [14:12] MUX=100   AIN0 vs GND
//   [11:9]  PGA=001   +/-4.096 V FS -> 1 LSB = 125 uV
//   [8]     MODE=1    single-shot / power-down
//   [7:5]   DR=011    64 SPS -> conversion ~15.6 ms, about half the 31.25 ms tick.
//                     (DR=32 SPS would take the whole 31.25 ms; with the
//                     ADC's +/-10% internal oscillator that can overrun.)
//   [4]     TS_MODE=0 ADC, not temp sensor
//   [3]     PULL_UP=1 pull-up on DOUT/DRDY
//   [2:1]   NOP=01    valid data, write config
//   [0]     1         reserved, always write 1
//
// Note the one-sample latency: each transaction starts a new conversion
// and reads the result of the PREVIOUS one. At 32 Hz that's a fixed 31.25 ms
// delay, which doesn't matter for GSR. It also means you never have to poll
// DRDY: the conversion finishes long before the next tick.
module ads1118_spi #(
    parameter logic [15:0] CFG   = 16'hC36B,
    parameter int          HALF  = 6,   // clk cycles per SCLK half-period: 12 MHz / (2*6) = 1 MHz
    parameter int          SETUP = 6    // CS-low to first SCLK edge (datasheet tCSSC >= 100 ns)
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,      // 1-cycle pulse (from tick_gen)
    output logic        cs_n,
    output logic        sclk,
    output logic        mosi,
    input  logic        miso,       // ADS1118 DOUT/DRDY
    output logic [15:0] data,       // last captured conversion (two's complement)
    output logic        data_valid, // 1-cycle pulse when `data` updates
    output logic        busy
);
    typedef enum logic [1:0] {IDLE, CS_SETUP, SHIFT, CS_HOLD} state_t;
    state_t state;

    logic [7:0]  div;      // half-period / setup counter
    logic [4:0]  nbits;    // falling edges seen so far
    logic [15:0] tx, rx;

    // Synchronize MISO into the clk domain. At 1 MHz SCLK and 12 MHz clk
    logic miso_s1, miso_s2;
    always_ff @(posedge clk) begin
        miso_s1 <= miso;
        miso_s2 <= miso_s1;
    end

    assign busy = (state != IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            cs_n       <= 1'b1;
            sclk       <= 1'b0;
            mosi       <= 1'b0;
            div        <= '0;
            nbits      <= '0;
            tx         <= '0;
            rx         <= '0;
            data       <= '0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;
            case (state)
                IDLE: begin
                    sclk <= 1'b0;
                    if (start) begin
                        cs_n  <= 1'b0;
                        tx    <= CFG;
                        div   <= '0;
                        nbits <= '0;
                        state <= CS_SETUP;
                    end
                end

                CS_SETUP: begin
                    if (div == SETUP - 1) begin
                        div   <= '0;
                        state <= SHIFT;
                    end else div <= div + 1'b1;
                end

                SHIFT: begin
                    if (div == HALF - 1) begin
                        div  <= '0;
                        sclk <= ~sclk;
                        if (!sclk) begin
                            // rising edge: put next config bit on MOSI (MSB first)
                            mosi <= tx[15];
                            tx   <= {tx[14:0], 1'b0};
                        end else begin
                            // falling edge: sample DOUT (MSB first).
                            // miso_s2 is the value from ~2 clk ago, i.e. well
                            // after the slave's rising-edge update settled.
                            rx    <= {rx[14:0], miso_s2};
                            nbits <= nbits + 1'b1;
                            if (nbits == 5'd15) state <= CS_HOLD;
                        end
                    end else div <= div + 1'b1;
                end

                CS_HOLD: begin
                    if (div == HALF - 1) begin
                        cs_n       <= 1'b1;
                        mosi       <= 1'b0;
                        data       <= rx;
                        data_valid <= 1'b1;
                        div        <= '0;
                        state      <= IDLE;
                    end else div <= div + 1'b1;
                end
            endcase
        end
    end
endmodule
