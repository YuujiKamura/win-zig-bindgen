const std = @import("std");
const win_zig_metadata = @import("win_zig_metadata");
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const coded = win_zig_metadata.coded_index;
const resolver = @import("resolver.zig");

pub const Context = struct {
    table_info: tables.Info,
    heaps: streams.Heaps,
    dependencies: ?*std.StringHashMap(void) = null,
    allocator: ?std.mem.Allocator = null,

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
            if (isBuiltinType(stripped)) return;
            if (isKnownStruct(stripped)) return;
            if (std.mem.eql(u8, stripped, "EventRegistrationToken")) return;
            if (std.mem.eql(u8, stripped, "IInspectable")) return;
            if (std.mem.eql(u8, stripped, "IUnknown")) return;

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
        \\pub const IID_TypedEventHandler_TabCloseRequested = GUID{ .data1 = 0x7093974b, .data2 = 0x0900, .data3 = 0x52ae, .data4 = .{ 0xaf, 0xd8, 0x70, 0xe5, 0x62, 0x3f, 0x45, 0x95 } };
        \\pub const IID_TypedEventHandler_AddTabButtonClick = GUID{ .data1 = 0x13df6907, .data2 = 0xbbb4, .data3 = 0x5f16, .data4 = .{ 0xbe, 0xac, 0x29, 0x38, 0xc1, 0x5e, 0x1d, 0x85 } };
        \\pub const IID_SelectionChangedEventHandler = GUID{ .data1 = 0xa232390d, .data2 = 0x0e34, .data3 = 0x595e, .data4 = .{ 0x89, 0x31, 0xfa, 0x92, 0x8a, 0x99, 0x09, 0xf4 } };
        \\pub const IID_TypedEventHandler_WindowClosed = GUID{ .data1 = 0x2a954d28, .data2 = 0x7f8b, .data3 = 0x5479, .data4 = .{ 0x8c, 0xe9, 0x90, 0x04, 0x24, 0xa0, 0x40, 0x9f } };
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

pub fn emitInterface(
    allocator: std.mem.Allocator,
    writer: anytype,
    ctx: Context,
    _: []const u8,
    interface_name: []const u8,
) !void {
    const type_row = try findTypeDefRow(ctx, interface_name);
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name = try ctx.heaps.getString(type_def.type_name);
    const ns = try ctx.heaps.getString(type_def.type_namespace);
    const is_winrt_iface = !std.mem.startsWith(u8, ns, "Windows.Win32.") and !std.mem.startsWith(u8, ns, "Windows.Wdk.");

    const guid = extractGuid(ctx, type_row) catch std.mem.zeroes([16]u8);

    const method_range_info = try methodRange(ctx.table_info, type_row);
    var methods = std.ArrayList(MethodMeta).empty;
    defer {
        for (methods.items) |m| {
            allocator.free(m.raw_name);
            allocator.free(m.norm_name);
            allocator.free(m.vtbl_sig);
            allocator.free(m.wrapper_sig);
            allocator.free(m.wrapper_call);
            allocator.free(m.raw_wrapper_sig);
            allocator.free(m.raw_wrapper_call);
        }
        methods.deinit(allocator);
    }

    var seen_method_names = std.StringHashMap(u32).init(allocator);
    defer {
        var it = seen_method_names.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        seen_method_names.deinit();
    }

    var seen_norm_names = std.StringHashMap(u32).init(allocator);
    defer {
        var it = seen_norm_names.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        seen_norm_names.deinit();
    }

    var i = method_range_info.start;
    while (i < method_range_info.end_exclusive) : (i += 1) {
        const m = try ctx.table_info.readMethodDef(i);
        const name = try ctx.heaps.getString(m.name);
        const sig_blob = try ctx.heaps.getBlob(m.signature);
        var sig_c = SigCursor{ .data = sig_blob };
        _ = sig_c.readByte();
        const param_count = sig_c.readCompressedUInt() orelse 0;
        const ret_type_opt = try decodeSigType(allocator, ctx, &sig_c, is_winrt_iface);
        const ret_type_raw = ret_type_opt orelse "void";
        defer if (ret_type_opt != null) allocator.free(ret_type_raw);

        // Collect actual parameter names from metadata
        var param_names_meta = try collectParamNames(allocator, ctx, i);
        defer param_names_meta.deinit(allocator);
        var all_param_names = std.ArrayList([]const u8).empty;
        defer {
            for (all_param_names.items) |n| allocator.free(n);
            all_param_names.deinit(allocator);
        }
        for (param_names_meta.items) |pn| {
            try all_param_names.append(allocator, try sanitizeIdentifier(allocator, pn));
        }
        while (all_param_names.items.len < param_count) {
            try all_param_names.append(allocator, try std.fmt.allocPrint(allocator, "p{d}", .{all_param_names.items.len}));
        }

        var vtbl_params = std.ArrayList(u8).empty;
        defer vtbl_params.deinit(allocator);
        try vtbl_params.appendSlice(allocator, "*anyopaque");

        var wrapper_params = std.ArrayList(u8).empty;
        defer wrapper_params.deinit(allocator);

        var wrapper_fwd_args = std.ArrayList(u8).empty;
        defer wrapper_fwd_args.deinit(allocator);

        var call_args = std.ArrayList(u8).empty;
        defer call_args.deinit(allocator);
        try call_args.appendSlice(allocator, "self");

        var wrapper_ret: []const u8 = try allocator.dupe(u8, "void");
        defer allocator.free(wrapper_ret);

        // WinRT getter: param_count==1 means ABI has out-param; param_count==0 means
        // the .winmd uses managed convention (return type IS the property type).
        const is_getter = std.mem.startsWith(u8, name, "get_") and (param_count == 1 or
            (param_count == 0 and !std.mem.eql(u8, ret_type_raw, "void")));

        var byref_indices = std.ArrayList(u32).empty;
        defer byref_indices.deinit(allocator);

        var param_vtbl_types = std.ArrayList([]const u8).empty;
        defer {
            for (param_vtbl_types.items) |t| allocator.free(t);
            param_vtbl_types.deinit(allocator);
        }

        var param_logical_types = std.ArrayList([]const u8).empty;
        defer {
            for (param_logical_types.items) |t| allocator.free(t);
            param_logical_types.deinit(allocator);
        }

        var p_idx: u32 = 0;
        while (p_idx < param_count) : (p_idx += 1) {
            const is_byref = (sig_c.pos < sig_c.data.len and sig_c.data[sig_c.pos] == 0x10);
            const p_type_opt = try decodeSigType(allocator, ctx, &sig_c, is_winrt_iface);
            const p_type_raw = p_type_opt orelse "?*anyopaque";
            if (is_byref) try byref_indices.append(allocator, p_idx);
            defer if (p_type_opt != null) allocator.free(p_type_raw);

            var p_type_vtbl = if (std.mem.eql(u8, p_type_raw, "anyopaque"))
                try allocator.dupe(u8, "?*anyopaque")
            else if (isBuiltinType(p_type_raw))
                try allocator.dupe(u8, p_type_raw)
            else if (std.mem.startsWith(u8, p_type_raw, "*")) blk_vtbl: {
                const inner = p_type_raw[1..];
                if (isBuiltinType(inner) or std.mem.eql(u8, inner, "EventRegistrationToken") or isKnownStruct(inner))
                    break :blk_vtbl try allocator.dupe(u8, p_type_raw) // *i32, *EventRegistrationToken, *GridLength
                else
                    break :blk_vtbl try allocator.dupe(u8, "*?*anyopaque"); // *IVector -> *?*anyopaque
            } else if (std.mem.startsWith(u8, p_type_raw, "?"))
                try allocator.dupe(u8, p_type_raw)
            else if (isKnownStruct(p_type_raw) or std.mem.eql(u8, p_type_raw, "EventRegistrationToken"))
                try allocator.dupe(u8, p_type_raw) // Color, GridLength, EventRegistrationToken pass by value
            else
                try allocator.dupe(u8, "?*anyopaque"); // interface names -> ?*anyopaque

            // No concessions needed - proper type resolution handles ABI mapping
            defer allocator.free(p_type_vtbl);

            try vtbl_params.appendSlice(allocator, ", ");
            try vtbl_params.appendSlice(allocator, p_type_vtbl);
            try param_vtbl_types.append(allocator, try allocator.dupe(u8, p_type_vtbl));
            try param_logical_types.append(allocator, try allocator.dupe(u8, p_type_raw));

            const p_name = all_param_names.items[p_idx];

            if (is_getter) {
                // Use logical type from decoded signature for return type
                const logical_raw = p_type_raw; // e.g., "*IVector", "*i32", "*GridLength"
                const logical_inner = if (std.mem.startsWith(u8, logical_raw, "*")) logical_raw[1..] else logical_raw;
                const is_iface_return = isInterfaceType(logical_inner);

                allocator.free(wrapper_ret);
                if (is_iface_return) {
                    wrapper_ret = try std.fmt.allocPrint(allocator, "*{s}", .{logical_inner});
                } else if (std.mem.startsWith(u8, p_type_vtbl, "*")) {
                    wrapper_ret = try allocator.dupe(u8, p_type_vtbl[1..]);
                } else {
                    wrapper_ret = try allocator.dupe(u8, p_type_vtbl);
                }
            } else {
                try wrapper_params.appendSlice(allocator, ", ");
                try wrapper_params.appendSlice(allocator, p_name);
                try wrapper_params.appendSlice(allocator, ": ");

                // Wrappers accept anytype for non-null pointers (lax casting),
                // but use concrete type for nullable pointers (callers may pass null).
                if (std.mem.eql(u8, p_type_vtbl, "HSTRING")) {
                    try wrapper_params.appendSlice(allocator, "anytype");
                } else if (std.mem.startsWith(u8, p_type_vtbl, "?*")) {
                    try wrapper_params.appendSlice(allocator, p_type_vtbl);
                } else {
                    try wrapper_params.appendSlice(allocator, p_type_vtbl);
                }

                try wrapper_fwd_args.appendSlice(allocator, ", ");
                try wrapper_fwd_args.appendSlice(allocator, p_name);

                try call_args.appendSlice(allocator, ", ");
                if (std.mem.eql(u8, p_type_vtbl, "HSTRING")) {
                    try call_args.appendSlice(allocator, "@ptrCast(");
                    try call_args.appendSlice(allocator, p_name);
                    try call_args.appendSlice(allocator, ")");
                } else {
                    try call_args.appendSlice(allocator, p_name);
                }
            }
        }

        // WinRT managed convention: non-void return type in .winmd → synthesize ABI out-param
        // Applies to getters (get_*), event subscriptions (add_*), and methods with non-void returns
        if (is_winrt_iface and std.mem.eql(u8, ret_type_raw, "SZARRAY")) {
            // WinRT array return: becomes [out] uint32 count, [out] T* definitions at ABI
            const synth_base: u32 = @intCast(param_vtbl_types.items.len);
            try vtbl_params.appendSlice(allocator, ", *u32");
            try param_vtbl_types.append(allocator, try allocator.dupe(u8, "*u32"));
            try param_logical_types.append(allocator, try allocator.dupe(u8, "*u32"));
            try byref_indices.append(allocator, synth_base);
            try all_param_names.append(allocator, try allocator.dupe(u8, "count"));

            try vtbl_params.appendSlice(allocator, ", *?*anyopaque");
            try param_vtbl_types.append(allocator, try allocator.dupe(u8, "*?*anyopaque"));
            try param_logical_types.append(allocator, try allocator.dupe(u8, "*?*anyopaque"));
            try byref_indices.append(allocator, synth_base + 1);
            try all_param_names.append(allocator, try allocator.dupe(u8, "definitions"));
        } else if (is_winrt_iface and !std.mem.eql(u8, ret_type_raw, "void")) {
            const is_iface_ret = isInterfaceType(ret_type_raw);
            const synth_param_idx: u32 = @intCast(param_vtbl_types.items.len);

            // Synthesize vtbl out-param
            // Known value types (i32, bool, f64, GridLength, Color, EventRegistrationToken) use *T at ABI
            // Everything else (interfaces, HSTRING, unknown structs like Thickness) becomes *?*anyopaque
            const is_known_value = isBuiltinType(ret_type_raw) or isKnownStruct(ret_type_raw) or std.mem.eql(u8, ret_type_raw, "EventRegistrationToken");
            const is_opaque_ptr = !is_known_value;
            if (is_opaque_ptr) {
                try vtbl_params.appendSlice(allocator, ", *?*anyopaque");
                try param_vtbl_types.append(allocator, try allocator.dupe(u8, "*?*anyopaque"));
                try param_logical_types.append(allocator, try std.fmt.allocPrint(allocator, "*{s}", .{ret_type_raw}));
            } else {
                const vtbl_out_type = try std.fmt.allocPrint(allocator, "*{s}", .{ret_type_raw});
                defer allocator.free(vtbl_out_type);
                try vtbl_params.appendSlice(allocator, ", ");
                try vtbl_params.appendSlice(allocator, vtbl_out_type);
                try param_vtbl_types.append(allocator, try allocator.dupe(u8, vtbl_out_type));
                try param_logical_types.append(allocator, try std.fmt.allocPrint(allocator, "*{s}", .{ret_type_raw}));
            }
            try byref_indices.append(allocator, synth_param_idx);
            try all_param_names.append(allocator, try allocator.dupe(u8, if (is_getter) "out" else "value"));

            // For getters, set wrapper_ret based on the return type
            if (is_getter) {
                allocator.free(wrapper_ret);
                if (is_iface_ret) {
                    wrapper_ret = try std.fmt.allocPrint(allocator, "*{s}", .{ret_type_raw});
                } else if (is_opaque_ptr) {
                    // HSTRING/?*anyopaque: opaque getter, wrapper_ret stays as ?*anyopaque for nullable path
                    wrapper_ret = try allocator.dupe(u8, "?*anyopaque");
                } else if (isBuiltinType(ret_type_raw) or isKnownStruct(ret_type_raw) or
                    std.mem.eql(u8, ret_type_raw, "EventRegistrationToken"))
                {
                    // Known primitive/struct: return by value
                    wrapper_ret = try allocator.dupe(u8, ret_type_raw);
                } else {
                    // Unknown struct type (Thickness, CornerRadius, etc): treat as opaque
                    wrapper_ret = try allocator.dupe(u8, "?*anyopaque");
                }
            }
        } else if (!is_winrt_iface) {
            // Win32 COM: metadata return type is actual return type (usually HRESULT, but not always)
            allocator.free(wrapper_ret);
            wrapper_ret = try allocator.dupe(u8, ret_type_raw);
        }

        var raw_name_seed = try allocator.dupe(u8, name);
        defer allocator.free(raw_name_seed);
        var norm_seed = try allocator.dupe(u8, name);
        defer allocator.free(norm_seed);
        var preserve_norm_case = false;

        if (is_winrt_iface) {
            if (std.mem.startsWith(u8, name, "get_")) {
                const suffix = name["get_".len..];
                allocator.free(raw_name_seed);
                raw_name_seed = try allocator.dupe(u8, suffix);
                allocator.free(norm_seed);
                norm_seed = try allocator.dupe(u8, suffix);
                preserve_norm_case = true;
            } else if (std.mem.startsWith(u8, name, "put_")) {
                const suffix = name["put_".len..];
                allocator.free(raw_name_seed);
                raw_name_seed = try std.fmt.allocPrint(allocator, "Set{s}", .{suffix});
                allocator.free(norm_seed);
                norm_seed = try allocator.dupe(u8, raw_name_seed);
                preserve_norm_case = true;
            } else if (std.mem.startsWith(u8, name, "add_")) {
                const suffix = name["add_".len..];
                allocator.free(raw_name_seed);
                raw_name_seed = try allocator.dupe(u8, suffix);
                allocator.free(norm_seed);
                norm_seed = try std.fmt.allocPrint(allocator, "Add{s}", .{suffix});
                preserve_norm_case = true;
            } else if (std.mem.startsWith(u8, name, "remove_")) {
                const suffix = name["remove_".len..];
                allocator.free(raw_name_seed);
                raw_name_seed = try std.fmt.allocPrint(allocator, "Remove{s}", .{suffix});
                allocator.free(norm_seed);
                norm_seed = try allocator.dupe(u8, raw_name_seed);
                preserve_norm_case = true;
            }
        }
        if (std.mem.eql(u8, name, "CreateInstance")) preserve_norm_case = true;

        while (raw_name_seed.len > 0 and !std.ascii.isAlphabetic(raw_name_seed[0]) and raw_name_seed[0] != '_') {
            const new_raw = try allocator.dupe(u8, raw_name_seed[1..]);
            allocator.free(raw_name_seed);
            raw_name_seed = new_raw;
        }
        while (norm_seed.len > 0 and !std.ascii.isAlphabetic(norm_seed[0]) and norm_seed[0] != '_') {
            const new_norm = try allocator.dupe(u8, norm_seed[1..]);
            allocator.free(norm_seed);
            norm_seed = new_norm;
        }

        const prev_count = seen_method_names.get(raw_name_seed) orelse 0;
        var unique = if (prev_count > 0) try std.fmt.allocPrint(allocator, "{s}_{d}", .{ raw_name_seed, prev_count }) else try allocator.dupe(u8, raw_name_seed);
        // Keep IXamlMetadataProvider overload naming compatible with existing call-sites.
        if (std.mem.eql(u8, type_name, "IXamlMetadataProvider") and std.mem.eql(u8, name, "GetXamlType") and prev_count > 0) {
            allocator.free(unique);
            unique = try allocator.dupe(u8, "GetXamlType_2");
        }
        try seen_method_names.put(try allocator.dupe(u8, raw_name_seed), prev_count + 1);

        var norm_name = if (std.mem.indexOfScalar(u8, norm_seed, '_')) |underscore_idx| blk: {
            const prefix = norm_seed[0..underscore_idx];
            const suffix = norm_seed[underscore_idx + 1 ..];
            break :blk try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, suffix });
        } else try allocator.dupe(u8, norm_seed);
        if (!preserve_norm_case and norm_name.len > 0) norm_name[0] = std.ascii.toLower(norm_name[0]);

        var emit_raw_wrapper_alias = true;
        if (is_getter and (isKnownStruct(wrapper_ret) or std.mem.eql(u8, wrapper_ret, "EventRegistrationToken")) and std.mem.eql(u8, norm_name, wrapper_ret)) {
            const renamed = try std.fmt.allocPrint(allocator, "Get{s}", .{norm_name});
            allocator.free(norm_name);
            norm_name = renamed;
            emit_raw_wrapper_alias = false;
        }

        const norm_prev = seen_norm_names.get(norm_name) orelse 0;
        if (norm_prev > 0) {
            const new_norm = try std.fmt.allocPrint(allocator, "{s}_{d}", .{ norm_name, norm_prev });
            allocator.free(norm_name);
            norm_name = new_norm;
        }
        try seen_norm_names.put(try allocator.dupe(u8, norm_name), norm_prev + 1);

        const vtbl_ret = if (is_winrt_iface) "HRESULT" else wrapper_ret;
        const vtbl_sig = try std.fmt.allocPrint(allocator, "*const fn ({s}) callconv(.winapi) {s}", .{ vtbl_params.items, vtbl_ret });
        var wrapper_sig: []const u8 = undefined;
        var wrapper_call: []const u8 = undefined;
        var raw_wrapper_sig: []const u8 = undefined;
        var raw_wrapper_call: []const u8 = undefined;

        if (is_getter) {
            const iface_inner = if (std.mem.startsWith(u8, wrapper_ret, "*")) wrapper_ret[1..] else wrapper_ret;
            const is_iface_getter = std.mem.startsWith(u8, wrapper_ret, "*") and isInterfaceType(iface_inner);
            const is_importable_iface = is_iface_getter and isImportableInterface(iface_inner);
            const is_nullable_getter = (std.mem.eql(u8, type_name, "IWindow") or std.mem.eql(u8, type_name, "IContentControl")) and std.mem.eql(u8, name, "get_Content");

            if (is_nullable_getter) {
                // Nullable interface getter: returns ?*IInspectable
                wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !?*IInspectable", .{norm_name});
                wrapper_call = try std.fmt.allocPrint(
                    allocator,
                    "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &out)); if (out) |p| return @ptrCast(@alignCast(p)); return null;",
                    .{unique},
                );
                raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !?*IInspectable", .{unique});
                raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
            } else if (is_importable_iface) {
                // Known interface getter: returns *InterfaceName with ptrCast
                wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !{s}", .{ norm_name, wrapper_ret });
                wrapper_call = try std.fmt.allocPrint(
                    allocator,
                    "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed));",
                    .{unique},
                );
                raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !{s}", .{ unique, wrapper_ret });
                raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
            } else if (is_iface_getter or std.mem.eql(u8, wrapper_ret, "?*anyopaque")) {
                // Opaque getter (unknown generic like IMap): returns *anyopaque with null check
                allocator.free(wrapper_ret);
                wrapper_ret = try allocator.dupe(u8, "*anyopaque");
                wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*anyopaque", .{norm_name});
                wrapper_call = try std.fmt.allocPrint(
                    allocator,
                    "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &out)); return out orelse error.WinRTFailed;",
                    .{unique},
                );
                raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*anyopaque", .{unique});
                raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
            } else {
                // Value/primitive getter
                const init = defaultInit(wrapper_ret);
                wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !{s}", .{ norm_name, wrapper_ret });
                wrapper_call = try std.fmt.allocPrint(allocator, "var out: {s} = {s}; try hrCheck(self.lpVtbl.{s}(self, &out)); return out;", .{ wrapper_ret, init, unique });
                raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !{s}", .{ unique, wrapper_ret });
                raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
            }
        } else {
            // CreateInstance must preserve COM aggregation shape:
            // outer -> { inner, instance }
            if (std.mem.eql(u8, name, "CreateInstance") and param_count >= 2) {
                wrapper_sig = try std.fmt.allocPrint(
                    allocator,
                    "pub fn {s}(self: *@This(), outer: ?*anyopaque) !struct {{ inner: ?*anyopaque, instance: *IInspectable }}",
                    .{norm_name},
                );
                wrapper_call = try std.fmt.allocPrint(
                    allocator,
                    "var inner: ?*anyopaque = null; var instance: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, outer, &inner, &instance)); return .{{ .inner = inner, .instance = @ptrCast(@alignCast(instance.?)) }};",
                    .{unique},
                );
                raw_wrapper_sig = try std.fmt.allocPrint(
                    allocator,
                    "pub fn {s}(self: *@This(), outer: ?*anyopaque) !struct {{ inner: ?*anyopaque, instance: *IInspectable }}",
                    .{unique},
                );
                raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}(outer);", .{norm_name});
                emit_raw_wrapper_alias = false;
            } else if (byref_indices.items.len > 0) {
                // Out-param wrapper: trailing BYREF params become return values
                // Build wrapper sig with only non-byref params
                var out_wrapper_params = std.ArrayList(u8).empty;
                defer out_wrapper_params.deinit(allocator);
                var out_fwd_args = std.ArrayList(u8).empty;
                defer out_fwd_args.deinit(allocator);
                var out_call_args = std.ArrayList(u8).empty;
                defer out_call_args.deinit(allocator);
                try out_call_args.appendSlice(allocator, "self");
                var out_locals = std.ArrayList(u8).empty;
                defer out_locals.deinit(allocator);
                var out_ret_fields = std.ArrayList(u8).empty;
                defer out_ret_fields.deinit(allocator);
                var out_ret_vals = std.ArrayList(u8).empty;
                defer out_ret_vals.deinit(allocator);
                var byref_count: u32 = 0;

                const actual_param_count: u32 = @intCast(param_vtbl_types.items.len);
                var pi: u32 = 0;
                while (pi < actual_param_count) : (pi += 1) {
                    var is_out = false;
                    for (byref_indices.items) |bi| {
                        if (bi == pi) {
                            is_out = true;
                            break;
                        }
                    }
                    const pvt = param_vtbl_types.items[pi];
                    if (is_out) {
                        // BYREF param: pvt starts with "*", inner type is pvt[1..]
                        const inner_type = if (std.mem.startsWith(u8, pvt, "*")) pvt[1..] else pvt;
                        const local_name = try std.fmt.allocPrint(allocator, "out{d}", .{byref_count});
                        defer allocator.free(local_name);
                        // Default init: pointers/optionals = null, integers = 0, else = undefined
                        const default_val = if (std.mem.eql(u8, inner_type, "bool"))
                            "false"
                        else if (std.mem.startsWith(u8, inner_type, "?") or std.mem.startsWith(u8, inner_type, "*"))
                            "null"
                        else if (std.mem.eql(u8, inner_type, "i32") or std.mem.eql(u8, inner_type, "u32") or
                            std.mem.eql(u8, inner_type, "i64") or std.mem.eql(u8, inner_type, "u64") or
                            std.mem.eql(u8, inner_type, "i16") or std.mem.eql(u8, inner_type, "u16") or
                            std.mem.eql(u8, inner_type, "i8") or std.mem.eql(u8, inner_type, "u8") or
                            std.mem.eql(u8, inner_type, "isize") or std.mem.eql(u8, inner_type, "usize") or
                            std.mem.eql(u8, inner_type, "f32") or std.mem.eql(u8, inner_type, "f64") or
                            std.mem.eql(u8, inner_type, "EventRegistrationToken"))
                            "0"
                        else
                            "undefined";
                        try out_locals.appendSlice(allocator, "var ");
                        try out_locals.appendSlice(allocator, local_name);
                        try out_locals.appendSlice(allocator, ": ");
                        try out_locals.appendSlice(allocator, inner_type);
                        try out_locals.appendSlice(allocator, " = ");
                        try out_locals.appendSlice(allocator, default_val);
                        try out_locals.appendSlice(allocator, "; ");

                        try out_call_args.appendSlice(allocator, ", &");
                        try out_call_args.appendSlice(allocator, local_name);

                        try out_ret_fields.appendSlice(allocator, inner_type);
                        try out_ret_fields.appendSlice(allocator, ", ");

                        try out_ret_vals.appendSlice(allocator, local_name);
                        try out_ret_vals.appendSlice(allocator, ", ");

                        byref_count += 1;
                    } else {
                        // Non-BYREF param: include in wrapper signature
                        const p_name = try std.fmt.allocPrint(allocator, "p{d}", .{pi});
                        defer allocator.free(p_name);
                        try out_fwd_args.appendSlice(allocator, ", ");
                        try out_fwd_args.appendSlice(allocator, p_name);
                        try out_wrapper_params.appendSlice(allocator, ", ");
                        try out_wrapper_params.appendSlice(allocator, p_name);
                        try out_wrapper_params.appendSlice(allocator, ": ");
                        if (std.mem.eql(u8, pvt, "HSTRING")) {
                            try out_wrapper_params.appendSlice(allocator, "anytype");
                        } else if (std.mem.startsWith(u8, pvt, "?*")) {
                            try out_wrapper_params.appendSlice(allocator, pvt);
                        } else {
                            try out_wrapper_params.appendSlice(allocator, pvt);
                        }

                        try out_call_args.appendSlice(allocator, ", ");
                        if (std.mem.eql(u8, pvt, "HSTRING")) {
                            try out_call_args.appendSlice(allocator, "@ptrCast(");
                            try out_call_args.appendSlice(allocator, p_name);
                            try out_call_args.appendSlice(allocator, ")");
                        } else {
                            try out_call_args.appendSlice(allocator, p_name);
                        }
                    }
                }

                if (byref_count == 1) {
                    // Single out-param: return it directly
                    const out_type = param_vtbl_types.items[byref_indices.items[0]];
                    const inner_type = if (std.mem.startsWith(u8, out_type, "*")) out_type[1..] else out_type;
                    // Get logical type for interface detection
                    const logical_type = param_logical_types.items[byref_indices.items[0]];
                    const logical_inner = if (std.mem.startsWith(u8, logical_type, "*")) logical_type[1..] else logical_type;
                    const is_iface_out = isInterfaceType(logical_inner);
                    const is_importable = is_iface_out and isImportableInterface(logical_inner);

                    if (is_importable) {
                        // Known importable interface out-param: return typed pointer with ptrCast
                        wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !*{s}", .{ norm_name, out_wrapper_params.items, logical_inner });
                        wrapper_call = try std.fmt.allocPrint(
                            allocator,
                            "var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}({s})); return @ptrCast(@alignCast(out0 orelse return error.WinRTFailed));",
                            .{ unique, out_call_args.items },
                        );
                        raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !*{s}", .{ unique, out_wrapper_params.items, logical_inner });
                    } else {
                        wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !{s}", .{ norm_name, out_wrapper_params.items, inner_type });
                        wrapper_call = try std.fmt.allocPrint(allocator, "{s}try hrCheck(self.lpVtbl.{s}({s})); return out0;", .{ out_locals.items, unique, out_call_args.items });
                        raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !{s}", .{ unique, out_wrapper_params.items, inner_type });
                    }
                    const fwd_args = if (out_fwd_args.items.len > 2) out_fwd_args.items[2..] else "";
                    raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}({s});", .{ norm_name, fwd_args });
                } else {
                    // Multiple out-params: return a struct
                    var ret_struct_sig = std.ArrayList(u8).empty;
                    defer ret_struct_sig.deinit(allocator);
                    try ret_struct_sig.appendSlice(allocator, "struct { ");

                    var ret_val_init = std.ArrayList(u8).empty;
                    defer ret_val_init.deinit(allocator);
                    try ret_val_init.appendSlice(allocator, ".{ ");

                    var bi: u32 = 0;
                    while (bi < byref_count) : (bi += 1) {
                        const param_index = byref_indices.items[bi];
                        const p_name = all_param_names.items[param_index];
                        const pvt = param_vtbl_types.items[param_index];
                        const inner_type = if (std.mem.startsWith(u8, pvt, "*")) pvt[1..] else pvt;

                        if (bi > 0) {
                            try ret_struct_sig.appendSlice(allocator, ", ");
                            try ret_val_init.appendSlice(allocator, ", ");
                        }
                        try ret_struct_sig.writer(allocator).print("{s}: {s}", .{ p_name, inner_type });
                        try ret_val_init.writer(allocator).print(".{s} = out{d}", .{ p_name, bi });
                    }
                    try ret_struct_sig.appendSlice(allocator, " }");
                    try ret_val_init.appendSlice(allocator, " }");

                    wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !{s}", .{ norm_name, out_wrapper_params.items, ret_struct_sig.items });
                    wrapper_call = try std.fmt.allocPrint(allocator, "{s}try hrCheck(self.lpVtbl.{s}({s})); return {s};", .{ out_locals.items, unique, out_call_args.items, ret_val_init.items });
                    raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !{s}", .{ unique, out_wrapper_params.items, ret_struct_sig.items });
                    const fwd_args = if (out_fwd_args.items.len > 2) out_fwd_args.items[2..] else "";
                    raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}({s});", .{ norm_name, fwd_args });
                }
            } else {
                wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !void", .{ norm_name, wrapper_params.items });
                wrapper_call = try std.fmt.allocPrint(allocator, "try hrCheck(self.lpVtbl.{s}({s}));", .{ unique, call_args.items });
                raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !void", .{ unique, wrapper_params.items });
                const fwd_args = if (wrapper_fwd_args.items.len > 2) wrapper_fwd_args.items[2..] else "";
                raw_wrapper_call = try std.fmt.allocPrint(allocator, "try self.{s}({s});", .{ norm_name, fwd_args });
            }
        }

        if (!emit_raw_wrapper_alias) {
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);
            raw_wrapper_sig = try allocator.dupe(u8, "");
            raw_wrapper_call = try allocator.dupe(u8, "");
        }

        try methods.append(allocator, .{ .raw_name = try allocator.dupe(u8, unique), .norm_name = norm_name, .vtbl_sig = vtbl_sig, .wrapper_sig = wrapper_sig, .wrapper_call = wrapper_call, .raw_wrapper_sig = raw_wrapper_sig, .raw_wrapper_call = raw_wrapper_call });
        allocator.free(unique);
    }

    // Collect inherited methods from parent interfaces (COM extends chain)
    var parent_methods = try collectParentMethods(allocator, ctx, type_row);
    defer {
        for (parent_methods.items) |m| {
            allocator.free(m.raw_name);
            allocator.free(m.norm_name);
            allocator.free(m.vtbl_sig);
            allocator.free(m.wrapper_sig);
            allocator.free(m.wrapper_call);
            allocator.free(m.raw_wrapper_sig);
            allocator.free(m.raw_wrapper_call);
        }
        parent_methods.deinit(allocator);
    }

    // Collect required interfaces from InterfaceImpl table (WinRT)
    var required_ifaces = try collectRequiredInterfaces(allocator, ctx, type_row);
    defer {
        for (required_ifaces.items) |n| allocator.free(n);
        required_ifaces.deinit(allocator);
    }

    var required_iface_methods = std.ArrayList(MethodMeta).empty;
    defer {
        for (required_iface_methods.items) |m| {
            allocator.free(m.raw_name);
            allocator.free(m.norm_name);
            allocator.free(m.vtbl_sig);
            allocator.free(m.wrapper_sig);
            allocator.free(m.wrapper_call);
            allocator.free(m.raw_wrapper_sig);
            allocator.free(m.raw_wrapper_call);
        }
        required_iface_methods.deinit(allocator);
    }
    for (required_ifaces.items) |iface_name| {
        if (std.mem.eql(u8, iface_name, type_name)) continue;
        var iface_methods = try collectInterfaceMethodsByName(allocator, ctx, iface_name);
        defer {
            for (iface_methods.items) |m| {
                allocator.free(m.raw_name);
                allocator.free(m.norm_name);
                allocator.free(m.vtbl_sig);
                allocator.free(m.wrapper_sig);
                allocator.free(m.wrapper_call);
                allocator.free(m.raw_wrapper_sig);
                allocator.free(m.raw_wrapper_call);
            }
            iface_methods.deinit(allocator);
        }
        for (iface_methods.items) |m| {
            try required_iface_methods.append(allocator, .{
                .raw_name = try allocator.dupe(u8, m.raw_name),
                .norm_name = try allocator.dupe(u8, m.norm_name),
                .vtbl_sig = try allocator.dupe(u8, m.vtbl_sig),
                .wrapper_sig = try allocator.dupe(u8, m.wrapper_sig),
                .wrapper_call = try allocator.dupe(u8, m.wrapper_call),
                .raw_wrapper_sig = try allocator.dupe(u8, m.raw_wrapper_sig),
                .raw_wrapper_call = try allocator.dupe(u8, m.raw_wrapper_call),
            });
        }
    }

    try writer.print("pub const {s} = extern struct {{\n", .{type_name});
    try writer.print("    pub const IID = GUID{{ .data1 = 0x{x:0>8}, .data2 = 0x{x:0>4}, .data3 = 0x{x:0>4}, .data4 = .{{ 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2} }} }};\n", .{ std.mem.readInt(u32, guid[0..4], .little), std.mem.readInt(u16, guid[4..6], .little), std.mem.readInt(u16, guid[6..8], .little), guid[8], guid[9], guid[10], guid[11], guid[12], guid[13], guid[14], guid[15] });
    try writer.writeAll("    lpVtbl: *const VTable,\n    pub const VTable = extern struct {\n        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,\n        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,\n        Release: *const fn (*anyopaque) callconv(.winapi) u32,\n        GetIids: VtblPlaceholder,\n        GetRuntimeClassName: VtblPlaceholder,\n        GetTrustLevel: VtblPlaceholder,\n");
    // Emit inherited parent methods (COM flat vtable: parent slots before child slots)
    for (parent_methods.items) |m| try writer.print("        {s}: {s},\n", .{ m.raw_name, m.vtbl_sig });
    for (required_iface_methods.items) |m| try writer.print("        {s}: {s},\n", .{ m.raw_name, m.vtbl_sig });
    for (methods.items) |m| try writer.print("        {s}: {s},\n", .{ m.raw_name, m.vtbl_sig });
    try writer.writeAll("    };\n");
    // Emit required interface references (WinRT)
    for (required_ifaces.items) |iface_name| {
        try writer.print("    pub const Requires_{s} = true; // requires {s}\n", .{ iface_name, iface_name });
    }
    try writer.writeAll("    pub fn release(self: *@This()) void { comRelease(self); }\n    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }\n");
    var emitted_required_forwarders = std.StringHashMap(void).init(allocator);
    defer {
        var it = emitted_required_forwarders.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        emitted_required_forwarders.deinit();
    }
    for (required_ifaces.items) |iface_name| {
        const iface_row = findTypeDefRow(ctx, iface_name) catch continue;
        const iface_range = methodRange(ctx.table_info, iface_row) catch continue;
        var iface_mi = iface_range.start;
        while (iface_mi < iface_range.end_exclusive) : (iface_mi += 1) {
            const iface_m = try ctx.table_info.readMethodDef(iface_mi);
            const iface_method_name = try ctx.heaps.getString(iface_m.name);
            const iface_sig_blob = try ctx.heaps.getBlob(iface_m.signature);
            var iface_sig_c = SigCursor{ .data = iface_sig_blob };
            _ = iface_sig_c.readByte();
            const iface_param_count = iface_sig_c.readCompressedUInt() orelse continue;
            if (iface_param_count != 0) continue;

            var forward_name = try allocator.dupe(u8, iface_method_name);
            defer allocator.free(forward_name);
            if (std.mem.startsWith(u8, iface_method_name, "get_")) {
                allocator.free(forward_name);
                forward_name = try allocator.dupe(u8, iface_method_name["get_".len..]);
            } else if (std.mem.startsWith(u8, iface_method_name, "put_")) {
                allocator.free(forward_name);
                forward_name = try std.fmt.allocPrint(allocator, "Set{s}", .{iface_method_name["put_".len..]});
            } else if (std.mem.startsWith(u8, iface_method_name, "remove_")) {
                allocator.free(forward_name);
                forward_name = try std.fmt.allocPrint(allocator, "Remove{s}", .{iface_method_name["remove_".len..]});
            } else if (std.mem.startsWith(u8, iface_method_name, "add_")) {
                allocator.free(forward_name);
                forward_name = try std.fmt.allocPrint(allocator, "Add{s}", .{iface_method_name["add_".len..]});
            }

            if (emitted_required_forwarders.contains(forward_name)) continue;
            try emitted_required_forwarders.put(try allocator.dupe(u8, forward_name), {});
            try writer.print(
                "    pub fn {s}(self: *@This()) !void {{ const base = try self.queryInterface({s}); _ = try base.{s}(); }}\n",
                .{ forward_name, iface_name, forward_name },
            );
        }
    }
    for (methods.items) |m| {
        try writer.print("    {s} {{ {s} }}\n", .{ m.wrapper_sig, m.wrapper_call });
        if (m.raw_wrapper_sig.len > 0 and !std.mem.eql(u8, m.norm_name, m.raw_name)) try writer.print("    {s} {{ {s} }}\n", .{ m.raw_wrapper_sig, m.raw_wrapper_call });
    }
    const cat = identifyTypeCategory(ctx, type_row) catch .other;
    if (cat == .delegate) {
        try writer.writeAll("    pub fn new() !*@This() { return error.NotImplemented; }\n");
    }
    try writer.writeAll("};\n\n");
}

