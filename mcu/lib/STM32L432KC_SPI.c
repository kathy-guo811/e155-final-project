// STM32L432KC_SPI.c
// Ishita Raje
// iraje@hmc.edu
// 10/30/2026

#include "STM32L432KC_SPI.h"
#include "STM32L432KC_GPIO.h"

void initSPI(int br, int cpol, int cpha) {

    RCC->APB2ENR |= RCC_APB2ENR_SPI1EN; //enable SPI clock
    SPI1->CR1 &= ~SPI_CR1_SPE_Msk; //clear SPE
    GPIOA->AFR[0] &= ~GPIO_AFRL_AFSEL5_Msk; //clear PA5
    GPIOA->AFR[0] |= (0b0101 << GPIO_AFRL_AFSEL5_Pos); //PA5 AF5 is SPI clock
    GPIOA->AFR[0] &= ~GPIO_AFRL_AFSEL6_Msk; //clear PA6
    GPIOA->AFR[0] |= (0b0101 << GPIO_AFRL_AFSEL6_Pos); //PA6 AF5 is SPI MISO
    GPIOB->AFR[0] &= ~GPIO_AFRL_AFSEL5_Msk; //clear PB5
    GPIOB->AFR[0] |= (0b0101 << GPIO_AFRL_AFSEL5_Pos); //PB5 AF5 is SPI MOSI

    pinMode(PA5, GPIO_ALT);
    pinMode(PA6, GPIO_ALT);
    pinMode(PB5, GPIO_ALT);

    SPI1->CR1 |= SPI_CR1_MSTR;  //master configuration
    SPI1->CR1 &= ~SPI_CR1_BR_Msk; // clear existing baud rate field
    SPI1->CR1 |= (br << SPI_CR1_BR_Pos);  // set br using input

    SPI1->CR1 &= ~SPI_CR1_CPHA_Msk; // clear existing clock phase
    SPI1->CR1 &= ~SPI_CR1_CPOL_Msk; // clear existing clock polarity
    SPI1->CR2 &= ~SPI_CR2_DS_Msk; // clear existing data size 
    SPI1->CR1 |= _VAL2FLD(SPI_CR1_CPHA, cpha);  //clock phase
    SPI1->CR1 |= _VAL2FLD(SPI_CR1_CPOL, cpol);  // clock polarity 
    SPI1->CR2 |= _VAL2FLD(SPI_CR2_DS, 0b0111);  // data size set yp 8-bit frame

    SPI1->CR1 |= SPI_CR1_SSM; // software slave management
    SPI1->CR1 |= SPI_CR1_SSI; // internal slave select
    
    SPI1->CR2 |= SPI_CR2_FRXTH;  //flag that goes to 1 when at least 8-bits avaliable 
    SPI1->CR1 |= SPI_CR1_SPE; //SPI enable
}

uint8_t spiSendReceive(uint8_t send) {
    while(!(SPI1->SR & SPI_SR_TXE)); // Wait until the transmit buffer is empty
    *(volatile int8_t *) (&SPI1->DR) = send; // Transmit the character over SPI
    while(!(SPI1->SR & SPI_SR_RXNE)); // Wait until data has been received
    uint8_t rec = *(volatile uint8_t *) (&SPI1->DR);
    return rec; // Return received character
}