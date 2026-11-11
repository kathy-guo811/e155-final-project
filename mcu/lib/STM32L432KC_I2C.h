// STM32L432KC_I2C.h
// Ishita Raje
// iraje@hmc.edu
// 11/10/2026

#ifndef STM32L4_I2C_H
#define STM32L4_I2C_H

#include <stdint.h>
#include <stm32l432xx.h>

///////////////////////////////////////////////////////////////////////////////
// Definitions
///////////////////////////////////////////////////////////////////////////////

// TIMINGR value for 100 kHz with a 16 MHz I2C clock (HSI16), from RM0394 Table 182:
// PRESC = 3, SCLDEL = 0x4, SDADEL = 0x2, SCLH = 0x0F, SCLL = 0x13
#define I2C_TIMING_100KHZ 0x30420F13

///////////////////////////////////////////////////////////////////////////////
// Function prototypes
///////////////////////////////////////////////////////////////////////////////

/* Enables I2C1 as a master at 100 kHz on PA9 (SCL) and PA10 (SDA).
 * Uses HSI16 as the I2C clock so the timing does not depend on the system clock.
 * GPIO port A must already be enabled with gpioEnable(GPIO_PORT_A).
 * External pull-up resistors to 3.3 V are needed on both lines. */
void initI2C(void);

/* Writes one byte to a register of an I2C device.
 *    -- addr: 7-bit device address
 *    -- reg: register address to write
 *    -- val: byte to write
 *    -- return: 0 if successful, -1 if the device did not respond (NACK) */
int i2cWriteReg(uint8_t addr, uint8_t reg, uint8_t val);

/* Reads n bytes from an I2C device, starting at register reg.
 *    -- addr: 7-bit device address
 *    -- reg: first register address to read
 *    -- buf: array to store the received bytes
 *    -- n: number of bytes to read
 *    -- return: 0 if successful, -1 if the device did not respond (NACK) */
int i2cReadRegs(uint8_t addr, uint8_t reg, uint8_t *buf, uint8_t n);

#endif
