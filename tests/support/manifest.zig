/// Manifest types, Zig/Rust output parsers, and manifest comparison.
/// Used by parity tests to compare Rust golden files against Zig generated output.
const std = @import("std");
const ctx = @import("context.zig");

const containsStr = ctx.containsStr;
const appendUniqueStr = ctx.appendUniqueStr;
const freeSliceList = ctx.freeSliceList;
const trimLine = ctx.trimLine;
const braceDelta = ctx.braceDelta;
const takeIdentifier = ctx.takeIdentifier;
const isLikelyInterfaceName = ctx.isLikelyInterfaceName;

pub const SymbolKind = enum {
    unknown,
    interface,
    class,
    struct_type,
    enum_type,
    alias,
};

/// Signature info for a single vtable slot.
pub const VtableSig = struct {
    /// Number of parameters excluding the implicit `this` pointer.
    /// null means the slot is a stub (usize in Rust, VtblPlaceholder in Zig).
    param_count: ?u32 = null,
    /// Normalized return type string (e.g. "HRESULT", "u32", "void").
    /// null means the slot is a stub.
    return_type: ?[]const u8 = null,

    pub fn isStub(self: VtableSig) bool {
        return self.param_count == null and self.return_type == null;
    }
};

pub const TypeShape = struct {
    name: []const u8,
    kind: SymbolKind,
    has_iid: bool = false,
    iid_value: ?[16]u8 = null,
    has_lpvtable: bool = false,
    fields: std.ArrayList([]const u8) = .empty,
    methods: std.ArrayList([]const u8) = .empty,
    vtable_methods: std.ArrayList([]const u8) = .empty,
    vtable_sigs: std.ArrayList(VtableSig) = .empty,
    enum_variants: std.ArrayList([]const u8) = .empty,
    required_ifaces: std.ArrayList([]const u8) = .empty,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, kind: SymbolKind) !TypeShape {
        return .{
            .name = try allocator.dupe(u8, name),
            .kind = kind,
        };
    }

    pub fn deinit(self: *TypeShape, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        freeSliceList(allocator, &self.fields);
        freeSliceList(allocator, &self.methods);
        freeSliceList(allocator, &self.vtable_methods);
        for (self.vtable_sigs.items) |sig| {
            if (sig.return_type) |rt| allocator.free(rt);
        }
        self.vtable_sigs.deinit(allocator);
        freeSliceList(allocator, &self.enum_variants);
        freeSliceList(allocator, &self.required_ifaces);
    }
};

pub const Manifest = struct {
    allocator: std.mem.Allocator,
    types: std.ArrayList(TypeShape) = .empty,
    functions: std.ArrayList([]const u8) = .empty,

    pub fn init(allocator: std.mem.Allocator) Manifest {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Manifest) void {
        for (self.types.items) |*t| t.deinit(self.allocator);
        self.types.deinit(self.allocator);
        freeSliceList(self.allocator, &self.functions);
    }

    pub fn ensureType(self: *Manifest, name: []const u8, preferred_kind: SymbolKind) !usize {
        for (self.types.items, 0..) |*t, i| {
            if (!std.mem.eql(u8, t.name, name)) continue;
            if (t.kind == .unknown and preferred_kind != .unknown) t.kind = preferred_kind;
            return i;
        }
        try self.types.append(self.allocator, try TypeShape.init(self.allocator, name, preferred_kind));
        return self.types.items.len - 1;
    }

    pub fn addFunction(self: *Manifest, name: []const u8) !void {
        try appendUniqueStr(self.allocator, &self.functions, name);
    }

    pub fn addField(self: *Manifest, type_index: usize, name: []const u8) !void {
        try appendUniqueStr(self.allocator, &self.types.items[type_index].fields, name);
    }

    pub fn addMethod(self: *Manifest, type_index: usize, name: []const u8) !void {
        try appendUniqueStr(self.allocator, &self.types.items[type_index].methods, name);
    }

    pub fn addVtableMethod(self: *Manifest, type_index: usize, name: []const u8) !void {
        if (containsStr(self.types.items[type_index].vtable_methods.items, name)) return;
        try self.types.items[type_index].vtable_methods.append(self.allocator, try self.allocator.dupe(u8, name));
        // Append a stub signature as placeholder (no signature info)
        try self.types.items[type_index].vtable_sigs.append(self.allocator, .{});
    }

    pub fn addVtableMethodWithSig(self: *Manifest, type_index: usize, name: []const u8, sig: VtableSig) !void {
        if (containsStr(self.types.items[type_index].vtable_methods.items, name)) return;
        try self.types.items[type_index].vtable_methods.append(self.allocator, try self.allocator.dupe(u8, name));
        const stored_sig = VtableSig{
            .param_count = sig.param_count,
            .return_type = if (sig.return_type) |rt| try self.allocator.dupe(u8, rt) else null,
        };
        try self.types.items[type_index].vtable_sigs.append(self.allocator, stored_sig);
    }

    pub fn addEnumVariant(self: *Manifest, type_index: usize, name: []const u8) !void {
        try appendUniqueStr(self.allocator, &self.types.items[type_index].enum_variants, name);
    }

    pub fn addRequiredIface(self: *Manifest, type_index: usize, name: []const u8) !void {
        try appendUniqueStr(self.allocator, &self.types.items[type_index].required_ifaces, name);
    }

    pub fn findType(self: *const Manifest, name: []const u8) ?*const TypeShape {
        for (self.types.items, 0..) |_, i| {
            if (std.mem.eql(u8, self.types.items[i].name, name)) return &self.types.items[i];
        }
        return null;
    }
};

