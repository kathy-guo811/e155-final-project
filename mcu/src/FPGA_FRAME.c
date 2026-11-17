// FPGA_FRAME.c
// Kathy Guo
// 11/16/2026
//
// MCU side of the FPGA → MCU link (task 1E). See FPGA_FRAME.h for the
// frame layout, pins and SPI settings.

#include "FPGA_FRAME.h"
#include "STM32L432KC_GPIO.h"
#include "STM32L432KC_SPI.h"

// CS low → first SCLK edge. The FPGA needs ~250 ns to see CS fall and load the
// frame. This loop is a few microseconds at 80 MHz, which is plenty.
#define CS_SETUP_LOOPS 100

static void shortDelay(void) {
    for (volatile int i = 0; i < CS_SETUP_LOOPS; i++);
}

void initFPGALink(void) {
    // CS idles high (FPGA not selected)
    pinMode(FPGA_CS_PIN, GPIO_OUTPUT);
    digitalWrite(FPGA_CS_PIN, PIO_HIGH);

    // SPI1 master, mode 0 (CPOL = 0, CPHA = 0), MSB first, 8-bit
    initSPI(FPGA_SPI_BR, 0, 0);
}

void readFPGAFrame(uint8_t buf[FRAME_LEN]) {
    // Throw away anything left in the receive FIFO
    while (SPI1->SR & SPI_SR_RXNE) {
        (void) *(volatile uint8_t *) &SPI1->DR;
    }

    digitalWrite(FPGA_CS_PIN, PIO_LOW);   // FPGA loads the frame on this edge
    shortDelay();

    for (int i = 0; i < FRAME_LEN; i++) {
        buf[i] = spiSendReceive(0x00);    // dummy byte out, frame byte in
    }

    while (SPI1->SR & SPI_SR_BSY);        // last bit fully clocked
    digitalWrite(FPGA_CS_PIN, PIO_HIGH);
}

int parseFPGAFrame(const uint8_t buf[FRAME_LEN], GsrFrame *f) {
    if (buf[0] != FRAME_HEADER) return FRAME_BAD_HEADER;

    uint8_t checksum = 0;
    for (int i = 0; i < FRAME_LEN - 1; i++) checksum ^= buf[i];
    if (checksum != buf[FRAME_LEN - 1]) return FRAME_BAD_CHECKSUM;

    // Multi-byte fields are sent high byte first
    f->seq       = buf[1];
    f->raw       = (int16_t)  ((buf[2]  << 8) | buf[3]);
    f->filtered  = (int16_t)  ((buf[4]  << 8) | buf[5]);
    f->baseline  = (int16_t)  ((buf[6]  << 8) | buf[7]);
    f->delta     = (int16_t)  ((buf[8]  << 8) | buf[9]);
    f->status    = buf[10];
    f->scr_count = buf[11];
    f->scr_amp   = (uint16_t) ((buf[12] << 8) | buf[13]);
    return FRAME_OK;
}

void initFrameTimer(uint32_t period_ms) {
    // TIM2 counts at 10 kHz (0.1 ms per tick). Using our own prescaler here
    // because 80 MHz / 1 kHz = 80,000 does not fit in the 16-bit PSC register.
    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;
    TIM2->CR1 &= ~TIM_CR1_CEN;
    TIM2->PSC  = (SystemCoreClock / 10000) - 1;   // 7999 at 80 MHz
    TIM2->ARR  = period_ms * 10 - 1;              // 99 for 10 ms
    TIM2->CNT  = 0;
    TIM2->EGR |= TIM_EGR_UG;                      // load PSC/ARR now
    TIM2->SR  &= ~TIM_SR_UIF;
    TIM2->CR1 |= TIM_CR1_CEN;
}

void waitFramePeriod(void) {
    while (!(TIM2->SR & TIM_SR_UIF));
    TIM2->SR &= ~TIM_SR_UIF;
}
