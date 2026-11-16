// spi_slave_tx.sv — FPGA SPI slave that shifts out a fixed-length frame.
//
// The STM32 is the master: it drives CS and SCLK. The FPGA only drives MISO.
//
// SPI mode 0 (CPOL=0, CPHA=0), the STM32 default:
//   - SCLK idles low
//   - the master SAMPLES MISO on the RISING edge
//   - so the slave must CHANGE MISO on the FALLING edge,
//     and the first bit (MSB) must already be on MISO when CS goes low.
//   The STM32 SPI1 setup must match: CPOL = 0, CPHA = 0, MSB first.
//
// SCLK and CS come from the STM32's clock domain, not the FPGA's 12 MHz clock,
// so they go through synchronizers (2 flops + 1 more to detect edges). That
// adds ~3 clk (~250 ns) of delay before MISO changes, which is fine as long as
// SCLK is slow: at 1 MHz the master samples 500 ns after the falling edge.
// Tested in sim: works up to 2 MHz, fails at 3 MHz. Use 1 MHz (2x margin).
//
// MOSI is not used: the frame only goes FPGA → MCU. The MCU sends dummy bytes.
module spi_slave_tx #(
    parameter int NBITS = 128            // 16 bytes
) (
    input  logic             clk,        // 12 MHz FPGA clock
    input  logic             rst_n,
    input  logic             sclk,       // from STM32 (async)
    input  logic             cs_n,       // from STM32 (async), active low
    output logic             miso,       // to STM32
    input  logic [NBITS-1:0] frame_in,   // frame to send, MSB (byte 0, bit 7) first
    output logic             load        // 1-cycle pulse, high on the SAME clock edge
                                         // that latches frame_in
);
    // Synchronizers: [0] and [1] are the 2-flop synchronizer, [2] is the
    // previous synchronized value, used to detect edges.
    logic [2:0] sclk_s, cs_s;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_s <= 3'b000;   // SCLK idles low
            cs_s   <= 3'b111;   // CS idles high
        end else begin
            sclk_s <= {sclk_s[1:0], sclk};
            cs_s   <= {cs_s[1:0],   cs_n};
        end
    end

    logic cs_fall, cs_active, sclk_fall;
    assign cs_fall   =  cs_s[2]   & ~cs_s[1];   // was high, now low
    assign cs_active = ~cs_s[1];
    assign sclk_fall =  sclk_s[2] & ~sclk_s[1]; // was high, now low

    logic [NBITS-1:0] shreg;

    // load is combinational so it lines up exactly with the latch edge.
    // (A registered load would arrive one cycle late, and a sample landing on
    // the latch cycle would get its new_sample flag wrongly cleared.)
    assign load = cs_fall;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shreg <= '0;
        end else begin
            if (cs_fall) begin
                // Snapshot the whole frame at once, so fields can't change
                // halfway through a transfer.
                shreg <= frame_in;
            end else if (cs_active && sclk_fall) begin
                // Master just sampled the current bit on the rising edge;
                // move the next bit onto MISO.
                shreg <= {shreg[NBITS-2:0], 1'b0};
            end
        end
    end

    assign miso = shreg[NBITS-1];
endmodule
