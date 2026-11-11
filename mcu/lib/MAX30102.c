// MAX30102.c
// Ishita Raje
// iraje@hmc.edu
// 11/10/2026

#include "MAX30102.h"
#include "STM32L432KC_I2C.h"

// Returns the PART_ID register (should be 0x15), or -1 if the sensor did not respond
int readPartID(void) {
    uint8_t id;
    if (i2cReadRegs(MAX30102_ADDR, PART_ID, &id, 1)) return -1;
    return id;
}

// Resets the sensor and sets SpO2 mode (red + IR), 100 samples/s, 18-bit.
// Returns 0 if successful, -1 if the sensor did not respond.
int initMAX30102(void) {
    uint8_t mode;

    if (i2cWriteReg(MAX30102_ADDR, MODE_CONFIG, 0x40)) return -1; // RESET bit
    do {
        if (i2cReadRegs(MAX30102_ADDR, MODE_CONFIG, &mode, 1)) return -1;
    } while (mode & 0x40); // RESET bit clears itself when done

    // no averaging (000), FIFO rollover on (1), almost-full = 0 (0000)
    if (i2cWriteReg(MAX30102_ADDR, FIFO_CONFIG, 0x10)) return -1;

    // ADC range 4096 nA (01), 100 samples/s (001), 411 us pulse = 18-bit (11) -> 0b0010_0111
    if (i2cWriteReg(MAX30102_ADDR, SPO2_CONFIG, 0x27)) return -1;

    // LED currents: 0x24 is about 7 mA. Raise if signal is small, lower if it maxes out
    if (i2cWriteReg(MAX30102_ADDR, LED1_PA, 0x24)) return -1;
    if (i2cWriteReg(MAX30102_ADDR, LED2_PA, 0x24)) return -1;

    // clear FIFO pointers so the FIFO starts empty
    if (i2cWriteReg(MAX30102_ADDR, FIFO_WR_PTR, 0x00)) return -1;
    if (i2cWriteReg(MAX30102_ADDR, OVF_COUNTER, 0x00)) return -1;
    if (i2cWriteReg(MAX30102_ADDR, FIFO_RD_PTR, 0x00)) return -1;

    // SpO2 mode (011): red and IR both on. Sampling starts here.
    if (i2cWriteReg(MAX30102_ADDR, MODE_CONFIG, 0x03)) return -1;

    return 0;
}

// Reads all samples waiting in the FIFO (up to maxSamples) into red[] and ir[].
// Returns the number of samples read, or -1 if the sensor did not respond.
int readPPG(uint32_t *red, uint32_t *ir, int maxSamples) {
    uint8_t wr, rd;
    uint8_t data[6];

    if (i2cReadRegs(MAX30102_ADDR, FIFO_WR_PTR, &wr, 1)) return -1;
    if (i2cReadRegs(MAX30102_ADDR, FIFO_RD_PTR, &rd, 1)) return -1;

    // pointers are 5 bits (0-31) and wrap around, so mask the difference
    int numSamples = (wr - rd) & 0x1F;
    if (numSamples > maxSamples) numSamples = maxSamples;

    for (int i = 0; i < numSamples; i++) {
        // one sample = 6 bytes: red (3 bytes) then IR (3 bytes), MSB first
        if (i2cReadRegs(MAX30102_ADDR, FIFO_DATA, data, 6)) return -1;

        // combine 3 bytes and keep the 18 data bits
        red[i] = (((uint32_t)data[0] << 16) | ((uint32_t)data[1] << 8) | data[2]) & 0x3FFFF;
        ir[i]  = (((uint32_t)data[3] << 16) | ((uint32_t)data[4] << 8) | data[5]) & 0x3FFFF;
    }
    return numSamples;
}
