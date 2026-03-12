/// Cross-WinMD type resolution probes.
/// Verifies that types resolve to concrete names, not anyopaque.
const std = @import("std");
const support = @import("test_support");
const cache_alloc = support.context.cache_alloc;
const generateWinuiOutput = support.winui.generateWinuiOutput;

// ============================================================
// Key/KeyStatus resolution (IKeyRoutedEventArgs)
// ============================================================

test "WINUI IKeyRoutedEventArgs: Key getter uses i32, not anyopaque" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "IKeyRoutedEventArgs") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "Key: *const fn (*anyopaque, *i32)") != null);
}

test "WINUI IKeyRoutedEventArgs: KeyStatus getter uses CorePhysicalKeyStatus, not anyopaque" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "IKeyRoutedEventArgs") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "KeyStatus: *const fn (*anyopaque, *CorePhysicalKeyStatus)") != null);
}

test "WINUI IKeyRoutedEventArgs: OriginalKey getter uses i32, not anyopaque" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "IKeyRoutedEventArgs") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "OriginalKey: *const fn (*anyopaque, *i32)") != null);
}

test "WINUI ICharacterReceivedRoutedEventArgs: KeyStatus getter uses CorePhysicalKeyStatus" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "ICharacterReceivedRoutedEventArgs") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "KeyStatus: *const fn (*anyopaque, *CorePhysicalKeyStatus)") != null);
}

test "WINUI IXamlReaderStatics: Load vtable out-param is typed, not anyopaque" {
    const allocator = std.testing.allocator;
    const generated = generateWinuiOutput(allocator, "IXamlReaderStatics") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "!*IInspectable") != null);
}

// ============================================================
// GENERICINST resolution
// ============================================================

test "WINUI #119: ThemeDictionaries getter resolves GENERICINST IMap, not anyopaque" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "IResourceDictionary") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // After Category A fix, GENERICINST IMap`2 should resolve to IMap, not ?*anyopaque
    const bad = "pub fn ThemeDictionaries(self: *@This()) !*anyopaque";
    try std.testing.expect(std.mem.indexOf(u8, generated, bad) == null);
}

// ============================================================
// Cross-WinMD resolution (companion WinMDs)
// ============================================================

test "WINUI #120: IWindow.CoreWindow resolves, not anyopaque" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "IWindow") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    const bad = "pub fn CoreWindow(self: *@This()) !*anyopaque";
    try std.testing.expect(std.mem.indexOf(u8, generated, bad) == null);
}

test "WINUI #120: IWindow.DispatcherQueue resolves, not anyopaque" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "IWindow") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    const bad = "pub fn DispatcherQueue(self: *@This()) !*anyopaque";
    try std.testing.expect(std.mem.indexOf(u8, generated, bad) == null);
}

// ============================================================
// Importability — interface getters return typed pointers
// ============================================================

test "WINUI ITabView: AddTabButtonCommand returns typed !*ICommand, not anyopaque" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "ITabView") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "!*ICommand") != null);
}

test "WINUI ITabView: GetExtensionInstance returns typed !*IDataTemplateExtension" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "ITabView") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "!*IDataTemplateExtension") != null);
}

test "WINUI ITabView: TabItems returns typed !*IVector (pre-existing importable)" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "ITabView") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "!*IVector") != null);
}

// ============================================================
// Pointer family — non-I* COM class resolution
// ============================================================

test "WINUI #125: IPointerRoutedEventArgs.GetCurrentPoint returns typed IPointerPoint" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "IPointerRoutedEventArgs") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    const bad = "pub fn GetCurrentPoint(";
    const good = "!*IPointerPoint";
    try std.testing.expect(std.mem.indexOf(u8, generated, bad) != null);
    const wrapper_pos = std.mem.indexOf(u8, generated, bad).?;
    const wrapper_line_end = std.mem.indexOfScalarPos(u8, generated, wrapper_pos, '\n') orelse generated.len;
    const wrapper_line = generated[wrapper_pos..wrapper_line_end];
    try std.testing.expect(std.mem.indexOf(u8, wrapper_line, good) != null);
}

test "WINUI #125: IPointerRoutedEventArgs.GetCurrentPoint does NOT return anyopaque" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "IPointerRoutedEventArgs") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    const bad_sig = "pub fn GetCurrentPoint(self: *@This()) !*anyopaque";
    try std.testing.expect(std.mem.indexOf(u8, generated, bad_sig) == null);
}

test "WINUI #125: PointerPoint struct emitted via dependency closure from Microsoft.UI.winmd" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "IPointerRoutedEventArgs") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const PointerPoint = extern struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const IPointerPoint = extern struct") != null);
}

// ============================================================
// SZARRAY — array return and input parameter expansion (#18)
// ============================================================

test "WINUI #18: GetXmlnsDefinitions SZARRAY return expands to count+items out params" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "IXamlMetadataProvider") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // Wrapper should return struct { count: u32, items: ?*anyopaque }
    try std.testing.expect(std.mem.indexOf(u8, generated, "count: u32, items: ?*anyopaque") != null);
}

test "WINUI #18: GetXmlnsDefinitions vtable has *u32 and *?*anyopaque out params" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "IXamlMetadataProvider") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // Vtable should have: GetXmlnsDefinitions: *const fn (*anyopaque, *u32, *?*anyopaque) callconv(.winapi) HRESULT
    try std.testing.expect(std.mem.indexOf(u8, generated, "GetXmlnsDefinitions: *const fn (*anyopaque, *u32, *?*anyopaque)") != null);
}

test "WINUI #18: SZARRAY return does NOT use bare 'SZARRAY' string in output" {
    const allocator = cache_alloc;
    const generated = generateWinuiOutput(allocator, "IXamlMetadataProvider") catch |e| {
        if (e == error.SkipZigTest) return e;
        return e;
    };
    defer allocator.free(generated);
    // The raw "SZARRAY" marker must never appear in generated output
    try std.testing.expect(std.mem.indexOf(u8, generated, "SZARRAY") == null);
}
