#include <avr/interrupt.h>
#include <avr/io.h>
#include <stdbool.h>
#include <stdint.h>

#include "config.h"
#include "gpio.h"
#include "ir.h"

/*
 * NEC IR receiver implementation using INT0 + Timer1.
 *
 * Assumes:
 *  - IR input on IR_PIN (INT0), active-low signal from receiver module
 *  - Timer1 free-running at 1 MHz (prescaler 8 on 8 MHz F_CPU)
 *
 * Public API:
 *  - void ir_init(void);
 *  - bool ir_take_command(uint8_t *cmd);
 */

/* NEC timing (microseconds, Timer1 @ 1MHz) */
#define IR_LEAD_MARK_MIN 8500
#define IR_LEAD_MARK_MAX 9500
#define IR_LEAD_SPACE_MIN 4000
#define IR_LEAD_SPACE_MAX 5000
#define IR_REPEAT_SPACE_MIN 2000
#define IR_REPEAT_SPACE_MAX 2600
#define IR_MARK_MIN 400
#define IR_MARK_MAX 700
#define IR_SPACE_0_MIN 400
#define IR_SPACE_0_MAX 700
#define IR_SPACE_1_MIN 1400
#define IR_SPACE_1_MAX 1900

typedef enum {
  IR_IDLE = 0,
  IR_LEAD_MARK,
  IR_DATA_MARK,
  IR_DATA_SPACE
} ir_state_t;

static volatile ir_state_t g_ir_state = IR_IDLE;
static volatile uint16_t g_ir_last_time = 0;
static volatile uint8_t g_ir_bit_index = 0;
static volatile uint32_t g_ir_data = 0;
static volatile uint8_t g_ir_command = 0;
static volatile bool g_ir_command_ready = false;

static inline bool in_range(uint16_t v, uint16_t min, uint16_t max) {
  return (v >= min) && (v <= max);
}

void ir_init(void) {
  /* Timer1 free-running @ 1MHz (prescaler 8) */
  TCCR1A = 0;
  TCCR1B = (1 << CS11);
  TCNT1 = 0;

  /* IR input: enable pullup */
  gpio_set_input(IR_PIN, 1);

  /* INT0 any logical change */
  EICRA = (1 << ISC00);
  EIMSK = (1 << INT0);

  g_ir_last_time = TCNT1;
}

bool ir_take_command(uint8_t *cmd) {
  bool ready = false;
  uint8_t sreg = SREG;
  cli();
  if (g_ir_command_ready) {
    g_ir_command_ready = false;
    *cmd = g_ir_command;
    ready = true;
  }
  SREG = sreg;
  return ready;
}

ISR(INT0_vect) {
  uint16_t now = TCNT1;
  uint16_t dt = (uint16_t)(now - g_ir_last_time);
  g_ir_last_time = now;

  uint8_t level = gpio_read(IR_PIN);

  if (level) {
    /* rising edge: end of mark */
    if (g_ir_state == IR_IDLE) {
      if (in_range(dt, IR_LEAD_MARK_MIN, IR_LEAD_MARK_MAX)) {
        g_ir_state = IR_LEAD_MARK;
      }
    } else if (g_ir_state == IR_DATA_MARK) {
      if (in_range(dt, IR_MARK_MIN, IR_MARK_MAX)) {
        g_ir_state = IR_DATA_SPACE;
      } else {
        g_ir_state = IR_IDLE;
      }
    }
  } else {
    /* falling edge: end of space */
    if (g_ir_state == IR_LEAD_MARK) {
      if (in_range(dt, IR_LEAD_SPACE_MIN, IR_LEAD_SPACE_MAX)) {
        g_ir_state = IR_DATA_MARK;
        g_ir_bit_index = 0;
        g_ir_data = 0;
      } else if (in_range(dt, IR_REPEAT_SPACE_MIN, IR_REPEAT_SPACE_MAX)) {
        /* repeat code ignored */
        g_ir_state = IR_IDLE;
      } else {
        g_ir_state = IR_IDLE;
      }
    } else if (g_ir_state == IR_DATA_SPACE) {
      uint8_t bit;
      if (in_range(dt, IR_SPACE_0_MIN, IR_SPACE_0_MAX)) {
        bit = 0;
      } else if (in_range(dt, IR_SPACE_1_MIN, IR_SPACE_1_MAX)) {
        bit = 1;
      } else {
        g_ir_state = IR_IDLE;
        return;
      }

      g_ir_data |= ((uint32_t)bit << g_ir_bit_index);
      g_ir_bit_index++;

      if (g_ir_bit_index >= 32) {
        uint8_t addr = (uint8_t)(g_ir_data & 0xFF);
        uint8_t addr_inv = (uint8_t)((g_ir_data >> 8) & 0xFF);
        uint8_t cmd = (uint8_t)((g_ir_data >> 16) & 0xFF);
        uint8_t cmd_inv = (uint8_t)((g_ir_data >> 24) & 0xFF);
        if ((uint8_t)(addr ^ addr_inv) == 0xFF &&
            (uint8_t)(cmd ^ cmd_inv) == 0xFF) {
          g_ir_command = cmd;
          g_ir_command_ready = true;
        }
        g_ir_state = IR_IDLE;
      } else {
        g_ir_state = IR_DATA_MARK;
      }
    }
  }
}
