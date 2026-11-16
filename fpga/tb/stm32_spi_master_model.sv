// stm32_spi_master_model.sv — fake STM32 SPI1 master, simulation only.
//
// Every FRAME_PERIOD it does what the real MCU code will do:
//   CS low → 128 SCLK cycles in SPI mode 0 (sample MISO on the rising edge,
//   MSB first) → CS high.
// The received 128 bits are left in `rx`, and `n_frames` counts up by 1 when
// each frame is complete, so the testbench can check it.
`timescale 1ns/1ps
module stm32_spi_master_model #(
    parameter real SCLK_HALF_NS   = 500.0,      // 1 MHz SCLK
    parameter real CS_SETUP_NS    = 2000.0,     // CS low → first SCLK (STM32 software CS is slow)
    parameter real FRAME_PERIOD_NS = 200_000.0, // real MCU: 10 ms; shortened for sim
    parameter int  NBITS          = 128
) (
    output logic             cs_n,
    output logic             sclk,
    input  logic             miso,
    output logic [NBITS-1:0] rx,
    output int               n_frames
);
    initial begin
        cs_n     = 1'b1;
        sclk     = 1'b0;
        rx       = '0;
        n_frames = 0;
        #(FRAME_PERIOD_NS / 3);              // start a bit after reset
        forever begin
            cs_n = 1'b0;
            #(CS_SETUP_NS);
            for (int i = 0; i < NBITS; i++) begin
                sclk = 1'b1;
                rx   = {rx[NBITS-2:0], miso};  // mode 0: sample on rising edge
                #(SCLK_HALF_NS);
                sclk = 1'b0;                   // slave changes MISO after this
                #(SCLK_HALF_NS);
            end
            #(CS_SETUP_NS);
            cs_n     = 1'b1;
            n_frames = n_frames + 1;
            #(FRAME_PERIOD_NS - 2*CS_SETUP_NS - 2*NBITS*SCLK_HALF_NS);
        end
    end
endmodule
