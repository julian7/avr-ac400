const std = @import("std");
const microzig = @import("microzig");
const atdf_mem = @import("tools/atdf_mem/lib.zig");

const MicroBuild = microzig.MicroBuild(.{
    .atmega = true,
});

pub fn build(b: *std.Build) void {
    const optimize = .ReleaseSmall;

    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;

    const atpack = b.dependency("atpack", .{});
    const atdf = atpack.path("atdf/ATmega88PA.atdf");

    const parsed_mem = atdf_mem.parseAtdfMemoryFromFile(b.allocator, atdf.getPath(b)) catch
        @panic("Failed to read ATDF file");
    const memory_regions = blk: {
        const regions = b.allocator.alloc(microzig.MemoryRegion, 2) catch @panic("OOM");
        regions[0] = .{
            .tag = .flash,
            .offset = parsed_mem.flash_start,
            .length = parsed_mem.flash_size,
            .access = .rx,
        };
        regions[1] = .{
            .tag = .ram,
            .offset = 0x800000 + parsed_mem.ram_start,
            .length = parsed_mem.ram_size,
            .access = .rw,
        };
        break :blk regions;
    };

    const avr5_target: std.Target.Query = .{
        .cpu_arch = .avr,
        .cpu_model = .{ .explicit = &std.Target.avr.cpu.avr5 },
        .os_tag = .freestanding,
        .abi = .eabi,
    };

    const chip_atmega88pa: microzig.Chip = .{
        .name = "ATmega88PA",
        .url = "https://www.microchip.com/en-us/product/atmega88pa",
        .register_definition = .{
            .atdf = atdf,
        },
        .memory_regions = memory_regions,
    };

    const base_target: microzig.Target = .{
        .dep = mz_dep,
        .preferred_binary_format = .hex,
        .zig_target = avr5_target,
        .cpu = .{
            .name = "avr5",
            .root_source_file = b.path("src/atmega88pa/cpu.zig"),
        },
        .chip = chip_atmega88pa,
        .hal = .{
            .root_source_file = b.path("src/atmega88pa/hal.zig"),
        },
        .bundle_compiler_rt = false,
        .bundle_ubsan_rt = false,
    };

    const firmware = mb.add_firmware(.{
        .name = "ac400",
        .target = base_target.derive(.{}),
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    mb.install_firmware(firmware, .{ .format = .hex });
    mb.install_firmware(firmware, .{ .format = .elf });
}
