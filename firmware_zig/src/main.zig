const config = @import("config.zig");
const ir = @import("ir.zig");
const microzig = @import("microzig");
const hal = microzig.hal;

inline fn pinWrite(pin: hal.gpio.Pin, v: bool) void {
    pin.put(@intFromBool(v));
}

inline fn pinRead(pin: hal.gpio.Pin) bool {
    return pin.read() == 1;
}

inline fn pinSetOutput(pin: hal.gpio.Pin) void {
    pin.set_direction(.output);
}

inline fn pinSetInput(pin: hal.gpio.Pin, pullup: bool) void {
    pin.set_direction(.input);
    pinWrite(pin, pullup);
}

pub const microzig_options = microzig.Options{
    .interrupts = .{
        .INT0 = ir.INT0,
        .TIMER0_COMPA = TIMER0_COMPA,
    },
};

// AVR registers (ATmega88PA-compatible)
// Defined in `avr_regs.zig`.

// Timer0 configuration handled by HAL.

// Clock configuration
const F_CPU: u32 = 8_000_000;
const TIMER0_PRESCALE: u32 = 64;
const TIMER0_OCR: u8 = @intCast((F_CPU / TIMER0_PRESCALE / 1000) - 1);

// Buzzer timings (ms)
const BUZZER_SHORT_MS: u16 = 80;
const BUZZER_LONG_MS: u16 = 400;
const BUZZER_GAP_MS: u16 = 120;

// IR commands
const IR_CMD_ON: u8 = 0x30;
const IR_CMD_OFF: u8 = 0x90;
const IR_CMD_TIME: u8 = 0xA0;

const Speed = enum(u8) {
    Off = 0,
    Low,
    Mid,
    High,
};

const Debounce = struct {
    integrator: u8,
    pressed: bool,
};

var g_ms: u32 = 0;

var g_speed: Speed = .Off;
var g_timer_sel_hours: u8 = 0; // 0,1,2,4
var g_timer_seconds_remaining: u32 = 0;

var g_buzzer_next_ms: u32 = 0;
var g_buzzer_state: u8 = 0;
var g_buzzer_beeps_remaining: u8 = 0;
var g_buzzer_on_ms: u16 = 0;
var g_buzzer_off_ms: u16 = 0;
var g_buzzer_followup_shorts: u8 = 0;

inline fn vload_u32(ptr: *volatile u32) u32 {
    return ptr.*;
}

inline fn vstore_u32(ptr: *volatile u32, value: u32) void {
    ptr.* = value;
}

inline fn readMs() u32 {
    const sreg = hal.interrupt.disable();
    const now = vload_u32(@as(*volatile u32, @ptrCast(&g_ms)));
    hal.interrupt.restore(sreg);
    return now;
}

inline fn timeDue(now_ms: u32, target_ms: u32) bool {
    const diff: i32 = @bitCast(now_ms -% target_ms);
    return diff >= 0;
}

fn buzzerSet(on: bool) void {
    pinWrite(config.BUZZER_PIN, on);
}

fn buzzerStart(beeps: u8, on_ms: u16, off_ms: u16) void {
    if (beeps == 0) return;

    const now_ms = readMs();

    g_buzzer_followup_shorts = 0;
    g_buzzer_beeps_remaining = beeps;
    g_buzzer_on_ms = on_ms;
    g_buzzer_off_ms = off_ms;
    g_buzzer_state = 1;
    buzzerSet(true);
    g_buzzer_next_ms = now_ms + @as(u32, on_ms);
}

fn buzzerStartTimer(shorts: u8) void {
    if (shorts == 0) return;
    buzzerStart(1, BUZZER_LONG_MS, BUZZER_GAP_MS);
    g_buzzer_followup_shorts = shorts;
}

fn buzzerUpdate(now_ms: u32) void {
    if (g_buzzer_state == 0) return;
    if (!timeDue(now_ms, g_buzzer_next_ms)) return;

    if (g_buzzer_state == 1) {
        buzzerSet(false);
        g_buzzer_state = 2;
        g_buzzer_next_ms = now_ms + @as(u32, g_buzzer_off_ms);
    } else {
        if (g_buzzer_beeps_remaining > 1) {
            g_buzzer_beeps_remaining -= 1;
            g_buzzer_state = 1;
            buzzerSet(true);
            g_buzzer_next_ms = now_ms + @as(u32, g_buzzer_on_ms);
        } else {
            g_buzzer_state = 0;
            g_buzzer_beeps_remaining = 0;
            if (g_buzzer_followup_shorts > 0) {
                const shorts = g_buzzer_followup_shorts;
                g_buzzer_followup_shorts = 0;
                buzzerStart(shorts, BUZZER_SHORT_MS, BUZZER_GAP_MS);
            }
        }
    }
}

fn updateLeds() void {
    pinWrite(config.LED1_PIN, g_timer_sel_hours == 1);
    pinWrite(config.LED2_PIN, g_timer_sel_hours == 2);
    pinWrite(config.LED3_PIN, g_timer_sel_hours == 4);

    pinWrite(config.LED4_PIN, g_speed == .High);
    pinWrite(config.LED5_PIN, g_speed == .Mid);
    pinWrite(config.LED6_PIN, g_speed == .Low);
}

fn relaysAllOff() void {
    pinWrite(config.RELAY_LOW_PIN, false);
    pinWrite(config.RELAY_MID_PIN, false);
    pinWrite(config.RELAY_HIGH_PIN, false);
}