pub fn emitEnum(_: std.mem.Allocator, writer: anytype, ctx: Context, type_row: u32) !void {
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name = try ctx.heaps.getString(type_def.type_name);
    const range = try fieldRange(ctx.table_info, type_row);

    // Detect underlying type from value__ field signature
    const backing_type = detectEnumBackingType(ctx, range) catch "i32";
    const is_signed = backing_type[0] == 'i';
    const is_flags = hasAttribute(ctx, type_row, "FlagsAttribute") catch false;

    try writer.print("pub const {s} = enum({s}) {{\n", .{ type_name, backing_type });

    var i = range.start;
    while (i < range.end_exclusive) : (i += 1) {
        const f = try ctx.table_info.readField(i);
        const name = try ctx.heaps.getString(f.name);
        if (std.mem.eql(u8, name, "value__")) continue;

        // Find constant value from Constant table
        const c_table = ctx.table_info.getTable(.Constant);
        var ci: u32 = 1;
        var val_i64: i64 = 0;
        var val_u64: u64 = 0;
        while (ci <= c_table.row_count) : (ci += 1) {
            const c = try ctx.table_info.readConstant(ci);
            const parent = try coded.decodeHasConstant(c.parent);
            if (parent.table == .Field and parent.row == i) {
                const blob = try ctx.heaps.getBlob(c.value);
                if (is_signed) {
                    val_i64 = readSignedConstant(blob, backing_type);
                } else {
                    val_u64 = readUnsignedConstant(blob, backing_type);
                }
                break;
            }
        }

        if (is_signed) {
            try writer.print("    {s} = {d},\n", .{ name, val_i64 });
        } else {
            try writer.print("    {s} = {d},\n", .{ name, val_u64 });
        }
    }
    try writer.writeAll("    _,\n");

    if (is_flags) {
        try writer.print(
            \\
            \\    pub fn toInt(self: @This()) {s} {{
            \\        return @intFromEnum(self);
            \\    }}
            \\    pub fn fromInt(value: {s}) @This() {{
            \\        return @enumFromInt(value);
            \\    }}
        , .{ backing_type, backing_type });
        try writer.writeAll("\n");
    }

    try writer.writeAll("};\n\n");
}

