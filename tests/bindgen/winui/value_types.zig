/// Value type representation probes.
/// Verifies enum struct-with-constants format and cross-WinMD struct emission.
const std = @import("std");
const support = @import("test_support");
const cache_alloc = support.context.cache_alloc;
const generateWinuiOutput = support.winui.generateWinuiOutput;

test "WINUI #124: CorePhysicalKeyStatus is emitted as extern struct" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "IKeyRoutedEventArgs") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const CorePhysicalKeyStatus = extern struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "RepeatCount: u32,") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "ScanCode: u32,") != null);
}

test "WINUI #124: VirtualKey is emitted as struct-with-constants, not enum" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "IKeyRoutedEventArgs") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const VirtualKey = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const VirtualKey = enum(") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const None: i32 = 0;") != null);
}

test "WINUI #124: GridLength struct emitted via dependency closure" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "IRowDefinition") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const GridLength = extern struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "Value: f64,") != null);
}

test "WINUI #124: GridUnitType emitted as struct-with-constants" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "IRowDefinition") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const GridUnitType = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const GridUnitType = enum(") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const Pixel: i32 =") != null);
}
