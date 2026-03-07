const std = @import("std");
const win_zig_metadata = @import("win_zig_metadata");
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const coded = win_zig_metadata.coded_index;
const resolver = @import("resolver.zig");

pub const Context = struct {
    table_info: tables.Info,
    heaps: streams.Heaps,
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

pub const TypeCategory = enum { interface, enum_type, struct_type, class, other };

pub fn writePrologue(writer: anytype) !void {
    try writer.writeAll(
        \\//! WinUI 3 COM interface definitions for Zig.
        \\//! GENERATED CODE - DO NOT EDIT.
        \\const std = @import("std");
        \\const GUID = std.os.windows.GUID;
        \\const HRESULT = std.os.windows.HRESULT;
        \\const HSTRING = ?*anyopaque;
        \\const EventRegistrationToken = i64;
        \\
        \\pub const VtblPlaceholder = ?*const anyopaque;
        \\
        \\pub const IID_RoutedEventHandler = GUID{ .Data1 = 0xaf8dae19, .Data2 = 0x0794, .Data3 = 0x5695, .Data4 = .{ 0x96, 0x8a, 0x07, 0x33, 0x3f, 0x92, 0x32, 0xe0 } };
        \\pub const IID_SizeChangedEventHandler = GUID{ .Data1 = 0x8d7b1a58, .Data2 = 0x14c6, .Data3 = 0x51c9, .Data4 = .{ 0x89, 0x2c, 0x9f, 0xcc, 0xe3, 0x68, 0xe7, 0x7d } };
        \\pub const IID_TypedEventHandler_TabCloseRequested = GUID{ .Data1 = 0x7093974b, .Data2 = 0x0900, .Data3 = 0x52ae, .Data4 = .{ 0xaf, 0xd8, 0x70, 0xe5, 0x62, 0x3f, 0x45, 0x95 } };
        \\pub const IID_TypedEventHandler_AddTabButtonClick = GUID{ .Data1 = 0x13df6907, .Data2 = 0xbbb4, .Data3 = 0x5f16, .Data4 = .{ 0xbe, 0xac, 0x29, 0x38, 0xc1, 0x5e, 0x1d, 0x85 } };
        \\pub const IID_SelectionChangedEventHandler = GUID{ .Data1 = 0xa232390d, .Data2 = 0x0e34, .Data3 = 0x595e, .Data4 = .{ 0x89, 0x31, 0xfa, 0x92, 0x8a, 0x99, 0x09, 0xf4 } };
        \\pub const IID_TypedEventHandler_WindowClosed = GUID{ .Data1 = 0x2a954d28, .Data2 = 0x7f8b, .Data3 = 0x5479, .Data4 = .{ 0x8c, 0xe9, 0x90, 0x04, 0x24, 0xa0, 0x40, 0x9f } };
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
        \\    pub const IID = GUID{ .Data1 = 0x00000000, .Data2 = 0x0000, .Data3 = 0x0000, .Data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
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
        \\    pub const IID = GUID{ .Data1 = 0xAFDBDF05, .Data2 = 0x2D12, .Data3 = 0x4D31, .Data4 = .{ 0x84, 0x1F, 0x72, 0x71, 0x50, 0x51, 0x46, 0x46 } };
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
    const type_row = findTypeDefRow(ctx, interface_name) catch return;
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name = try ctx.heaps.getString(type_def.type_name);

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
    defer seen_method_names.deinit();
    
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
        const ret_type_raw = try decodeSigType(allocator, ctx, &sig_c, true) orelse "void";
        defer if (!isBuiltinType(ret_type_raw) and !std.mem.eql(u8, ret_type_raw, "void") and !std.mem.eql(u8, ret_type_raw, "SZARRAY")) allocator.free(ret_type_raw);


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
            const p_type_raw = try decodeSigType(allocator, ctx, &sig_c, true) orelse "?*anyopaque";
            if (is_byref) try byref_indices.append(allocator, p_idx);
            defer if (!isBuiltinType(p_type_raw)) allocator.free(p_type_raw);

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
                const p_name = try std.fmt.allocPrint(allocator, "p{d}", .{p_idx});
                defer allocator.free(p_name);
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
        if (std.mem.eql(u8, ret_type_raw, "SZARRAY")) {
            // WinRT array return: becomes [out] uint32 count, [out] T* definitions at ABI
            const synth_base: u32 = @intCast(param_vtbl_types.items.len);
            try vtbl_params.appendSlice(allocator, ", *u32");
            try param_vtbl_types.append(allocator, try allocator.dupe(u8, "*u32"));
            try param_logical_types.append(allocator, try allocator.dupe(u8, "*u32"));
            try byref_indices.append(allocator, synth_base);
            try vtbl_params.appendSlice(allocator, ", *?*anyopaque");
            try param_vtbl_types.append(allocator, try allocator.dupe(u8, "*?*anyopaque"));
            try param_logical_types.append(allocator, try allocator.dupe(u8, "*?*anyopaque"));
            try byref_indices.append(allocator, synth_base + 1);
        } else if (!std.mem.eql(u8, ret_type_raw, "void")) {
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
        }

        const prev_count = seen_method_names.get(name) orelse 0;
        var unique = if (prev_count > 0) try std.fmt.allocPrint(allocator, "{s}_{d}", .{ name, prev_count }) else try allocator.dupe(u8, name);
        // Keep IXamlMetadataProvider overload naming compatible with existing call-sites.
        if (std.mem.eql(u8, type_name, "IXamlMetadataProvider") and std.mem.eql(u8, name, "GetXamlType") and prev_count > 0) {
            allocator.free(unique);
            unique = try allocator.dupe(u8, "GetXamlType_2");
        }
        try seen_method_names.put(name, prev_count + 1);
        
        var norm_name = if (std.mem.indexOfScalar(u8, name, '_')) |underscore_idx| blk: {
            const prefix = name[0..underscore_idx];
            const suffix = name[underscore_idx+1..];
            break :blk try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, suffix });
        } else try allocator.dupe(u8, name);
        if (norm_name.len > 0) norm_name[0] = std.ascii.toLower(norm_name[0]);

        const norm_prev = seen_norm_names.get(norm_name) orelse 0;
        if (norm_prev > 0) {
            const new_norm = try std.fmt.allocPrint(allocator, "{s}_{d}", .{ norm_name, norm_prev });
            allocator.free(norm_name);
            norm_name = new_norm;
        }
        try seen_norm_names.put(try allocator.dupe(u8, norm_name), norm_prev + 1);

        const vtbl_sig = try std.fmt.allocPrint(allocator, "*const fn ({s}) callconv(.winapi) HRESULT", .{vtbl_params.items});
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
                        if (bi == pi) { is_out = true; break; }
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
                } else if (byref_count == 2 and std.mem.eql(u8, name, "GetXmlnsDefinitions")) {
                    // GetXmlnsDefinitions: 2 out-params → named struct return
                    wrapper_sig = try std.fmt.allocPrint(
                        allocator,
                        "pub fn {s}(self: *@This()) !struct {{ count: u32, definitions: ?*anyopaque }}",
                        .{norm_name},
                    );
                    wrapper_call = try std.fmt.allocPrint(
                        allocator,
                        "var count: u32 = 0; var definitions: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &count, &definitions)); return .{{ .count = count, .definitions = definitions }};",
                        .{unique},
                    );
                    raw_wrapper_sig = try std.fmt.allocPrint(
                        allocator,
                        "pub fn {s}(self: *@This()) !struct {{ count: u32, definitions: ?*anyopaque }}",
                        .{unique},
                    );
                    raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
                } else {
                    // Multiple out-params: return a struct (fallback to void for now)
                    wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !void", .{ norm_name, wrapper_params.items });
                    wrapper_call = try std.fmt.allocPrint(allocator, "try hrCheck(self.lpVtbl.{s}({s}));", .{ unique, call_args.items });
                    raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !void", .{ unique, wrapper_params.items });
                    const fwd_args = if (wrapper_fwd_args.items.len > 2) wrapper_fwd_args.items[2..] else "";
                    raw_wrapper_call = try std.fmt.allocPrint(allocator, "try self.{s}({s});", .{ norm_name, fwd_args });
                }
            } else {
                wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !void", .{ norm_name, wrapper_params.items });
                wrapper_call = try std.fmt.allocPrint(allocator, "try hrCheck(self.lpVtbl.{s}({s}));", .{ unique, call_args.items });
                raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !void", .{ unique, wrapper_params.items });
                const fwd_args = if (wrapper_fwd_args.items.len > 2) wrapper_fwd_args.items[2..] else "";
                raw_wrapper_call = try std.fmt.allocPrint(allocator, "try self.{s}({s});", .{ norm_name, fwd_args });
            }
        }

        try methods.append(allocator, .{ .raw_name = try allocator.dupe(u8, unique), .norm_name = norm_name, .vtbl_sig = vtbl_sig, .wrapper_sig = wrapper_sig, .wrapper_call = wrapper_call, .raw_wrapper_sig = raw_wrapper_sig, .raw_wrapper_call = raw_wrapper_call });
        allocator.free(unique);
    }

    try writer.print("pub const {s} = extern struct {{\n", .{type_name});
    try writer.print("    pub const IID = GUID{{ .Data1 = 0x{x:0>8}, .Data2 = 0x{x:0>4}, .Data3 = 0x{x:0>4}, .Data4 = .{{ 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2}, 0x{x:0>2} }} }};\n", .{ std.mem.readInt(u32, guid[0..4], .little), std.mem.readInt(u16, guid[4..6], .little), std.mem.readInt(u16, guid[6..8], .little), guid[8], guid[9], guid[10], guid[11], guid[12], guid[13], guid[14], guid[15] });
    try writer.writeAll("    lpVtbl: *const VTable,\n    pub const VTable = extern struct {\n        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,\n        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,\n        Release: *const fn (*anyopaque) callconv(.winapi) u32,\n        GetIids: VtblPlaceholder,\n        GetRuntimeClassName: VtblPlaceholder,\n        GetTrustLevel: VtblPlaceholder,\n");
    for (methods.items) |m| try writer.print("        {s}: {s},\n", .{ m.raw_name, m.vtbl_sig });
    try writer.writeAll("    };\n");
    if (std.mem.eql(u8, type_name, "ISolidColorBrush")) {
        try writer.writeAll("    pub const Color = extern struct { a: u8, r: u8, g: u8, b: u8 };\n");
    }
    try writer.writeAll("    pub fn release(self: *@This()) void { comRelease(self); }\n    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }\n");
    for (methods.items) |m| {
        try writer.print("    {s} {{ {s} }}\n", .{ m.wrapper_sig, m.wrapper_call });
        if (!std.mem.eql(u8, m.norm_name, m.raw_name)) try writer.print("    {s} {{ {s} }}\n", .{ m.raw_wrapper_sig, m.raw_wrapper_call });
    }
    try writer.writeAll("};\n\n");
}