fn detectEnumBackingType(ctx: Context, range: MethodRange) ![]const u8 {
    var i = range.start;
    while (i < range.end_exclusive) : (i += 1) {
        const f = try ctx.table_info.readField(i);
        const name = try ctx.heaps.getString(f.name);
        if (std.mem.eql(u8, name, "value__")) {
            const sig_blob = try ctx.heaps.getBlob(f.signature);
            if (sig_blob.len < 3) return "i32";
            // Field sig: 0x06 (FIELD), optional custom mods, then element type
            const elem = sig_blob[2];
            return switch (elem) {
                0x04 => "i8",
                0x05 => "u8",
                0x06 => "i16",
                0x07 => "u16",
                0x08 => "i32",
                0x09 => "u32",
                0x0A => "i64",
                0x0B => "u64",
                else => "i32",
            };
        }
    }
    return "i32";
}

fn readSignedConstant(blob: []const u8, backing_type: []const u8) i64 {
    if (std.mem.eql(u8, backing_type, "i8")) {
        if (blob.len >= 1) return @as(i64, @as(i8, @bitCast(blob[0])));
    } else if (std.mem.eql(u8, backing_type, "i16")) {
        if (blob.len >= 2) return @as(i64, std.mem.readInt(i16, blob[0..2], .little));
    } else if (std.mem.eql(u8, backing_type, "i64")) {
        if (blob.len >= 8) return std.mem.readInt(i64, blob[0..8], .little);
    } else {
        if (blob.len >= 4) return @as(i64, std.mem.readInt(i32, blob[0..4], .little));
    }
    return 0;
}

