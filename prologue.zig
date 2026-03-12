const std = @import("std");

pub fn writePrologue(writer: anytype) !void {
    try writer.writeAll(
        \\//! WinUI 3 COM interface definitions for Zig.
        \\//! GENERATED CODE - DO NOT EDIT.
        \\const std = @import("std");
        \\pub const GUID = extern struct {
        \\    data1: u32,
        \\    data2: u16,
        \\    data3: u16,
        \\    data4: [8]u8,
        \\
        \\    pub fn equals(self: GUID, other: GUID) bool {
        \\        return self.data1 == other.data1 and self.data2 == other.data2 and self.data3 == other.data3 and std.mem.eql(u8, &self.data4, &other.data4);
        \\    }
        \\};
        \\pub const HRESULT = i32;
        \\
    );
    try writePrologueSharedTail(writer);
}

pub fn writePrologueWithImport(writer: anytype, winrt_import: []const u8) !void {
    try writer.print(
        \\//! WinUI 3 COM interface definitions for Zig.
        \\//! GENERATED CODE - DO NOT EDIT.
        \\const std = @import("std");
        \\const winrt = @import("{s}");
        \\pub const GUID = winrt.GUID;
        \\pub const HRESULT = winrt.HRESULT;
        \\
    , .{winrt_import});
    // Write the rest of the prologue (from BOOL onwards, shared with writePrologue)
    try writePrologueSharedTail(writer);
}

fn writePrologueSharedTail(writer: anytype) !void {
    try writer.writeAll(
        \\pub const BOOL = i32;
        \\pub const FARPROC = ?*anyopaque;
        \\pub const HSTRING = ?*anyopaque;
        \\pub const HANDLE = extern struct {
        \\    Value: isize,
        \\    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
        \\};
        \\pub const HWND = extern struct {
        \\    Value: isize,
        \\    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
        \\};
        \\pub const HINSTANCE = extern struct {
        \\    Value: isize,
        \\    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
        \\};
        \\pub const HMODULE = extern struct {
        \\    Value: isize,
        \\    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
        \\};
        \\pub const WPARAM = extern struct { Value: usize };
        \\pub const LPARAM = extern struct { Value: isize };
        \\pub const LPCWSTR = [*]const u16;
        \\pub const LPWSTR = [*]u16;
        \\pub const POINT = extern struct {
        \\    x: i32,
        \\    y: i32,
        \\};
        \\pub const RECT = extern struct {
        \\    left: i32,
        \\    top: i32,
        \\    right: i32,
        \\    bottom: i32,
        \\};
        \\pub const EventRegistrationToken = i64;
        \\
        \\pub const VtblPlaceholder = ?*const anyopaque;
        \\
        \\pub const IID_RoutedEventHandler = GUID{ .data1 = 0xaf8dae19, .data2 = 0x0794, .data3 = 0x5695, .data4 = .{ 0x96, 0x8a, 0x07, 0x33, 0x3f, 0x92, 0x32, 0xe0 } };
        \\pub const IID_SizeChangedEventHandler = GUID{ .data1 = 0x8d7b1a58, .data2 = 0x14c6, .data3 = 0x51c9, .data4 = .{ 0x89, 0x2c, 0x9f, 0xcc, 0xe3, 0x68, 0xe7, 0x7d } };
        \\pub const IID_SelectionChangedEventHandler = GUID{ .data1 = 0xa232390d, .data2 = 0x0e34, .data3 = 0x595e, .data4 = .{ 0x89, 0x31, 0xfa, 0x92, 0x8a, 0x99, 0x09, 0xf4 } };
        \\
        \\pub fn comRelease(self: anytype) void {
        \\    const obj: *IUnknown = @ptrCast(@alignCast(self));
        \\    _ = obj.lpVtbl.Release(@ptrCast(obj));
        \\}
        \\
        \\pub fn comQueryInterface(self: anytype, comptime T: type) !*T {
        \\    const obj: *IUnknown = @ptrCast(@alignCast(self));
        \\    var out: ?*anyopaque = null;
        \\    const hr = obj.lpVtbl.QueryInterface(@ptrCast(obj), &T.IID, &out);
        \\    if (hr < 0) return error.WinRTFailed;
        \\    return @ptrCast(@alignCast(out.?));
        \\}
        \\
        \\pub fn hrCheck(hr: HRESULT) !void {
        \\    if (hr < 0) return error.WinRTFailed;
        \\}
        \\
        \\pub fn isValidComPtr(ptr: usize) bool {
        \\    if (ptr == 0 or ptr == 0xFFFFFFFF or ptr == 0xFFFFFFFFFFFFFFFF) return false;
        \\    if (ptr < 0x10000) return false;
        \\    return true;
        \\}
        \\
        \\pub const IUnknown = extern struct {
        \\    pub const IID = GUID{ .data1 = 0x00000000, .data2 = 0x0000, .data3 = 0x0000, .data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
        \\    lpVtbl: *const VTable,
        \\    pub const VTable = extern struct {
        \\        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        \\        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        \\        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        \\    };
        \\    pub fn release(self: *@This()) void { comRelease(self); }
        \\    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
        \\};
        \\
        \\pub const IInspectable = extern struct {
        \\    pub const IID = GUID{ .data1 = 0xAFDBDF05, .data2 = 0x2D12, .data3 = 0x4D31, .data4 = .{ 0x84, 0x1F, 0x72, 0x71, 0x50, 0x51, 0x46, 0x46 } };
        \\    lpVtbl: *const VTable,
        \\    pub const VTable = extern struct {
        \\        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        \\        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        \\        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        \\        GetIids: VtblPlaceholder,
        \\        GetRuntimeClassName: VtblPlaceholder,
        \\        GetTrustLevel: VtblPlaceholder,
        \\    };
        \\    pub fn release(self: *@This()) void { comRelease(self); }
        \\    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
        \\};
        \\
    );
}
