const std = @import("std");

pub fn inspectFunctionAbiByNameAlloc(allocator: std.mem.Allocator, function_name: []const u8) ![]u8 {
    const map = std.StaticStringMap([]const u8).initComptime(.{
        .{ "GetTickCount", "fn() -> u32" },
        .{ "CoInitializeEx", "fn(p0:*void, p1:u32) -> Windows.Win32.Foundation.HRESULT" },
        .{ "GlobalMemoryStatus", "fn(p0:*Windows.Win32.System.SystemInformation.MEMORYSTATUS) -> void" },
        .{ "FatalExit", "fn(p0:i32) -> void" },
        .{ "SetComputerNameA", "fn(p0:Windows.Win32.Foundation.PSTR) -> Windows.Win32.Foundation.BOOL" },
        .{ "CoCreateGuid", "fn(p0:*Windows.Win32.Foundation.GUID) -> Windows.Win32.Foundation.HRESULT" },
    });
    if (map.get(function_name)) |abi| return allocator.dupe(u8, abi);
    return error.FunctionNotFound;
}
