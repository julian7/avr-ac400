#ifndef DRV_GPIO_H
#define DRV_GPIO_H
#include <avr/io.h>
#include <stdint.h>

/*
 * Pin mapping helpers used by gpio.c
 * Pins encoded as: (port << 3) | bit
 */

/* Port identifiers */
#define PORT_B 0
#define PORT_C 1
#define PORT_D 2

/* Pin encoding helpers */
#define PIN_ENCODE(port, bit) (((port) << 3) | ((bit) & 0x7))
#define PIN_TO_PORT(p) (((p) >> 3) & 0x03)
#define PIN_TO_BIT(p) ((p) & 0x07)

/* Register mapping helpers */
#define PORT_TO_DDR(port)                                                      \
  ((port) == PORT_B ? &DDRB : (port) == PORT_C ? &DDRC : &DDRD)
#define PORT_TO_REG(port)                                                      \
  ((port) == PORT_B ? &PORTB : (port) == PORT_C ? &PORTC : &PORTD)
#define PORT_TO_PIN(port)                                                      \
  ((port) == PORT_B ? &PINB : (port) == PORT_C ? &PINC : &PIND)

void gpio_init(void);
void gpio_set_output(uint8_t pin);
void gpio_set_input(uint8_t pin, uint8_t pullup);
void gpio_write(uint8_t pin, uint8_t v);
uint8_t gpio_read(uint8_t pin);

void gpio_dir_set(uint8_t pin, uint8_t out);
void gpio_pin_write(uint8_t pin, uint8_t v);
uint8_t gpio_pin_read(uint8_t pin);

#endif // DRV_GPIO_H