// ============================================================
// Vtable signature extraction helpers
// ============================================================

/// Normalize a return type string to a common representation across Rust/Zig.
/// Maps Rust types to their Zig equivalents for comparison.
fn normalizeReturnType(raw: []const u8) []const u8 {
    // Normalize HRESULT variants across Rust (windows_core::HRESULT, windows_sys::core::HRESULT) and Zig
    if (std.mem.eql(u8, raw, "HRESULT")) return "HRESULT";
    if (std.mem.endsWith(u8, raw, "::HRESULT")) return "HRESULT";
    if (std.mem.eql(u8, raw, "u32")) return "u32";
    if (std.mem.eql(u8, raw, "i32")) return "i32";
    if (std.mem.eql(u8, raw, "usize")) return "usize";
    if (std.mem.eql(u8, raw, "void")) return "void";
    if (std.mem.eql(u8, raw, "u64")) return "u64";
    if (std.mem.eql(u8, raw, "i64")) return "i64";
    if (std.mem.eql(u8, raw, "u16")) return "u16";
    if (std.mem.eql(u8, raw, "i16")) return "i16";
    if (std.mem.eql(u8, raw, "u8")) return "u8";
    if (std.mem.eql(u8, raw, "i8")) return "i8";
    if (std.mem.eql(u8, raw, "bool") or std.mem.eql(u8, raw, "BOOL")) return "BOOL";
    // Anything else, keep as-is (will be compared loosely)
    return raw;
}

/// Count commas at the top level of a parameter list (respecting nested parens/brackets).
/// Returns the number of parameters. An empty string returns 0.
/// Handles trailing commas correctly (e.g. "a, b," counts as 2, not 3).
fn countFnParams(params: []const u8) u32 {
    const trimmed = std.mem.trim(u8, params, " \t\r\n,");
    if (trimmed.len == 0) return 0;
    var count: u32 = 1;
    var depth: i32 = 0;
    for (trimmed) |ch| {
        switch (ch) {
            '(', '<', '[' => depth += 1,
            ')', '>', ']' => depth -= 1,
            ',' => {
                if (depth == 0) count += 1;
            },
            else => {},
        }
    }
    return count;
}

/// Parse a Rust vtable field signature from a line like:
///   `pub Close: unsafe extern "system" fn(*mut core::ffi::c_void) -> windows_core::HRESULT,`
/// or a stub like:
///   `SetCompleted: usize,`
/// Returns a VtableSig. For stubs, both fields are null.
fn parseRustVtblSig(line: []const u8) VtableSig {
    // Check for usize stub
    if (std.mem.indexOf(u8, line, ": usize") != null) return .{};

    // Look for "fn(" to find the function signature
    const fn_marker = std.mem.indexOf(u8, line, " fn(") orelse return .{};
    const params_start = fn_marker + " fn(".len;

    // Find matching closing paren
    var depth: i32 = 1;
    var pos = params_start;
    while (pos < line.len and depth > 0) : (pos += 1) {
        if (line[pos] == '(') depth += 1;
        if (line[pos] == ')') depth -= 1;
    }
    if (depth != 0) return .{};
    const params_end = pos - 1;
    const params = line[params_start..params_end];

    // Count params, subtract 1 for `this` (first *mut core::ffi::c_void)
    const total_params = countFnParams(params);
    const user_params = if (total_params > 0) total_params - 1 else 0;

    // Parse return type: look for " -> " after closing paren
    const after_paren = line[pos..];
    const ret_type = if (std.mem.indexOf(u8, after_paren, " -> ")) |arrow| blk: {
        const rt_start = arrow + " -> ".len;
        const rt_raw = std.mem.trim(u8, after_paren[rt_start..], " \t,;");
        break :blk normalizeReturnType(rt_raw);
    } else "void";

    return .{
        .param_count = user_params,
        .return_type = ret_type,
    };
}

/// Parse a Zig vtable field signature from a line like:
///   `QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,`
/// or a stub like:
///   `GetIids: VtblPlaceholder,`
/// Returns a VtableSig.
fn parseZigVtblSig(line: []const u8) VtableSig {
    // Check for VtblPlaceholder stub
    if (std.mem.indexOf(u8, line, "VtblPlaceholder") != null) return .{};

    // Look for "fn (" or "fn(" to find the function signature
    const fn_marker = std.mem.indexOf(u8, line, "fn (") orelse
        (std.mem.indexOf(u8, line, "fn(") orelse return .{});
    const open_paren = std.mem.indexOfScalarPos(u8, line, fn_marker, '(') orelse return .{};
    const params_start = open_paren + 1;

    // Find matching closing paren
    var depth: i32 = 1;
    var pos = params_start;
    while (pos < line.len and depth > 0) : (pos += 1) {
        if (line[pos] == '(') depth += 1;
        if (line[pos] == ')') depth -= 1;
    }
    if (depth != 0) return .{};
    const params_end = pos - 1;
    const params = line[params_start..params_end];

    // Count params, subtract 1 for `this` (first *anyopaque)
    const total_params = countFnParams(params);
    const user_params = if (total_params > 0) total_params - 1 else 0;

    // Parse return type: after "callconv(.winapi) " or after ") "
    const after_paren = line[pos..];
    const ret_type = if (std.mem.indexOf(u8, after_paren, "callconv(")) |cc_start| blk: {
        // Find the closing paren of callconv(...)
        const cc_close = std.mem.indexOfScalarPos(u8, after_paren, cc_start, ')') orelse break :blk "void";
        const rest = std.mem.trimLeft(u8, after_paren[cc_close + 1 ..], " \t");
        const rt_raw = std.mem.trim(u8, rest, " \t,;");
        if (rt_raw.len == 0) break :blk "void";
        break :blk normalizeReturnType(rt_raw);
    } else "void";

    return .{
        .param_count = user_params,
        .return_type = ret_type,
    };
}