fn readUnsignedConstant(blob: []const u8, backing_type: []const u8) u64 {
    if (std.mem.eql(u8, backing_type, "u8")) {
        if (blob.len >= 1) return @as(u64, blob[0]);
    } else if (std.mem.eql(u8, backing_type, "u16")) {
        if (blob.len >= 2) return @as(u64, std.mem.readInt(u16, blob[0..2], .little));
    } else if (std.mem.eql(u8, backing_type, "u64")) {
        if (blob.len >= 8) return std.mem.readInt(u64, blob[0..8], .little);
    } else {
        if (blob.len >= 4) return @as(u64, std.mem.readInt(u32, blob[0..4], .little));
    }
    return 0;
}

fn hasAttribute(ctx: Context, type_row: u32, attr_name: []const u8) !bool {
    const ca_table = ctx.table_info.getTable(.CustomAttribute);
    var row: u32 = 1;
    while (row <= ca_table.row_count) : (row += 1) {
        const ca = try ctx.table_info.readCustomAttribute(row);
        const parent = try coded.decodeHasCustomAttribute(ca.parent);
        if (parent.table == .TypeDef and parent.row == type_row) {
            const ty = try coded.decodeCustomAttributeType(ca.ca_type);
            if (ty.table == .MemberRef) {
                const tr = try ctx.table_info.readMemberRef(ty.row);
                const tr_parent = try coded.decodeMemberRefParent(tr.class);
                if (tr_parent.table == .TypeRef) {
                    const tr_type = try ctx.table_info.readTypeRef(tr_parent.row);
                    const tr_name = try ctx.heaps.getString(tr_type.type_name);
                    if (std.mem.eql(u8, tr_name, attr_name)) return true;
                }
            }
        }
    }
    return false;
}

