/// Delegate generation probes.
/// Verifies delegate vtable correctness (.ctor exclusion, Invoke presence).
const std = @import("std");
const support = @import("test_support");
const generateWinuiOutput = support.winui.generateWinuiOutput;

fn extractBlock(
    text: []const u8,
    start_marker: []const u8,
    end_marker: []const u8,
) ![]const u8 {
    const start = std.mem.indexOf(u8, text, start_marker) orelse return error.TestUnexpectedResult;
    const tail = text[start..];
    const end_rel = std.mem.indexOf(u8, tail, end_marker) orelse return error.TestUnexpectedResult;
    return tail[0 .. end_rel + end_marker.len];
}

test "WINUI ScrollEventHandler: no .ctor in vtable" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "ScrollEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "ctor:") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn ctor(") == null);
}

test "WINUI ScrollEventHandler: has Invoke but not .ctor wrapper" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "ScrollEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn invoke(") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn ctor(") == null);
}

test "WINUI ScrollEventHandler: Invoke slot exists" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "ScrollEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "Invoke: *const fn") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn invoke(") != null);
}

test "WINUI RoutedEventHandler: no .ctor wrapper" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "RoutedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn ctor(") == null);
}

test "WINUI RoutedEventHandler: delegate vtable is IUnknown plus Invoke" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "RoutedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);

    const block = try extractBlock(
        generated,
        "pub const RoutedEventHandler = extern struct {\n",
        "    pub fn release(self: *@This()) void { comRelease(self); }\n",
    );
    const vtable = try extractBlock(
        block,
        "    pub const VTable = extern struct {\n",
        "    };\n",
    );

    try std.testing.expect(std.mem.indexOf(u8, vtable, "GetIids:") == null);
    try std.testing.expect(std.mem.indexOf(u8, vtable, "GetRuntimeClassName:") == null);
    try std.testing.expect(std.mem.indexOf(u8, vtable, "GetTrustLevel:") == null);

    const qi = std.mem.indexOf(u8, vtable, "        QueryInterface:") orelse return error.TestUnexpectedResult;
    const addref = std.mem.indexOf(u8, vtable, "        AddRef:") orelse return error.TestUnexpectedResult;
    const release = std.mem.indexOf(u8, vtable, "        Release:") orelse return error.TestUnexpectedResult;
    const invoke = std.mem.indexOf(u8, vtable, "        Invoke:") orelse return error.TestUnexpectedResult;

    try std.testing.expect(qi < addref);
    try std.testing.expect(addref < release);
    try std.testing.expect(release < invoke);
    try std.testing.expect(std.mem.indexOf(u8, vtable[release..invoke], "VtblPlaceholder") == null);
}