// ============================================================
// Zig generated output parser
// ============================================================

fn parseGeneratedTypeStart(line: []const u8) ?struct { name: []const u8, kind: SymbolKind } {
    const prefix = "pub const ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    const eq_pos = std.mem.indexOf(u8, rest, " = ") orelse return null;
    const name = takeIdentifier(rest[0..eq_pos]);
    if (name.len == 0) return null;
    const rhs = rest[eq_pos + 3 ..];
    if (std.mem.indexOf(u8, rhs, "enum") != null) return .{ .name = name, .kind = .enum_type };
    if (std.mem.indexOf(u8, rhs, "struct") != null) {
        if (std.mem.eql(u8, name, "WPARAM") or std.mem.eql(u8, name, "LPARAM")) {
            return .{ .name = name, .kind = .enum_type };
        }
        return .{ .name = name, .kind = .struct_type };
    }
    return .{ .name = name, .kind = .alias };
}

fn parseGeneratedFnName(line: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, "pub ")) return null;
    var rest = line[4..];
    if (std.mem.startsWith(u8, rest, "extern ")) {
        rest = rest[7..];
        if (std.mem.startsWith(u8, rest, "\"")) {
            const closing_quote = std.mem.indexOfScalarPos(u8, rest, 1, '\"') orelse return null;
            rest = std.mem.trimLeft(u8, rest[closing_quote + 1 ..], " \t");
        }
    }
    if (!std.mem.startsWith(u8, rest, "fn ")) return null;
    rest = rest[3..];
    const open = std.mem.indexOfScalar(u8, rest, '(') orelse return null;
    const name = takeIdentifier(rest[0..open]);
    if (name.len > 0) return name;
    return null;
}

fn parseGeneratedFieldName(line: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, line, "pub ")) return null;
    const colon = std.mem.indexOfScalar(u8, line, ':') orelse return null;
    const name = takeIdentifier(std.mem.trim(u8, line[0..colon], " \t"));
    if (name.len == 0) return null;
    return name;
}

fn parseGeneratedEnumVariantName(line: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, line, "pub const ")) {
        const rest = line["pub const ".len..];
        const colon = std.mem.indexOfScalar(u8, rest, ':') orelse return null;
        const name = takeIdentifier(rest[0..colon]);
        if (name.len == 0) return null;
        return name;
    }
    if (std.mem.startsWith(u8, line, "pub ")) return null;
    const eq_pos = std.mem.indexOfScalar(u8, line, '=') orelse return null;
    const name = takeIdentifier(std.mem.trim(u8, line[0..eq_pos], " \t"));
    if (name.len == 0) return null;
    return name;
}

fn parseGeneratedRequiredIface(line: []const u8) ?[]const u8 {
    const prefix = "pub const Requires_";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    const eq_pos = std.mem.indexOf(u8, rest, " = ") orelse return null;
    const name = takeIdentifier(rest[0..eq_pos]);
    if (name.len == 0) return null;
    return name;
}

fn finalizeGeneratedType(t: *TypeShape) void {
    if (t.kind != .struct_type) return;
    if (t.has_iid and t.has_lpvtable) {
        t.kind = if (isLikelyInterfaceName(t.name)) .interface else .class;
        return;
    }
    if (t.required_ifaces.items.len > 0 and !isLikelyInterfaceName(t.name)) {
        t.kind = .class;
    }
}

/// Parse a Zig GUID literal like:
/// `GUID{ .data1 = 0x96369f54, .data2 = 0x8eb6, .data3 = 0x48f0, .data4 = .{ 0xab, 0xce, ... } }`
/// into 16 raw bytes (data1 LE, data2 LE, data3 LE, data4 raw).
fn parseZigGuidValue(line: []const u8) ?[16]u8 {
    const iid_prefix = "pub const IID = GUID";
    const start = std.mem.indexOf(u8, line, iid_prefix) orelse return null;
    const rest = line[start + iid_prefix.len ..];

    var result: [16]u8 = undefined;

    // Parse .data1
    const d1_start = std.mem.indexOf(u8, rest, ".data1 = 0x") orelse return null;
    const d1_hex_start = d1_start + ".data1 = 0x".len;
    const d1_hex_end = std.mem.indexOfScalarPos(u8, rest, d1_hex_start, ',') orelse return null;
    const d1 = std.fmt.parseUnsigned(u32, rest[d1_hex_start..d1_hex_end], 16) catch return null;
    std.mem.writeInt(u32, result[0..4], d1, .little);

    // Parse .data2
    const d2_start = std.mem.indexOfPos(u8, rest, d1_hex_end, ".data2 = 0x") orelse return null;
    const d2_hex_start = d2_start + ".data2 = 0x".len;
    const d2_hex_end = std.mem.indexOfScalarPos(u8, rest, d2_hex_start, ',') orelse return null;
    const d2 = std.fmt.parseUnsigned(u16, rest[d2_hex_start..d2_hex_end], 16) catch return null;
    std.mem.writeInt(u16, result[4..6], d2, .little);

    // Parse .data3
    const d3_start = std.mem.indexOfPos(u8, rest, d2_hex_end, ".data3 = 0x") orelse return null;
    const d3_hex_start = d3_start + ".data3 = 0x".len;
    const d3_hex_end = std.mem.indexOfScalarPos(u8, rest, d3_hex_start, ',') orelse return null;
    const d3 = std.fmt.parseUnsigned(u16, rest[d3_hex_start..d3_hex_end], 16) catch return null;
    std.mem.writeInt(u16, result[6..8], d3, .little);

    // Parse .data4 = .{ 0xNN, 0xNN, ... } (8 bytes)
    const d4_start = std.mem.indexOfPos(u8, rest, d3_hex_end, ".data4 = .{") orelse return null;
    var pos = d4_start + ".data4 = .{".len;
    for (0..8) |i| {
        // Skip whitespace and find "0x"
        while (pos < rest.len and (rest[pos] == ' ' or rest[pos] == ',')) : (pos += 1) {}
        if (pos + 2 >= rest.len) return null;
        if (rest[pos] != '0' or rest[pos + 1] != 'x') return null;
        pos += 2;
        const byte_end = blk: {
            var e = pos;
            while (e < rest.len and std.ascii.isHex(rest[e])) : (e += 1) {}
            break :blk e;
        };
        if (byte_end == pos) return null;
        result[8 + i] = std.fmt.parseUnsigned(u8, rest[pos..byte_end], 16) catch return null;
        pos = byte_end;
    }

    return result;
}

