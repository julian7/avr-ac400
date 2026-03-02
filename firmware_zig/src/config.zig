const microzig = @import("microzig");
const gpio = microzig.hal.gpio;

/// Board configuration: signal mappings for ATmega88PA
/// - LEDs: PC0..PC5
/// - Buzzer: PD0
/// - IR: PD2 (INT0)
/// - Keys: PD3 (ON), PD4 (OFF)
/// - Relays: PD5 (LOW), PD6 (MID), PD7 (HIGH)
pub const LED1_PIN = gpio.pin(.c, 0);
pub const LED2_PIN = gpio.pin(.c, 1);
pub const LED3_PIN = gpio.pin(.c, 2);
pub const LED4_PIN = gpio.pin(.c, 3);
pub const LED5_PIN = gpio.pin(.c, 4);
pub const LED6_PIN = gpio.pin(.c, 5);

pub const BUZZER_PIN = gpio.pin(.d, 0);
pub const IR_PIN = gpio.pin(.d, 2);
pub const ON_KEY_PIN = gpio.pin(.d, 3);
pub const OFF_KEY_PIN = gpio.pin(.d, 4);

pub const RELAY_LOW_PIN = gpio.pin(.d, 5);
pub const RELAY_MID_PIN = gpio.pin(.d, 6);
pub const RELAY_HIGH_PIN = gpio.pin(.d, 7);