pub fn emitStruct(allocator: std.mem.Allocator, writer: anytype, ctx: Context, type_row: u32) !void {
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name = try ctx.heaps.getString(type_def.type_name);
    try writer.print("pub const {s} = extern struct {{\n", .{type_name});
    const range = try fieldRange(ctx.table_info, type_row);
    var i = range.start;
    while (i < range.end_exclusive) : (i += 1) {
        const f = try ctx.table_info.readField(i);
        const name = try ctx.heaps.getString(f.name);
        const sig_blob = try ctx.heaps.getBlob(f.signature);
        var sig_c = SigCursor{ .data = sig_blob };
        _ = sig_c.readByte();
        const ty_opt = try decodeSigType(allocator, ctx, &sig_c, false);
        const ty = ty_opt orelse "?*anyopaque";
        defer if (ty_opt != null) allocator.free(ty);
        try writer.print("    {s}: {s},\n", .{ name, ty });
    }
    try writer.writeAll("};\n\n");
}

fn isKnownStruct(name: []const u8) bool {
    const structs = [_][]const u8{ "GridLength", "Color", "Point", "Size", "Rect", "Thickness", "CornerRadius" };
    for (structs) |s| if (std.mem.eql(u8, name, s)) return true;
    return false;
}

fn sanitizeIdentifier(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const keywords = [_][]const u8{ "addrspace", "align", "and", "asm", "async", "await", "break", "catch", "comptime", "const", "continue", "defer", "else", "enum", "errdefer", "error", "export", "extern", "fn", "for", "if", "inline", "noalias", "noinline", "nosuspend", "opaque", "or", "orelse", "packed", "anyframe", "pub", "resume", "return", "linksection", "struct", "suspend", "switch", "test", "threadlocal", "try", "type", "union", "unreachable", "usingnamespace", "var", "volatile", "while" };
    for (keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) {
            return try std.fmt.allocPrint(allocator, "@\"{s}\"", .{name});
        }
    }
    return try allocator.dupe(u8, name);
}

fn paramRange(info: tables.Info, method_row: u32) !MethodRange {
    const md = try info.readMethodDef(method_row);
    return .{ .start = md.param_list, .end_exclusive = if (method_row < info.getTable(.MethodDef).row_count) (try info.readMethodDef(method_row + 1)).param_list else info.getTable(.Param).row_count + 1 };
}

fn collectParamNames(allocator: std.mem.Allocator, ctx: Context, method_row: u32) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8).empty;
    const range = try paramRange(ctx.table_info, method_row);
    var pi = range.start;
    while (pi < range.end_exclusive) : (pi += 1) {
        const p = try ctx.table_info.readParam(pi);
        if (p.sequence == 0) continue; // Skip return type
        try result.append(allocator, try ctx.heaps.getString(p.name));
    }
    return result;
}

fn customAttributeTypeName(ctx: Context, ca_type: u32) !?[]const u8 {
    const ty = coded.decodeCustomAttributeType(ca_type) catch return null;
    if (ty.table != .MemberRef) return null;
    const mr = try ctx.table_info.readMemberRef(ty.row);
    const parent = coded.decodeMemberRefParent(mr.class) catch return null;
    return switch (parent.table) {
        .TypeRef => blk: {
            const tr = try ctx.table_info.readTypeRef(parent.row);
            break :blk try ctx.heaps.getString(tr.type_name);
        },
        .TypeDef => blk: {
            const td = try ctx.table_info.readTypeDef(parent.row);
            break :blk try ctx.heaps.getString(td.type_name);
        },
        else => null,
    };
}

fn decodeCustomAttributeString(blob: []const u8) ?[]const u8 {
    if (blob.len < 3) return null;
    if (blob[0] != 0x01 or blob[1] != 0x00) return null;
    var c = SigCursor{ .data = blob[2..] };
    const len = c.readCompressedUInt() orelse return null;
    if (len == 0xFF) return null;
    if (c.pos + len > c.data.len) return null;
    return c.data[c.pos .. c.pos + len];
}

fn registerAssociatedEnumDependencies(allocator: std.mem.Allocator, ctx: Context, method_row: u32) !void {
    if (ctx.dependencies == null) return;
    const range = try paramRange(ctx.table_info, method_row);
    const ca_table = ctx.table_info.getTable(.CustomAttribute);
    var ca_row: u32 = 1;
    while (ca_row <= ca_table.row_count) : (ca_row += 1) {
        const ca = try ctx.table_info.readCustomAttribute(ca_row);
        const parent = coded.decodeHasCustomAttribute(ca.parent) catch continue;
        if (parent.table != .Param or parent.row < range.start or parent.row >= range.end_exclusive) continue;
        const attr_name = try customAttributeTypeName(ctx, ca.ca_type) orelse continue;
        if (!std.mem.eql(u8, attr_name, "AssociatedEnumAttribute")) continue;
        const blob = try ctx.heaps.getBlob(ca.value);
        const enum_name = decodeCustomAttributeString(blob) orelse continue;
        try ctx.registerDependency(allocator, enum_name);
    }
}

/// Returns true if the interface type is importable (defined in generated output or com_native).
/// Unknown interfaces (ICommand, IXamlMember, etc.) should use *anyopaque instead.
fn isImportableInterface(name: []const u8) bool {
    const importable = [_][]const u8{ "IInspectable", "IVector", "IXamlType" };
    for (importable) |iface| if (std.mem.eql(u8, name, iface)) return true;
    return false;
}

fn isInterfaceType(name: []const u8) bool {
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

fn defaultInit(ty: []const u8) []const u8 {
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
    if (std.mem.eql(u8, ty, "Color")) return ".{ .a = 0, .r = 0, .g = 0, .b = 0 }";
    return "undefined";
}

fn isBuiltinType(t: []const u8) bool {
    const builtins = [_][]const u8{ "void", "bool", "anyopaque", "?*anyopaque", "GUID", "HSTRING", "isize", "usize", "u8", "i8", "u16", "i16", "u32", "i32", "u64", "i64", "f32", "f64", "HWND", "HANDLE", "HINSTANCE", "HMODULE", "BOOL", "WPARAM", "LPARAM", "LPCWSTR", "LPWSTR", "HRESULT", "POINT", "RECT" };
    for (builtins) |b| if (std.mem.eql(u8, t, b)) return true;
    return false;
}

fn typeNameMatches(query_name: []const u8, actual_name: []const u8) bool {
    if (std.mem.eql(u8, query_name, actual_name)) return true;
    if (actual_name.len <= query_name.len) return false;
    if (!std.mem.startsWith(u8, actual_name, query_name)) return false;
    return actual_name[query_name.len] == '`';
}

pub fn findTypeDefRow(ctx: Context, interface_name: []const u8) !u32 {
    const dot_index = std.mem.lastIndexOfScalar(u8, interface_name, '.');
    const want_ns = if (dot_index) |idx| interface_name[0..idx] else null;
    const want_name = if (dot_index) |idx| interface_name[idx + 1 ..] else interface_name;
    const t = ctx.table_info.getTable(.TypeDef);
    var first_name_match: ?u32 = null;
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try ctx.table_info.readTypeDef(row);
        const name = try ctx.heaps.getString(td.type_name);
        const ns = try ctx.heaps.getString(td.type_namespace);
        if (!typeNameMatches(want_name, name)) continue;
        if (want_ns == null) return row;
        if (std.mem.eql(u8, ns, want_ns.?)) return row;
        if (std.mem.endsWith(u8, ns, want_ns.?)) return row;
        if (first_name_match == null) first_name_match = row;
    }
    if (first_name_match) |r| return r;
    return error.InterfaceNotFound;
}

fn methodRange(info: tables.Info, type_row: u32) !MethodRange {
    const td = try info.readTypeDef(type_row);
    return .{ .start = td.method_list, .end_exclusive = if (type_row < info.getTable(.TypeDef).row_count) (try info.readTypeDef(type_row + 1)).method_list else info.getTable(.MethodDef).row_count + 1 };
}

fn fieldRange(info: tables.Info, type_row: u32) !MethodRange {
    const td = try info.readTypeDef(type_row);
    return .{ .start = td.field_list, .end_exclusive = if (type_row < info.getTable(.TypeDef).row_count) (try info.readTypeDef(type_row + 1)).field_list else info.getTable(.Field).row_count + 1 };
}

fn extractGuid(ctx: Context, type_row: u32) ![16]u8 {
    const ca_table = ctx.table_info.getTable(.CustomAttribute);
    var row: u32 = 1;
    while (row <= ca_table.row_count) : (row += 1) {
        const ca = try ctx.table_info.readCustomAttribute(row);
        const parent = try coded.decodeHasCustomAttribute(ca.parent);
        if (parent.table == .TypeDef and parent.row == type_row) {
            const ty = try coded.decodeCustomAttributeType(ca.ca_type);
            const tr = try ctx.table_info.readMemberRef(ty.row);
            const tr_parent = try coded.decodeMemberRefParent(tr.class);
            const tr_type = try ctx.table_info.readTypeRef(tr_parent.row);
            const tr_name = try ctx.heaps.getString(tr_type.type_name);
            if (std.mem.eql(u8, tr_name, "GuidAttribute")) {
                const blob = try ctx.heaps.getBlob(ca.value);
                if (blob.len >= 18) return blob[2..18].*;
            }
        }
    }
    return error.MissingGuidAttribute;
}

const SigCursor = struct {
    data: []const u8,
    pos: usize = 0,
    fn readByte(self: *@This()) ?u8 {
        if (self.pos >= self.data.len) return null;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }
    fn readCompressedUInt(self: *@This()) ?u32 {
        const b1 = self.readByte() orelse return null;
        if (b1 & 0x80 == 0) return b1;
        const b2 = self.readByte() orelse return null;
        if (b1 & 0x40 == 0) return (@as(u32, b1 & 0x3F) << 8) | b2;
        const b3 = self.readByte() orelse return null;
        const b4 = self.readByte() orelse return null;
        return (@as(u32, b1 & 0x1F) << 24) | (@as(u32, b2) << 16) | (@as(u32, b3) << 8) | b4;
    }
};