/// Parse a Rust-style hex GUID like `0x96369f54_8eb6_48f0_abce_c1b211e627c3`
/// into 16 raw bytes (data1 LE, data2 LE, data3 LE, data4 raw).
fn parseRustGuidHex(hex_str: []const u8) ?[16]u8 {
    if (!std.mem.startsWith(u8, hex_str, "0x")) return null;
    // Strip "0x" prefix and all underscores
    var clean: [32]u8 = undefined;
    var clean_len: usize = 0;
    for (hex_str[2..]) |ch| {
        if (ch == '_') continue;
        if (!std.ascii.isHex(ch)) break;
        if (clean_len >= 32) return null;
        clean[clean_len] = ch;
        clean_len += 1;
    }
    if (clean_len != 32) return null;

    // Parse 32 hex chars: 8 (data1) + 4 (data2) + 4 (data3) + 16 (data4)
    var result: [16]u8 = undefined;
    const d1 = std.fmt.parseUnsigned(u32, clean[0..8], 16) catch return null;
    std.mem.writeInt(u32, result[0..4], d1, .little);
    const d2 = std.fmt.parseUnsigned(u16, clean[8..12], 16) catch return null;
    std.mem.writeInt(u16, result[4..6], d2, .little);
    const d3 = std.fmt.parseUnsigned(u16, clean[12..16], 16) catch return null;
    std.mem.writeInt(u16, result[6..8], d3, .little);

    // data4: 8 bytes, each is 2 hex chars, stored raw (big-endian order)
    for (0..8) |i| {
        result[8 + i] = std.fmt.parseUnsigned(u8, clean[16 + i * 2 .. 16 + i * 2 + 2], 16) catch return null;
    }

    return result;
}

pub fn parseGeneratedManifest(allocator: std.mem.Allocator, text: []const u8) !Manifest {
    var manifest = Manifest.init(allocator);
    errdefer manifest.deinit();

    var current_type: ?usize = null;
    var type_depth: i32 = 0;
    var in_vtable = false;
    var vtable_depth: i32 = 0;

    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = trimLine(raw_line);
        if (line.len == 0 or std.mem.startsWith(u8, line, "//!")) continue;

        if (current_type == null) {
            if (parseGeneratedTypeStart(line)) |decl| {
                current_type = try manifest.ensureType(decl.name, decl.kind);
                type_depth = braceDelta(line);
                in_vtable = false;
                vtable_depth = 0;
                if (type_depth == 0) current_type = null;
                continue;
            }
            if (parseGeneratedFnName(line)) |fn_name| {
                try manifest.addFunction(fn_name);
            }
            continue;
        }

        const type_index = current_type.?;
        const t = &manifest.types.items[type_index];

        if (in_vtable) {
            if (parseGeneratedFieldName(line)) |vtbl_name| {
                const sig = parseZigVtblSig(line);
                try manifest.addVtableMethodWithSig(type_index, vtbl_name, sig);
            }
            vtable_depth += braceDelta(line);
            type_depth += braceDelta(line);
            if (vtable_depth <= 0) in_vtable = false;
            if (type_depth <= 0) {
                finalizeGeneratedType(t);
                current_type = null;
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "pub const VTable = extern struct {")) {
            in_vtable = true;
            vtable_depth = braceDelta(line);
            type_depth += braceDelta(line);
            continue;
        }
        if (std.mem.startsWith(u8, line, "pub const IID = ")) {
            t.has_iid = true;
            if (parseZigGuidValue(line)) |guid| t.iid_value = guid;
        }
        if (std.mem.startsWith(u8, line, "lpVtbl: *const VTable")) t.has_lpvtable = true;
        if (parseGeneratedRequiredIface(line)) |iface_name| try manifest.addRequiredIface(type_index, iface_name);

        switch (t.kind) {
            .enum_type => {
                if (parseGeneratedEnumVariantName(line)) |variant_name| try manifest.addEnumVariant(type_index, variant_name);
            },
            .struct_type => {
                if (parseGeneratedEnumVariantName(line)) |variant_name| {
                    try manifest.addEnumVariant(type_index, variant_name);
                } else if (parseGeneratedFnName(line)) |method_name| {
                    try manifest.addMethod(type_index, method_name);
                } else if (parseGeneratedFieldName(line)) |field_name| {
                    try manifest.addField(type_index, field_name);
                }
            },
            else => {
                if (parseGeneratedFnName(line)) |method_name| {
                    try manifest.addMethod(type_index, method_name);
                } else if (parseGeneratedFieldName(line)) |field_name| {
                    try manifest.addField(type_index, field_name);
                }
            },
        }

        type_depth += braceDelta(line);
        if (type_depth <= 0) {
            finalizeGeneratedType(t);
            current_type = null;
        }
    }

    return manifest;
}

