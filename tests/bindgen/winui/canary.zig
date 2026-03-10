/// Exception manifest integrity probes.
/// Verifies winui_native_exceptions.json consistency for downstream consumers.
const std = @import("std");

fn readManifest(allocator: std.mem.Allocator) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, "winui_native_exceptions.json", 1024 * 1024) catch |e| {
        std.debug.print("Cannot read winui_native_exceptions.json: {}\n", .{e});
        return error.SkipZigTest;
    };
}

test "WINUI #122: exception manifest has no consumer_alias entries" {
    const allocator = std.testing.allocator;
    const json_data = try readManifest(allocator);
    defer allocator.free(json_data);
    const types_end = std.mem.indexOf(u8, json_data, "\"removed\"") orelse json_data.len;
    const types_section = json_data[0..types_end];
    try std.testing.expect(std.mem.indexOf(u8, types_section, "\"consumer_alias\"") == null);
}

test "WINUI #122: every exception entry has a category" {
    const allocator = std.testing.allocator;
    const json_data = try readManifest(allocator);
    defer allocator.free(json_data);
    var entry_count: usize = 0;
    var cat_count: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, json_data, pos, "\"keep_handwritten\"")) |p| {
        entry_count += 1;
        pos = p + 1;
    }
    pos = 0;
    const types_end = std.mem.indexOf(u8, json_data, "\"removed\"") orelse json_data.len;
    while (pos < types_end) {
        if (std.mem.indexOfPos(u8, json_data, pos, "\"category\"")) |p| {
            if (p < types_end) {
                cat_count += 1;
                pos = p + 1;
            } else break;
        } else break;
    }
    try std.testing.expect(cat_count >= entry_count);
}

test "WINUI #122: no stale consumer_alias in active types" {
    const allocator = std.testing.allocator;
    const json_data = try readManifest(allocator);
    defer allocator.free(json_data);
    const types_end = std.mem.indexOf(u8, json_data, "\"removed\"") orelse json_data.len;
    const types_section = json_data[0..types_end];
    try std.testing.expect(std.mem.indexOf(u8, types_section, "IFrameworkElement2") == null);
    try std.testing.expect(std.mem.indexOf(u8, types_section, "IPanel2") == null);
    const removed_section = json_data[types_end..];
    try std.testing.expect(std.mem.indexOf(u8, removed_section, "IFrameworkElement2") != null);
    try std.testing.expect(std.mem.indexOf(u8, removed_section, "IPanel2") != null);
}
