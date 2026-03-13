/// Delegate Impl generation probes.
/// Verifies that WinRT delegate types get a companion *Impl(Context, CallbackFn)
/// provider-side implementation box.
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

test "WINUI RoutedEventHandler: Impl vtable_instance omits IInspectable slots" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "RoutedEventHandler") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);

    const block = try extractBlock(
        generated,
        "pub fn RoutedEventHandlerImpl(comptime Context: type, comptime CallbackFn: type) type {\n",
        "        pub fn create(allocator: @import(\"std\").mem.Allocator, context: *Context, callback: CallbackFn) !*Self {\n",
    );
    const vtable_instance = try extractBlock(
        block,
        "        const vtable_instance = Delegate.VTable{\n",
        "        };\n",
    );

    try std.testing.expect(std.mem.indexOf(u8, vtable_instance, ".GetIids") == null);
    try std.testing.expect(std.mem.indexOf(u8, vtable_instance, ".GetRuntimeClassName") == null);
    try std.testing.expect(std.mem.indexOf(u8, vtable_instance, ".GetTrustLevel") == null);

    const qi = std.mem.indexOf(u8, vtable_instance, "            .QueryInterface =") orelse return error.TestUnexpectedResult;
    const addref = std.mem.indexOf(u8, vtable_instance, "            .AddRef =") orelse return error.TestUnexpectedResult;
    const release = std.mem.indexOf(u8, vtable_instance, "            .Release =") orelse return error.TestUnexpectedResult;
    const invoke = std.mem.indexOf(u8, vtable_instance, "            .Invoke =") orelse return error.TestUnexpectedResult;

    try std.testing.expect(qi < addref);
    try std.testing.expect(addref < release);
    try std.testing.expect(release < invoke);
}
