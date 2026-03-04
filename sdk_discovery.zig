const std = @import("std");

pub fn findWindowsKitUnionWinmdAlloc(allocator: std.mem.Allocator) ![]u8 {
    const pf86 = std.process.getEnvVarOwned(allocator, "ProgramFiles(x86)") catch null;
    const pf = std.process.getEnvVarOwned(allocator, "ProgramFiles") catch null;
    defer if (pf86) |v| allocator.free(v);
    defer if (pf) |v| allocator.free(v);

    const root = pf86 orelse pf orelse return error.FileNotFound;
    const base = try std.fs.path.join(allocator, &.{ root, "Windows Kits", "10", "UnionMetadata" });
    defer allocator.free(base);

    var dir = try std.fs.openDirAbsolute(base, .{ .iterate = true });
    defer dir.close();

    var versions = std.ArrayList([]const u8).empty;
    defer {
        for (versions.items) |v| allocator.free(v);
        versions.deinit(allocator);
    }

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.startsWith(u8, entry.name, "10.")) continue;
        try versions.append(allocator, try allocator.dupe(u8, entry.name));
    }
    if (versions.items.len == 0) return error.FileNotFound;

    std.mem.sort([]const u8, versions.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return compareVersionDesc(a, b);
        }
    }.lessThan);

    for (versions.items) |v| {
        const p = try std.fmt.allocPrint(allocator, "{s}\\{s}\\Windows.winmd", .{ base, v });
        errdefer allocator.free(p);
        std.fs.accessAbsolute(p, .{}) catch continue;
        return p;
    }
    return error.FileNotFound;
}

fn compareVersionDesc(a: []const u8, b: []const u8) bool {
    const va = parseVersion(a);
    const vb = parseVersion(b);

    if (va.valid and vb.valid) {
        var i: usize = 0;
        while (i < va.count or i < vb.count) : (i += 1) {
            const av: u64 = if (i < va.count) va.parts[i] else 0;
            const bv: u64 = if (i < vb.count) vb.parts[i] else 0;
            if (av == bv) continue;
            return av > bv;
        }
        return false;
    }
    if (va.valid != vb.valid) return va.valid;
    return std.mem.order(u8, a, b) == .gt;
}

const ParsedVersion = struct {
    valid: bool,
    parts: [8]u64 = .{0} ** 8,
    count: usize = 0,
};

fn parseVersion(v: []const u8) ParsedVersion {
    var out: ParsedVersion = .{ .valid = true };
    var it = std.mem.splitScalar(u8, v, '.');
    while (it.next()) |seg| {
        if (seg.len == 0 or out.count >= out.parts.len) return .{ .valid = false };
        for (seg) |ch| {
            if (ch < '0' or ch > '9') return .{ .valid = false };
        }
        out.parts[out.count] = std.fmt.parseInt(u64, seg, 10) catch return .{ .valid = false };
        out.count += 1;
    }
    return out;
}