pub fn emitEnum(allocator: std.mem.Allocator, writer: anytype, ctx: Context, type_row: u32) !void {
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name = try ctx.heaps.getString(type_def.type_name);
    try writer.print("pub const {s} = enum(i32) {{\n", .{type_name});
    const range = try fieldRange(ctx.table_info, type_row);
    var i = range.start;
    while (i < range.end_exclusive) : (i += 1) {
        const f = try ctx.table_info.readField(i);
        const name = try ctx.heaps.getString(f.name);
        if (std.mem.eql(u8, name, "value__")) continue;
        const c_table = ctx.table_info.getTable(.Constant);
        var ci: u32 = 1;
        var val: i32 = 0;
        while (ci <= c_table.row_count) : (ci += 1) {
            const c = try ctx.table_info.readConstant(ci);
            const parent = try coded.decodeHasConstant(c.parent);
            if (parent.table == .Field and parent.row == i) {
                const blob = try ctx.heaps.getBlob(c.value);
                if (blob.len >= 4) val = std.mem.readInt(i32, blob[0..4], .little);
                break;
            }
        }
        const cleaned = try allocator.dupe(u8, name);
        defer allocator.free(cleaned);
        for (cleaned) |*ch| if (ch.* >= 'A' and ch.* <= 'Z') { ch.* = ch.* + ('a' - 'A'); };
        try writer.print("    {s} = {d},\n", .{ cleaned, val });
    }
    try writer.writeAll("};\n\n");
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
        const ty = try decodeSigType(allocator, ctx, &sig_c, false) orelse "?*anyopaque";
        defer if (!isBuiltinType(ty)) allocator.free(ty);
        try writer.print("    {s}: {s},\n", .{ name, ty });
    }
    try writer.writeAll("};\n\n");
}

