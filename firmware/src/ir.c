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
 *  - Timer1 free-running at 8/1024 MHz (/1024 on 8 MHz F_CPU)
 *
 * Public API:
 *  - void ir_init(void);
 *  - bool ir_take_command(uint8_t *cmd);
 */

volatile uint8_t ir_state;
volatile uint8_t ir_bitctr;
volatile uint8_t ir_tmp_value;
volatile uint8_t ir_tmp_keyhold;
volatile uint8_t ir_tmp_ovf;
volatile struct ir_struct ir;
volatile struct ir_struct ir_tmp;

void ir_reset_counter(void) {
  TCNT1H = 0xFF;
  TCNT1L = 0x00;
}

void ir_init(void) {
  TCCR1A = 0;
  TCCR1B = (1 << CS10) | (1 << CS12); // clk/1024
  TIMSK1 |= (1 << TOIE1);

  /* IR input: enable pullup */
  gpio_set_input(IR_PIN, 1);

  /* INT0 any logical change */
  EICRA = (1 << ISC00);
  EIMSK = (1 << INT0);

  ir_state = IR_BURST;
  ir_tmp_keyhold = 0;
  ir_tmp_ovf = 0;
  ir_reset_counter();
}

bool ir_take_command(uint8_t *cmd) {
  uint8_t sreg = SREG;
  cli();
  if (ir.status & 1 << IR_RECEIVED) {
    *cmd = ir.command;
    ir.status &= ~(1 << IR_RECEIVED);
    SREG = sreg;
    return true;
  }
  SREG = sreg;
  return false;
}

bool between(uint8_t value, uint8_t low, uint8_t high) {
  return value >= low && value <= high;
}

bool ir_received() { return !!(ir.status & 1 << IR_RECEIVED); }

void process_value() {
  if (ir_state == IR_ADDRESS) {
#ifdef PROTOCOL_NEC_EXTENDED
    ir_tmp.address_l = ir_tmp_value;
#else
    ir_tmp.address = ir_tmp_value;
#endif
    ir_state = IR_ADDRESS_INV;
  } else if (ir_state == IR_ADDRESS_INV) {
#ifdef PROTOCOL_NEC_EXTENDED
    ir_tmp.address_h = ~ir_tmp_value;
#else
    if ((ir_tmp.address ^ ~ir_tmp_value & 0xff) != 0) {
      ir_state = IR_BURST;
      return;
    }
#endif
    ir_state = IR_COMMAND;
  } else if (ir_state == IR_COMMAND) {
    ir_tmp.command = ir_tmp_value;
    ir_state = IR_COMMAND_INV;
  } else if (ir_state == IR_COMMAND_INV) {
    ir_state = IR_BURST;
    if ((ir_tmp.command ^ ~ir_tmp_value & 0xff) != 0) {
      return;
    }
    ir_tmp_keyhold = IR_HOLD_OVF;
#ifdef PROTOCOL_NEC_EXTENDED
    ir.address_l = ir_tmp.address_l;
    ir.address_h = ir_tmp.address_h;
#else
    ir.address = ir_tmp.address;
#endif
    ir.command = ir_tmp.command;
    ir.status |= (1 << IR_RECEIVED) | (1 << IR_SIGVALID);
  }
  ir_bitctr = 0;
  ir_tmp_value = 0;
}

ISR(INT0_vect) {
  uint8_t port_state = gpio_read(IR_PIN);
  uint8_t cnt_state = TCNT1L;

  if (ir_tmp_ovf != 0) {
    // overflow, ignore
    ir_tmp_ovf = 0;
    ir_state = IR_BURST;
    ir_reset_counter();
    return;
  }

  switch (ir_state) {
  case IR_BURST:
    if (port_state) {
      if (between(cnt_state, TIME_BURST_MIN, TIME_BURST_MAX)) {
        ir_state = IR_GAP;
        ir_reset_counter();
      }
    } else {
      ir_reset_counter();
    }
    break;

  case IR_GAP:
    if (!port_state) {
      if (between(cnt_state, TIME_GAP_MIN, TIME_GAP_MAX)) {
        ir_state = IR_ADDRESS;
        ir_tmp_value = 0;
        ir_bitctr = 0;
        ir.status &= ~(1 << IR_KEYHOLD);
        ir_reset_counter();
        break;
      } else if (between(cnt_state, TIME_HOLD_MIN, TIME_HOLD_MAX) &&
                 ir.status & (1 << IR_SIGVALID)) {
        ir.status |= (1 << IR_KEYHOLD);
        ir_tmp_keyhold = IR_HOLD_OVF;
      }
    }
    ir_state = IR_BURST;
    break;

  case IR_ADDRESS:
  case IR_ADDRESS_INV:
  case IR_COMMAND:
  case IR_COMMAND_INV:
    if (port_state) {
      if (between(cnt_state, TIME_PULSE_MIN, TIME_PULSE_MAX)) {
        ir_reset_counter();
        break;
      }
      // should not happen
      ir_state = IR_BURST;
      break;
    }
    {
      bool has_value = false;
      bool value = false;
      if (between(cnt_state, TIME_ZERO_MIN, TIME_ZERO_MAX)) {
        has_value = true;
      } else if (between(cnt_state, TIME_ONE_MIN, TIME_ONE_MAX)) {
        has_value = true;
        value = true;
      }
      if (!has_value) {
        ir_state = IR_BURST;
        break;
      }
      if (value) {
        ir_tmp_value |= (1 << ir_bitctr++);
      } else {
        ir_tmp_value &= ~(1 << ir_bitctr++);
      }
    }
    ir_reset_counter();
    if (ir_bitctr >= 8) {
      process_value();
    }
    break;
  }
}

ISR(TIMER1_OVF_vect) {
  ir_reset_counter();
  ir_tmp_ovf = 1;
  if (ir_tmp_keyhold > 0) {
    ir_tmp_keyhold--;
    if (ir_tmp_keyhold == 0)
      ir.status &= ~((1 << IR_KEYHOLD) | (1 << IR_SIGVALID));
  }
}
