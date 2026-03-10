/// Delegate generation probes.
/// Verifies delegate vtable correctness (.ctor exclusion, Invoke presence).
const std = @import("std");
const support = @import("test_support");
const generateWinuiOutput = support.winui.generateWinuiOutput;

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
