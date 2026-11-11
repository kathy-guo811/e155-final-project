/*
File: main.c
Author: Ishita Raje
Email: iraje@hmc.edu
Date: 11/10/2026

MAX30102 bring-up test.
  No sensor connected: should print "No ACK" (NACK visible on logic analyzer).
  Sensor connected: should print PART_ID = 0x15, then stream red,ir samples.
*/

#include <stdio.h>
#include "main.h"
#include "STM32L432KC_I2C.h"
#include "MAX30102.h"

int main(void) {
  configureFlash();
  configureClock();

  gpioEnable(GPIO_PORT_A);
  gpioEnable(GPIO_PORT_B);

  initI2C();

  uint32_t red[MAX_SAMPLES];
  uint32_t ir[MAX_SAMPLES];

  int id = readPartID();
  if (id < 0) {
    printf("No ACK from MAX30102\n");
    while(1);
  }
  printf("PART_ID = 0x%02X (expect 0x15)\n", id);

  if (initMAX30102()) {
    printf("MAX30102 init failed\n");
    while(1);
  }
  printf("MAX30102 configured: SpO2 mode, 100 samples/s\n");

  while(1) {
    // only prints when the sensor has new samples (100 per second)
    int n = readPPG(red, ir, MAX_SAMPLES);
    for (int i = 0; i < n; i++) {
      printf("%lu,%lu\n", red[i], ir[i]); // CSV format for plotting
    }
  }
}