fn resolveTypeDefOrRefFullNameAlloc(allocator: std.mem.Allocator, ctx: Context, tdor: coded.Decoded) !?[]const u8 {
    return switch (tdor.table) {
        .TypeDef => blk: {
            const td = try ctx.table_info.readTypeDef(tdor.row);
            const ns = try ctx.heaps.getString(td.type_namespace);
            const name = try ctx.heaps.getString(td.type_name);
            if (ns.len == 0) break :blk try allocator.dupe(u8, name);
            break :blk try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, name });
        },
        .TypeRef => blk: {
            const tr = try ctx.table_info.readTypeRef(tdor.row);
            const ns = try ctx.heaps.getString(tr.type_namespace);
            const name = try ctx.heaps.getString(tr.type_name);
            if (ns.len == 0) break :blk try allocator.dupe(u8, name);
            break :blk try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, name });
        },
        .TypeSpec => blk: {
            const base = try resolveTypeSpecBaseType(ctx, tdor.row) orelse break :blk null;
            break :blk try resolveTypeDefOrRefFullNameAlloc(allocator, ctx, base);
        },
        else => null,
    };
}

fn resolveTypeDefOrRefNameRaw(ctx: Context, tdor: coded.Decoded) !?[]const u8 {
    return switch (tdor.table) {
        .TypeDef => blk: {
            const td = try ctx.table_info.readTypeDef(tdor.row);
            break :blk try ctx.heaps.getString(td.type_name);
        },
        .TypeRef => blk: {
            const tr = try ctx.table_info.readTypeRef(tdor.row);
            break :blk try ctx.heaps.getString(tr.type_name);
        },
        .TypeSpec => blk: {
            const base = try resolveTypeSpecBaseType(ctx, tdor.row) orelse break :blk null;
            break :blk try resolveTypeDefOrRefNameRaw(ctx, base);
        },
        else => null,
    };
}

/// Resolve a TypeDefOrRef coded index to a TypeDef row in the same metadata.
/// For TypeDef, returns the row directly. For TypeRef, searches TypeDef table by name.
/// Returns null if unresolvable (e.g., TypeSpec or not found).
fn resolveTypeDefOrRefToRow(ctx: Context, tdor: coded.Decoded) !?u32 {
    switch (tdor.table) {
        .TypeDef => return tdor.row,
        .TypeRef => {
            const tr = try ctx.table_info.readTypeRef(tdor.row);
            const ref_name = try ctx.heaps.getString(tr.type_name);
            const ref_ns = try ctx.heaps.getString(tr.type_namespace);
            const t = ctx.table_info.getTable(.TypeDef);
            var first_name_match: ?u32 = null;
            var row: u32 = 1;
            while (row <= t.row_count) : (row += 1) {
                const td = try ctx.table_info.readTypeDef(row);
                const name = try ctx.heaps.getString(td.type_name);
                const ns = try ctx.heaps.getString(td.type_namespace);
                if (typeNameMatches(ref_name, name) and std.mem.eql(u8, ns, ref_ns)) return row;
                if (first_name_match == null and typeNameMatches(ref_name, name)) first_name_match = row;
            }
            return first_name_match;
        },
        .TypeSpec => {
            const base = try resolveTypeSpecBaseType(ctx, tdor.row) orelse return null;
            return try resolveTypeDefOrRefToRow(ctx, base);
        },
        else => return null,
    }
}

fn resolveTypeSpecBaseType(ctx: Context, type_spec_row: u32) !?coded.Decoded {
    const ts = ctx.table_info.readTypeSpec(type_spec_row) catch return null;
    const blob = try ctx.heaps.getBlob(ts.signature);
    var c = SigCursor{ .data = blob };
    const lead = c.readByte() orelse return null;
    return switch (lead) {
        0x11, 0x12 => blk: {
            const tdor_idx = c.readCompressedUInt() orelse return null;
            break :blk try coded.decodeTypeDefOrRef(tdor_idx);
        },
        0x15 => blk: {
            _ = c.readByte() orelse return null; // CLASS or VALUETYPE
            const tdor_idx = c.readCompressedUInt() orelse return null;
            break :blk try coded.decodeTypeDefOrRef(tdor_idx);
        },
        else => null,
    };
}

/// Collect parent interface method names for COM interfaces by walking the extends chain.
/// Stops at IUnknown/IInspectable (already hardcoded in vtable).
/// Returns method names in vtable order (grandparent first, then parent, etc.).
fn collectParentMethods(allocator: std.mem.Allocator, ctx: Context, type_row: u32) !std.ArrayList(MethodMeta) {
    var parent_chain = std.ArrayList(u32).empty;
    defer parent_chain.deinit(allocator);

    // Walk extends chain to collect parent TypeDef rows (excluding IUnknown/IInspectable)
    var cur_row = type_row;
    while (true) {
        const td = try ctx.table_info.readTypeDef(cur_row);
        if (td.extends == 0) break;
        const extends_tdor = coded.decodeTypeDefOrRef(td.extends) catch break;
        const parent_name = resolveTypeDefOrRefNameRaw(ctx, extends_tdor) catch break;
        if (parent_name == null) break;
        // Stop at IUnknown/IInspectable — these are already in the hardcoded vtable base
        if (std.mem.eql(u8, parent_name.?, "IUnknown") or std.mem.eql(u8, parent_name.?, "IInspectable")) break;
        if (try resolveTypeDefOrRefFullNameAlloc(allocator, ctx, extends_tdor)) |parent_full| {
            defer allocator.free(parent_full);
            try ctx.registerDependency(allocator, parent_full);
        } else {
            try ctx.registerDependency(allocator, parent_name.?);
        }
        const parent_row = resolveTypeDefOrRefToRow(ctx, extends_tdor) catch break;
        if (parent_row == null) break;
        try parent_chain.append(allocator, parent_row.?);
        cur_row = parent_row.?;
    }

    // Reverse so grandparent methods come first
    std.mem.reverse(u32, parent_chain.items);

    var result = std.ArrayList(MethodMeta).empty;
    for (parent_chain.items) |parent_row| {
        const range = try methodRange(ctx.table_info, parent_row);
        var mi = range.start;
        while (mi < range.end_exclusive) : (mi += 1) {
            const m = try ctx.table_info.readMethodDef(mi);
            const name = try ctx.heaps.getString(m.name);
            // Build a simple VtblPlaceholder entry for inherited methods
            try result.append(allocator, .{
                .raw_name = try allocator.dupe(u8, name),
                .norm_name = try allocator.dupe(u8, name),
                .vtbl_sig = try allocator.dupe(u8, "VtblPlaceholder"),
                .wrapper_sig = try allocator.dupe(u8, ""),
                .wrapper_call = try allocator.dupe(u8, ""),
                .raw_wrapper_sig = try allocator.dupe(u8, ""),
                .raw_wrapper_call = try allocator.dupe(u8, ""),
            });
        }
    }
    return result;
}

/// Collect required interface names from the InterfaceImpl table (for WinRT interfaces).
fn collectRequiredInterfaces(allocator: std.mem.Allocator, ctx: Context, type_row: u32) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8).empty;
    const t = ctx.table_info.getTable(.InterfaceImpl);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const impl = ctx.table_info.readInterfaceImpl(row) catch continue;
        if (impl.class != type_row) continue;
        const iface_tdor = coded.decodeTypeDefOrRef(impl.interface) catch continue;
        if (iface_tdor.table == .TypeSpec) {
            const ts = ctx.table_info.readTypeSpec(iface_tdor.row) catch continue;
            const sig = try ctx.heaps.getBlob(ts.signature);
            var sig_c = SigCursor{ .data = sig };
            const parsed = try decodeSigType(allocator, ctx, &sig_c, true);
            if (parsed) |p| allocator.free(p);
        }
        const iface_name = resolveTypeDefOrRefNameRaw(ctx, iface_tdor) catch continue;
        if (iface_name) |n| {
            // Strip backtick arity suffix (e.g., "IAsyncOperation`1" -> "IAsyncOperation")
            const backtick = std.mem.indexOfScalar(u8, n, '`');
            const clean = if (backtick) |bt| n[0..bt] else n;
            if (try resolveTypeDefOrRefFullNameAlloc(allocator, ctx, iface_tdor)) |iface_full| {
                defer allocator.free(iface_full);
                try ctx.registerDependency(allocator, iface_full);
            } else {
                try ctx.registerDependency(allocator, clean);
            }
            try result.append(allocator, try allocator.dupe(u8, clean));
        }
    }
    return result;
}

fn appendUniqueShortName(
    allocator: std.mem.Allocator,
    list: *std.ArrayList([]const u8),
    name: []const u8,
) !void {
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse 0;
    const short = if (dot > 0) name[dot + 1 ..] else name;
    for (list.items) |existing| {
        if (std.mem.eql(u8, existing, short)) return;
    }
    try list.append(allocator, try allocator.dupe(u8, short));
}

fn normalizeWinRtMethodName(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, name, "get_")) {
        return allocator.dupe(u8, name["get_".len..]);
    }
    if (std.mem.startsWith(u8, name, "put_")) {
        return std.fmt.allocPrint(allocator, "Set{s}", .{name["put_".len..]});
    }
    if (std.mem.startsWith(u8, name, "add_")) {
        return std.fmt.allocPrint(allocator, "Add{s}", .{name["add_".len..]});
    }
    if (std.mem.startsWith(u8, name, "remove_")) {
        return std.fmt.allocPrint(allocator, "Remove{s}", .{name["remove_".len..]});
    }
    return allocator.dupe(u8, name);
}

fn collectInterfaceMethodsByName(
    allocator: std.mem.Allocator,
    ctx: Context,
    iface_name: []const u8,
) !std.ArrayList(MethodMeta) {
    var result = std.ArrayList(MethodMeta).empty;
    const iface_row = findTypeDefRow(ctx, iface_name) catch return result;
    const range = try methodRange(ctx.table_info, iface_row);
    var mi = range.start;
    while (mi < range.end_exclusive) : (mi += 1) {
        const m = try ctx.table_info.readMethodDef(mi);
        const name = try ctx.heaps.getString(m.name);

        // Decode signature to trigger registerDependency for types used in this method
        const sig_blob = try ctx.heaps.getBlob(m.signature);
        var sig_c = SigCursor{ .data = sig_blob };
        _ = sig_c.readByte();
        const param_count = sig_c.readCompressedUInt() orelse 0;
        if (decodeSigType(allocator, ctx, &sig_c, true) catch null) |ret_type| {
            allocator.free(ret_type);
        }
        var p_idx: u32 = 0;
        while (p_idx < param_count) : (p_idx += 1) {
            _ = (sig_c.pos < sig_c.data.len and sig_c.data[sig_c.pos] == 0x10);
            if (decodeSigType(allocator, ctx, &sig_c, true) catch null) |p_type| {
                allocator.free(p_type);
            }
        }

        try result.append(allocator, .{
            .raw_name = try allocator.dupe(u8, name),
            .norm_name = try normalizeWinRtMethodName(allocator, name),
            .vtbl_sig = try allocator.dupe(u8, "VtblPlaceholder"),
            .wrapper_sig = try allocator.dupe(u8, ""),
            .wrapper_call = try allocator.dupe(u8, ""),
            .raw_wrapper_sig = try allocator.dupe(u8, ""),
            .raw_wrapper_call = try allocator.dupe(u8, ""),
        });
    }
    return result;
}