// ============================================================
// Rust golden file parser
// ============================================================

fn parseMacroFirstIdent(manifest: *Manifest, text: []const u8, macro_name: []const u8, kind: SymbolKind) !void {
    var search_from: usize = 0;
    while (std.mem.indexOfPos(u8, text, search_from, macro_name)) |start| {
        const body_start = start + macro_name.len;
        const body_end = std.mem.indexOfPos(u8, text, body_start, ");") orelse break;
        const body = text[body_start..body_end];
        var it = std.mem.tokenizeAny(u8, body, " \t\r\n,");
        const first = it.next() orelse {
            search_from = body_end + 2;
            continue;
        };
        const ident = takeIdentifier(first);
        if (ident.len > 0) {
            const type_index = try manifest.ensureType(ident, kind);
            // For define_interface!, the third token is the GUID hex literal
            _ = it.next(); // skip second token (Vtbl name)
            if (it.next()) |guid_tok| {
                if (parseRustGuidHex(guid_tok)) |guid| {
                    manifest.types.items[type_index].iid_value = guid;
                }
            }
        }
        search_from = body_end + 2;
    }
}

fn parseRequiredHierarchyMacros(manifest: *Manifest, text: []const u8) !void {
    const macro_name = "required_hierarchy!(";
    var search_from: usize = 0;
    while (std.mem.indexOfPos(u8, text, search_from, macro_name)) |start| {
        const body_start = start + macro_name.len;
        const body_end = std.mem.indexOfPos(u8, text, body_start, ");") orelse break;
        const body = text[body_start..body_end];
        var it = std.mem.tokenizeAny(u8, body, " \t\r\n,");
        const owner_tok = it.next() orelse {
            search_from = body_end + 2;
            continue;
        };
        const owner = takeIdentifier(owner_tok);
        if (owner.len == 0) {
            search_from = body_end + 2;
            continue;
        }
        const owner_index = try manifest.ensureType(owner, .class);
        while (it.next()) |tok| {
            const iface = takeIdentifier(tok);
            if (iface.len == 0) continue;
            try manifest.addRequiredIface(owner_index, iface);
        }
        search_from = body_end + 2;
    }
}

fn parseRustTypeAliasName(line: []const u8) ?[]const u8 {
    const prefix = "pub type ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    const eq_pos = std.mem.indexOf(u8, rest, " = ") orelse return null;
    const name = takeIdentifier(rest[0..eq_pos]);
    if (name.len == 0) return null;
    return name;
}

fn parseRustStructDecl(line: []const u8) ?struct {
    name: []const u8,
    kind: SymbolKind,
    is_block: bool,
    is_vtbl: bool,
} {
    const prefix = "pub struct ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    const name = takeIdentifier(rest);
    if (name.len == 0) return null;

    if (std.mem.indexOfScalar(u8, rest, '{') != null) {
        return .{
            .name = name,
            .kind = .struct_type,
            .is_block = true,
            .is_vtbl = std.mem.endsWith(u8, name, "_Vtbl"),
        };
    }
    if (std.mem.indexOfScalar(u8, rest, '(') != null) {
        const kind: SymbolKind = if (std.mem.indexOf(u8, rest, "(pub i") != null or std.mem.indexOf(u8, rest, "(pub u") != null)
            .enum_type
        else
            .unknown;
        return .{
            .name = name,
            .kind = kind,
            .is_block = false,
            .is_vtbl = false,
        };
    }
    if (std.mem.indexOfScalar(u8, rest, ';') != null) {
        return .{
            .name = name,
            .kind = .class,
            .is_block = false,
            .is_vtbl = false,
        };
    }
    return null;
}

fn parseRustImplStart(line: []const u8) ?[]const u8 {
    const prefix = "impl ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    if (rest.len == 0 or rest[0] == '<') return null;
    if (std.mem.indexOf(u8, rest, " for ") != null) return null;
    const brace = std.mem.indexOfScalar(u8, rest, '{') orelse return null;
    const head = std.mem.trim(u8, rest[0..brace], " \t");
    const name = takeIdentifier(head);
    if (name.len == 0) return null;
    if (std.mem.endsWith(u8, name, "_Vtbl")) return null;
    return name;
}

fn parseRustFnName(line: []const u8) ?[]const u8 {
    const direct_prefixes = [_][]const u8{
        "pub unsafe fn ",
        "pub fn ",
    };
    for (direct_prefixes) |prefix| {
        if (!std.mem.startsWith(u8, line, prefix)) continue;
        const rest = line[prefix.len..];
        const open = std.mem.indexOfScalar(u8, rest, '(') orelse return null;
        const name = takeIdentifier(rest[0..open]);
        if (name.len > 0) return name;
    }
    if (std.mem.startsWith(u8, line, "windows_link::link!(") or std.mem.indexOf(u8, line, "windows_core::link!(") != null) {
        if (std.mem.indexOf(u8, line, " fn ")) |pos| {
            const rest = line[pos + 4 ..];
            const open = std.mem.indexOfScalar(u8, rest, '(') orelse return null;
            const name = takeIdentifier(rest[0..open]);
            if (name.len > 0) return name;
        }
    }
    return null;
}

