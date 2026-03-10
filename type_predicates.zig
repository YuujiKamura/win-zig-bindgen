const std = @import("std");

pub fn isBuiltinType(t: []const u8) bool {
    const builtins = [_][]const u8{ "void", "bool", "anyopaque", "?*anyopaque", "GUID", "HSTRING", "isize", "usize", "u8", "i8", "u16", "i16", "u32", "i32", "u64", "i64", "f32", "f64", "HWND", "HANDLE", "HINSTANCE", "HMODULE", "BOOL", "WPARAM", "LPARAM", "LPCWSTR", "LPWSTR", "HRESULT", "POINT", "RECT" };
    for (builtins) |b| if (std.mem.eql(u8, t, b)) return true;
    return false;
}

pub fn isKnownStruct(name: []const u8) bool {
    const structs = [_][]const u8{ "GridLength", "Color", "Point", "Size", "Rect", "Thickness", "CornerRadius", "CorePhysicalKeyStatus", "Vector2", "Vector3", "Matrix3x2", "Matrix4x4", "Quaternion", "Plane" };
    for (structs) |s| if (std.mem.eql(u8, name, s)) return true;
    return false;
}

/// Cross-WinMD enum types that decodeSigType returns as short names.
/// These must be treated as i32 at ABI level since the enum definition lives
/// in a different WinMD (Windows.winmd) and resolveTypeDefOrRefToRow returns null.
pub fn isKnownExternalEnum(name: []const u8) bool {
    const enums = [_][]const u8{ "VirtualKey", "VirtualKeyModifiers", "CoreCursorType" };
    for (enums) |e| if (std.mem.eql(u8, name, e)) return true;
    return false;
}

pub fn isInterfaceType(name: []const u8) bool {
    // Returns true if the name is a known WinRT interface type.
    // WinRT interfaces always start with 'I' followed by uppercase.
    if (isBuiltinType(name)) return false;
    if (isKnownStruct(name)) return false;
    if (std.mem.eql(u8, name, "EventRegistrationToken")) return false;
    if (std.mem.eql(u8, name, "?*anyopaque")) return false;
    if (std.mem.eql(u8, name, "anyopaque")) return false;
    if (std.mem.startsWith(u8, name, "?")) return false;
    if (std.mem.startsWith(u8, name, "[")) return false; // [*]const u16 etc.
    if (std.mem.startsWith(u8, name, "*")) return isInterfaceType(name[1..]);
    if (name.len < 2) return false;
    // Interface names: IFoo, IBar (I + uppercase)
    return name[0] == 'I' and name[1] >= 'A' and name[1] <= 'Z';
}

/// Returns true if the interface type is importable (will be generated in the output).
/// Any interface name that reached this point was resolved from a WinMD TypeDef,
/// meaning it will be generated via the dependency worklist. Cross-WinMD types that
/// could NOT be resolved were already mapped to ?*anyopaque by decodeSigType.
pub fn isImportableInterface(name: []const u8) bool {
    if (!isInterfaceType(name)) return false;
    return true;
}

pub fn typeNameMatches(query_name: []const u8, actual_name: []const u8) bool {
    if (std.mem.eql(u8, query_name, actual_name)) return true;
    if (actual_name.len <= query_name.len) return false;
    if (!std.mem.startsWith(u8, actual_name, query_name)) return false;
    return actual_name[query_name.len] == '`';
}

pub fn defaultInit(ty: []const u8) []const u8 {
    if (std.mem.startsWith(u8, ty, "?") or std.mem.startsWith(u8, ty, "*")) return "null";
    if (std.mem.eql(u8, ty, "HSTRING")) return "null"; // HSTRING = ?*anyopaque
    if (std.mem.eql(u8, ty, "bool")) return "false";
    if (std.mem.eql(u8, ty, "i32") or std.mem.eql(u8, ty, "u32") or
        std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64") or
        std.mem.eql(u8, ty, "i16") or std.mem.eql(u8, ty, "u16") or
        std.mem.eql(u8, ty, "i8") or std.mem.eql(u8, ty, "u8") or
        std.mem.eql(u8, ty, "f32") or std.mem.eql(u8, ty, "f64") or
        std.mem.eql(u8, ty, "isize") or std.mem.eql(u8, ty, "usize") or
        std.mem.eql(u8, ty, "EventRegistrationToken")) return "0";
    if (std.mem.eql(u8, ty, "GridLength")) return ".{ .Value = 0, .GridUnitType = 0 }";
    if (std.mem.eql(u8, ty, "Color")) return ".{ .A = 0, .R = 0, .G = 0, .B = 0 }";
    if (std.mem.eql(u8, ty, "Vector2")) return ".{ .X = 0, .Y = 0 }";
    if (std.mem.eql(u8, ty, "Vector3")) return ".{ .X = 0, .Y = 0, .Z = 0 }";
    if (std.mem.eql(u8, ty, "Quaternion")) return ".{ .X = 0, .Y = 0, .Z = 0, .W = 0 }";
    if (std.mem.eql(u8, ty, "Matrix3x2")) return ".{ .M11 = 0, .M12 = 0, .M21 = 0, .M22 = 0, .M31 = 0, .M32 = 0 }";
    if (std.mem.eql(u8, ty, "Matrix4x4")) return ".{ .M11 = 0, .M12 = 0, .M13 = 0, .M14 = 0, .M21 = 0, .M22 = 0, .M23 = 0, .M24 = 0, .M31 = 0, .M32 = 0, .M33 = 0, .M34 = 0, .M41 = 0, .M42 = 0, .M43 = 0, .M44 = 0 }";
    if (std.mem.eql(u8, ty, "Plane")) return ".{ .Normal = .{ .X = 0, .Y = 0, .Z = 0 }, .D = 0 }";
    return "undefined";
}

pub fn sanitizeIdentifier(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const keywords = [_][]const u8{ "addrspace", "align", "and", "asm", "async", "await", "break", "catch", "comptime", "const", "continue", "defer", "else", "enum", "errdefer", "error", "export", "extern", "fn", "for", "if", "inline", "noalias", "noinline", "nosuspend", "opaque", "or", "orelse", "packed", "anyframe", "pub", "resume", "return", "linksection", "struct", "suspend", "switch", "test", "threadlocal", "try", "type", "union", "unreachable", "usingnamespace", "var", "volatile", "while" };
    for (keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) {
            return try std.fmt.allocPrint(allocator, "@\"{s}\"", .{name});
        }
    }
    return try allocator.dupe(u8, name);
}