fn isKnownStruct(name: []const u8) bool {
    const structs = [_][]const u8{ "GridLength", "Color" };
    for (structs) |s| if (std.mem.eql(u8, name, s)) return true;
    return false;
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
    const builtins = [_][]const u8{ "void", "bool", "anyopaque", "?*anyopaque", "GUID", "HSTRING", "isize", "usize", "u8", "i8", "u16", "i16", "u32", "i32", "u64", "i64", "f32", "f64" };
    for (builtins) |b| if (std.mem.eql(u8, t, b)) return true;
    return false;
}

pub fn findTypeDefRow(ctx: Context, interface_name: []const u8) !u32 {
    const dot_index = std.mem.lastIndexOfScalar(u8, interface_name, '.');
    const want_ns = if (dot_index) |idx| interface_name[0..idx] else null;
    const want_name = if (dot_index) |idx| interface_name[idx + 1 ..] else interface_name;
    const t = ctx.table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try ctx.table_info.readTypeDef(row);
        const name = try ctx.heaps.getString(td.type_name);
        const ns = try ctx.heaps.getString(td.type_namespace);
        if (std.mem.eql(u8, name, want_name)) if (want_ns == null or std.mem.eql(u8, ns, want_ns.?)) return row;
    }
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
        else => null,
    };
}

