//! WinUI 3 COM interface definitions for Zig.
//! GENERATED CODE - DO NOT EDIT.
const std = @import("std");
const GUID = std.os.windows.GUID;
const HRESULT = std.os.windows.HRESULT;
const HSTRING = ?*anyopaque;
const EventRegistrationToken = i64;

pub const VtblPlaceholder = ?*const anyopaque;

pub const IID_RoutedEventHandler = GUID{ .Data1 = 0xdae23d85, .Data2 = 0x69ca, .Data3 = 0x5bdf, .Data4 = .{ 0x80, 0x5b, 0x61, 0x61, 0xa3, 0xa2, 0x15, 0xcc } };
pub const IID_SizeChangedEventHandler = GUID{ .Data1 = 0x8d7b1a58, .Data2 = 0x14c6, .Data3 = 0x51c9, .Data4 = .{ 0x89, 0x2c, 0x9f, 0xcc, 0xe3, 0x68, 0xe7, 0x7d } };
pub const IID_TypedEventHandler_TabCloseRequested = GUID{ .Data1 = 0x7093974b, .Data2 = 0x0900, .Data3 = 0x52ae, .Data4 = .{ 0xaf, 0xd8, 0x70, 0xe5, 0x62, 0x3f, 0x45, 0x95 } };
pub const IID_TypedEventHandler_AddTabButtonClick = GUID{ .Data1 = 0x13df6907, .Data2 = 0xbbb4, .Data3 = 0x5f16, .Data4 = .{ 0xbe, 0xac, 0x29, 0x38, 0xc1, 0x5e, 0x1d, 0x85 } };
pub const IID_SelectionChangedEventHandler = GUID{ .Data1 = 0xa232390d, .Data2 = 0x0e34, .Data3 = 0x595e, .Data4 = .{ 0x89, 0x31, 0xfa, 0x92, 0x8a, 0x99, 0x09, 0xf4 } };
pub const IID_TypedEventHandler_WindowClosed = GUID{ .Data1 = 0x2a954d28, .Data2 = 0x7f8b, .Data3 = 0x5479, .Data4 = .{ 0x8c, 0xe9, 0x90, 0x04, 0x24, 0xa0, 0x40, 0x9f } };

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

pub const IUnknown = extern struct {
    pub const IID = GUID{ .Data1 = 0x00000000, .Data2 = 0x0000, .Data3 = 0x0000, .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
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
    pub const IID = GUID{ .Data1 = 0xAFDBDF05, .Data2 = 0x2D12, .Data3 = 0x4D31, .Data4 = .{ 0x84, 0x1F, 0x72, 0x71, 0x50, 0x51, 0x46, 0x46 } };
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

pub const IPersistFile = extern struct {
    pub const IID = GUID{ .Data1 = 0x0000010b, .Data2 = 0x0000, .Data3 = 0x0000, .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
        IsDirty: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Load: *const fn (*anyopaque, ?*anyopaque, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        Save: *const fn (*anyopaque, ?*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SaveCompleted: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetCurFile: *const fn (*anyopaque, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IPersist = true; // requires IPersist
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn isDirty(self: *@This()) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.IsDirty(self, &out0)); return out0; }
    pub fn IsDirty(self: *@This()) !?*anyopaque { return self.isDirty(); }
    pub fn load(self: *@This(), p0: ?*anyopaque, p1: i32) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.Load(self, p0, p1, &out0)); return out0; }
    pub fn Load(self: *@This(), p0: ?*anyopaque, p1: i32) !?*anyopaque { return self.load(p0, p1); }
    pub fn save(self: *@This(), p0: ?*anyopaque, p1: ?*anyopaque) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.Save(self, p0, p1, &out0)); return out0; }
    pub fn Save(self: *@This(), p0: ?*anyopaque, p1: ?*anyopaque) !?*anyopaque { return self.save(p0, p1); }
    pub fn saveCompleted(self: *@This(), p0: ?*anyopaque) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.SaveCompleted(self, p0, &out0)); return out0; }
    pub fn SaveCompleted(self: *@This(), p0: ?*anyopaque) !?*anyopaque { return self.saveCompleted(p0); }
    pub fn getCurFile(self: *@This(), p0: *?*anyopaque) !?*anyopaque { var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetCurFile(self, p0, &out0)); return out0; }
    pub fn GetCurFile(self: *@This(), p0: *?*anyopaque) !?*anyopaque { return self.getCurFile(p0); }
};

