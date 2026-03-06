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
        \\pub const IVector = extern struct {
        \\    // Windows.Foundation.Collections.IVector<IInspectable>
        \\    pub const IID = GUID{ .Data1 = 0xb32bdca4, .Data2 = 0x5e52, .Data3 = 0x5b27, .Data4 = .{ 0xbc, 0x5d, 0xd6, 0x6a, 0x1a, 0x26, 0x8c, 0x2a } };
        \\    lpVtbl: *const VTable,
        \\    pub const VTable = extern struct {
        \\        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        \\        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        \\        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        \\        GetIids: VtblPlaceholder,
        \\        GetRuntimeClassName: VtblPlaceholder,
        \\        GetTrustLevel: VtblPlaceholder,
        \\        GetAt: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.winapi) HRESULT,
        \\        get_Size: *const fn (*anyopaque, *u32) callconv(.winapi) HRESULT,
        \\        GetView: VtblPlaceholder,
        \\        IndexOf: *const fn (*anyopaque, ?*anyopaque, *u32, *i32) callconv(.winapi) HRESULT,
        \\        SetAt: VtblPlaceholder,
        \\        InsertAt: *const fn (*anyopaque, u32, ?*anyopaque) callconv(.winapi) HRESULT,
        \\        RemoveAt: *const fn (*anyopaque, u32) callconv(.winapi) HRESULT,
        \\        Append: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        \\        RemoveAtEnd: VtblPlaceholder,
        \\        Clear: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        \\        GetMany: VtblPlaceholder,
        \\        ReplaceAll: VtblPlaceholder,
        \\    };
        \\    pub fn release(self: *@This()) void { comRelease(self); }
        \\    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
        \\    pub fn getSize(self: *@This()) !u32 { var out: u32 = 0; try hrCheck(self.lpVtbl.get_Size(self, &out)); return out; }
        \\    pub fn getAt(self: *@This(), i: u32) !*anyopaque { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.GetAt(self, i, &out)); return out orelse error.WinRTFailed; }
        \\    pub fn insertAt(self: *@This(), i: u32, item: ?*anyopaque) !void { try hrCheck(self.lpVtbl.InsertAt(self, i, item)); }
        \\    pub fn append(self: *@This(), item: ?*anyopaque) !void { try hrCheck(self.lpVtbl.Append(self, item)); }
        \\    pub fn removeAt(self: *@This(), i: u32) !void { try hrCheck(self.lpVtbl.RemoveAt(self, i)); }
        \\    pub fn clear(self: *@This()) !void { try hrCheck(self.lpVtbl.Clear(self)); }
        \\    pub fn indexOf(self: *@This(), item: ?*anyopaque) !?u32 { var idx: u32 = 0; var found: i32 = 0; try hrCheck(self.lpVtbl.IndexOf(self, item, &idx, &found)); if (found != 0) return idx; return null; }
        \\};
        \\
        \\pub const GridUnitType = struct {
        \\    pub const Pixel: i32 = 0;
        \\    pub const Auto: i32 = 1;
        \\    pub const Star: i32 = 2;
        \\};
        \\pub const GridLength = extern struct {
        \\    Value: f64,
        \\    GridUnitType: i32,
        \\};
        \\
        \\pub const IPropertyValue = extern struct {
        \\    pub const IID = GUID{ .Data1 = 0x4bd682dd, .Data2 = 0x7554, .Data3 = 0x40e9, .Data4 = .{ 0x9a, 0x9b, 0x82, 0x65, 0x4e, 0xde, 0x7e, 0x62 } };
        \\    lpVtbl: *const VTable,
        \\    pub const VTable = extern struct {
        \\        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        \\        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        \\        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        \\        GetIids: VtblPlaceholder,
        \\        GetRuntimeClassName: VtblPlaceholder,
        \\        GetTrustLevel: VtblPlaceholder,
        \\        get_Type: VtblPlaceholder,
        \\        get_IsNumericScalar: VtblPlaceholder,
        \\        GetUInt8: VtblPlaceholder,
        \\        GetInt16: VtblPlaceholder,
        \\        GetUInt16: VtblPlaceholder,
        \\        GetInt32: VtblPlaceholder,
        \\        GetUInt32: VtblPlaceholder,
        \\        GetInt64: VtblPlaceholder,
        \\        GetUInt64: VtblPlaceholder,
        \\        GetSingle: VtblPlaceholder,
        \\        GetDouble: VtblPlaceholder,
        \\        GetChar16: VtblPlaceholder,
        \\        GetBoolean: VtblPlaceholder,
        \\        GetString: *const fn (*anyopaque, *HSTRING) callconv(.winapi) HRESULT,
        \\    };
        \\    pub fn release(self: *@This()) void { comRelease(self); }
        \\    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
        \\    pub fn getString(self: *@This()) !HSTRING { var out: HSTRING = null; try hrCheck(self.lpVtbl.GetString(self, &out)); return out; }
        \\};
        \\
        \\pub const IPropertyValueStatics = extern struct {
        \\    pub const IID = GUID{ .Data1 = 0x629bdbc8, .Data2 = 0xd932, .Data3 = 0x4ff4, .Data4 = .{ 0x96, 0xb9, 0x8d, 0x96, 0xc5, 0xc1, 0xe8, 0x58 } };
        \\    lpVtbl: *const VTable,
        \\    pub const VTable = extern struct {
        \\        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        \\        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        \\        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        \\        GetIids: VtblPlaceholder,
        \\        GetRuntimeClassName: VtblPlaceholder,
        \\        GetTrustLevel: VtblPlaceholder,
        \\        CreateEmpty: VtblPlaceholder,
        \\        CreateUInt8: VtblPlaceholder,
        \\        CreateInt16: VtblPlaceholder,
        \\        CreateUInt16: VtblPlaceholder,
        \\        CreateInt32: VtblPlaceholder,
        \\        CreateUInt32: VtblPlaceholder,
        \\        CreateInt64: VtblPlaceholder,
        \\        CreateUInt64: VtblPlaceholder,
        \\        CreateSingle: VtblPlaceholder,
        \\        CreateDouble: VtblPlaceholder,
        \\        CreateChar16: VtblPlaceholder,
        \\        CreateBoolean: VtblPlaceholder,
        \\        CreateString: *const fn (*anyopaque, HSTRING, *?*anyopaque) callconv(.winapi) HRESULT,
        \\    };
        \\    pub fn release(self: *@This()) void { comRelease(self); }
        \\    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
        \\    pub fn createString(self: *@This(), s: HSTRING) !*IInspectable { var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.CreateString(self, s, &out)); return @ptrCast(@alignCast(out.?)); }
        \\};
        \\
        \\pub const ISwapChainPanelNative = extern struct {
        \\    pub const IID = GUID{ .Data1 = 0x63aad0b8, .Data2 = 0x7c24, .Data3 = 0x40ff, .Data4 = .{ 0x85, 0xa8, 0x64, 0x0d, 0x94, 0x4c, 0xc3, 0x25 } };
        \\    lpVtbl: *const VTable,
        \\    pub const VTable = extern struct {
        \\        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        \\        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        \\        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        \\        SetSwapChain: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        \\    };
        \\    pub fn release(self: *ISwapChainPanelNative) void { comRelease(self); }
        \\    pub fn queryInterface(self: *ISwapChainPanelNative, comptime T: type) !*T { return comQueryInterface(self, T); }
        \\    pub fn setSwapChain(self: *@This(), sc: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetSwapChain(self, sc)); }
        \\};
        \\
        \\pub const IWindowNative = extern struct {
        \\    pub const IID = GUID{ .Data1 = 0xeecdbf0e, .Data2 = 0xbae9, .Data3 = 0x4cb6, .Data4 = .{ 0xa6, 0x8e, 0x95, 0x98, 0xe1, 0xcb, 0x57, 0xbb } };
        \\    lpVtbl: *const VTable,
        \\    pub const VTable = extern struct {
        \\        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        \\        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        \\        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        \\        getWindowHandle: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        \\    };
        \\    pub fn release(self: *@This()) void { comRelease(self); }
        \\    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
        \\    pub fn getWindowHandle(self: *@This()) !*anyopaque { var h: ?*anyopaque = null; try hrCheck(self.lpVtbl.getWindowHandle(self, &h)); return h orelse error.WinRTFailed; }
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
        _ = try decodeSigType(allocator, ctx, &sig_c, true);

        var vtbl_params = std.ArrayList(u8).empty;
        defer vtbl_params.deinit(allocator);
        try vtbl_params.appendSlice(allocator, "*anyopaque");

        var wrapper_params = std.ArrayList(u8).empty;
        defer wrapper_params.deinit(allocator);

        var call_args = std.ArrayList(u8).empty;
        defer call_args.deinit(allocator);
        try call_args.appendSlice(allocator, "self");

        var wrapper_ret: []const u8 = try allocator.dupe(u8, "void");
        defer allocator.free(wrapper_ret);

        const is_getter = std.mem.startsWith(u8, name, "get_") and param_count == 1;

        var p_idx: u32 = 0;
        while (p_idx < param_count) : (p_idx += 1) {
            const p_type_raw = try decodeSigType(allocator, ctx, &sig_c, true) orelse "?*anyopaque";
            defer if (!isBuiltinType(p_type_raw)) allocator.free(p_type_raw);

            var p_type_vtbl = if (std.mem.eql(u8, p_type_raw, "anyopaque"))
                try allocator.dupe(u8, "?*anyopaque")
            else if (isBuiltinType(p_type_raw) or std.mem.startsWith(u8, p_type_raw, "*") or std.mem.startsWith(u8, p_type_raw, "?"))
                try allocator.dupe(u8, p_type_raw)
            else
                // Unknown/complex projected types must remain pointer-like at ABI edge.
                try allocator.dupe(u8, "?*anyopaque");
            
            // CONCESSION: Ghostty expects pointers for many things it passes as i32/usize
            if (std.mem.eql(u8, name, "Start") or std.mem.eql(u8, name, "CreateInstance") or std.mem.eql(u8, name, "put_Content") or std.mem.eql(u8, name, "put_Title")) {
                if (p_idx == 0) { // First arg usually the object or string
                    allocator.free(p_type_vtbl);
                    p_type_vtbl = try allocator.dupe(u8, "?*anyopaque");
                }
            }
            if (std.mem.containsAtLeast(u8, name, 1, "add_") or std.mem.containsAtLeast(u8, name, 1, "remove_")) {
                if (std.mem.eql(u8, p_type_vtbl, "i32")) {
                    allocator.free(p_type_vtbl);
                    p_type_vtbl = try allocator.dupe(u8, "i64");
                }
            }
            defer allocator.free(p_type_vtbl);

            try vtbl_params.appendSlice(allocator, ", ");
            try vtbl_params.appendSlice(allocator, p_type_vtbl);

            if (is_getter) {
                allocator.free(wrapper_ret);
                if (std.mem.startsWith(u8, p_type_vtbl, "*")) {
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
                
                // CONCESSION: In wrappers, accept anything for pointers to match Ghostty's lax casting
                if (std.mem.startsWith(u8, p_type_vtbl, "?*") or std.mem.eql(u8, p_type_vtbl, "HSTRING")) {
                    try wrapper_params.appendSlice(allocator, "anytype");
                } else {
                    try wrapper_params.appendSlice(allocator, p_type_vtbl);
                }

                try call_args.appendSlice(allocator, ", ");
                if (std.mem.startsWith(u8, p_type_vtbl, "?*") or std.mem.eql(u8, p_type_vtbl, "HSTRING")) {
                    try call_args.appendSlice(allocator, "@ptrCast(");
                    try call_args.appendSlice(allocator, p_name);
                    try call_args.appendSlice(allocator, ")");
                } else {
                    try call_args.appendSlice(allocator, p_name);
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

        var vtbl_sig = try std.fmt.allocPrint(allocator, "*const fn ({s}) callconv(.winapi) HRESULT", .{vtbl_params.items});
        var wrapper_sig: []const u8 = undefined;
        var wrapper_call: []const u8 = undefined;
        var raw_wrapper_sig: []const u8 = undefined;
        var raw_wrapper_call: []const u8 = undefined;

        if (is_getter) {
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !{s}", .{ norm_name, wrapper_ret });
            wrapper_call = try std.fmt.allocPrint(allocator, "var out: {s} = undefined; try hrCheck(self.lpVtbl.{s}(self, &out)); return out;", .{ wrapper_ret, unique });
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !{s}", .{ unique, wrapper_ret });
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{ norm_name });
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
            } else {
                wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !void", .{ norm_name, wrapper_params.items });
                wrapper_call = try std.fmt.allocPrint(allocator, "try hrCheck(self.lpVtbl.{s}({s}));", .{ unique, call_args.items });
                raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !void", .{ unique, wrapper_params.items });
                const args_suffix = if (call_args.items.len > 5) call_args.items[5..] else "";
                raw_wrapper_call = try std.fmt.allocPrint(allocator, "try self.{s}({s});", .{ norm_name, args_suffix });
            }
        }

        // Hard ABI contracts used by Ghostty call sites.
        if (std.mem.eql(u8, type_name, "ITabView") and std.mem.eql(u8, name, "get_TabItems")) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*IVector", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(
                allocator,
                "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &out)); return @ptrCast(@alignCast(out.?));",
                .{unique},
            );
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*IVector", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "ITabView") and
            (std.mem.eql(u8, name, "add_TabCloseRequested") or
            std.mem.eql(u8, name, "add_AddTabButtonClick") or
            std.mem.eql(u8, name, "add_SelectionChanged")))
        {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: anytype) !EventRegistrationToken", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(
                allocator,
                "var t: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.{s}(self, @ptrCast(p0), &t)); return t;",
                .{unique},
            );
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: anytype) !EventRegistrationToken", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}(p0);", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "IWindow") and std.mem.eql(u8, name, "add_Closed")) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(
                allocator,
                "var t: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.{s}(self, p0, &t)); return t;",
                .{unique},
            );
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}(p0);", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "ITabView") and std.mem.eql(u8, name, "get_SelectedIndex")) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, *i32) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !i32", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(allocator, "var out: i32 = 0; try hrCheck(self.lpVtbl.{s}(self, &out)); return out;", .{unique});
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !i32", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "ITabView") and std.mem.eql(u8, name, "get_SelectedItem")) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*IInspectable", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(allocator, "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &out)); return @ptrCast(@alignCast(out.?));", .{unique});
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*IInspectable", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
        }

        if ((std.mem.eql(u8, type_name, "IWindow") or std.mem.eql(u8, type_name, "IContentControl")) and std.mem.eql(u8, name, "get_Content")) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !?*IInspectable", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(allocator, "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &out)); if (out) |p| return @ptrCast(@alignCast(p)); return null;", .{unique});
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !?*IInspectable", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "ITabViewTabCloseRequestedEventArgs") and std.mem.eql(u8, name, "get_Tab")) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*IInspectable", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(allocator, "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &out)); return @ptrCast(@alignCast(out.?));", .{unique});
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*IInspectable", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
        }

        if ((std.mem.eql(u8, name, "put_Content") or std.mem.eql(u8, name, "put_Background") or std.mem.eql(u8, name, "put_Header"))) {
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: ?*anyopaque) !void", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(allocator, "try hrCheck(self.lpVtbl.{s}(self, p0));", .{unique});
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: ?*anyopaque) !void", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}(p0);", .{norm_name});
        }

        if (std.mem.startsWith(u8, name, "remove_") and param_count == 1) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);
            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, EventRegistrationToken) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: EventRegistrationToken) !void", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(allocator, "try hrCheck(self.lpVtbl.{s}(self, p0));", .{unique});
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: EventRegistrationToken) !void", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}(p0);", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "IFrameworkElement") and (std.mem.eql(u8, name, "add_Loaded") or std.mem.eql(u8, name, "add_SizeChanged"))) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, ?*anyopaque, *EventRegistrationToken) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(
                allocator,
                "var t: EventRegistrationToken = 0; try hrCheck(self.lpVtbl.{s}(self, p0, &t)); return t;",
                .{unique},
            );
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: ?*anyopaque) !EventRegistrationToken", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}(p0);", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "IApplicationFactory") and std.mem.eql(u8, name, "CreateInstance")) {
            allocator.free(vtbl_sig);
            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, ?*anyopaque, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT");
        }

        if (std.mem.eql(u8, type_name, "IXamlMetadataProvider") and std.mem.eql(u8, name, "GetXmlnsDefinitions")) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, *u32, *?*anyopaque) callconv(.winapi) HRESULT");
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
        }

        if (std.mem.eql(u8, type_name, "IXamlMetadataProvider") and
            (std.mem.eql(u8, name, "GetXamlType") or std.mem.eql(u8, unique, "GetXamlType_2")))
        {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: ?*anyopaque) !*IXamlType", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(
                allocator,
                "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, p0, &out)); return @ptrCast(@alignCast(out.?));",
                .{unique},
            );
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: ?*anyopaque) !*IXamlType", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}(p0);", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "IXamlType") and std.mem.eql(u8, name, "ActivateInstance")) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*IInspectable", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(
                allocator,
                "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &out)); return @ptrCast(@alignCast(out.?));",
                .{unique},
            );
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*IInspectable", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "ISolidColorBrush") and std.mem.eql(u8, name, "put_Color")) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, Color) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: Color) !void", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(allocator, "try hrCheck(self.lpVtbl.{s}(self, p0));", .{unique});
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: Color) !void", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}(p0);", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "IPanel") and std.mem.eql(u8, name, "get_Children")) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*IVector", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(
                allocator,
                "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &out)); return @ptrCast(@alignCast(out.?));",
                .{unique},
            );
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*IVector", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "IGrid") and std.mem.eql(u8, name, "get_RowDefinitions")) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*IVector", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(
                allocator,
                "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &out)); return @ptrCast(@alignCast(out.?));",
                .{unique},
            );
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*IVector", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "IGridStatics") and (std.mem.eql(u8, name, "SetRow") or std.mem.eql(u8, name, "SetColumn"))) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, ?*anyopaque, i32) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: ?*anyopaque, p1: i32) !void", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(allocator, "try hrCheck(self.lpVtbl.{s}(self, p0, p1));", .{unique});
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: ?*anyopaque, p1: i32) !void", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}(p0, p1);", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "IRowDefinition") and std.mem.eql(u8, name, "put_Height")) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, GridLength) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: GridLength) !void", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(allocator, "try hrCheck(self.lpVtbl.{s}(self, p0));", .{unique});
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(), p0: GridLength) !void", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}(p0);", .{norm_name});
        }

        if (std.mem.eql(u8, type_name, "IRowDefinition") and std.mem.eql(u8, name, "get_Height")) {
            allocator.free(vtbl_sig);
            allocator.free(wrapper_sig);
            allocator.free(wrapper_call);
            allocator.free(raw_wrapper_sig);
            allocator.free(raw_wrapper_call);

            vtbl_sig = try allocator.dupe(u8, "*const fn (*anyopaque, *GridLength) callconv(.winapi) HRESULT");
            wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !GridLength", .{norm_name});
            wrapper_call = try std.fmt.allocPrint(
                allocator,
                "var out: GridLength = .{{ .Value = 0, .GridUnitType = 0 }}; try hrCheck(self.lpVtbl.{s}(self, &out)); return out;",
                .{unique},
            );
            raw_wrapper_sig = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !GridLength", .{unique});
            raw_wrapper_call = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
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
        0x10 => try allocator.dupe(u8, "anyopaque"),
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
            const dot = std.mem.lastIndexOfScalar(u8, full, '.') orelse return try allocator.dupe(u8, full);
            const short = full[dot+1..];
            const t = ctx.table_info.getTable(.TypeDef);
            var found_td: ?u32 = null;
            var row: u32 = 1;
            while (row <= t.row_count) : (row += 1) {
                const td = try ctx.table_info.readTypeDef(row);
                const name_td = try ctx.heaps.getString(td.type_name);
                if (std.mem.eql(u8, name_td, short)) { found_td = row; break; }
            }
            if (found_td) |td_row| {
                const cat = identifyTypeCategory(ctx, td_row) catch .other;
                if (cat == .enum_type or cat == .struct_type) break :blk try allocator.dupe(u8, short);
            }
            break :blk try allocator.dupe(u8, "?*anyopaque");
        },
        else => try allocator.dupe(u8, "?*anyopaque"),
    };
}
