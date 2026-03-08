const std = @import("std");
const pe = @import("pe.zig");

pub const MetadataError = error{
    Truncated,
    BadCliHeader,
    BadMetadataSignature,
    MissingStream,
} || pe.PeError || std.mem.Allocator.Error;

pub const StreamInfo = struct {
    name: []const u8,
    data: []const u8,
    offset: u32,
    size: u32,
};

pub const Info = struct {
    metadata_offset: usize,
    metadata_size: u32,
    streams: []const StreamInfo,

    pub fn getStream(self: Info, name: []const u8) ?StreamInfo {
        for (self.streams) |s| {
            if (std.mem.eql(u8, s.name, name)) return s;
        }
        return null;
    }
};

pub fn parse(allocator: std.mem.Allocator, pe_info: pe.Info) MetadataError!Info {
    const cli_off = try pe_info.rvaToOffset(pe_info.cli_header_rva);
    if (cli_off + 16 > pe_info.data.len) return error.Truncated;

    const cb = readU32(pe_info.data, cli_off) orelse return error.Truncated;
    if (cb < 16) return error.BadCliHeader;
    const metadata_rva = readU32(pe_info.data, cli_off + 8) orelse return error.Truncated;
    const metadata_size = readU32(pe_info.data, cli_off + 12) orelse return error.Truncated;
    if (metadata_rva == 0 or metadata_size == 0) return error.BadCliHeader;

    const md_off = try pe_info.rvaToOffset(metadata_rva);
    if (md_off + metadata_size > pe_info.data.len) return error.Truncated;
    if (readU32(pe_info.data, md_off) != 0x424A5342) return error.BadMetadataSignature; // BSJB

    var cursor = md_off + 4;
    _ = readU16(pe_info.data, cursor) orelse return error.Truncated; // major
    cursor += 2;
    _ = readU16(pe_info.data, cursor) orelse return error.Truncated; // minor
    cursor += 2;
    _ = readU32(pe_info.data, cursor) orelse return error.Truncated; // reserved
    cursor += 4;
    const version_len = readU32(pe_info.data, cursor) orelse return error.Truncated;
    cursor += 4;
    if (cursor + version_len > pe_info.data.len) return error.Truncated;
    cursor += align4(version_len);

    _ = readU16(pe_info.data, cursor) orelse return error.Truncated; // flags
    cursor += 2;
    const stream_count = readU16(pe_info.data, cursor) orelse return error.Truncated;
    cursor += 2;

    const streams = try allocator.alloc(StreamInfo, stream_count);
    for (streams, 0..) |*s, i| {
        _ = i;
        const stream_rel_off = readU32(pe_info.data, cursor) orelse return error.Truncated;
        cursor += 4;
        const stream_size = readU32(pe_info.data, cursor) orelse return error.Truncated;
        cursor += 4;

        const name_start = cursor;
        var name_end = name_start;
        while (name_end < pe_info.data.len and pe_info.data[name_end] != 0) : (name_end += 1) {}
        if (name_end >= pe_info.data.len) return error.Truncated;

        const name = pe_info.data[name_start..name_end];
        const name_bytes_with_nul = (name_end - name_start) + 1;
        cursor += align4(@intCast(name_bytes_with_nul));

        const abs_off = md_off + stream_rel_off;
        if (abs_off + stream_size > pe_info.data.len) return error.Truncated;
        s.* = .{
            .name = name,
            .data = pe_info.data[abs_off .. abs_off + stream_size],
            .offset = stream_rel_off,
            .size = stream_size,
        };
    }

    return .{
        .metadata_offset = md_off,
        .metadata_size = metadata_size,
        .streams = streams,
    };
}

fn align4(v: u32) u32 {
    return (v + 3) & ~@as(u32, 3);
}

fn readU16(data: []const u8, off: usize) ?u16 {
    if (off + 2 > data.len) return null;
    return std.mem.readInt(u16, data[off..][0..2], .little);
}

