const std = @import("std");

pub const PeError = error{
    BadDosSignature,
    BadPESignature,
    Truncated,
    MissingCliDirectory,
    RvaNotMapped,
} || std.mem.Allocator.Error;

pub const Section = struct {
    virtual_address: u32,
    virtual_size: u32,
    raw_ptr: u32,
    raw_size: u32,
};

pub const Info = struct {
    data: []const u8,
    sections: []const Section,
    cli_header_rva: u32,
    cli_header_size: u32,

    pub fn rvaToOffset(self: Info, rva: u32) PeError!usize {
        for (self.sections) |sec| {
            const span = @max(sec.virtual_size, sec.raw_size);
            if (rva >= sec.virtual_address and rva < sec.virtual_address + span) {
                const rel = rva - sec.virtual_address;
                const out = @as(usize, sec.raw_ptr) + rel;
                if (out > self.data.len) return error.Truncated;
                return out;
            }
        }

        if (rva < self.data.len) return rva;
        return error.RvaNotMapped;
    }
};

pub fn parse(allocator: std.mem.Allocator, data: []const u8) PeError!Info {
    if (data.len < 0x40) return error.Truncated;
    if (!std.mem.eql(u8, data[0..2], "MZ")) return error.BadDosSignature;

    const pe_off = readU32(data, 0x3c) orelse return error.Truncated;
    if (pe_off + 4 + 20 > data.len) return error.Truncated;
    if (!std.mem.eql(u8, data[pe_off .. pe_off + 4], "PE\x00\x00")) return error.BadPESignature;

    const coff_off = pe_off + 4;
    const number_of_sections = readU16(data, coff_off + 2) orelse return error.Truncated;
    const size_of_optional_header = readU16(data, coff_off + 16) orelse return error.Truncated;
    const optional_off = coff_off + 20;
    if (optional_off + size_of_optional_header > data.len) return error.Truncated;

    const opt_magic = readU16(data, optional_off) orelse return error.Truncated;
    const data_dirs_off: usize = switch (opt_magic) {
        0x10b => optional_off + 96,
        0x20b => optional_off + 112,
        else => return error.MissingCliDirectory,
    };
    const cli_dir_off = data_dirs_off + (14 * 8);
    if (cli_dir_off + 8 > optional_off + size_of_optional_header) return error.MissingCliDirectory;
    const cli_rva = readU32(data, cli_dir_off) orelse return error.Truncated;
    const cli_size = readU32(data, cli_dir_off + 4) orelse return error.Truncated;
    if (cli_rva == 0 or cli_size == 0) return error.MissingCliDirectory;

    const section_off = optional_off + size_of_optional_header;
    const sec_count = @as(usize, number_of_sections);
    if (section_off + sec_count * 40 > data.len) return error.Truncated;

    const sections = try allocator.alloc(Section, sec_count);
    for (sections, 0..) |*sec, i| {
        const off = section_off + i * 40;
        sec.* = .{
            .virtual_size = readU32(data, off + 8) orelse return error.Truncated,
            .virtual_address = readU32(data, off + 12) orelse return error.Truncated,
            .raw_size = readU32(data, off + 16) orelse return error.Truncated,
            .raw_ptr = readU32(data, off + 20) orelse return error.Truncated,
        };
    }

    return .{
        .data = data,
        .sections = sections,
        .cli_header_rva = cli_rva,
        .cli_header_size = cli_size,
    };
}

fn readU16(data: []const u8, off: usize) ?u16 {
    if (off + 2 > data.len) return null;
    return std.mem.readInt(u16, data[off..][0..2], .little);
}

fn readU32(data: []const u8, off: usize) ?u32 {
    if (off + 4 > data.len) return null;
    return std.mem.readInt(u32, data[off..][0..4], .little);
}

test "rvaToOffset maps through section range" {
    const info = Info{
        .data = &([_]u8{0} ** 0x400),
        .sections = &[_]Section{
            .{
                .virtual_address = 0x2000,
                .virtual_size = 0x100,
                .raw_ptr = 0x180,
                .raw_size = 0x200,
            },
        },
        .cli_header_rva = 0,
        .cli_header_size = 0,
    };
    const off = try info.rvaToOffset(0x2010);
    try std.testing.expectEqual(@as(usize, 0x190), off);
}

test "rvaToOffset falls back for raw file RVA" {
    const info = Info{
        .data = &([_]u8{0} ** 0x200),
        .sections = &.{},
        .cli_header_rva = 0,
        .cli_header_size = 0,
    };
    const off = try info.rvaToOffset(0x40);
    try std.testing.expectEqual(@as(usize, 0x40), off);
}

test "rvaToOffset returns not mapped for out of range" {
    const info = Info{
        .data = &([_]u8{0} ** 0x20),
        .sections = &.{},
        .cli_header_rva = 0,
        .cli_header_size = 0,
    };
    try std.testing.expectError(error.RvaNotMapped, info.rvaToOffset(0x2000));
}

test "parse rejects non-MZ signatures" {
    var data: [64]u8 = .{0} ** 64;
    try std.testing.expectError(error.BadDosSignature, parse(std.testing.allocator, &data));
}

test "parse accepts minimal PE32+ with CLI directory" {
    var data: [0x400]u8 = .{0} ** 0x400;
    data[0] = 'M';
    data[1] = 'Z';
    // e_lfanew = 0x80
    std.mem.writeInt(u32, data[0x3c..][0..4], 0x80, .little);

    // PE signature
    data[0x80] = 'P';
    data[0x81] = 'E';
    data[0x82] = 0;
    data[0x83] = 0;

    const coff_off: usize = 0x84;
    std.mem.writeInt(u16, data[coff_off + 2 ..][0..2], 1, .little); // sections
    std.mem.writeInt(u16, data[coff_off + 16 ..][0..2], 0xF0, .little); // optional header size

    const optional_off: usize = coff_off + 20;
    std.mem.writeInt(u16, data[optional_off..][0..2], 0x20b, .little); // PE32+

    // CLI data directory entry (index 14)
    const cli_dir_off: usize = optional_off + 112 + (14 * 8);
    std.mem.writeInt(u32, data[cli_dir_off..][0..4], 0x2000, .little); // CLI RVA
    std.mem.writeInt(u32, data[cli_dir_off + 4 ..][0..4], 0x48, .little); // CLI size

    // One section header at optional_off + 0xF0
    const sec_off: usize = optional_off + 0xF0;
    std.mem.writeInt(u32, data[sec_off + 8 ..][0..4], 0x1000, .little); // virtual size
    std.mem.writeInt(u32, data[sec_off + 12 ..][0..4], 0x2000, .little); // virtual address
    std.mem.writeInt(u32, data[sec_off + 16 ..][0..4], 0x200, .little); // raw size
    std.mem.writeInt(u32, data[sec_off + 20 ..][0..4], 0x180, .little); // raw ptr

    const info = try parse(std.testing.allocator, &data);
    defer std.testing.allocator.free(info.sections);
    try std.testing.expectEqual(@as(u32, 0x2000), info.cli_header_rva);
    try std.testing.expectEqual(@as(usize, 1), info.sections.len);
}
