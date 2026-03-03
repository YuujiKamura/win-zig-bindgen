const std = @import("std");

pub const HeapError = error{
    InvalidIndex,
    InvalidCompressedInt,
    Truncated,
};

pub const Heaps = struct {
    strings: []const u8,
    blob: []const u8,
    guid: []const u8,

    pub fn getString(self: Heaps, index: u32) HeapError![]const u8 {
        if (index == 0) return "";
        if (index >= self.strings.len) return error.InvalidIndex;
        const start = @as(usize, index);
        const end = std.mem.indexOfScalarPos(u8, self.strings, start, 0) orelse return error.Truncated;
        return self.strings[start..end];
    }

    pub fn getBlob(self: Heaps, index: u32) HeapError![]const u8 {
        if (index == 0) return &.{};
        if (index >= self.blob.len) return error.InvalidIndex;
        const start = @as(usize, index);
        const len_info = try decodeCompressedUInt(self.blob[start..]);
        const data_start = start + len_info.used;
        const data_end = data_start + len_info.value;
        if (data_end > self.blob.len) return error.Truncated;
        return self.blob[data_start..data_end];
    }

    pub fn getGuid(self: Heaps, index: u32) HeapError![16]u8 {
        if (index == 0) return error.InvalidIndex;
        const start = (@as(usize, index) - 1) * 16;
        if (start + 16 > self.guid.len) return error.InvalidIndex;
        return self.guid[start..][0..16].*;
    }
};

pub const CompressedUInt = struct {
    value: usize,
    used: usize,
};

pub fn decodeCompressedUInt(data: []const u8) HeapError!CompressedUInt {
    if (data.len == 0) return error.InvalidCompressedInt;
    const b0 = data[0];
    if ((b0 & 0x80) == 0) {
        return .{ .value = b0, .used = 1 };
    }
    if ((b0 & 0xC0) == 0x80) {
        if (data.len < 2) return error.InvalidCompressedInt;
        const value = (@as(usize, b0 & 0x3F) << 8) | data[1];
        return .{ .value = value, .used = 2 };
    }
    if ((b0 & 0xE0) == 0xC0) {
        if (data.len < 4) return error.InvalidCompressedInt;
        const value = (@as(usize, b0 & 0x1F) << 24) |
            (@as(usize, data[1]) << 16) |
            (@as(usize, data[2]) << 8) |
            data[3];
        return .{ .value = value, .used = 4 };
    }
    return error.InvalidCompressedInt;
}

test "blob heap reads compressed-length payload" {
    // Index 1 -> length 3 -> bytes AA BB CC.
    const heaps = Heaps{
        .strings = &.{},
        .blob = &.{ 0x00, 0x03, 0xaa, 0xbb, 0xcc },
        .guid = &.{},
    };
    const b = try heaps.getBlob(1);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xbb, 0xcc }, b);
}

test "guid heap is 1-based" {
    var bytes: [32]u8 = undefined;
    for (&bytes, 0..) |*v, i| v.* = @intCast(i);
    const heaps = Heaps{
        .strings = &.{},
        .blob = &.{},
        .guid = &bytes,
    };
    const g = try heaps.getGuid(2);
    try std.testing.expectEqual(@as(u8, 16), g[0]);
    try std.testing.expectEqual(@as(u8, 31), g[15]);
}