pub fn emitFunctions(
    allocator: std.mem.Allocator,
    writer: anytype,
    ctx: Context,
    type_row: u32,
) !void {
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name = try ctx.heaps.getString(type_def.type_name);

    const range = try methodRange(ctx.table_info, type_row);
    var i = range.start;
    
    // We need to group functions by their DLL (ImportScope)
    // For now, we'll emit them individually. 
    // In a real scenario, Win32 functions are in a class with no fields and only static methods.
    
    try writer.print("// Standalone functions for {s}\n", .{type_name});

    while (i < range.end_exclusive) : (i += 1) {
        const m = try ctx.table_info.readMethodDef(i);
        const name = try ctx.heaps.getString(m.name);
        
        // Check if static (0x0010)
        if ((m.flags & 0x0010) == 0) continue;

        try registerAssociatedEnumDependencies(allocator, ctx, i);

        const sig_blob = try ctx.heaps.getBlob(m.signature);
        var sig_c = SigCursor{ .data = sig_blob };
        _ = sig_c.readByte(); 
        const param_count = sig_c.readCompressedUInt() orelse 0;
        const ret_type_opt = try decodeSigType(allocator, ctx, &sig_c, false);
        const ret_type = ret_type_opt orelse "void";
        defer if (ret_type_opt != null) allocator.free(ret_type);

        // Collect actual parameter names
        var param_names_meta = try collectParamNames(allocator, ctx, i);
        defer param_names_meta.deinit(allocator);
        var all_param_names = std.ArrayList([]const u8).empty;
        defer {
            for (all_param_names.items) |n| allocator.free(n);
            all_param_names.deinit(allocator);
        }
        for (param_names_meta.items) |pn| {
            try all_param_names.append(allocator, try sanitizeIdentifier(allocator, pn));
        }
        while (all_param_names.items.len < param_count) {
            try all_param_names.append(allocator, try std.fmt.allocPrint(allocator, "p{d}", .{all_param_names.items.len}));
        }

        var params = std.ArrayList([]const u8).empty;
        defer {
            for (params.items) |p| allocator.free(p);
            params.deinit(allocator);
        }

        var p_idx: u32 = 0;
        while (p_idx < param_count) : (p_idx += 1) {
            const p_type_opt = try decodeSigType(allocator, ctx, &sig_c, false);
            try params.append(allocator, p_type_opt orelse try allocator.dupe(u8, "?*anyopaque"));
        }

        // Try to find DLL name from ImplMap
        const dll_name = try findDllName(ctx, i) orelse "UNKNOWN";

        try writer.print("pub extern \"{s}\" fn {s}(", .{ dll_name, name });
        for (params.items, 0..) |p, pi| {
            if (pi > 0) try writer.writeAll(", ");
            const p_name = all_param_names.items[pi];
            try writer.print("{s}: {s}", .{ p_name, p });
        }
        try writer.print(") callconv(.winapi) {s};\n", .{ret_type});
    }
    try writer.writeAll("\n");
}

fn findDllName(ctx: Context, method_row: u32) !?[]const u8 {
    const im_table = ctx.table_info.getTable(.ImplMap);
    var row: u32 = 1;
    while (row <= im_table.row_count) : (row += 1) {
        const im = try ctx.table_info.readImplMap(row);
        const member = try coded.decodeMemberForwarded(im.member_forwarded);
        if (member.table == .MethodDef and member.row == method_row) {
            const mr = try ctx.table_info.readModuleRef(im.import_scope);
            return try ctx.heaps.getString(mr.name);
        }
    }
    return null;
}

pub fn identifyTypeCategory(ctx: Context, type_row: u32) !TypeCategory {
    const td = try ctx.table_info.readTypeDef(type_row);
    if ((td.flags & 0x00000020) != 0) return .interface;
    if (td.extends == 0) return .other;
    const extends_tdor = try coded.decodeTypeDefOrRef(td.extends);
    const base = try resolveTypeDefOrRefNameRaw(ctx, extends_tdor) orelse return .other;
    if (std.mem.eql(u8, base, "Enum")) return .enum_type;
    if (std.mem.eql(u8, base, "ValueType")) return .struct_type;
    if (std.mem.eql(u8, base, "MulticastDelegate")) return .delegate;
    return .class;
}

fn decodeSigType(allocator: std.mem.Allocator, ctx: Context, c: *SigCursor, is_winrt_iface: bool) !?[]const u8 {
    const b = c.readByte() orelse return null;
    return switch (b) {
        0x01 => try allocator.dupe(u8, "void"),
        0x02 => try allocator.dupe(u8, "bool"),
        0x03 => try allocator.dupe(u8, "u16"),
        0x04 => try allocator.dupe(u8, "i8"),
        0x05 => try allocator.dupe(u8, "u8"),
        0x06 => try allocator.dupe(u8, "i16"),
        0x07 => try allocator.dupe(u8, "u16"),
        0x08 => try allocator.dupe(u8, "i32"),
        0x09 => try allocator.dupe(u8, "u32"),
        0x0a => try allocator.dupe(u8, "i64"),
        0x0b => try allocator.dupe(u8, "u64"),
        0x0c => try allocator.dupe(u8, "f32"),
        0x0d => try allocator.dupe(u8, "f64"),
        0x0e => try allocator.dupe(u8, "[*]const u16"),
        0x10 => blk: {
            const inner = try decodeSigType(allocator, ctx, c, is_winrt_iface) orelse break :blk null;
            defer allocator.free(inner);
            break :blk try std.fmt.allocPrint(allocator, "*{s}", .{inner});
        },
        0x0f => blk: {
            const inner = try decodeSigType(allocator, ctx, c, is_winrt_iface) orelse break :blk null;
            defer allocator.free(inner);
            break :blk try std.fmt.allocPrint(allocator, "*{s}", .{inner});
        },
        0x1f, 0x20 => blk: {
            _ = c.readCompressedUInt() orelse break :blk null;
            break :blk try decodeSigType(allocator, ctx, c, is_winrt_iface);
        },
        0x1c => try allocator.dupe(u8, "HSTRING"),
        0x11, 0x12 => blk: {
            const tdor_idx = c.readCompressedUInt() orelse break :blk null;
            const tdor = try coded.decodeTypeDefOrRef(tdor_idx);
            const full = try resolveTypeDefOrRefFullNameAlloc(allocator, ctx, tdor) orelse break :blk null;
            defer allocator.free(full);

            if (std.mem.eql(u8, full, "System.Guid") or std.mem.eql(u8, full, "Guid")) break :blk try allocator.dupe(u8, "GUID");
            if (std.mem.eql(u8, full, "System.IntPtr")) break :blk try allocator.dupe(u8, "isize");
            if (std.mem.eql(u8, full, "System.UIntPtr")) break :blk try allocator.dupe(u8, "usize");
            if (std.mem.endsWith(u8, full, ".HWND")) break :blk try allocator.dupe(u8, "HWND");
            if (std.mem.endsWith(u8, full, ".HANDLE")) break :blk try allocator.dupe(u8, "HANDLE");
            if (std.mem.endsWith(u8, full, ".BOOL")) break :blk try allocator.dupe(u8, "BOOL");
            if (std.mem.endsWith(u8, full, ".WPARAM")) break :blk try allocator.dupe(u8, "WPARAM");
            if (std.mem.endsWith(u8, full, ".LPARAM")) break :blk try allocator.dupe(u8, "LPARAM");
            if (std.mem.endsWith(u8, full, ".LPCWSTR")) break :blk try allocator.dupe(u8, "LPCWSTR");
            if (std.mem.endsWith(u8, full, ".LPWSTR")) break :blk try allocator.dupe(u8, "LPWSTR");
            if (std.mem.endsWith(u8, full, ".HRESULT")) break :blk try allocator.dupe(u8, "HRESULT");
            const dot = std.mem.lastIndexOfScalar(u8, full, '.');
            const short = if (dot) |d| full[d + 1 ..] else full;

            try ctx.registerDependency(allocator, full);

            var found_td: ?u32 = null;
            if (tdor.table == .TypeDef) {
                found_td = tdor.row;
            } else {
                found_td = resolveTypeDefOrRefToRow(ctx, tdor) catch null;
            }

            if (found_td) |td_row| {
                const cat = identifyTypeCategory(ctx, td_row) catch .other;
                if (cat == .enum_type) break :blk try allocator.dupe(u8, "i32");
                if (cat == .struct_type) break :blk try allocator.dupe(u8, short);
                if (cat == .interface) break :blk try allocator.dupe(u8, short);
            }

            // Well-known types or cross-WinMD types not in this TypeDef table
            if (std.mem.eql(u8, short, "IInspectable")) break :blk try allocator.dupe(u8, "IInspectable");
            if (std.mem.eql(u8, short, "IXamlType")) break :blk try allocator.dupe(u8, "IXamlType");
            if (std.mem.eql(u8, short, "EventRegistrationToken")) break :blk try allocator.dupe(u8, "EventRegistrationToken");
            if (isKnownStruct(short)) break :blk try allocator.dupe(u8, short);
            
            // For cross-WinMD references (e.g. Windows.Foundation), we often want the short name.
            // If it looks like an interface or is in a Windows namespace, use the short name.
            if (isInterfaceType(short) or std.mem.startsWith(u8, full, "Windows.")) {
                break :blk try allocator.dupe(u8, short);
            }

            break :blk try allocator.dupe(u8, "?*anyopaque");
        },
        0x1d => blk: {
            // SZARRAY: consume element type to keep cursor aligned
            const elem = try decodeSigType(allocator, ctx, c, is_winrt_iface);
            if (elem) |e| allocator.free(e);
            // WinRT array return: becomes [out] uint32, [out] T* at ABI level
            // Return a marker so the caller can detect it
            break :blk try allocator.dupe(u8, "SZARRAY");
        },
        0x15 => blk: {
            // GENERICINST: marker CLASS/VALUETYPE, TypeDefOrRef, count, type_args...
            _ = c.readByte() orelse break :blk try allocator.dupe(u8, "?*anyopaque"); // CLASS (0x12) or VALUETYPE (0x11)
            const tdor_idx = c.readCompressedUInt() orelse break :blk try allocator.dupe(u8, "?*anyopaque");
            const gen_arg_count = c.readCompressedUInt() orelse break :blk try allocator.dupe(u8, "?*anyopaque");
            // Consume all generic type arguments to keep cursor aligned
            var ga: u32 = 0;
            while (ga < gen_arg_count) : (ga += 1) {
                const arg = try decodeSigType(allocator, ctx, c, is_winrt_iface);
                if (arg) |a| allocator.free(a);
            }
            // Resolve the base type name
            const tdor = try coded.decodeTypeDefOrRef(tdor_idx);
            const full = try resolveTypeDefOrRefFullNameAlloc(allocator, ctx, tdor) orelse break :blk try allocator.dupe(u8, "?*anyopaque");
            defer allocator.free(full);

            try ctx.registerDependency(allocator, full);

            // Strip namespace
            const dot = std.mem.lastIndexOfScalar(u8, full, '.');
            const short_raw = if (dot) |d| full[d + 1 ..] else full;
            // Strip backtick arity suffix (e.g., "IVector`1" -> "IVector")
            const backtick = std.mem.indexOfScalar(u8, short_raw, '`');
            const short = if (backtick) |bt| short_raw[0..bt] else short_raw;
            // Check if it's a known generated or imported type
            if (std.mem.eql(u8, short, "IVector")) {
                break :blk try allocator.dupe(u8, "IVector");
            }
            break :blk try allocator.dupe(u8, "?*anyopaque");
        },
        else => try allocator.dupe(u8, "?*anyopaque"),
    };
}

