// FPGA_FRAME.h
// Kathy Guo
// 11/16/2026
//
// MCU side of the FPGA → MCU link (task 1E).
//
// The STM32 is the SPI master. Every 10 ms it pulls CS low, clocks out 16
// dummy bytes on SPI1 and keeps the 16 bytes the FPGA sends back on MISO.
//
// SPI settings (must match fpga/src/spi_slave_tx.sv):
//   SPI1, master, mode 0 (CPOL = 0, CPHA = 0), MSB first, 8-bit transfers
//   SCLK = 80 MHz / 64 = 1.25 MHz  (FPGA slave tested in sim up to 2 MHz)
//   Software chip select on PA11
//
// Pins:
//   PA5  SPI1 SCK   → FPGA sclk (P26 via SW7 switch 3)
//   PA6  SPI1 MISO  ← FPGA miso (P27 via SW7 switch 4)
//   PB5  SPI1 MOSI  (configured by initSPI but not connected; FPGA ignores it)
//   PA11 GPIO       → FPGA cs_n (P20 via SW7 switch 5)
//
// Frame layout (byte 0 first, multi-byte fields high byte first):
//   0      header       0b10100101
//   1      seq          +1 every frame the FPGA sends
//   2-3    raw          ADC code (signed)
//   4-5    filtered     IIR output (signed)
//   6-7    baseline     (signed)
//   8-9    delta        filtered - baseline (signed)
//   10     status       bit 0 new_sample, bit 1 scr_active
//   11     scr_count
//   12-13  scr_amp
//   14     reserved (0)
//   15     checksum     XOR of bytes 0-14

#ifndef FPGA_FRAME_H
#define FPGA_FRAME_H

#include <stdint.h>
#include <stm32l432xx.h>

///////////////////////////////////////////////////////////////////////////////
// Constants
///////////////////////////////////////////////////////////////////////////////

#define FRAME_LEN           16
#define FRAME_HEADER        0b10100101

#define STATUS_NEW_SAMPLE   (1 << 0)
#define STATUS_SCR_ACTIVE   (1 << 1)

#define FPGA_CS_PIN         PA11
#define FPGA_SPI_BR         0b101   // SCLK = 80 MHz / 2^(5+1) = 1.25 MHz

// parseFPGAFrame() return codes
#define FRAME_OK            0
#define FRAME_BAD_HEADER    1
#define FRAME_BAD_CHECKSUM  2

///////////////////////////////////////////////////////////////////////////////
// Types
///////////////////////////////////////////////////////////////////////////////

typedef struct {
    uint8_t  seq;
    int16_t  raw;
    int16_t  filtered;
    int16_t  baseline;
    int16_t  delta;
    uint8_t  status;
    uint8_t  scr_count;
    uint16_t scr_amp;
} GsrFrame;

///////////////////////////////////////////////////////////////////////////////
// Function prototypes
///////////////////////////////////////////////////////////////////////////////

/* Sets up SPI1 in mode 0 at 1.25 MHz and the CS pin (idle high).
 * Call after configureClock() and gpioEnable() for ports A and B. */
void initFPGALink(void);

/* Reads one 16-byte frame from the FPGA into buf (byte 0 = header). */
void readFPGAFrame(uint8_t buf[FRAME_LEN]);

/* Checks header and checksum, then unpacks buf into *f.
 * Returns FRAME_OK, FRAME_BAD_HEADER or FRAME_BAD_CHECKSUM.
 * *f is only filled in when the frame is OK. */
int parseFPGAFrame(const uint8_t buf[FRAME_LEN], GsrFrame *f);

/* Starts TIM2 so that waitFramePeriod() returns once every period_ms. */
void initFrameTimer(uint32_t period_ms);

/* Blocks until the next frame period starts (polls TIM2's update flag). */
void waitFramePeriod(void);

#endif