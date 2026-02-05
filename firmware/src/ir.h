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

void ir_init(void);
bool ir_take_command(uint8_t *cmd);

#endif // IR_H