pub fn emitClass(allocator: std.mem.Allocator, writer: anytype, ctx: Context, type_row: u32) !void {
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name = try ctx.heaps.getString(type_def.type_name);
    const ns = try ctx.heaps.getString(type_def.type_namespace);
    
    const full_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ns, type_name});
    defer allocator.free(full_name);

    // Resolve default interface
    const rctx = @import("resolver.zig").Context{ .table_info = ctx.table_info, .heaps = ctx.heaps };
    const default_iface_full_opt = @import("resolver.zig").resolveDefaultInterfaceNameForRuntimeClassAlloc(rctx, allocator, full_name) catch null;

    var ifaces_to_implement = std.ArrayList([]const u8).empty;
    defer {
        for (ifaces_to_implement.items) |item| allocator.free(item);
        ifaces_to_implement.deinit(allocator);
    }

    var default_iface_short: ?[]const u8 = null;
    if (default_iface_full_opt) |full| {
        defer allocator.free(full);
        try ctx.registerDependency(allocator, full);
        const dot = std.mem.lastIndexOfScalar(u8, full, '.') orelse 0;
        const short = if (dot > 0) full[dot + 1 ..] else full;
        default_iface_short = try allocator.dupe(u8, short);
        try appendUniqueShortName(allocator, &ifaces_to_implement, short);
    }
    defer if (default_iface_short) |short| allocator.free(short);

    // Also register factory/statics interfaces (any other implemented interfaces)
    const ii_table = ctx.table_info.getTable(.InterfaceImpl);
    var row: u32 = 1;
    while (row <= ii_table.row_count) : (row += 1) {
        const ii = try ctx.table_info.readInterfaceImpl(row);
        if (ii.class == type_row) {
            const iface_tdor = try coded.decodeTypeDefOrRef(ii.interface);
            if (iface_tdor.table == .TypeSpec) {
                const ts = ctx.table_info.readTypeSpec(iface_tdor.row) catch continue;
                const sig = try ctx.heaps.getBlob(ts.signature);
                var sig_c = SigCursor{ .data = sig };
                const parsed = try decodeSigType(allocator, ctx, &sig_c, true);
                if (parsed) |p| allocator.free(p);
            }
            const iface_name = resolveTypeDefOrRefNameRaw(ctx, iface_tdor) catch continue;
            if (iface_name) |n| {
                const clean = if (std.mem.indexOfScalar(u8, n, '`')) |bt| n[0..bt] else n;
                try ctx.registerDependency(allocator, clean);
                try appendUniqueShortName(allocator, &ifaces_to_implement, clean);
            }
        }
    }

    // Static and Activatable attributes
    const ca_table = ctx.table_info.getTable(.CustomAttribute);
    row = 1;
    while (row <= ca_table.row_count) : (row += 1) {
        const ca = try ctx.table_info.readCustomAttribute(row);
        const parent = try coded.decodeHasCustomAttribute(ca.parent);
        if (parent.table == .TypeDef and parent.row == type_row) {
            const ty = try coded.decodeCustomAttributeType(ca.ca_type);
            const tr = try ctx.table_info.readMemberRef(ty.row);
            const tr_parent = try coded.decodeMemberRefParent(tr.class);
            const tr_type = try ctx.table_info.readTypeRef(tr_parent.row);
            const attr_name = try ctx.heaps.getString(tr_type.type_name);
            if (std.mem.eql(u8, attr_name, "StaticAttribute") or std.mem.eql(u8, attr_name, "ActivatableAttribute")) {
                const blob = try ctx.heaps.getBlob(ca.value);
                // CustomAttribute blob: 0x01 0x00 followed by length-prefixed string if it takes a Type
                // A Type string is e.g. "Windows.Foundation.IDeferralFactory"
                if (blob.len > 3 and blob[0] == 0x01 and blob[1] == 0x00) {
                    var c = SigCursor{ .data = blob[2..] };
                    const len = c.readCompressedUInt() orelse 0;
                    if (len > 0 and c.pos + len <= c.data.len) {
                        const factory_type_full = c.data[c.pos .. c.pos + len];
                        try ctx.registerDependency(allocator, factory_type_full);
                        try appendUniqueShortName(allocator, &ifaces_to_implement, factory_type_full);
                    }
                }
            }
        }
    }

    var iface_head: usize = 0;
    while (iface_head < ifaces_to_implement.items.len) : (iface_head += 1) {
        const iface = ifaces_to_implement.items[iface_head];
        const iface_row = findTypeDefRow(ctx, iface) catch continue;
        var required = collectRequiredInterfaces(allocator, ctx, iface_row) catch continue;
        defer {
            for (required.items) |item| allocator.free(item);
            required.deinit(allocator);
        }
        for (required.items) |req| {
            try appendUniqueShortName(allocator, &ifaces_to_implement, req);
        }
    }

    try writer.print("pub const {s} = extern struct {{\n", .{type_name});
    if (default_iface_short) |short| {
        try writer.print("    pub const IID = {s}.IID;\n", .{short});
        try writer.writeAll("    lpVtbl: *const VTable,\n");
        try writer.print("    pub const VTable = {s}.VTable;\n", .{short});
    }
    
    for (ifaces_to_implement.items) |iface| {
        if (default_iface_short) |short| {
            if (std.mem.eql(u8, iface, short)) continue;
        }
        try writer.print("    pub const Requires_{s} = true; // requires {s}\n", .{ iface, iface });
    }

    var emitted_methods = std.StringHashMap(void).init(allocator);
    defer {
        var it = emitted_methods.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        emitted_methods.deinit();
    }

    for (ifaces_to_implement.items) |iface| {
        var methods = collectInterfaceMethodsByName(allocator, ctx, iface) catch continue;
        defer {
            for (methods.items) |m| {
                allocator.free(m.raw_name);
                allocator.free(m.norm_name);
                allocator.free(m.vtbl_sig);
                allocator.free(m.wrapper_sig);
                allocator.free(m.wrapper_call);
                allocator.free(m.raw_wrapper_sig);
                allocator.free(m.raw_wrapper_call);
            }
            methods.deinit(allocator);
        }
        for (methods.items) |m| {
            if (!emitted_methods.contains(m.norm_name)) {
                try writer.print("    pub fn {s}() void {{}}\n", .{m.norm_name});
                try emitted_methods.put(try allocator.dupe(u8, m.norm_name), {});
            }
            if (!std.mem.eql(u8, m.norm_name, m.raw_name)) {
                if (!emitted_methods.contains(m.raw_name)) {
                    try writer.print("    pub fn {s}() void {{}}\n", .{m.raw_name});
                    try emitted_methods.put(try allocator.dupe(u8, m.raw_name), {});
                }
            }
        }
    }

    try writer.writeAll("};\n\n");
}

pub fn emitDelegate(allocator: std.mem.Allocator, writer: anytype, ctx: Context, type_row: u32) !void {
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name = try ctx.heaps.getString(type_def.type_name);
    const ns = try ctx.heaps.getString(type_def.type_namespace);
    const is_winrt = !std.mem.startsWith(u8, ns, "Windows.Win32.") and !std.mem.startsWith(u8, ns, "Windows.Wdk.");

    if (is_winrt) {
        // WinRT delegates are COM interfaces
        try emitInterface(allocator, writer, ctx, "", type_name);
        return;
    }

    // Win32 Delegate (function pointer type alias)
    const method_range_info = try methodRange(ctx.table_info, type_row);
    var i = method_range_info.start;
    var invoke_row: ?u32 = null;
    while (i < method_range_info.end_exclusive) : (i += 1) {
        const m = try ctx.table_info.readMethodDef(i);
        const name = try ctx.heaps.getString(m.name);
        if (std.mem.eql(u8, name, "Invoke")) {
            invoke_row = i;
            break;
        }
    }
    
    if (invoke_row) |row| {
        const m = try ctx.table_info.readMethodDef(row);
        const sig_blob = try ctx.heaps.getBlob(m.signature);
        var sig_c = SigCursor{ .data = sig_blob };
        _ = sig_c.readByte();
        const param_count = sig_c.readCompressedUInt() orelse 0;
        const ret_type_opt = try decodeSigType(allocator, ctx, &sig_c, false);
        const ret_type_raw = ret_type_opt orelse "void";
        defer if (ret_type_opt != null) allocator.free(ret_type_raw);

        var param_names_meta = try collectParamNames(allocator, ctx, row);
        defer param_names_meta.deinit(allocator);

        var params = std.ArrayList(u8).empty;
        defer params.deinit(allocator);

        var p_idx: u32 = 0;
        while (p_idx < param_count) : (p_idx += 1) {
            _ = (sig_c.pos < sig_c.data.len and sig_c.data[sig_c.pos] == 0x10);
            const p_type_opt = try decodeSigType(allocator, ctx, &sig_c, false);
            const p_type_raw = p_type_opt orelse "?*anyopaque";
            defer if (p_type_opt != null) allocator.free(p_type_raw);
            
            const p_type = if (std.mem.eql(u8, p_type_raw, "anyopaque"))
                "?*anyopaque"
            else if (isBuiltinType(p_type_raw))
                p_type_raw
            else if (std.mem.startsWith(u8, p_type_raw, "*") or std.mem.startsWith(u8, p_type_raw, "?"))
                p_type_raw
            else if (isKnownStruct(p_type_raw) or std.mem.eql(u8, p_type_raw, "EventRegistrationToken"))
                p_type_raw
            else
                "?*anyopaque";

            if (p_idx > 0) try params.appendSlice(allocator, ", ");
            
            const p_name = if (p_idx < param_names_meta.items.len) param_names_meta.items[p_idx] else "p";
            const sanitized = try sanitizeIdentifier(allocator, p_name);
            defer allocator.free(sanitized);

            try params.writer(allocator).print("{s}: {s}", .{sanitized, p_type});
        }
        
        try writer.print("pub const {s} = ?*const fn ({s}) callconv(.winapi) {s};\n\n", .{type_name, params.items, ret_type_raw});
    }
}
