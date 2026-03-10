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

pub const TypeShape = struct {
    name: []const u8,
    kind: SymbolKind,
    has_iid: bool = false,
    has_lpvtable: bool = false,
    fields: std.ArrayList([]const u8) = .empty,
    methods: std.ArrayList([]const u8) = .empty,
    vtable_methods: std.ArrayList([]const u8) = .empty,
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
        try appendUniqueStr(self.allocator, &self.types.items[type_index].vtable_methods, name);
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
                try manifest.addVtableMethod(type_index, vtbl_name);
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
        if (std.mem.startsWith(u8, line, "pub const IID = ")) t.has_iid = true;
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
        if (ident.len > 0) _ = try manifest.ensureType(ident, kind);
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
    if (std.mem.indexOf(u8, line, ": unsafe extern") == null and
        std.mem.indexOf(u8, line, ": usize") == null and
        std.mem.indexOf(u8, line, ": Option<") == null and
        std.mem.indexOf(u8, line, ": *const") == null)
    {
        return null;
    }
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
                if (!std.mem.eql(u8, field_name, "base__")) try manifest.addVtableMethod(type_index, field_name);
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
        fail_count += compareExpectedList(case_id, exp_type.name, "vtable method", exp_type.vtable_methods.items, act_type.vtable_methods.items);
        fail_count += compareExpectedList(case_id, exp_type.name, "enum variant", exp_type.enum_variants.items, act_type.enum_variants.items);
        fail_count += compareExpectedList(case_id, exp_type.name, "required interface", exp_type.required_ifaces.items, act_type.required_ifaces.items);
    }

    return fail_count;
}
