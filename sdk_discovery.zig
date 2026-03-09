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

pub fn findWin32DefaultWinmdAlloc(allocator: std.mem.Allocator) ![]u8 {
    // Try NuGet package cache first
    const userprofile = std.process.getEnvVarOwned(allocator, "USERPROFILE") catch null;
    defer if (userprofile) |v| allocator.free(v);

    if (userprofile) |home| {
        const nuget_base = try std.fs.path.join(allocator, &.{ home, ".nuget", "packages", "microsoft.windows.sdk.win32metadata" });
        defer allocator.free(nuget_base);

        if (std.fs.openDirAbsolute(nuget_base, .{ .iterate = true })) |*dir_ptr| {
            var dir = dir_ptr.*;
            defer dir.close();
            var versions = std.ArrayList([]const u8).empty;
            defer {
                for (versions.items) |v| allocator.free(v);
                versions.deinit(allocator);
            }
            var it = dir.iterate();
            while (try it.next()) |entry| {
                if (entry.kind != .directory) continue;
                try versions.append(allocator, try allocator.dupe(u8, entry.name));
            }
            if (versions.items.len > 0) {
                std.mem.sort([]const u8, versions.items, {}, struct {
                    fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                        return compareVersionDesc(a, b);
                    }
                }.lessThan);
                for (versions.items) |v| {
                    const p = try std.fmt.allocPrint(allocator, "{s}\\{s}\\Windows.Win32.winmd", .{ nuget_base, v });
                    errdefer allocator.free(p);
                    std.fs.accessAbsolute(p, .{}) catch {
                        allocator.free(p);
                        continue;
                    };
                    return p;
                }
            }
        } else |_| {}
    }

    // Try Windows SDK References folder
    const pf86 = std.process.getEnvVarOwned(allocator, "ProgramFiles(x86)") catch null;
    const pf = std.process.getEnvVarOwned(allocator, "ProgramFiles") catch null;
    defer if (pf86) |v| allocator.free(v);
    defer if (pf) |v| allocator.free(v);

    const root = pf86 orelse pf orelse return error.FileNotFound;
    const base = try std.fs.path.join(allocator, &.{ root, "Windows Kits", "10", "References" });
    defer allocator.free(base);

    if (std.fs.openDirAbsolute(base, .{ .iterate = true })) |*dir_ptr| {
        var dir = dir_ptr.*;
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
        if (versions.items.len > 0) {
            std.mem.sort([]const u8, versions.items, {}, struct {
                fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                    return compareVersionDesc(a, b);
                }
            }.lessThan);
            for (versions.items) |v| {
                const p = try std.fmt.allocPrint(allocator, "{s}\\{s}\\Windows.Win32.winmd", .{ base, v });
                errdefer allocator.free(p);
                std.fs.accessAbsolute(p, .{}) catch {
                    allocator.free(p);
                    continue;
                };
                return p;
            }
        }
    } else |_| {}

    return error.FileNotFound;
}

pub fn findXamlWinmdAlloc(allocator: std.mem.Allocator) ![]u8 {
    const userprofile = std.process.getEnvVarOwned(allocator, "USERPROFILE") catch null;
    defer if (userprofile) |v| allocator.free(v);

    const home = userprofile orelse return error.FileNotFound;
    const nuget_base = try std.fs.path.join(allocator, &.{ home, ".nuget", "packages", "microsoft.windowsappsdk" });
    defer allocator.free(nuget_base);

    var dir = std.fs.openDirAbsolute(nuget_base, .{ .iterate = true }) catch return error.FileNotFound;
    defer dir.close();

    var versions = std.ArrayList([]const u8).empty;
    defer {
        for (versions.items) |v| allocator.free(v);
        versions.deinit(allocator);
    }

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        try versions.append(allocator, try allocator.dupe(u8, entry.name));
    }
    if (versions.items.len == 0) return error.FileNotFound;

    std.mem.sort([]const u8, versions.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return compareVersionDesc(a, b);
        }
    }.lessThan);

    for (versions.items) |v| {
        const p = try std.fs.path.join(allocator, &.{ nuget_base, v, "lib", "uap10.0", "Microsoft.UI.Xaml.winmd" });
        errdefer allocator.free(p);
        std.fs.accessAbsolute(p, .{}) catch {
            allocator.free(p);
            continue;
        };
        return p;
    }
    return error.FileNotFound;
}

/// Discover Microsoft.UI.winmd (contains Microsoft.UI.Input namespace, IPointerPoint etc.)
/// Located at: .nuget/packages/microsoft.windowsappsdk/<ver>/lib/uap10.0.<build>/Microsoft.UI.winmd
pub fn findMicrosoftUiWinmdAlloc(allocator: std.mem.Allocator) ![]u8 {
    const userprofile = std.process.getEnvVarOwned(allocator, "USERPROFILE") catch null;
    defer if (userprofile) |v| allocator.free(v);

    const home = userprofile orelse return error.FileNotFound;
    const nuget_base = try std.fs.path.join(allocator, &.{ home, ".nuget", "packages", "microsoft.windowsappsdk" });
    defer allocator.free(nuget_base);

    var dir = std.fs.openDirAbsolute(nuget_base, .{ .iterate = true }) catch return error.FileNotFound;
    defer dir.close();

    var versions = std.ArrayList([]const u8).empty;
    defer {
        for (versions.items) |v| allocator.free(v);
        versions.deinit(allocator);
    }

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        try versions.append(allocator, try allocator.dupe(u8, entry.name));
    }
    if (versions.items.len == 0) return error.FileNotFound;

    std.mem.sort([]const u8, versions.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return compareVersionDesc(a, b);
        }
    }.lessThan);

    // Try uap10.0.18362 first (higher min version), then uap10.0.17763
    const subdirs = [_][]const u8{ "uap10.0.18362", "uap10.0.17763" };
    for (versions.items) |v| {
        for (subdirs) |subdir| {
            const p = try std.fs.path.join(allocator, &.{ nuget_base, v, "lib", subdir, "Microsoft.UI.winmd" });
            std.fs.accessAbsolute(p, .{}) catch {
                allocator.free(p);
                continue;
            };
            return p;
        }
    }
    return error.FileNotFound;
}

fn parseVersion(v: []const u8) ParsedVersion {
    // Strip pre-release suffix (e.g. "69.0.7-preview" → "69.0.7")
    const base = if (std.mem.indexOfScalar(u8, v, '-')) |dash| v[0..dash] else v;
    var out: ParsedVersion = .{ .valid = true };
    var it = std.mem.splitScalar(u8, base, '.');
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
