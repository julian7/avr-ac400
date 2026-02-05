#ifndef CONFIG_H
#define CONFIG_H

#include "gpio.h"
#include <avr/io.h>
#include <stdint.h>

/*
 * Board configuration: signal mappings for ATmega88PA
 *
 * - LEDs: PC0..PC5
 * - Buzzer: PD0
 * - IR: PD2 (INT0)
 * - Keys: PD3 (ON), PD4 (OFF)
 * - Relays: PD5 (LOW), PD6 (MID), PD7 (HIGH)
 */

#define LED1_PIN PIN_ENCODE(PORT_C, 0)
#define LED2_PIN PIN_ENCODE(PORT_C, 1)
#define LED3_PIN PIN_ENCODE(PORT_C, 2)
#define LED4_PIN PIN_ENCODE(PORT_C, 3)
#define LED5_PIN PIN_ENCODE(PORT_C, 4)
#define LED6_PIN PIN_ENCODE(PORT_C, 5)

#define BUZZER_PIN PIN_ENCODE(PORT_D, 0)
#define IR_PIN PIN_ENCODE(PORT_D, 2)
#define ON_KEY_PIN PIN_ENCODE(PORT_D, 3)
#define OFF_KEY_PIN PIN_ENCODE(PORT_D, 4)

#define RELAY_LOW_PIN PIN_ENCODE(PORT_D, 5)
#define RELAY_MID_PIN PIN_ENCODE(PORT_D, 6)
#define RELAY_HIGH_PIN PIN_ENCODE(PORT_D, 7)

#endif // CONFIG_H
