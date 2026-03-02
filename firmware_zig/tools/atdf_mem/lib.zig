const std = @import("std");

pub const ParsedMemory = struct {
    flash_start: u64,
    flash_size: u64,
    ram_start: u64,
    ram_size: u64,
};

pub fn parseAtdfMemoryFromFile(allocator: std.mem.Allocator, atdf_path: []const u8) !ParsedMemory {
    const data = try std.fs.cwd().readFileAlloc(allocator, atdf_path, 1024 * 1024);
    defer allocator.free(data);
    return parseAtdfMemory(allocator, data);
}

pub fn parseAtdfMemory(allocator: std.mem.Allocator, data: []const u8) ParsedMemory {
    const prog_space = findAddressSpaceBlock(data, "prog") orelse data;
    const data_space = findAddressSpaceBlock(data, "data") orelse data;

    const flash_seg = findFirstMemorySegment(allocator, prog_space, &.{ "FLASH", "PROGMEM" }, "flash");
    const flash_start = parseAttrHex(allocator, flash_seg, "start");
    const flash_size = parseAttrHex(allocator, flash_seg, "size");

    const ram_seg = findFirstMemorySegment(allocator, data_space, &.{ "IRAM", "SRAM", "INTERNAL_SRAM" }, "ram");
    const ram_start = parseAttrHex(allocator, ram_seg, "start");
    const ram_size = parseAttrHex(allocator, ram_seg, "size");

    return .{
        .flash_start = flash_start,
        .flash_size = flash_size,
        .ram_start = ram_start,
        .ram_size = ram_size,
    };
}

fn findAddressSpaceBlock(data: []const u8, space_name: []const u8) ?[]const u8 {
    const marker = "name=\"";
    var search_from: usize = 0;

    while (true) {
        const idx = std.mem.indexOfPos(u8, data, search_from, "<address-space") orelse return null;
        const end_tag = std.mem.indexOfPos(u8, data, idx, "</address-space>") orelse return null;
        const header_end = std.mem.indexOfPos(u8, data, idx, ">") orelse return null;

        const header = data[idx..header_end];
        if (std.mem.indexOf(u8, header, marker)) |name_idx| {
            const value_start = name_idx + marker.len;
            const value_end = std.mem.indexOfPos(u8, header, value_start, "\"") orelse return null;
            if (std.mem.eql(u8, header[value_start..value_end], space_name)) {
                return data[header_end + 1 .. end_tag];
            }
        }

        search_from = end_tag + "</address-space>".len;
    }
}

fn findFirstMemorySegment(
    allocator: std.mem.Allocator,
    data: []const u8,
    names: []const []const u8,
    type_attr: []const u8,
) []const u8 {
    for (names) |name| {
        if (findMemorySegmentByName(allocator, data, name)) |seg| return seg;
    }
    if (findMemorySegmentByType(allocator, data, type_attr)) |seg| return seg;
    @panic("ATDF missing memory segment");
}

fn findMemorySegmentByName(allocator: std.mem.Allocator, data: []const u8, name: []const u8) ?[]const u8 {
    const marker = std.fmt.allocPrint(allocator, "name=\"{s}\"", .{name}) catch @panic("OOM");
    defer allocator.free(marker);

    const name_idx = std.mem.indexOf(u8, data, marker) orelse return null;
    const seg_start = std.mem.lastIndexOf(u8, data[0..name_idx], "<memory-segment") orelse @panic("ATDF segment start not found");
    const seg_end = std.mem.indexOfPos(u8, data, name_idx, "/>") orelse @panic("ATDF segment end not found");

    return data[seg_start..seg_end];
}

fn findMemorySegmentByType(allocator: std.mem.Allocator, data: []const u8, type_attr: []const u8) ?[]const u8 {
    const marker = std.fmt.allocPrint(allocator, "type=\"{s}\"", .{type_attr}) catch @panic("OOM");
    defer allocator.free(marker);

    const type_idx = std.mem.indexOf(u8, data, marker) orelse return null;
    const seg_start = std.mem.lastIndexOf(u8, data[0..type_idx], "<memory-segment") orelse @panic("ATDF segment start not found");
    const seg_end = std.mem.indexOfPos(u8, data, type_idx, "/>") orelse @panic("ATDF segment end not found");

    return data[seg_start..seg_end];
}

fn parseAttrHex(allocator: std.mem.Allocator, segment: []const u8, attr: []const u8) u64 {
    const key = std.fmt.allocPrint(allocator, "{s}=\"", .{attr}) catch @panic("OOM");
    defer allocator.free(key);

    const key_idx = std.mem.indexOf(u8, segment, key) orelse @panic("ATDF attribute not found");
    const val_start = key_idx + key.len;
    const val_end = std.mem.indexOfPos(u8, segment, val_start, "\"") orelse @panic("ATDF attribute end not found");

    const value = segment[val_start..val_end];
    if (std.mem.startsWith(u8, value, "0x")) {
        return std.fmt.parseInt(u64, value[2..], 16) catch @panic("Invalid hex value");
    }
    return std.fmt.parseInt(u64, value, 10) catch @panic("Invalid value");
}
