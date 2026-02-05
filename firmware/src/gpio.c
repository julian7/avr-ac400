#include "gpio.h"
#include <avr/io.h>

void gpio_init(void) {}

void gpio_dir_set(uint8_t pin, uint8_t out) {
  uint8_t port = PIN_TO_PORT(pin);
  uint8_t bit = PIN_TO_BIT(pin);
  volatile uint8_t *ddr = PORT_TO_DDR(port);
  if (out)
    *ddr |= (1 << bit);
  else
    *ddr &= ~(1 << bit);
}

uint8_t gpio_pin_read(uint8_t pin) {
  uint8_t port = PIN_TO_PORT(pin);
  uint8_t bit = PIN_TO_BIT(pin);
  volatile uint8_t *pinreg = PORT_TO_PIN(port);
  return ((*pinreg) & (1 << bit)) ? 1 : 0;
}

void gpio_set_input(uint8_t pin, uint8_t pullup) {
  gpio_dir_set(pin, 0);
  gpio_pin_write(pin, pullup ? 1 : 0);
}

uint8_t gpio_read(uint8_t pin) { return gpio_pin_read(pin); }

void gpio_pin_write(uint8_t pin, uint8_t v) {
  uint8_t port = PIN_TO_PORT(pin);
  uint8_t bit = PIN_TO_BIT(pin);
  volatile uint8_t *portreg = PORT_TO_REG(port);
  if (v)
    *portreg |= (1 << bit);
  else
    *portreg &= ~(1 << bit);
}

void gpio_set_output(uint8_t pin) { gpio_dir_set(pin, 1); }

void gpio_write(uint8_t pin, uint8_t v) { gpio_pin_write(pin, v); }