fn parseRustFieldLikeName(line: []const u8) ?[]const u8 {
    var rest = line;
    if (std.mem.startsWith(u8, rest, "pub ")) rest = rest[4..];
    const colon = std.mem.indexOfScalar(u8, rest, ':') orelse return null;
    const name = takeIdentifier(std.mem.trim(u8, rest[0..colon], " \t"));
    if (name.len == 0) return null;
    return name;
}

fn parseRustVtblFieldName(line: []const u8) ?[]const u8 {
    // Check for single-line type specifications
    const has_type_on_line = (std.mem.indexOf(u8, line, ": unsafe extern") != null or
        std.mem.indexOf(u8, line, ": usize") != null or
        std.mem.indexOf(u8, line, ": Option<") != null or
        std.mem.indexOf(u8, line, ": *const") != null);

    // Also handle multi-line declarations where "pub Name:" or "Name:" ends the line
    // and the type (e.g. "unsafe extern ...") continues on the next line.
    const is_trailing_colon = blk: {
        if (has_type_on_line) break :blk false;
        const trimmed = std.mem.trimRight(u8, line, " \t,");
        break :blk (trimmed.len > 0 and trimmed[trimmed.len - 1] == ':');
    };

    if (!has_type_on_line and !is_trailing_colon) return null;

    const name = parseRustFieldLikeName(line) orelse return null;
    if (!(std.mem.startsWith(u8, line, "pub ") or std.mem.eql(u8, name, "base__") or std.ascii.isUpper(name[0]))) return null;
    return name;
}

fn parseRustEnumVariant(line: []const u8) ?[]const u8 {
    const prefix = "pub const ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    if (std.mem.startsWith(u8, rest, "fn ")) return null;
    if (std.mem.indexOf(u8, line, ": Self") == null) return null;
    const colon = std.mem.indexOfScalar(u8, rest, ':') orelse return null;
    const name = takeIdentifier(rest[0..colon]);
    if (name.len == 0) return null;
    return name;
}

pub fn parseRustManifest(allocator: std.mem.Allocator, text: []const u8) !Manifest {
    var manifest = Manifest.init(allocator);
    errdefer manifest.deinit();

    try parseMacroFirstIdent(&manifest, text, "define_interface!(", .interface);
    try parseRequiredHierarchyMacros(&manifest, text);

    var current_impl: ?usize = null;
    var impl_depth: i32 = 0;
    var current_struct: ?usize = null;
    var struct_depth: i32 = 0;
    var current_vtbl: ?usize = null;
    var vtbl_depth: i32 = 0;

    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = trimLine(raw_line);
        const is_top_level = raw_line.len == line.len;
        if (line.len == 0 or std.mem.startsWith(u8, line, "#![")) continue;
        if (std.mem.indexOf(u8, line, "define_interface!(") != null or std.mem.indexOf(u8, line, "required_hierarchy!(") != null) continue;

        if (current_impl) |type_index| {
            if (std.mem.startsWith(u8, line, "pub fn ")) {
                if (parseRustFnName(line)) |method_name| try manifest.addMethod(type_index, method_name);
            } else if (parseRustEnumVariant(line)) |variant_name| {
                try manifest.addEnumVariant(type_index, variant_name);
            }
            impl_depth += braceDelta(line);
            if (impl_depth <= 0) current_impl = null;
            continue;
        }

        if (current_vtbl) |type_index| {
            if (parseRustVtblFieldName(line)) |field_name| {
                if (!std.mem.eql(u8, field_name, "base__")) {
                    // For multi-line signatures, we need the accumulated text.
                    // Collect lines until the entry is complete (balanced parens and ends with comma).
                    var accum = std.ArrayList(u8).empty;
                    defer accum.deinit(allocator);
                    try accum.appendSlice(allocator, line);

                    // Check if signature is complete on this line
                    var fn_paren_depth: i32 = 0;
                    var has_fn = false;
                    for (line) |ch| {
                        if (ch == '(') fn_paren_depth += 1;
                        if (ch == ')') fn_paren_depth -= 1;
                    }
                    has_fn = std.mem.indexOf(u8, line, " fn(") != null;

                    // If we have "fn(" but parens aren't balanced, accumulate more lines
                    if (has_fn and fn_paren_depth > 0) {
                        while (lines.next()) |cont_raw| {
                            const cont = trimLine(cont_raw);
                            try accum.append(allocator, ' ');
                            try accum.appendSlice(allocator, cont);
                            for (cont) |ch| {
                                if (ch == '(') fn_paren_depth += 1;
                                if (ch == ')') fn_paren_depth -= 1;
                            }
                            vtbl_depth += braceDelta(cont);
                            if (fn_paren_depth <= 0) break;
                        }
                    }

                    // Also handle trailing-colon case: field name on one line, signature on next lines.
                    // But NOT for lines that are already complete (e.g. "Type: usize,").
                    const is_already_complete = std.mem.indexOf(u8, line, ": usize") != null or
                        (fn_paren_depth == 0 and std.mem.endsWith(u8, std.mem.trimRight(u8, line, " \t"), ","));
                    if (!has_fn and !is_already_complete) {
                        // Keep reading until we get the full signature
                        while (lines.next()) |cont_raw| {
                            const cont = trimLine(cont_raw);
                            try accum.append(allocator, ' ');
                            try accum.appendSlice(allocator, cont);
                            vtbl_depth += braceDelta(cont);
                            for (cont) |ch| {
                                if (ch == '(') fn_paren_depth += 1;
                                if (ch == ')') fn_paren_depth -= 1;
                            }
                            // Stop when we have a complete fn signature or hit a comma/closing brace
                            if (std.mem.indexOf(u8, cont, " fn(") != null or
                                std.mem.indexOf(u8, cont, "usize") != null)
                            {
                                has_fn = true;
                            }
                            if (has_fn and fn_paren_depth <= 0) break;
                            if (!has_fn and (std.mem.endsWith(u8, std.mem.trimRight(u8, cont, " \t"), ",") or
                                std.mem.endsWith(u8, std.mem.trimRight(u8, cont, " \t"), "}"))) break;
                        }
                    }

                    const sig = parseRustVtblSig(accum.items);
                    try manifest.addVtableMethodWithSig(type_index, field_name, sig);
                }
            }
            vtbl_depth += braceDelta(line);
            if (vtbl_depth <= 0) current_vtbl = null;
            continue;
        }

        if (current_struct) |type_index| {
            if (parseRustFieldLikeName(line)) |field_name| try manifest.addField(type_index, field_name);
            struct_depth += braceDelta(line);
            if (struct_depth <= 0) current_struct = null;
            continue;
        }

        if (is_top_level) {
            if (parseRustFnName(line)) |fn_name| {
                try manifest.addFunction(fn_name);
                continue;
            }
            if (parseRustTypeAliasName(line)) |alias_name| {
                _ = try manifest.ensureType(alias_name, .unknown);
                continue;
            }
            if (parseRustStructDecl(line)) |decl| {
                if (decl.is_vtbl) {
                    const base_name = decl.name[0 .. decl.name.len - "_Vtbl".len];
                    const type_index = try manifest.ensureType(base_name, .unknown);
                    current_vtbl = type_index;
                    vtbl_depth = braceDelta(line);
                    continue;
                }
                const type_index = try manifest.ensureType(decl.name, decl.kind);
                if (decl.is_block) {
                    current_struct = type_index;
                    struct_depth = braceDelta(line);
                }
                continue;
            }
            if (parseRustImplStart(line)) |impl_name| {
                const type_index = try manifest.ensureType(impl_name, .unknown);
                current_impl = type_index;
                impl_depth = braceDelta(line);
                continue;
            }
        }
    }

    return manifest;
}