pub fn identifyTypeCategory(ctx: Context, type_row: u32) !TypeCategory {
    const td = try ctx.table_info.readTypeDef(type_row);
    if ((td.flags & 0x00000020) != 0) return .interface;
    if (td.extends == 0) return .other;
    const extends_tdor = try coded.decodeTypeDefOrRef(td.extends);
    const base = try resolveTypeDefOrRefNameRaw(ctx, extends_tdor) orelse return .other;
    if (std.mem.eql(u8, base, "Enum")) return .enum_type;
    if (std.mem.eql(u8, base, "ValueType")) return .struct_type;
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
            defer if (!isBuiltinType(inner)) allocator.free(inner);
            break :blk try std.fmt.allocPrint(allocator, "*{s}", .{inner});
        },
        0x0f => blk: {
            const inner = try decodeSigType(allocator, ctx, c, is_winrt_iface) orelse break :blk null;
            defer if (!isBuiltinType(inner)) allocator.free(inner);
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
            const full = try resolveTypeDefOrRefNameRaw(ctx, tdor) orelse break :blk null;
            if (std.mem.eql(u8, full, "System.Guid")) break :blk try allocator.dupe(u8, "GUID");
            if (std.mem.eql(u8, full, "System.IntPtr")) break :blk try allocator.dupe(u8, "isize");
            if (std.mem.eql(u8, full, "System.UIntPtr")) break :blk try allocator.dupe(u8, "usize");
            const dot = std.mem.lastIndexOfScalar(u8, full, '.');
            const short = if (dot) |d| full[d+1..] else full;
            var found_td: ?u32 = null;
            if (tdor.table == .TypeDef) {
                found_td = tdor.row;
            } else {
                const t = ctx.table_info.getTable(.TypeDef);
                var row: u32 = 1;
                while (row <= t.row_count) : (row += 1) {
                    const td = try ctx.table_info.readTypeDef(row);
                    const name_td = try ctx.heaps.getString(td.type_name);
                    if (std.mem.eql(u8, name_td, short)) { found_td = row; break; }
                }
            }
            if (found_td) |td_row| {
                const cat = identifyTypeCategory(ctx, td_row) catch .other;
                if (cat == .enum_type) break :blk try allocator.dupe(u8, "i32");
                if (cat == .struct_type) break :blk try allocator.dupe(u8, short);
                if (cat == .interface) break :blk try allocator.dupe(u8, short);
            }
            // Well-known types without TypeDef in this winmd
            if (std.mem.eql(u8, short, "IInspectable")) break :blk try allocator.dupe(u8, "IInspectable");
            if (std.mem.eql(u8, short, "IXamlType")) break :blk try allocator.dupe(u8, "IXamlType");
            if (std.mem.eql(u8, short, "EventRegistrationToken")) break :blk try allocator.dupe(u8, "EventRegistrationToken");
            if (isKnownStruct(short)) break :blk try allocator.dupe(u8, short);
            break :blk try allocator.dupe(u8, "?*anyopaque");
        },
        0x1d => blk: {
            // SZARRAY: consume element type to keep cursor aligned
            const elem = try decodeSigType(allocator, ctx, c, is_winrt_iface);
            if (elem) |e| if (!isBuiltinType(e)) allocator.free(e);
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
                if (arg) |a| if (!isBuiltinType(a)) allocator.free(a);
            }
            // Resolve the base type name
            const tdor = try coded.decodeTypeDefOrRef(tdor_idx);
            const full = try resolveTypeDefOrRefNameRaw(ctx, tdor) orelse break :blk try allocator.dupe(u8, "?*anyopaque");
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
