//! WinUI 3 COM interface definitions for Zig.
//! GENERATED CODE - DO NOT EDIT.
const std = @import("std");
pub const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,

    pub fn equals(self: GUID, other: GUID) bool {
        return self.data1 == other.data1 and self.data2 == other.data2 and self.data3 == other.data3 and std.mem.eql(u8, &self.data4, &other.data4);
    }
};
pub const HRESULT = i32;
pub const BOOL = i32;
pub const FARPROC = ?*anyopaque;
pub const HSTRING = ?*anyopaque;
pub const HANDLE = extern struct {
    Value: isize,
    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
};
pub const HWND = extern struct {
    Value: isize,
    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
};
pub const HINSTANCE = extern struct {
    Value: isize,
    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
};
pub const HMODULE = extern struct {
    Value: isize,
    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
};
pub const WPARAM = extern struct { Value: usize };
pub const LPARAM = extern struct { Value: isize };
pub const LPCWSTR = [*]const u16;
pub const LPWSTR = [*]u16;
pub const POINT = extern struct {
    x: i32,
    y: i32,
};
pub const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};
pub const EventRegistrationToken = i64;

pub const VtblPlaceholder = ?*const anyopaque;

pub fn comRelease(self: anytype) void {
    const obj: *IUnknown = @ptrCast(@alignCast(self));
    _ = obj.lpVtbl.Release(@ptrCast(obj));
}

pub fn comQueryInterface(self: anytype, comptime T: type) !*T {
    const obj: *IUnknown = @ptrCast(@alignCast(self));
    var out: ?*anyopaque = null;
    const hr = obj.lpVtbl.QueryInterface(@ptrCast(obj), &T.IID, &out);
    if (hr < 0) return error.WinRTFailed;
    return @ptrCast(@alignCast(out.?));
}

pub fn hrCheck(hr: HRESULT) !void {
    if (hr < 0) return error.WinRTFailed;
}

pub fn isValidComPtr(ptr: usize) bool {
    if (ptr == 0 or ptr == 0xFFFFFFFF or ptr == 0xFFFFFFFFFFFFFFFF) return false;
    if (ptr < 0x10000) return false;
    return true;
}

pub const IUnknown = extern struct {
    pub const IID = GUID{ .data1 = 0x00000000, .data2 = 0x0000, .data3 = 0x0000, .data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
};

pub const IInspectable = extern struct {
    pub const IID = GUID{ .data1 = 0xAFDBDF05, .data2 = 0x2D12, .data3 = 0x4D31, .data4 = .{ 0x84, 0x1F, 0x72, 0x71, 0x50, 0x51, 0x46, 0x46 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
};
pub const IVisualTreeHelperStatics = extern struct {
    pub const IID = GUID{ .data1 = 0x5aece43c, .data2 = 0x7651, .data3 = 0x5bb5, .data4 = .{ 0x85, 0x5c, 0x21, 0x98, 0x49, 0x6e, 0x45, 0x5e } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        FindElementsInHostCoordinates: *const fn (*anyopaque, Point, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        FindElementsInHostCoordinates_2: *const fn (*anyopaque, Rect, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        FindElementsInHostCoordinates_3: *const fn (*anyopaque, Point, ?*anyopaque, bool, *?*anyopaque) callconv(.winapi) HRESULT,
        FindElementsInHostCoordinates_4: *const fn (*anyopaque, Rect, ?*anyopaque, bool, *?*anyopaque) callconv(.winapi) HRESULT,
        GetChild: *const fn (*anyopaque, ?*anyopaque, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetChildrenCount: *const fn (*anyopaque, ?*anyopaque, *i32) callconv(.winapi) HRESULT,
        GetParent: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        DisconnectChildrenRecursive: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        GetOpenPopups: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetOpenPopupsForXamlRoot: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn findElementsInHostCoordinates(self: *@This(), p0: Point, p1: ?*anyopaque) !*IIterable { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.FindElementsInHostCoordinates(self, p0, p1, &out0)); return @ptrCast(@alignCast(out0 orelse return error.WinRTFailed)); }
    pub fn FindElementsInHostCoordinates(self: *@This(), p0: Point, p1: ?*anyopaque) !*IIterable { return self.findElementsInHostCoordinates(p0, p1); }
    pub fn findElementsInHostCoordinates_1(self: *@This(), p0: Rect, p1: ?*anyopaque) !*IIterable { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.FindElementsInHostCoordinates_2(self, p0, p1, &out0)); return @ptrCast(@alignCast(out0 orelse return error.WinRTFailed)); }
    pub fn FindElementsInHostCoordinates_2(self: *@This(), p0: Rect, p1: ?*anyopaque) !*IIterable { return self.findElementsInHostCoordinates_1(p0, p1); }
    pub fn FindElementsInHostCoordinates_3(self: *@This(), p0: Point, p1: ?*anyopaque, p2: bool) !*IIterable { return self.findElementsInHostCoordinates_1(p0, p1, p2); }
    pub fn FindElementsInHostCoordinates_4(self: *@This(), p0: Rect, p1: ?*anyopaque, p2: bool) !*IIterable { return self.findElementsInHostCoordinates_1(p0, p1, p2); }
    pub fn getChild(self: *@This(), p0: ?*anyopaque, p1: i32) !*IDependencyObject { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetChild(self, p0, p1, &out0)); return @ptrCast(@alignCast(out0 orelse return error.WinRTFailed)); }
    pub fn GetChild(self: *@This(), p0: ?*anyopaque, p1: i32) !*IDependencyObject { return self.getChild(p0, p1); }
    pub fn getChildrenCount(self: *@This(), p0: ?*anyopaque) !i32 { var out0: i32 = 0; try hrCheck(self.lpVtbl.GetChildrenCount(self, p0, &out0)); return out0; }
    pub fn GetChildrenCount(self: *@This(), p0: ?*anyopaque) !i32 { return self.getChildrenCount(p0); }
    pub fn getParent(self: *@This(), p0: ?*anyopaque) !*IDependencyObject { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetParent(self, p0, &out0)); return @ptrCast(@alignCast(out0 orelse return error.WinRTFailed)); }
    pub fn GetParent(self: *@This(), p0: ?*anyopaque) !*IDependencyObject { return self.getParent(p0); }
    pub fn disconnectChildrenRecursive(self: *@This(), element: ?*anyopaque) !void { try hrCheck(self.lpVtbl.DisconnectChildrenRecursive(self, element)); }
    pub fn DisconnectChildrenRecursive(self: *@This(), element: ?*anyopaque) !void { try self.disconnectChildrenRecursive(element); }
    pub fn getOpenPopups(self: *@This(), p0: ?*anyopaque) !*IVectorView { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetOpenPopups(self, p0, &out0)); return @ptrCast(@alignCast(out0 orelse return error.WinRTFailed)); }
    pub fn GetOpenPopups(self: *@This(), p0: ?*anyopaque) !*IVectorView { return self.getOpenPopups(p0); }
    pub fn getOpenPopupsForXamlRoot(self: *@This(), p0: ?*anyopaque) !*IVectorView { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetOpenPopupsForXamlRoot(self, p0, &out0)); return @ptrCast(@alignCast(out0 orelse return error.WinRTFailed)); }
    pub fn GetOpenPopupsForXamlRoot(self: *@This(), p0: ?*anyopaque) !*IVectorView { return self.getOpenPopupsForXamlRoot(p0); }
};

