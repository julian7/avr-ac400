const microzig = @import("microzig");

/// ATmega88PA register address map (data memory addresses).
/// NOTE: These are data space addresses (I/O addr + 0x20).
pub const SREG: *volatile u8 = @as(*volatile u8, @ptrFromInt(0x5F));

const EIMSK: *volatile u8 = @as(*volatile u8, @ptrFromInt(0x3D));
const EICRA: *volatile u8 = @as(*volatile u8, @ptrFromInt(0x69));

const TCCR0A: *volatile u8 = @as(*volatile u8, @ptrFromInt(0x44));
const TCCR0B: *volatile u8 = @as(*volatile u8, @ptrFromInt(0x45));
const OCR0A: *volatile u8 = @as(*volatile u8, @ptrFromInt(0x47));
const TIMSK0: *volatile u8 = @as(*volatile u8, @ptrFromInt(0x6E));

const TCCR1A: *volatile u8 = @as(*volatile u8, @ptrFromInt(0x80));
const TCCR1B: *volatile u8 = @as(*volatile u8, @ptrFromInt(0x81));
const TCNT1: *volatile u16 = @as(*volatile u16, @ptrFromInt(0x84));

inline fn setBit(reg: *volatile u8, bit: u3) void {
    reg.* |= (@as(u8, 1) << bit);
}

inline fn clearBit(reg: *volatile u8, bit: u3) void {
    reg.* &= ~(@as(u8, 1) << bit);
}

/// Minimal ATmega88PA HAL with GPIO support.
/// Uses IO-space addresses for SBI/CBI.
pub const gpio = struct {
    pub const Port = enum(u2) {
        b = 1,
        c = 2,
        d = 3,

        pub const Regs = extern struct {
            /// Port Input Pins
            PIN: u8,
            /// Port Data Direction Register
            DDR: u8,
            /// Port Data Register
            PORT: u8,
        };

        /// IO-space addresses (not data-space). These are used so SBI/CBI works.
        pub inline fn get_regs(port: Port) *volatile Regs {
            return switch (port) {
                .b => @as(*volatile Regs, @ptrFromInt(0x3)),
                .c => @as(*volatile Regs, @ptrFromInt(0x6)),
                .d => @as(*volatile Regs, @ptrFromInt(0x9)),
            };
        }
    };

    pub fn pin(port: Port, num: u3) Pin {
        return Pin{
            .port = port,
            .num = num,
        };
    }

    pub const Direction = enum {
        input,
        output,
    };

    pub const Pin = packed struct(u5) {
        port: Port,
        num: u3,

        pub inline fn set_direction(p: Pin, dir: Direction) void {
            const dir_addr: *volatile u8 = &p.port.get_regs().DDR;
            switch (dir) {
                .input => clearBit(dir_addr, p.num),
                .output => setBit(dir_addr, p.num),
            }
        }

        pub inline fn read(p: Pin) u1 {
            const pin_addr: *volatile u8 = &p.port.get_regs().PIN;
            return @truncate(pin_addr.* >> p.num & 0x01);
        }

        pub inline fn put(p: Pin, value: u1) void {
            const port_addr: *volatile u8 = &p.port.get_regs().PORT;
            switch (value) {
                1 => setBit(port_addr, p.num),
                0 => clearBit(port_addr, p.num),
            }
        }

        pub inline fn toggle(p: Pin) void {
            const pin_addr: *volatile u8 = &p.port.get_regs().PIN;
            pin_addr.* = (@as(u8, 1) << p.num);
        }
    };
};

pub const interrupt = struct {
    const I_BIT: u3 = 7;

    pub inline fn disable() u8 {
        const s = SREG.*;
        clearBit(SREG, I_BIT);
        return s;
    }

    pub inline fn enable() void {
        setBit(SREG, I_BIT);
    }

    pub inline fn restore(s: u8) void {
        SREG.* = s;
    }
};

pub const timer0 = struct {
    const WGM01: u3 = 1;
    const CS00: u3 = 0;
    const CS01: u3 = 1;
    const CS02: u3 = 2;
    const OCIE0A: u3 = 1;

    pub const Prescale = enum {
        div1,
        div8,
        div64,
        div256,
        div1024,
    };

    pub fn init_ctc(ocr: u8, prescale: Prescale) void {
        TCCR0A.* = 0;
        TCCR0B.* = 0;
        setBit(TCCR0A, WGM01);
        OCR0A.* = ocr;
        apply_prescale(prescale);
    }

    pub fn enable_compare_a_interrupt() void {
        setBit(TIMSK0, OCIE0A);
    }

    inline fn apply_prescale(p: Prescale) void {
        switch (p) {
            .div1 => setBit(TCCR0B, CS00),
            .div8 => setBit(TCCR0B, CS01),
            .div64 => {
                setBit(TCCR0B, CS00);
                setBit(TCCR0B, CS01);
            },
            .div256 => setBit(TCCR0B, CS02),
            .div1024 => {
                setBit(TCCR0B, CS02);
                setBit(TCCR0B, CS00);
            },
        }
    }
};

pub const timer1 = struct {
    const CS11: u3 = 1;

    pub fn init_prescale_div8() void {
        TCCR1A.* = 0;
        TCCR1B.* = 0;
        setBit(TCCR1B, CS11);
        TCNT1.* = 0;
    }

    pub fn reset() void {
        TCNT1.* = 0;
    }

    pub fn read() u16 {
        return TCNT1.*;
    }
};

pub const extint = struct {
    const ISC00: u3 = 0;
    const INT0: u3 = 0;

    pub fn enable_int0_any_change() void {
        setBit(EICRA, ISC00);
        setBit(EIMSK, INT0);
    }
};
