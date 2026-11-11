// MAX30102.h
// Ishita Raje
// iraje@hmc.edu
// 11/10/2026

#ifndef MAX30102_H
#define MAX30102_H

#include <stdint.h>
#include <stm32l432xx.h>  // CMSIS device library include

///////////////////////////////////////////////////////////////////////////////
// Definitions
///////////////////////////////////////////////////////////////////////////////

#define MAX30102_ADDR   0x57  // 7-bit I2C address

// Register addresses from the MAX30102 register map
#define FIFO_WR_PTR     0x04
#define OVF_COUNTER     0x05
#define FIFO_RD_PTR     0x06
#define FIFO_DATA       0x07
#define FIFO_CONFIG     0x08
#define MODE_CONFIG     0x09
#define SPO2_CONFIG     0x0A
#define LED1_PA         0x0C  // red LED current
#define LED2_PA         0x0D  // IR LED current
#define PART_ID         0xFF  // should read 0x15

///////////////////////////////////////////////////////////////////////////////
// Function prototypes
///////////////////////////////////////////////////////////////////////////////

int readPartID(void);
int initMAX30102(void);
int readPPG(uint32_t *red, uint32_t *ir, int maxSamples);

#endif