fn setSpeed(speed: Speed) void {
    relaysAllOff();
    g_speed = speed;

    switch (speed) {
        .Low => pinWrite(config.RELAY_LOW_PIN, true),
        .Mid => pinWrite(config.RELAY_MID_PIN, true),
        .High => pinWrite(config.RELAY_HIGH_PIN, true),
        else => {},
    }

    updateLeds();
}

fn nextSpeed(s: Speed) Speed {
    return switch (s) {
        .Off => .Low,
        .Low => .Mid,
        .Mid => .High,
        .High => .Low,
    };
}

fn nextTimerSelHours(h: u8) u8 {
    return switch (h) {
        0 => 1,
        1 => 2,
        2 => 4,
        else => 0,
    };
}

fn timerRotateFromIr() void {
    g_timer_sel_hours = nextTimerSelHours(g_timer_sel_hours);

    g_timer_seconds_remaining = switch (g_timer_sel_hours) {
        1 => 3600,
        2 => 7200,
        4 => 14400,
        else => 0,
    };

    if (g_timer_sel_hours > 0) {
        buzzerStartTimer(g_timer_sel_hours);
    }

    updateLeds();
}

fn debounceUpdate(db: *Debounce, raw_pressed: bool) bool {
    const max: u8 = 3;
    if (raw_pressed) {
        if (db.integrator < max) db.integrator += 1;
    } else {
        if (db.integrator > 0) db.integrator -= 1;
    }

    const new_pressed = db.integrator >= max;
    const pressed_event = (!db.pressed and new_pressed);
    db.pressed = new_pressed;
    return pressed_event;
}

fn ioInit() void {
    pinSetOutput(config.RELAY_LOW_PIN);
    pinSetOutput(config.RELAY_MID_PIN);
    pinSetOutput(config.RELAY_HIGH_PIN);
    relaysAllOff();

    pinSetOutput(config.BUZZER_PIN);
    buzzerSet(false);

    pinSetInput(config.ON_KEY_PIN, true);
    pinSetInput(config.OFF_KEY_PIN, true);

    pinSetOutput(config.LED1_PIN);
    pinSetOutput(config.LED2_PIN);
    pinSetOutput(config.LED3_PIN);
    pinSetOutput(config.LED4_PIN);
    pinSetOutput(config.LED5_PIN);
    pinSetOutput(config.LED6_PIN);
    updateLeds();
}

fn timer0Init() void {
    hal.timer0.init_ctc(TIMER0_OCR, .div64);
    hal.timer0.enable_compare_a_interrupt();
}

fn handleCommand(cmd: u8) void {
    switch (cmd) {
        IR_CMD_ON => {
            buzzerStart(1, BUZZER_SHORT_MS, BUZZER_GAP_MS);
            if (g_speed == .Off) {
                setSpeed(.Low);
            } else {
                setSpeed(nextSpeed(g_speed));
            }
        },
        IR_CMD_OFF => {
            buzzerStart(1, BUZZER_SHORT_MS, BUZZER_GAP_MS);
            setSpeed(.Off);
            g_timer_sel_hours = 0;
            g_timer_seconds_remaining = 0;
            updateLeds();
        },
        IR_CMD_TIME => {
            timerRotateFromIr();
        },
        else => {},
    }
}

pub fn TIMER0_COMPA() void {
    const v = vload_u32(@as(*volatile u32, @ptrCast(&g_ms)));
    vstore_u32(@as(*volatile u32, @ptrCast(&g_ms)), v +% 1);
}

pub fn main() void {
    ioInit();
    timer0Init();
    ir.irInit();
    hal.interrupt.enable();

    var on_db = Debounce{ .integrator = 0, .pressed = false };
    var off_db = Debounce{ .integrator = 0, .pressed = false };

    var last_debounce_ms: u32 = 0;
    var last_second_ms: u32 = 0;

    while (true) {
        const now_ms = readMs();

        buzzerUpdate(now_ms);

        if (now_ms -% last_debounce_ms >= 10) {
            last_debounce_ms +%= 10;

            const on_raw = !pinRead(config.ON_KEY_PIN);
            const off_raw = !pinRead(config.OFF_KEY_PIN);

            if (debounceUpdate(&on_db, on_raw)) {
                buzzerStart(1, BUZZER_SHORT_MS, BUZZER_GAP_MS);
                if (g_speed == .Off) {
                    setSpeed(.Low);
                } else {
                    setSpeed(nextSpeed(g_speed));
                }
            }

            if (debounceUpdate(&off_db, off_raw)) {
                buzzerStart(1, BUZZER_SHORT_MS, BUZZER_GAP_MS);
                setSpeed(.Off);
                g_timer_sel_hours = 0;
                g_timer_seconds_remaining = 0;
                updateLeds();
            }
        }

        if (now_ms -% last_second_ms >= 1000) {
            last_second_ms +%= 1000;
            if (g_timer_seconds_remaining > 0 and g_speed != .Off) {
                g_timer_seconds_remaining -= 1;
                if (g_timer_seconds_remaining == 0) {
                    g_timer_sel_hours = 0;
                    setSpeed(.Off);
                    buzzerStart(1, BUZZER_LONG_MS, BUZZER_GAP_MS);
                }
                updateLeds();
            }
        }

        var cmd: u8 = 0;
        if (ir.irTakeCommand(&cmd)) {
            handleCommand(cmd);
        }
    }
}
