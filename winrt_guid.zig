const std = @import("std");

pub const Guid = struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,

    pub fn fromBlob(blob: [16]u8) Guid {
        return .{
            .data1 = std.mem.readInt(u32, blob[0..4], .little),
            .data2 = std.mem.readInt(u16, blob[4..6], .little),
            .data3 = std.mem.readInt(u16, blob[6..8], .little),
            .data4 = blob[8..16].*,
        };
    }

    pub fn formatDashedLower(self: Guid, writer: anytype) !void {
        try writer.print(
            "{x:0>8}-{x:0>4}-{x:0>4}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}",
            .{
                self.data1,
                self.data2,
                self.data3,
                self.data4[0],
                self.data4[1],
                self.data4[2],
                self.data4[3],
                self.data4[4],
                self.data4[5],
                self.data4[6],
                self.data4[7],
            },
        );
    }

    pub fn toDashedLowerAlloc(self: Guid, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(
            allocator,
            "{x:0>8}-{x:0>4}-{x:0>4}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}",
            .{
                self.data1,
                self.data2,
                self.data3,
                self.data4[0],
                self.data4[1],
                self.data4[2],
                self.data4[3],
                self.data4[4],
                self.data4[5],
                self.data4[6],
                self.data4[7],
            },
        );
    }

    pub fn toBlob(self: Guid) [16]u8 {
        var out: [16]u8 = undefined;
        std.mem.writeInt(u32, out[0..4], self.data1, .little);
        std.mem.writeInt(u16, out[4..6], self.data2, .little);
        std.mem.writeInt(u16, out[6..8], self.data3, .little);
        @memcpy(out[8..16], &self.data4);
        return out;
    }
};

const winrt_generic_namespace: [16]u8 = .{
    0x11, 0xf4, 0x7a, 0xd5, 0x7b, 0x73, 0x42, 0xc0,
    0xab, 0xae, 0x87, 0x8b, 0x1e, 0x16, 0xad, 0xee,
};

pub fn guidFromSignature(signature: []const u8) Guid {
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(&winrt_generic_namespace);
    hasher.update(signature);

    var digest: [20]u8 = undefined;
    hasher.final(&digest);

    const first = std.mem.readInt(u32, digest[0..4], .big);
    const second = std.mem.readInt(u16, digest[4..6], .big);
    var third = std.mem.readInt(u16, digest[6..8], .big);
    third = (third & 0x0fff) | (5 << 12);
    const fourth0: u8 = (digest[8] & 0x3f) | 0x80;

    return .{
        .data1 = first,
        .data2 = second,
        .data3 = third,
        .data4 = .{
            fourth0, digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15],
        },
    };
}

pub fn classSignatureAlloc(
    allocator: std.mem.Allocator,
    runtime_name: []const u8,
    default_iface: Guid,
) ![]u8 {
    const iid = try default_iface.toDashedLowerAlloc(allocator);
    defer allocator.free(iid);
    return std.fmt.allocPrint(allocator, "rc({s};{{{s}}})", .{ runtime_name, iid });
}

pub fn typedEventHandlerIid(sender_sig: []const u8, result_sig: []const u8, allocator: std.mem.Allocator) !Guid {
    const sig = try std.fmt.allocPrint(
        allocator,
        "pinterface({{9de1c534-6ae1-11e0-84e1-18a905bcc53f}};{s};{s})",
        .{ sender_sig, result_sig },
    );
    defer allocator.free(sig);
    return guidFromSignature(sig);
}

pub const ParseGuidError = error{ InvalidGuidText };

