`timescale 1ns/1ps
// gsr_buffer.sv — circular buffer of raw GSR samples in block RAM (EBR).
//
// Every `we` pulse (data_valid from ads1118_spi) writes one 16-bit sample at
// wptr and advances wptr. With AW = 10 that is 1024 samples = 32 s at 32 Hz.
//
// - wptr is AW bits wide, so 1023 + 1 rolls over to 0 by itself.
//   No compare logic is needed to wrap.
// - The read is registered (rdata updates on the clock edge AFTER raddr is
//   set). That matches the iCE40 EBR's read port, so Radiant can put the
//   array in block RAM instead of building it out of LUTs.
// - The memory itself has no reset (EBR can't be cleared in one cycle).
//   Only wptr is reset. Old contents are just overwritten as data comes in.
// - wptr is an output so a reader can find recent samples:
//   the newest sample is at wptr - 1, the one before that at wptr - 2, etc.
module gsr_buffer #(
    parameter int AW = 10              // address bits: depth = 2^AW
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          we,          // 1-cycle write pulse (data_valid)
    input  logic [15:0]   wdata,       // sample to store (ADS1118 code)
    input  logic [AW-1:0] raddr,       // address to read
    output logic [15:0]   rdata,       // mem[raddr], one clock later
    output logic [AW-1:0] wptr         // next address to be written
);
    logic [15:0] mem [0:(1<<AW)-1];

    // Memory: write port and registered read port. No reset here.
    always_ff @(posedge clk) begin
        if (we) mem[wptr] <= wdata;
        rdata <= mem[raddr];
    end

    // Write pointer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)  wptr <= '0;
        else if (we) wptr <= wptr + 1'b1;
    end
endmodule
