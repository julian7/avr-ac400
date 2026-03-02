const config = @import("config.zig");
const microzig = @import("microzig");
const hal = microzig.hal;

/// NEC IR receiver interface
/// - Uses INT0 for edge timing capture
/// - Uses Timer1 as a free-running timebase
/// - irInit() must be called once during startup.
/// - irTakeCommand() returns true and writes the command byte when ready.
/// NEC timing (microseconds, Timer1 @ 1MHz)
const IR_LEAD_MARK_MIN: u16 = 8500;
const IR_LEAD_MARK_MAX: u16 = 9500;
const IR_LEAD_SPACE_MIN: u16 = 4000;
const IR_LEAD_SPACE_MAX: u16 = 5000;
const IR_REPEAT_SPACE_MIN: u16 = 2000;
const IR_REPEAT_SPACE_MAX: u16 = 2600;
const IR_MARK_MIN: u16 = 400;
const IR_MARK_MAX: u16 = 700;
const IR_SPACE_0_MIN: u16 = 400;
const IR_SPACE_0_MAX: u16 = 700;
const IR_SPACE_1_MIN: u16 = 1400;
const IR_SPACE_1_MAX: u16 = 1900;

const IrState = enum(u8) {
    Idle = 0,
    LeadMark = 1,
    DataMark = 2,
    DataSpace = 3,
};

var g_ir_state: IrState = .Idle;
var g_ir_last_time: u16 = 0;
var g_ir_bit_index: u8 = 0;
var g_ir_data: u32 = 0;
var g_ir_command: u8 = 0;
var g_ir_command_ready: bool = false;

inline fn inRange(v: u16, min: u16, max: u16) bool {
    return (v >= min) and (v <= max);
}

pub fn irInit() void {
    // Timer1 free-running @ 1MHz (prescaler 8 on 8 MHz F_CPU)
    hal.timer1.init_prescale_div8();
    hal.timer1.reset();

    // IR input: enable pullup
    config.IR_PIN.set_direction(.input);
    config.IR_PIN.put(1);

    // INT0 any logical change
    hal.extint.enable_int0_any_change();

    g_ir_last_time = hal.timer1.read();
}

pub fn irTakeCommand(cmd: *u8) bool {
    var ready: bool = false;
    const sreg = hal.interrupt.disable();
    if (g_ir_command_ready) {
        g_ir_command_ready = false;
        cmd.* = g_ir_command;
        ready = true;
    }
    hal.interrupt.restore(sreg);
    return ready;
}

pub fn INT0() void {
    const now: u16 = hal.timer1.read();
    const dt: u16 = now -% g_ir_last_time;
    g_ir_last_time = now;

    const level: bool = config.IR_PIN.read() == 1;

    if (level) {
        // rising edge: end of mark
        if (g_ir_state == .Idle) {
            if (inRange(dt, IR_LEAD_MARK_MIN, IR_LEAD_MARK_MAX)) {
                g_ir_state = .LeadMark;
            }
        } else if (g_ir_state == .DataMark) {
            if (inRange(dt, IR_MARK_MIN, IR_MARK_MAX)) {
                g_ir_state = .DataSpace;
            } else {
                g_ir_state = .Idle;
            }
        }
    } else {
        // falling edge: end of space
        if (g_ir_state == .LeadMark) {
            if (inRange(dt, IR_LEAD_SPACE_MIN, IR_LEAD_SPACE_MAX)) {
                g_ir_state = .DataMark;
                g_ir_bit_index = 0;
                g_ir_data = 0;
            } else if (inRange(dt, IR_REPEAT_SPACE_MIN, IR_REPEAT_SPACE_MAX)) {
                // repeat code ignored
                g_ir_state = .Idle;
            } else {
                g_ir_state = .Idle;
            }
        } else if (g_ir_state == .DataSpace) {
            var bit: u8 = 0;
            if (inRange(dt, IR_SPACE_0_MIN, IR_SPACE_0_MAX)) {
                bit = 0;
            } else if (inRange(dt, IR_SPACE_1_MIN, IR_SPACE_1_MAX)) {
                bit = 1;
            } else {
                g_ir_state = .Idle;
                return;
            }

            g_ir_data |= (@as(u32, bit) << @as(u5, @intCast(g_ir_bit_index)));
            g_ir_bit_index += 1;

            if (g_ir_bit_index >= 32) {
                const addr: u8 = @as(u8, @truncate(g_ir_data & 0xFF));
                const addr_inv: u8 = @as(u8, @truncate((g_ir_data >> 8) & 0xFF));
                const cmd: u8 = @as(u8, @truncate((g_ir_data >> 16) & 0xFF));
                const cmd_inv: u8 = @as(u8, @truncate((g_ir_data >> 24) & 0xFF));
                if (((addr ^ addr_inv) & 0xFF) == 0xFF and ((cmd ^ cmd_inv) & 0xFF) == 0xFF) {
                    g_ir_command = cmd;
                    g_ir_command_ready = true;
                }
                g_ir_state = .Idle;
            } else {
                g_ir_state = .DataMark;
            }
        }
    }
}
