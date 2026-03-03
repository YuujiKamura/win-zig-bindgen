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