// ============================================================
// Manifest comparison
// ============================================================

fn compareExpectedList(
    case_id: []const u8,
    owner: []const u8,
    label: []const u8,
    expected: []const []const u8,
    actual: []const []const u8,
) usize {
    var fail_count: usize = 0;
    for (expected) |name| {
        if (containsStr(actual, name)) continue;
        std.log.err("[{s}] missing {s} on {s}: {s}", .{ case_id, label, owner, name });
        fail_count += 1;
    }
    return fail_count;
}

/// Compare two VtableSig values. Returns true if they are compatible.
/// Stubs in either side are always compatible (no info to compare).
/// When both sides have signatures, compare param_count and return_type.
///
/// Handles the "UDT return" pattern: Rust uses an out-pointer parameter with
/// void return, while Zig may return the value directly (one fewer param,
/// non-void return). This is a legitimate cross-language ABI difference.
fn signaturesMatch(expected_sig: VtableSig, actual_sig: VtableSig) bool {
    // If either is a stub, we can't compare — treat as compatible
    if (expected_sig.isStub() or actual_sig.isStub()) return true;

    const exp_pc = expected_sig.param_count orelse return true;
    const act_pc = actual_sig.param_count orelse return true;
    const exp_rt = expected_sig.return_type orelse return true;
    const act_rt = actual_sig.return_type orelse return true;

    // Exact match
    if (exp_pc == act_pc and std.mem.eql(u8, exp_rt, act_rt)) return true;

    // UDT return pattern: Rust has N params + void return,
    // Zig has N-1 params + concrete return type.
    // The last Rust param is an out-pointer for the return value.
    if (exp_pc > 0 and act_pc + 1 == exp_pc) {
        if (std.mem.eql(u8, exp_rt, "void") and !std.mem.eql(u8, act_rt, "void")) return true;
    }

    // SZARRAY pattern: Rust expands array params as (len, ptr) = 2 params,
    // Zig may keep them as a single slice/SZARRAY param.
    // Allow expected to have more params than actual when return types match.
    if (exp_pc > act_pc and std.mem.eql(u8, exp_rt, act_rt)) return true;

    return false;
}

