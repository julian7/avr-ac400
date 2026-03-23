#ifndef IR_H
#define IR_H

#include <stdbool.h>
#include <stdint.h>

/*
 * NEC IR receiver interface
 *
 * - Uses INT0 for edge timing capture
 * - Uses Timer1 as a free-running timebase
 *
 * ir_init() must be called once during startup.
 * ir_take_command() returns true and writes the command byte when ready.
 */

// #define PROTOCOL_NEC_EXTENDED

// AGC Burst, 9ms typ; in 8.5-9.5ms
#define TIME_BURST_MIN 65
#define TIME_BURST_MAX 75

// Gap after AGC Burst, 4.5ms typ, in 4-5ms
#define TIME_GAP_MIN 30
#define TIME_GAP_MAX 40

// Gap (key hold) after AGC Burst, 2.25ms typ, in 2-2.6ms
#define TIME_HOLD_MIN 15
#define TIME_HOLD_MAX 20

// Short pulse for each bit, 560us typ, in 400-700us
#define TIME_PULSE_MIN 2
#define TIME_PULSE_MAX 7

// Gap for logical 0, 560us typ, in 400-700us
#define TIME_ZERO_MIN 2
#define TIME_ZERO_MAX 7

// Gap for logical 1, 1.69ms typ, in 1.4-1.9ms
#define TIME_ONE_MIN 9
#define TIME_ONE_MAX 19

// Definition for state machine
enum ir_state_t {
  IR_BURST,
  IR_GAP,
  IR_ADDRESS,
  IR_ADDRESS_INV,
  IR_COMMAND,
  IR_COMMAND_INV
};

// Definition for status bits
#define IR_RECEIVED 0 // Received new command
#define IR_KEYHOLD 1  // Key hold
#define IR_SIGVALID 2 // Valid signal (Internal used)

// Timer Overflows till keyhold flag is cleared
#define IR_HOLD_OVF 5

// Struct definition
struct ir_struct {
#ifdef PROTOCOL_NEC_EXTENDED
  uint8_t address_l;
  uint8_t address_h;
#else
  uint8_t address;
#endif
  uint8_t command;
  uint8_t status;
};

// Global status structure
extern volatile struct ir_struct ir;

void ir_init(void);
bool ir_take_command(uint8_t *cmd);

#endif // IR_H
