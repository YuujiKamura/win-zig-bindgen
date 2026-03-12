/// Delegate Impl generation probes.
/// Verifies that WinRT delegate types get a companion *Impl(Context, CallbackFn)
/// provider-side implementation box.
const std = @import("std");
const support = @import("test_support");
const generateWinuiOutput = support.winui.generateWinuiOutput;

test "WINUI RoutedEventHandler: has Impl companion function" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "RoutedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "RoutedEventHandlerImpl(") != null);
}

test "WINUI RoutedEventHandler: Impl has create and createWithIid" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "RoutedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn create(") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn createWithIid(") != null);
}

test "WINUI RoutedEventHandler: Impl has comPtr" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "RoutedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn comPtr(") != null);
}

test "WINUI RoutedEventHandler: no error.NotImplemented" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "RoutedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "error.NotImplemented") == null);
}

test "WINUI SizeChangedEventHandler: has Impl companion function" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "SizeChangedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "SizeChangedEventHandlerImpl(") != null);
}

test "WINUI ScrollEventHandler: has Impl companion function" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "ScrollEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "ScrollEventHandlerImpl(") != null);
}

test "WINUI SelectionChangedEventHandler: has Impl companion function" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "SelectionChangedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "SelectionChangedEventHandlerImpl(") != null);
}