fn readU32(data: []const u8, off: usize) ?u32 {
    if (off + 4 > data.len) return null;
    return std.mem.readInt(u32, data[off..][0..4], .little);
}

test "align4 rounds up to 4-byte boundary" {
    try std.testing.expectEqual(@as(u32, 0), align4(0));
    try std.testing.expectEqual(@as(u32, 4), align4(1));
    try std.testing.expectEqual(@as(u32, 4), align4(4));
    try std.testing.expectEqual(@as(u32, 8), align4(5));
}

test "getStream finds stream by name" {
    const streams_arr = [_]StreamInfo{
        .{ .name = "#~", .data = &.{ 1, 2 }, .offset = 1, .size = 2 },
        .{ .name = "#Strings", .data = &.{ 3 }, .offset = 3, .size = 1 },
    };
    const info = Info{
        .metadata_offset = 0,
        .metadata_size = 0,
        .streams = &streams_arr,
    };
    try std.testing.expect(info.getStream("#~") != null);
    try std.testing.expect(info.getStream("#Blob") == null);
}

test "parse rejects bad metadata signature" {
    var data: [0x200]u8 = .{0} ** 0x200;
    // CLI header at 0x40
    std.mem.writeInt(u32, data[0x40..][0..4], 16, .little);
    std.mem.writeInt(u32, data[0x48..][0..4], 0x80, .little); // metadata RVA
    std.mem.writeInt(u32, data[0x4c..][0..4], 0x60, .little); // metadata size

    const p = pe.Info{
        .data = &data,
        .sections = &.{},
        .cli_header_rva = 0x40,
        .cli_header_size = 16,
    };
    try std.testing.expectError(error.BadMetadataSignature, parse(std.testing.allocator, p));
}

test "parse reads single stream metadata header" {
    var data: [0x200]u8 = .{0} ** 0x200;
    // CLI header at 0x40
    std.mem.writeInt(u32, data[0x40..][0..4], 16, .little);
    std.mem.writeInt(u32, data[0x48..][0..4], 0x80, .little); // metadata RVA
    std.mem.writeInt(u32, data[0x4c..][0..4], 0x60, .little); // metadata size

    const md: usize = 0x80;
    std.mem.writeInt(u32, data[md..][0..4], 0x424A5342, .little); // BSJB
    std.mem.writeInt(u16, data[md + 4 ..][0..2], 1, .little); // major
    std.mem.writeInt(u16, data[md + 6 ..][0..2], 1, .little); // minor
    std.mem.writeInt(u32, data[md + 8 ..][0..4], 0, .little); // reserved
    std.mem.writeInt(u32, data[md + 12 ..][0..4], 12, .little); // version length
    @memcpy(data[md + 16 ..][0..12], "v4.0.30319\x00\x00");
    std.mem.writeInt(u16, data[md + 28 ..][0..2], 0, .little); // flags
    std.mem.writeInt(u16, data[md + 30 ..][0..2], 1, .little); // stream count

    std.mem.writeInt(u32, data[md + 32 ..][0..4], 0x40, .little); // stream rel offset
    std.mem.writeInt(u32, data[md + 36 ..][0..4], 4, .little); // stream size
    @memcpy(data[md + 40 ..][0..3], "#~\x00");

    @memcpy(data[md + 0x40 ..][0..4], &[_]u8{ 0xaa, 0xbb, 0xcc, 0xdd });

    const p = pe.Info{
        .data = &data,
        .sections = &.{},
        .cli_header_rva = 0x40,
        .cli_header_size = 16,
    };

    const info = try parse(std.testing.allocator, p);
    defer std.testing.allocator.free(info.streams);
    try std.testing.expectEqual(@as(usize, md), info.metadata_offset);
    try std.testing.expectEqual(@as(usize, 1), info.streams.len);
    const s = info.getStream("#~") orelse return error.MissingStream;
    try std.testing.expectEqual(@as(u32, 4), s.size);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xbb, 0xcc, 0xdd }, s.data);
}