/// Order-sensitive comparison for vtable method slots.
///
/// Rust golden files skip `base__` (inherited parent vtable slots), so the
/// expected list contains only the type's own methods.  Zig output inlines
/// all parent methods, so actual may be longer with inherited slots at the
/// front.
///
/// Strategy: find the offset in `actual` where `expected[0]` first appears,
/// then verify positional equality from that offset.  If expected is empty
/// but actual is not, that is fine (all slots are inherited).
fn compareVtableSlotOrder(
    case_id: []const u8,
    owner: []const u8,
    expected: []const []const u8,
    actual: []const []const u8,
    expected_sigs: []const VtableSig,
    actual_sigs: []const VtableSig,
) usize {
    if (expected.len == 0) return 0;

    // Find the offset in actual where the type's own methods begin.
    // This is where expected[0] should appear.
    var offset: ?usize = null;
    for (actual, 0..) |name, i| {
        if (std.mem.eql(u8, name, expected[0])) {
            offset = i;
            break;
        }
    }

    if (offset == null) {
        // expected[0] not found in actual at all — fall back to missing-item report
        std.log.err("[{s}] vtable method on {s}: expected first slot '{s}' not found in actual", .{
            case_id, owner, expected[0],
        });
        var fail_count: usize = 1;
        for (expected[1..]) |name| {
            if (!containsStr(actual, name)) {
                std.log.err("[{s}] missing vtable method on {s}: {s}", .{ case_id, owner, name });
                fail_count += 1;
            }
        }
        return fail_count;
    }

    const base_offset = offset.?;
    var fail_count: usize = 0;

    // Check that enough slots remain in actual after the offset
    if (base_offset + expected.len > actual.len) {
        std.log.err("[{s}] vtable on {s}: expected {d} own slots at offset {d}, but actual only has {d} total", .{
            case_id, owner, expected.len, base_offset, actual.len,
        });
        // Compare what we can, then report missing
        const available = actual.len - base_offset;
        for (0..available) |i| {
            if (!std.mem.eql(u8, expected[i], actual[base_offset + i])) {
                std.log.err("[{s}] vtable slot {d} on {s}: expected '{s}', got '{s}'", .{
                    case_id, base_offset + i, owner, expected[i], actual[base_offset + i],
                });
                fail_count += 1;
            }
        }
        for (available..expected.len) |i| {
            std.log.err("[{s}] vtable slot {d} on {s}: expected '{s}', missing in actual", .{
                case_id, base_offset + i, owner, expected[i],
            });
            fail_count += 1;
        }
        return fail_count;
    }

    // Positional comparison from offset (name + signature)
    for (0..expected.len) |i| {
        if (!std.mem.eql(u8, expected[i], actual[base_offset + i])) {
            std.log.err("[{s}] vtable slot {d} on {s}: expected '{s}', got '{s}'", .{
                case_id, base_offset + i, owner, expected[i], actual[base_offset + i],
            });
            fail_count += 1;
            continue; // name mismatch, skip sig comparison for this slot
        }

        // Compare signatures if both sides have signature data
        if (i < expected_sigs.len and (base_offset + i) < actual_sigs.len) {
            const exp_sig = expected_sigs[i];
            const act_sig = actual_sigs[base_offset + i];
            if (!signaturesMatch(exp_sig, act_sig)) {
                const exp_pc = if (exp_sig.param_count) |pc| pc else 0;
                const act_pc = if (act_sig.param_count) |pc| pc else 0;
                const exp_rt = exp_sig.return_type orelse "?";
                const act_rt = act_sig.return_type orelse "?";
                std.log.err("[{s}] vtable sig mismatch slot {d} '{s}' on {s}: expected params={d} ret={s}, got params={d} ret={s}", .{
                    case_id, base_offset + i, expected[i], owner,
                    exp_pc, exp_rt,
                    act_pc, act_rt,
                });
                fail_count += 1;
            }
        }
    }

    return fail_count;
}

pub fn compareManifests(case_id: []const u8, expected: *const Manifest, actual: *const Manifest, opts: ctx.CompareOptions) usize {
    var fail_count: usize = 0;

    for (expected.functions.items) |fn_name| {
        if (opts.allow_nt_wait_compat and std.mem.eql(u8, fn_name, "NtWaitForSingleObject") and containsStr(actual.functions.items, "WaitForSingleObjectEx")) continue;
        if (containsStr(actual.functions.items, fn_name)) continue;
        std.log.err("[{s}] missing function: {s}", .{ case_id, fn_name });
        fail_count += 1;
    }

    for (expected.types.items) |exp_type| {
        const act_type = actual.findType(exp_type.name) orelse {
            if (opts.allow_sys_fn_ptr_alias and exp_type.kind == .unknown and containsStr(actual.functions.items, exp_type.name)) continue;
            std.log.err("[{s}] missing type: {s}", .{ case_id, exp_type.name });
            fail_count += 1;
            continue;
        };

        if (exp_type.iid_value != null and act_type.iid_value != null) {
            if (!std.mem.eql(u8, &exp_type.iid_value.?, &act_type.iid_value.?)) {
                std.log.err("[{s}] GUID mismatch for {s}", .{ case_id, exp_type.name });
                fail_count += 1;
            }
        }

        if (exp_type.kind != .unknown and act_type.kind != .unknown and exp_type.kind != act_type.kind) {
            const is_enum_to_struct = (exp_type.kind == .enum_type and act_type.kind == .struct_type);
            if (!is_enum_to_struct) {
                std.log.err("[{s}] kind mismatch for {s}: expected={s} actual={s}", .{
                    case_id,
                    exp_type.name,
                    @tagName(exp_type.kind),
                    @tagName(act_type.kind),
                });
                fail_count += 1;
            }
        }

        fail_count += compareExpectedList(case_id, exp_type.name, "field", exp_type.fields.items, act_type.fields.items);
        fail_count += compareExpectedList(case_id, exp_type.name, "method", exp_type.methods.items, act_type.methods.items);
        fail_count += compareVtableSlotOrder(case_id, exp_type.name, exp_type.vtable_methods.items, act_type.vtable_methods.items, exp_type.vtable_sigs.items, act_type.vtable_sigs.items);
        fail_count += compareExpectedList(case_id, exp_type.name, "enum variant", exp_type.enum_variants.items, act_type.enum_variants.items);
        fail_count += compareExpectedList(case_id, exp_type.name, "required interface", exp_type.required_ifaces.items, act_type.required_ifaces.items);
    }

    return fail_count;
}
