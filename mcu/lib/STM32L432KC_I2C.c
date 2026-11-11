// STM32L432KC_I2C.c
// Ishita Raje
// iraje@hmc.edu
// 11/10/2026

#include "STM32L432KC_I2C.h"
#include "STM32L432KC_GPIO.h"

void initI2C(void) {

    RCC->CR |= RCC_CR_HSION; // turn on HSI16
    while(!(RCC->CR & RCC_CR_HSIRDY)); // wait until HSI16 is ready

    RCC->CCIPR &= ~RCC_CCIPR_I2C1SEL_Msk; // clear I2C1 clock select
    RCC->CCIPR |= (0b10 << RCC_CCIPR_I2C1SEL_Pos); // 10 = HSI16 is the I2C1 clock

    RCC->APB1ENR1 |= RCC_APB1ENR1_I2C1EN; // enable I2C1 clock
    I2C1->CR1 &= ~I2C_CR1_PE; // disable I2C1 so TIMINGR can be written

    GPIOA->AFR[1] &= ~GPIO_AFRH_AFSEL9_Msk; // clear PA9
    GPIOA->AFR[1] |= (0b0100 << GPIO_AFRH_AFSEL9_Pos); // PA9 AF4 is I2C1 SCL
    GPIOA->AFR[1] &= ~GPIO_AFRH_AFSEL10_Msk; // clear PA10
    GPIOA->AFR[1] |= (0b0100 << GPIO_AFRH_AFSEL10_Pos); // PA10 AF4 is I2C1 SDA

    pinMode(PA9, GPIO_ALT);
    pinMode(PA10, GPIO_ALT);
    GPIOA->PUPDR &= ~GPIO_PUPDR_PUPD9_Msk; // no internal pull-up (using external ones)
    GPIOA->PUPDR &= ~GPIO_PUPDR_PUPD10_Msk;
    GPIOA->OTYPER |= GPIO_OTYPER_OT9; // I2C lines must be open-drain
    GPIOA->OTYPER |= GPIO_OTYPER_OT10;

    I2C1->TIMINGR = I2C_TIMING_100KHZ; // 100 kHz bus speed
    I2C1->CR1 |= I2C_CR1_PE; // I2C enable
}

// Waits for a flag in I2C1->ISR. If the device sends a NACK instead, clears it and returns -1.
static int waitForFlag(uint32_t flag) {
    while(!(I2C1->ISR & flag)) {
        if (I2C1->ISR & I2C_ISR_NACKF) {
            I2C1->ICR = I2C_ICR_NACKCF; // clear NACK flag
            while(!(I2C1->ISR & I2C_ISR_STOPF)); // hardware sends STOP after a NACK
            I2C1->ICR = I2C_ICR_STOPCF; // clear STOP flag
            return -1;
        }
    }
    return 0;
}

int i2cWriteReg(uint8_t addr, uint8_t reg, uint8_t val) {
    while(I2C1->ISR & I2C_ISR_BUSY); // wait until the bus is free

    // START, write mode, 2 bytes (register + value), send STOP automatically at the end
    I2C1->CR2 = (addr << 1) | (2 << I2C_CR2_NBYTES_Pos) | I2C_CR2_AUTOEND | I2C_CR2_START;

    if (waitForFlag(I2C_ISR_TXIS)) return -1; // wait until ready to send
    I2C1->TXDR = reg; // send register address
    if (waitForFlag(I2C_ISR_TXIS)) return -1;
    I2C1->TXDR = val; // send value

    if (waitForFlag(I2C_ISR_STOPF)) return -1; // wait for STOP
    I2C1->ICR = I2C_ICR_STOPCF; // clear STOP flag
    return 0;
}

int i2cReadRegs(uint8_t addr, uint8_t reg, uint8_t *buf, uint8_t n) {
    while(I2C1->ISR & I2C_ISR_BUSY); // wait until the bus is free

    // First: START, write mode, 1 byte (register address), no STOP
    I2C1->CR2 = (addr << 1) | (1 << I2C_CR2_NBYTES_Pos) | I2C_CR2_START;

    if (waitForFlag(I2C_ISR_TXIS)) return -1;
    I2C1->TXDR = reg; // send register address
    if (waitForFlag(I2C_ISR_TC)) return -1; // wait until address byte is done

    // Then: repeated START, read mode, n bytes, send STOP automatically at the end
    I2C1->CR2 = (addr << 1) | I2C_CR2_RD_WRN | (n << I2C_CR2_NBYTES_Pos) | I2C_CR2_AUTOEND | I2C_CR2_START;

    for (int i = 0; i < n; i++) {
        if (waitForFlag(I2C_ISR_RXNE)) return -1; // wait for each byte
        buf[i] = I2C1->RXDR;
    }

    if (waitForFlag(I2C_ISR_STOPF)) return -1; // wait for STOP
    I2C1->ICR = I2C_ICR_STOPCF; // clear STOP flag
    return 0;
}
