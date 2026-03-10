const std = @import("std");
const win_zig_metadata = @import("win_zig_metadata");
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;

pub const builtin_types = [_][]const u8{ "void", "bool", "anyopaque", "?*anyopaque", "GUID", "HSTRING", "isize", "usize", "u8", "i8", "u16", "i16", "u32", "i32", "u64", "i64", "f32", "f64", "HWND", "HANDLE", "HINSTANCE", "HMODULE", "BOOL", "WPARAM", "LPARAM", "LPCWSTR", "LPWSTR", "HRESULT", "POINT", "RECT" };

pub fn isBuiltinTypeName(name: []const u8) bool {
    for (&builtin_types) |bt| {
        if (std.mem.eql(u8, name, bt)) return true;
    }
    return false;
}

pub const CompanionMetadata = struct {
    table_info: tables.Info,
    heaps: streams.Heaps,
};

pub const Context = struct {
    table_info: tables.Info,
    heaps: streams.Heaps,
    dependencies: ?*std.StringHashMap(void) = null,
    allocator: ?std.mem.Allocator = null,
    companions: []const CompanionMetadata = &.{},

    pub fn registerDependency(self: Context, allocator: std.mem.Allocator, name: []const u8) !void {
        if (self.dependencies) |deps| {
            var stripped = name;
            while (stripped.len > 0) {
                if (stripped[0] == '*' or stripped[0] == '?' or stripped[0] == '[') {
                    if (std.mem.indexOfScalar(u8, stripped, ']')) |idx| {
                        stripped = stripped[idx + 1 ..];
                    } else {
                        stripped = stripped[1..];
                    }
                } else break;
            }
            if (stripped.len == 0) return;
            if (isBuiltinTypeName(stripped)) return;

            // Check both full name and short name (after last dot) for prologue types
            const dep_dot = std.mem.lastIndexOfScalar(u8, stripped, '.');
            const dep_short = if (dep_dot) |d| stripped[d + 1 ..] else stripped;
            if (std.mem.eql(u8, dep_short, "EventRegistrationToken")) return;
            if (std.mem.eql(u8, dep_short, "IInspectable")) return;
            if (std.mem.eql(u8, dep_short, "IUnknown")) return;

            // Skip generic types with backtick arity suffix (e.g., "IVector`1", "TypedEventHandler`2")
            // These cannot be emitted as concrete types without type parameters
            if (std.mem.indexOfScalar(u8, stripped, '`') != null) return;

            const dot = std.mem.lastIndexOfScalar(u8, stripped, '.');
            const first_char = if (dot) |d| stripped[d + 1] else stripped[0];

            if (first_char >= 'A' and first_char <= 'Z') {
                if (!deps.contains(stripped)) {
                    try deps.put(try allocator.dupe(u8, stripped), {});
                }
            }
        }
    }
};

pub const MethodMeta = struct {
    raw_name: []const u8,
    norm_name: []const u8,
    vtbl_sig: []const u8,
    wrapper_sig: []const u8,
    wrapper_call: []const u8,
    raw_wrapper_sig: []const u8,
    raw_wrapper_call: []const u8,
};

pub const MethodRange = struct {
    start: u32,
    end_exclusive: u32,
};

pub const TypeCategory = enum { interface, enum_type, struct_type, class, delegate, other };
