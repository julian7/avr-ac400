const std = @import("std");
const microzig = @import("microzig");

const I_BIT: u3 = 7;

pub const interrupt = struct {
    pub fn enable_interrupts() void {
        asm volatile ("sei");
    }

    pub fn disable_interrupts() void {
        asm volatile ("cli");
    }

    pub fn globally_enabled() bool {
        return (microzig.hal.SREG.* & (@as(u8, 1) << I_BIT)) != 0;
    }
};

pub inline fn sbi(comptime reg: u5, comptime bit: u3) void {
    asm volatile ("sbi %[reg], %[bit]"
        :
        : [reg] "I" (reg),
          [bit] "I" (bit),
    );
}

pub inline fn cbi(comptime reg: u5, comptime bit: u3) void {
    asm volatile ("cbi %[reg], %[bit]"
        :
        : [reg] "I" (reg),
          [bit] "I" (bit),
    );
}

pub const InterruptOptions = blk: {
    const HandlerFn = *const fn () void;
    var fields: []const std.builtin.Type.StructField = &.{};

    for (@typeInfo(microzig.chip.VectorTable).@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "RESET")) continue;
        fields = fields ++ [_]std.builtin.Type.StructField{.{
            .name = field.name,
            .type = ?HandlerFn,
            .default_value_ptr = @as(*const anyopaque, @ptrCast(&@as(?HandlerFn, null))),
            .is_comptime = false,
            .alignment = @alignOf(?HandlerFn),
        }};
    }

    break :blk @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
};

pub const vector_table_asm = blk: {
    std.debug.assert(std.mem.eql(u8, "RESET", std.meta.fields(microzig.chip.VectorTable)[0].name));

    const jmp_instr = if (std.mem.eql(u8, microzig.chip.raw_properties.family, "AVR TINY") or std.mem.eql(u8, microzig.chip.raw_properties.family, "tinyAVR")) "rjmp" else "jmp";
    var asm_str: []const u8 = jmp_instr ++ " microzig_start\n";

    for (std.meta.fields(microzig.chip.VectorTable)[1..]) |entry| {
        const maybe_handler = if (@hasField(InterruptOptions, entry.name))
            @field(microzig.options.interrupts, entry.name)
        else
            null;

        const new_insn = if (maybe_handler) |handler| overload: {
            const isr = make_isr_handler(entry.name, handler);
            break :overload jmp_instr ++ " " ++ isr.exported_name;
        } else jmp_instr ++ " microzig_unhandled_vector";

        const entryTypeInfo = @typeInfo(entry.type);
        const repeat = if (entryTypeInfo == .array) entryTypeInfo.array.len else 1;
        for (0..repeat) |_| {
            asm_str = asm_str ++ new_insn ++ "\n";
        }
    }

    break :blk asm_str;
};

fn vector_table() callconv(.naked) noreturn {
    asm volatile (vector_table_asm);
}

export fn abort() noreturn {
    microzig.hang();
}

pub fn export_startup_logic() void {
    _ = startup_logic;
    @export(&vector_table, .{
        .name = "_start",
    });
}

fn make_isr_handler(comptime name: []const u8, comptime func: anytype) type {
    const is_fn = switch (@typeInfo(@TypeOf(func))) {
        .@"fn" => true,
        .pointer => |ptr| @typeInfo(ptr.child) == .@"fn",
        else => false,
    };
    if (!is_fn) {
        @compileError("Interrupt handler must be a function or function pointer. '" ++ name ++ "' is not callable");
    }

    const isr_asm =
        \\push r0
        \\in r0, 0x3F
        \\cli
        \\push r0
        \\push r1
        \\clr r1
        \\push r2
        \\push r3
        \\push r4
        \\push r5
        \\push r6
        \\push r7
        \\push r8
        \\push r9
        \\push r10
        \\push r11
        \\push r12
        \\push r13
        \\push r14
        \\push r15
        \\push r16
        \\push r17
        \\push r18
        \\push r19
        \\push r20
        \\push r21
        \\push r22
        \\push r23
        \\push r24
        \\push r25
        \\push r26
        \\push r27
        \\push r28
        \\push r29
        \\push r30
        \\push r31
        \\call %[handler]
        \\pop r31
        \\pop r30
        \\pop r29
        \\pop r28
        \\pop r27
        \\pop r26
        \\pop r25
        \\pop r24
        \\pop r23
        \\pop r22
        \\pop r21
        \\pop r20
        \\pop r19
        \\pop r18
        \\pop r17
        \\pop r16
        \\pop r15
        \\pop r14
        \\pop r13
        \\pop r12
        \\pop r11
        \\pop r10
        \\pop r9
        \\pop r8
        \\pop r7
        \\pop r6
        \\pop r5
        \\pop r4
        \\pop r3
        \\pop r2
        \\pop r1
        \\pop r0
        \\out 0x3F, r0
        \\pop r0
        \\reti
    ;

    return struct {
        pub const exported_name = "microzig_isr_" ++ name;

        pub fn isr_vector() callconv(.naked) void {
            asm volatile (isr_asm
                :
                : [handler] "i" (@intFromPtr(func)),
            );
        }

        comptime {
            const options: std.builtin.ExportOptions = .{ .name = exported_name, .linkage = .strong };
            @export(&isr_vector, options);
        }
    };
}

pub const startup_logic = struct {
    export fn microzig_unhandled_vector() callconv(.c) noreturn {
        @panic("Unhandled interrupt");
    }

    extern fn microzig_main() noreturn;

    export fn microzig_start() callconv(.c) noreturn {
        copy_data_to_ram();
        clear_bss();

        microzig_main();
    }

    fn copy_data_to_ram() void {
        asm volatile (
            \\  ; load Z register with the address of the data in flash
            \\  ldi r30, lo8(microzig_data_load_start)
            \\  ldi r31, hi8(microzig_data_load_start)
            \\  ; load X register with address of the data in ram
            \\  ldi r26, lo8(microzig_data_start)
            \\  ldi r27, hi8(microzig_data_start)
            \\  ; load address of end of the data in ram
            \\  ldi r24, lo8(microzig_data_end)
            \\  ldi r25, hi8(microzig_data_end)
            \\  rjmp .L2
            \\
            \\.L1:
            \\  lpm r18, Z+ ; copy from Z into r18 and increment Z
            \\  st X+, r18  ; store r18 at location X and increment X
            \\
            \\.L2:
            \\  cp r26, r24
            \\  cpc r27, r25 ; check and branch if we are at the end of data
            \\  brne .L1
        );
    }

    fn clear_bss() void {
        asm volatile (
            \\  ; load X register with the beginning of bss section
            \\  ldi r26, lo8(microzig_bss_start)
            \\  ldi r27, hi8(microzig_bss_start)
            \\  ; load end of the bss in registers
            \\  ldi r24, lo8(microzig_bss_end)
            \\  ldi r25, hi8(microzig_bss_end)
            \\  ldi r18, 0x00
            \\  rjmp .L4
            \\
            \\.L3:
            \\  st X+, r18
            \\
            \\.L4:
            \\  cp r26, r24
            \\  cpc r27, r25 ; check and branch if we are at the end of bss
            \\  brne .L3
        );
    }
};