pub fn parseGuidText(text_in: []const u8) ParseGuidError!Guid {
    var text = text_in;
    if (text.len >= 2 and text[0] == '{' and text[text.len - 1] == '}') {
        text = text[1 .. text.len - 1];
    }
    if (text.len != 36) return error.InvalidGuidText;
    if (text[8] != '-' or text[13] != '-' or text[18] != '-' or text[23] != '-') return error.InvalidGuidText;

    const d1 = parseHexU32(text[0..8]) catch return error.InvalidGuidText;
    const d2 = parseHexU16(text[9..13]) catch return error.InvalidGuidText;
    const d3 = parseHexU16(text[14..18]) catch return error.InvalidGuidText;

    var d4: [8]u8 = undefined;
    d4[0] = parseHexU8(text[19..21]) catch return error.InvalidGuidText;
    d4[1] = parseHexU8(text[21..23]) catch return error.InvalidGuidText;
    d4[2] = parseHexU8(text[24..26]) catch return error.InvalidGuidText;
    d4[3] = parseHexU8(text[26..28]) catch return error.InvalidGuidText;
    d4[4] = parseHexU8(text[28..30]) catch return error.InvalidGuidText;
    d4[5] = parseHexU8(text[30..32]) catch return error.InvalidGuidText;
    d4[6] = parseHexU8(text[32..34]) catch return error.InvalidGuidText;
    d4[7] = parseHexU8(text[34..36]) catch return error.InvalidGuidText;

    return .{
        .data1 = d1,
        .data2 = d2,
        .data3 = d3,
        .data4 = d4,
    };
}

fn parseHexNibble(c: u8) ParseGuidError!u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.InvalidGuidText,
    };
}

fn parseHexU8(s: []const u8) ParseGuidError!u8 {
    if (s.len != 2) return error.InvalidGuidText;
    return (try parseHexNibble(s[0]) << 4) | try parseHexNibble(s[1]);
}

fn parseHexU16(s: []const u8) ParseGuidError!u16 {
    if (s.len != 4) return error.InvalidGuidText;
    var v: u16 = 0;
    for (s) |c| v = (v << 4) | try parseHexNibble(c);
    return v;
}

fn parseHexU32(s: []const u8) ParseGuidError!u32 {
    if (s.len != 8) return error.InvalidGuidText;
    var v: u32 = 0;
    for (s) |c| v = (v << 4) | try parseHexNibble(c);
    return v;
}

test "signature GUID matches known SelectionChangedEventHandler-adjacent vectors" {
    const alloc = std.testing.allocator;

    // Sender: TabView runtime class signature
    const tabview_iface = Guid{
        .data1 = 0x07b509e1,
        .data2 = 0x1d38,
        .data3 = 0x551b,
        .data4 = .{ 0x95, 0xf4, 0x47, 0x32, 0xb0, 0x49, 0xf6, 0xa6 },
    };
    const sender_sig = try classSignatureAlloc(alloc, "Microsoft.UI.Xaml.Controls.TabView", tabview_iface);
    defer alloc.free(sender_sig);

    // AddTabButtonClick: TResult = cinterface(IInspectable)
    const addtab = try typedEventHandlerIid(sender_sig, "cinterface(IInspectable)", alloc);
    const addtab_str = try addtab.toDashedLowerAlloc(alloc);
    defer alloc.free(addtab_str);
    try std.testing.expectEqualStrings("13df6907-bbb4-5f16-beac-2938c15e1d85", addtab_str);

    // TabCloseRequested: TResult = TabViewTabCloseRequestedEventArgs runtime class signature
    const close_args_iface = Guid{
        .data1 = 0xd56ab9b2,
        .data2 = 0xe264,
        .data3 = 0x5c7e,
        .data4 = .{ 0xa1, 0xcb, 0xe4, 0x1a, 0x16, 0xa6, 0xc6, 0xc6 },
    };
    const close_sig = try classSignatureAlloc(alloc, "Microsoft.UI.Xaml.Controls.TabViewTabCloseRequestedEventArgs", close_args_iface);
    defer alloc.free(close_sig);

    const close = try typedEventHandlerIid(sender_sig, close_sig, alloc);
    const close_str = try close.toDashedLowerAlloc(alloc);
    defer alloc.free(close_str);
    try std.testing.expectEqualStrings("7093974b-0900-52ae-afd8-70e5623f4595", close_str);
}

test "parseGuidText accepts dashed and braced forms" {
    const a = try parseGuidText("7093974b-0900-52ae-afd8-70e5623f4595");
    const b = try parseGuidText("{7093974b-0900-52ae-afd8-70e5623f4595}");
    const sa = try a.toDashedLowerAlloc(std.testing.allocator);
    defer std.testing.allocator.free(sa);
    const sb = try b.toDashedLowerAlloc(std.testing.allocator);
    defer std.testing.allocator.free(sb);
    try std.testing.expectEqualStrings("7093974b-0900-52ae-afd8-70e5623f4595", sa);
    try std.testing.expectEqualStrings("7093974b-0900-52ae-afd8-70e5623f4595", sb);
}
