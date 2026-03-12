const std = @import("std");
const win_zig_metadata = @import("win_zig_metadata");
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const coded = win_zig_metadata.coded_index;
const resolver = @import("resolver.zig");

// Re-export types from submodules for backward compatibility
pub const context_mod = @import("context.zig");
const ui = @import("unified_index.zig");
pub const Context = ui.UnifiedContext;
pub const CompanionMetadata = context_mod.CompanionMetadata;
pub const MethodMeta = context_mod.MethodMeta;
pub const MethodRange = context_mod.MethodRange;
pub const TypeCategory = context_mod.TypeCategory;

const tp = @import("type_predicates.zig");
const nav = @import("metadata_nav.zig");
const sig = @import("sig_decode.zig");
const dep = @import("dependency.zig");
const prol = @import("prologue.zig");
const event_iid = @import("event_iid.zig");

// Re-export public functions from submodules
pub const writePrologue = prol.writePrologue;
pub const writePrologueWithImport = prol.writePrologueWithImport;
pub const identifyTypeCategory = sig.identifyTypeCategory;
pub const findTypeDefRow = nav.findTypeDefRow;

pub fn emitInterface(
    allocator: std.mem.Allocator,
    writer: anytype,
    ctx: Context,
    _: []const u8,
    interface_name: []const u8,
    emitted_event_iids: ?*std.StringHashMap(void),
) !void {
    const type_row = try nav.findTypeDefRow(ctx, interface_name);
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name_raw = try ctx.heaps.getString(type_def.type_name);
    const type_name = if (std.mem.indexOfScalar(u8, type_name_raw, '`')) |bt| type_name_raw[0..bt] else type_name_raw;
    const ns = try ctx.heaps.getString(type_def.type_namespace);
    const is_winrt_iface = !std.mem.startsWith(u8, ns, "Windows.Win32.") and !std.mem.startsWith(u8, ns, "Windows.Wdk.");

    const guid = nav.extractGuid(ctx, type_row) catch std.mem.zeroes([16]u8);

    const method_range_info = try nav.methodRange(ctx.table_info, type_row);
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
        if (std.mem.eql(u8, name, ".ctor")) continue;
        const sig_blob = try ctx.heaps.getBlob(m.signature);
        var sig_c = sig.SigCursor{ .data = sig_blob };
        _ = sig_c.readByte();
        const param_count = sig_c.readCompressedUInt() orelse 0;
        const ret_type_opt = try sig.decodeSigType(allocator, ctx, &sig_c, is_winrt_iface);
        const ret_type_raw = ret_type_opt orelse "void";
        defer if (ret_type_opt != null) allocator.free(ret_type_raw);

        var param_names_meta = try sig.collectParamNames(allocator, ctx, i);
        defer param_names_meta.deinit(allocator);
        var all_param_names = std.ArrayList([]const u8).empty;
        defer {
            for (all_param_names.items) |n| allocator.free(n);
            all_param_names.deinit(allocator);
        }
        for (param_names_meta.items) |pn| {
            try all_param_names.append(allocator, try tp.sanitizeIdentifier(allocator, pn));
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
            const p_type_opt = try sig.decodeSigType(allocator, ctx, &sig_c, is_winrt_iface);
            const p_type_raw = p_type_opt orelse "?*anyopaque";
            if (is_byref) try byref_indices.append(allocator, p_idx);
            defer if (p_type_opt != null) allocator.free(p_type_raw);

            var p_type_vtbl = if (std.mem.eql(u8, p_type_raw, "anyopaque"))
                try allocator.dupe(u8, "?*anyopaque")
            else if (tp.isBuiltinType(p_type_raw))
                try allocator.dupe(u8, p_type_raw)
            else if (std.mem.startsWith(u8, p_type_raw, "*")) blk_vtbl: {
                const inner = p_type_raw[1..];
                if (tp.isBuiltinType(inner) or std.mem.eql(u8, inner, "EventRegistrationToken") or tp.isKnownStruct(inner))
                    break :blk_vtbl try allocator.dupe(u8, p_type_raw)
                else
                    break :blk_vtbl try allocator.dupe(u8, "*?*anyopaque");
            } else if (std.mem.startsWith(u8, p_type_raw, "?"))
                try allocator.dupe(u8, p_type_raw)
            else if (tp.isKnownStruct(p_type_raw) or std.mem.eql(u8, p_type_raw, "EventRegistrationToken"))
                try allocator.dupe(u8, p_type_raw)
            else if (tp.isInterfaceType(p_type_raw) or sig.isComObjectType(ctx, p_type_raw))
                try allocator.dupe(u8, "?*anyopaque")
            else
                try allocator.dupe(u8, "?*anyopaque");

            defer allocator.free(p_type_vtbl);

            try vtbl_params.appendSlice(allocator, ", ");
            try vtbl_params.appendSlice(allocator, p_type_vtbl);
            try param_vtbl_types.append(allocator, try allocator.dupe(u8, p_type_vtbl));
            try param_logical_types.append(allocator, try allocator.dupe(u8, p_type_raw));

            const p_name = all_param_names.items[p_idx];

            if (is_getter) {
                const logical_raw = p_type_raw;
                const logical_inner = if (std.mem.startsWith(u8, logical_raw, "*")) logical_raw[1..] else logical_raw;
                const is_iface_return = tp.isInterfaceType(logical_inner) or sig.isComObjectType(ctx, logical_inner);

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

                if (std.mem.eql(u8, p_type_vtbl, "HSTRING")) {
                    try wrapper_params.appendSlice(allocator, "anytype");
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

        if (is_winrt_iface and std.mem.eql(u8, ret_type_raw, "SZARRAY")) {
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
            const is_iface_ret = tp.isInterfaceType(ret_type_raw);
            const synth_param_idx: u32 = @intCast(param_vtbl_types.items.len);

            const is_known_value = tp.isBuiltinType(ret_type_raw) or tp.isKnownStruct(ret_type_raw) or std.mem.eql(u8, ret_type_raw, "EventRegistrationToken");
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

            if (is_getter) {
                allocator.free(wrapper_ret);
                if (is_iface_ret or sig.isComObjectType(ctx, ret_type_raw)) {
                    wrapper_ret = try std.fmt.allocPrint(allocator, "*{s}", .{ret_type_raw});
                } else if (tp.isBuiltinType(ret_type_raw) or tp.isKnownStruct(ret_type_raw) or
                    std.mem.eql(u8, ret_type_raw, "EventRegistrationToken"))
                {
                    wrapper_ret = try allocator.dupe(u8, ret_type_raw);
                } else {
                    wrapper_ret = try allocator.dupe(u8, "?*anyopaque");
                }
            }
        } else if (!is_winrt_iface) {
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
        const ret_base = if (std.mem.startsWith(u8, wrapper_ret, "*")) wrapper_ret[1..] else wrapper_ret;
        if (is_getter and (std.mem.eql(u8, norm_name, ret_base) or std.mem.eql(u8, norm_seed, ret_base))) {
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

        {
            const sanitized_norm = try tp.sanitizeIdentifier(allocator, norm_name);
            if (!std.mem.eql(u8, sanitized_norm, norm_name)) {
                allocator.free(norm_name);
                norm_name = @constCast(sanitized_norm);
            } else {
                allocator.free(sanitized_norm);
            }
        }

        const vtbl_ret = if (is_winrt_iface) "HRESULT" else wrapper_ret;
        const vtbl_sig_str = try std.fmt.allocPrint(allocator, "*const fn ({s}) callconv(.winapi) {s}", .{ vtbl_params.items, vtbl_ret });
        var wrapper_sig_str: []const u8 = undefined;
        var wrapper_call_str: []const u8 = undefined;
        var raw_wrapper_sig_str: []const u8 = undefined;
        var raw_wrapper_call_str: []const u8 = undefined;

        if (is_getter) {
            const iface_inner = if (std.mem.startsWith(u8, wrapper_ret, "*")) wrapper_ret[1..] else wrapper_ret;
            const is_iface_getter = std.mem.startsWith(u8, wrapper_ret, "*") and (tp.isInterfaceType(iface_inner) or sig.isComObjectType(ctx, iface_inner));
            const is_importable_iface = is_iface_getter;
            const is_nullable_getter = (std.mem.eql(u8, type_name, "IWindow") or std.mem.eql(u8, type_name, "IContentControl")) and std.mem.eql(u8, name, "get_Content");

            if (is_nullable_getter) {
                wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !?*IInspectable", .{norm_name});
                wrapper_call_str = try std.fmt.allocPrint(
                    allocator,
                    "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &out)); if (out) |p| return @ptrCast(@alignCast(p)); return null;",
                    .{unique},
                );
                raw_wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !?*IInspectable", .{unique});
                raw_wrapper_call_str = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
            } else if (is_importable_iface) {
                wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !{s}", .{ norm_name, wrapper_ret });
                wrapper_call_str = try std.fmt.allocPrint(
                    allocator,
                    "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &out)); return @ptrCast(@alignCast(out orelse return error.WinRTFailed));",
                    .{unique},
                );
                raw_wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !{s}", .{ unique, wrapper_ret });
                raw_wrapper_call_str = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
            } else if (is_iface_getter or std.mem.eql(u8, wrapper_ret, "?*anyopaque")) {
                allocator.free(wrapper_ret);
                wrapper_ret = try allocator.dupe(u8, "*anyopaque");
                wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*anyopaque", .{norm_name});
                wrapper_call_str = try std.fmt.allocPrint(
                    allocator,
                    "var out: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, &out)); return out orelse error.WinRTFailed;",
                    .{unique},
                );
                raw_wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !*anyopaque", .{unique});
                raw_wrapper_call_str = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
            } else {
                const init = tp.defaultInit(wrapper_ret);
                wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !{s}", .{ norm_name, wrapper_ret });
                wrapper_call_str = try std.fmt.allocPrint(allocator, "var out: {s} = {s}; try hrCheck(self.lpVtbl.{s}(self, &out)); return out;", .{ wrapper_ret, init, unique });
                raw_wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This()) !{s}", .{ unique, wrapper_ret });
                raw_wrapper_call_str = try std.fmt.allocPrint(allocator, "return self.{s}();", .{norm_name});
            }
        } else {
            if (std.mem.eql(u8, name, "CreateInstance") and param_count >= 2) {
                wrapper_sig_str = try std.fmt.allocPrint(
                    allocator,
                    "pub fn {s}(self: *@This(), outer: ?*anyopaque) !struct {{ inner: ?*anyopaque, instance: *IInspectable }}",
                    .{norm_name},
                );
                wrapper_call_str = try std.fmt.allocPrint(
                    allocator,
                    "var inner: ?*anyopaque = null; var instance: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}(self, outer, &inner, &instance)); return .{{ .inner = inner, .instance = @ptrCast(@alignCast(instance.?)) }};",
                    .{unique},
                );
                raw_wrapper_sig_str = try std.fmt.allocPrint(
                    allocator,
                    "pub fn {s}(self: *@This(), outer: ?*anyopaque) !struct {{ inner: ?*anyopaque, instance: *IInspectable }}",
                    .{unique},
                );
                raw_wrapper_call_str = try std.fmt.allocPrint(allocator, "return self.{s}(outer);", .{norm_name});
                emit_raw_wrapper_alias = false;
            } else if (byref_indices.items.len > 0) {
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
                        const inner_type = if (std.mem.startsWith(u8, pvt, "*")) pvt[1..] else pvt;
                        const local_name = try std.fmt.allocPrint(allocator, "out{d}", .{byref_count});
                        defer allocator.free(local_name);
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
                        const p_name = try std.fmt.allocPrint(allocator, "p{d}", .{pi});
                        defer allocator.free(p_name);
                        try out_fwd_args.appendSlice(allocator, ", ");
                        try out_fwd_args.appendSlice(allocator, p_name);
                        try out_wrapper_params.appendSlice(allocator, ", ");
                        try out_wrapper_params.appendSlice(allocator, p_name);
                        try out_wrapper_params.appendSlice(allocator, ": ");

                        if (std.mem.eql(u8, pvt, "HSTRING")) {
                            try out_wrapper_params.appendSlice(allocator, "anytype");
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
                    const out_type = param_vtbl_types.items[byref_indices.items[0]];
                    const inner_type = if (std.mem.startsWith(u8, out_type, "*")) out_type[1..] else out_type;
                    const logical_type = param_logical_types.items[byref_indices.items[0]];
                    const logical_inner = if (std.mem.startsWith(u8, logical_type, "*")) logical_type[1..] else logical_type;
                    const is_com_out = tp.isInterfaceType(logical_inner) or sig.isComObjectType(ctx, logical_inner);

                    if (is_com_out) {
                        wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !*{s}", .{ norm_name, out_wrapper_params.items, logical_inner });
                        wrapper_call_str = try std.fmt.allocPrint(
                            allocator,
                            "var out0: ?*anyopaque = null; try hrCheck(self.lpVtbl.{s}({s})); return @ptrCast(@alignCast(out0 orelse return error.WinRTFailed));",
                            .{ unique, out_call_args.items },
                        );
                        raw_wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !*{s}", .{ unique, out_wrapper_params.items, logical_inner });
                    } else {
                        wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !{s}", .{ norm_name, out_wrapper_params.items, inner_type });
                        wrapper_call_str = try std.fmt.allocPrint(allocator, "{s}try hrCheck(self.lpVtbl.{s}({s})); return out0;", .{ out_locals.items, unique, out_call_args.items });
                        raw_wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !{s}", .{ unique, out_wrapper_params.items, inner_type });
                    }
                    const fwd_args = if (out_fwd_args.items.len > 2) out_fwd_args.items[2..] else "";
                    raw_wrapper_call_str = try std.fmt.allocPrint(allocator, "return self.{s}({s});", .{ norm_name, fwd_args });
                } else {
                    var ret_struct_sig = std.ArrayList(u8).empty;
                    defer ret_struct_sig.deinit(allocator);
                    try ret_struct_sig.appendSlice(allocator, "struct { ");

                    var ret_val_init = std.ArrayList(u8).empty;
                    defer ret_val_init.deinit(allocator);
                    try ret_val_init.appendSlice(allocator, ".{ ");

                    var seen_field_names = std.StringHashMap(u32).init(allocator);
                    defer seen_field_names.deinit();
                    var bi: u32 = 0;
                    while (bi < byref_count) : (bi += 1) {
                        const param_index = byref_indices.items[bi];
                        const p_name_raw = all_param_names.items[param_index];
                        const pvt = param_vtbl_types.items[param_index];
                        const field_count = seen_field_names.get(p_name_raw) orelse 0;
                        try seen_field_names.put(p_name_raw, field_count + 1);
                        const p_name = if (field_count > 0)
                            try std.fmt.allocPrint(allocator, "{s}_{d}", .{ p_name_raw, field_count })
                        else
                            try allocator.dupe(u8, p_name_raw);
                        defer allocator.free(p_name);
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

                    wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !{s}", .{ norm_name, out_wrapper_params.items, ret_struct_sig.items });
                    wrapper_call_str = try std.fmt.allocPrint(allocator, "{s}try hrCheck(self.lpVtbl.{s}({s})); return {s};", .{ out_locals.items, unique, out_call_args.items, ret_val_init.items });
                    raw_wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !{s}", .{ unique, out_wrapper_params.items, ret_struct_sig.items });
                    const fwd_args = if (out_fwd_args.items.len > 2) out_fwd_args.items[2..] else "";
                    raw_wrapper_call_str = try std.fmt.allocPrint(allocator, "return self.{s}({s});", .{ norm_name, fwd_args });
                }
            } else {
                wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !void", .{ norm_name, wrapper_params.items });
                wrapper_call_str = try std.fmt.allocPrint(allocator, "try hrCheck(self.lpVtbl.{s}({s}));", .{ unique, call_args.items });
                raw_wrapper_sig_str = try std.fmt.allocPrint(allocator, "pub fn {s}(self: *@This(){s}) !void", .{ unique, wrapper_params.items });
                const fwd_args = if (wrapper_fwd_args.items.len > 2) wrapper_fwd_args.items[2..] else "";
                raw_wrapper_call_str = try std.fmt.allocPrint(allocator, "try self.{s}({s});", .{ norm_name, fwd_args });
            }
        }

        if (!emit_raw_wrapper_alias) {
            allocator.free(raw_wrapper_sig_str);
            allocator.free(raw_wrapper_call_str);
            raw_wrapper_sig_str = try allocator.dupe(u8, "");
            raw_wrapper_call_str = try allocator.dupe(u8, "");
        }

        try methods.append(allocator, .{ .raw_name = try allocator.dupe(u8, unique), .norm_name = norm_name, .vtbl_sig = vtbl_sig_str, .wrapper_sig = wrapper_sig_str, .wrapper_call = wrapper_call_str, .raw_wrapper_sig = raw_wrapper_sig_str, .raw_wrapper_call = raw_wrapper_call_str });
        allocator.free(unique);
    }

    var parent_methods = try dep.collectParentMethods(allocator, ctx, type_row);
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

    var required_ifaces = try dep.collectRequiredInterfaces(allocator, ctx, type_row);
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
        var iface_methods = try dep.collectInterfaceMethodsByName(allocator, ctx, iface_name);
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
    {
        var vtbl_seen = std.StringHashMap(void).init(allocator);
        defer {
            var kit = vtbl_seen.keyIterator();
            while (kit.next()) |k| allocator.free(k.*);
            vtbl_seen.deinit();
        }
        var slot_idx: u32 = 0;
        // WinRT ABI: vtable contains ONLY own methods + IInspectable base.
        // Required/parent interface methods are accessed via QueryInterface, not inlined.
        const all_method_lists = [_][]const MethodMeta{methods.items};
        for (all_method_lists) |method_list| {
            for (method_list) |m| {
                if (vtbl_seen.contains(m.raw_name)) {
                    try writer.print("        _reserved_slot_{d}: VtblPlaceholder,\n", .{slot_idx});
                } else {
                    try writer.print("        {s}: {s},\n", .{ m.raw_name, m.vtbl_sig });
                    try vtbl_seen.put(try allocator.dupe(u8, m.raw_name), {});
                }
                slot_idx += 1;
            }
        }
    }
    try writer.writeAll("    };\n");
    for (required_ifaces.items) |iface_name| {
        const trimmed = std.mem.trim(u8, iface_name, " \t\r\n\x00");
        if (trimmed.len == 0) continue;
        try writer.print("    pub const Requires_{s} = true; // requires {s}\n", .{ trimmed, trimmed });
    }
    try writer.writeAll("    pub fn release(self: *@This()) void { comRelease(self); }\n    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }\n");
    var emitted_required_forwarders = std.StringHashMap(void).init(allocator);
    defer {
        var it = emitted_required_forwarders.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        emitted_required_forwarders.deinit();
    }
    for (required_ifaces.items) |iface_name| {
        const iface_row = nav.findTypeDefRow(ctx, iface_name) catch continue;
        const iface_range = nav.methodRange(ctx.table_info, iface_row) catch continue;
        var iface_mi = iface_range.start;
        while (iface_mi < iface_range.end_exclusive) : (iface_mi += 1) {
            const iface_m = try ctx.table_info.readMethodDef(iface_mi);
            const iface_method_name = try ctx.heaps.getString(iface_m.name);
            const iface_sig_blob = try ctx.heaps.getBlob(iface_m.signature);
            var iface_sig_c = sig.SigCursor{ .data = iface_sig_blob };
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
        if (!emitted_required_forwarders.contains(m.norm_name)) {
            try writer.print("    {s} {{ {s} }}\n", .{ m.wrapper_sig, m.wrapper_call });
            try emitted_required_forwarders.put(try allocator.dupe(u8, m.norm_name), {});
        }
        if (m.raw_wrapper_sig.len > 0 and !std.mem.eql(u8, m.norm_name, m.raw_name)) {
            if (!emitted_required_forwarders.contains(m.raw_name)) {
                try writer.print("    {s} {{ {s} }}\n", .{ m.raw_wrapper_sig, m.raw_wrapper_call });
                try emitted_required_forwarders.put(try allocator.dupe(u8, m.raw_name), {});
            }
        }
    }
    const cat = sig.identifyTypeCategory(ctx, type_row) catch .other;
    if (cat == .delegate) {
        try writer.print("    pub fn new() !*@This() {{ @compileError(\"use {s}Impl instead\"); }}\n", .{type_name});
    }
    try writer.writeAll("};\n\n");

    // Emit TypedEventHandler parameterized IIDs for add_ methods on this interface
    {
        var ei = method_range_info.start;
        while (ei < method_range_info.end_exclusive) : (ei += 1) {
            const result = event_iid.computeTypedEventHandlerIid(allocator, ctx, ei) catch continue;
            if (result) |r| {
                defer allocator.free(r.event_suffix);
                // Skip duplicates: different interfaces may have events with the same suffix
                // (e.g. CharacterReceived on IUIElement vs InputKeyboardSource).
                // First-emitted wins.
                if (emitted_event_iids) |set| {
                    const key = std.fmt.allocPrint(allocator, "IID_TypedEventHandler_{s}", .{r.event_suffix}) catch continue;
                    if (set.contains(key)) {
                        allocator.free(key);
                        continue;
                    }
                    set.put(key, {}) catch {
                        allocator.free(key);
                        continue;
                    };
                }
                try writer.print("pub const IID_TypedEventHandler_{s} = ", .{r.event_suffix});
                try event_iid.formatGuidLiteral(r.guid, writer);
                try writer.writeAll(";\n");
            }
        }
    }
}

pub fn emitEnum(_: std.mem.Allocator, writer: anytype, ctx: Context, type_row: u32) !void {
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name_raw = try ctx.heaps.getString(type_def.type_name);
    const type_name = if (std.mem.indexOfScalar(u8, type_name_raw, '`')) |bt| type_name_raw[0..bt] else type_name_raw;
    const range = try nav.fieldRange(ctx.table_info, type_row);

    const backing_type = sig.detectEnumBackingType(ctx, range) catch "i32";
    const is_signed = backing_type[0] == 'i';

    try writer.print("pub const {s} = struct {{\n", .{type_name});

    var ii = range.start;
    while (ii < range.end_exclusive) : (ii += 1) {
        const f = try ctx.table_info.readField(ii);
        const name = try ctx.heaps.getString(f.name);
        if (std.mem.eql(u8, name, "value__")) continue;

        const c_table = ctx.table_info.getTable(.Constant);
        var ci: u32 = 1;
        var val_i64: i64 = 0;
        var val_u64: u64 = 0;
        while (ci <= c_table.row_count) : (ci += 1) {
            const c = try ctx.table_info.readConstant(ci);
            const parent = try coded.decodeHasConstant(c.parent);
            if (parent.table == .Field and parent.row == ii) {
                const blob = try ctx.heaps.getBlob(c.value);
                if (is_signed) {
                    val_i64 = sig.readSignedConstant(blob, backing_type);
                } else {
                    val_u64 = sig.readUnsignedConstant(blob, backing_type);
                }
                break;
            }
        }

        if (is_signed) {
            try writer.print("    pub const {s}: {s} = {d};\n", .{ name, backing_type, val_i64 });
        } else {
            try writer.print("    pub const {s}: {s} = {d};\n", .{ name, backing_type, val_u64 });
        }
    }

    try writer.writeAll("};\n\n");
}

pub fn emitStruct(allocator: std.mem.Allocator, writer: anytype, ctx: Context, type_row: u32) !void {
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name_raw = try ctx.heaps.getString(type_def.type_name);
    const type_name = if (std.mem.indexOfScalar(u8, type_name_raw, '`')) |bt| type_name_raw[0..bt] else type_name_raw;
    try writer.print("pub const {s} = extern struct {{\n", .{type_name});
    const range = try nav.fieldRange(ctx.table_info, type_row);
    var ii = range.start;
    while (ii < range.end_exclusive) : (ii += 1) {
        const f = try ctx.table_info.readField(ii);
        const name = try ctx.heaps.getString(f.name);
        const sig_blob = try ctx.heaps.getBlob(f.signature);
        var sig_c = sig.SigCursor{ .data = sig_blob };
        _ = sig_c.readByte();
        const ty_opt = try sig.decodeSigType(allocator, ctx, &sig_c, false);
        const ty = ty_opt orelse "?*anyopaque";
        defer if (ty_opt != null) allocator.free(ty);
        try writer.print("    {s}: {s},\n", .{ name, ty });
    }
    try writer.writeAll("};\n\n");
}

pub fn emitFunctions(
    allocator: std.mem.Allocator,
    writer: anytype,
    ctx: Context,
    type_row: u32,
) !void {
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name_raw = try ctx.heaps.getString(type_def.type_name);
    const type_name = if (std.mem.indexOfScalar(u8, type_name_raw, '`')) |bt| type_name_raw[0..bt] else type_name_raw;

    const range = try nav.methodRange(ctx.table_info, type_row);
    var ii = range.start;

    try writer.print("// Standalone functions for {s}\n", .{type_name});

    while (ii < range.end_exclusive) : (ii += 1) {
        const m = try ctx.table_info.readMethodDef(ii);
        const name = try ctx.heaps.getString(m.name);

        if ((m.flags & 0x0010) == 0) continue;

        try dep.registerAssociatedEnumDependencies(allocator, ctx, ii);

        const sig_blob = try ctx.heaps.getBlob(m.signature);
        var sig_c = sig.SigCursor{ .data = sig_blob };
        _ = sig_c.readByte();
        const param_count = sig_c.readCompressedUInt() orelse 0;
        const ret_type_opt = try sig.decodeSigType(allocator, ctx, &sig_c, false);
        const ret_type = ret_type_opt orelse "void";
        defer if (ret_type_opt != null) allocator.free(ret_type);

        var param_names_meta = try sig.collectParamNames(allocator, ctx, ii);
        defer param_names_meta.deinit(allocator);
        var all_param_names = std.ArrayList([]const u8).empty;
        defer {
            for (all_param_names.items) |n| allocator.free(n);
            all_param_names.deinit(allocator);
        }
        for (param_names_meta.items) |pn| {
            try all_param_names.append(allocator, try tp.sanitizeIdentifier(allocator, pn));
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
            const p_type_opt = try sig.decodeSigType(allocator, ctx, &sig_c, false);
            try params.append(allocator, p_type_opt orelse try allocator.dupe(u8, "?*anyopaque"));
        }

        const dll_name = try findDllName(ctx, ii) orelse "UNKNOWN";

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

/// Extract a factory type name from a CustomAttribute blob (after the 0x01 0x00 prolog).
/// Matches windows-rs: only returns a string if it looks like a fully-qualified type name
/// (contains '.'), distinguishing ActivatableAttribute(Type, uint, string) from
/// ActivatableAttribute(uint, string) where the first arg is NOT a type name.
fn extractFactoryTypeFromBlob(data: []const u8) ?[]const u8 {
    if (data.len == 0) return null;
    var c = sig.SigCursor{ .data = data };
    // Try to read a SerString (compressed-uint length prefix + UTF-8 bytes)
    const len = c.readCompressedUInt() orelse return null;
    if (len == 0 or c.pos + len > c.data.len) return null;
    const candidate = c.data[c.pos .. c.pos + len];
    // windows-rs: only use strings that contain '.' (fully-qualified "Namespace.TypeName")
    if (std.mem.indexOfScalar(u8, candidate, '.') == null) return null;
    // Validate all bytes are printable ASCII (type names don't contain control chars)
    for (candidate) |b| {
        if (b < 0x20 or b > 0x7e) return null;
    }
    return candidate;
}

pub fn emitClass(allocator: std.mem.Allocator, writer: anytype, ctx: Context, type_row: u32) !void {
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const type_name_raw = try ctx.heaps.getString(type_def.type_name);
    const type_name = if (std.mem.indexOfScalar(u8, type_name_raw, '`')) |bt| type_name_raw[0..bt] else type_name_raw;
    const ns = try ctx.heaps.getString(type_def.type_namespace);

    const full_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, type_name });
    defer allocator.free(full_name);

    const rctx = resolver.Context{ .table_info = ctx.table_info, .heaps = ctx.heaps };
    const default_iface_full_opt = resolver.resolveDefaultInterfaceNameForRuntimeClassAlloc(rctx, allocator, full_name) catch null;

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
        try dep.appendUniqueShortName(allocator, &ifaces_to_implement, short);
    }
    defer if (default_iface_short) |short| allocator.free(short);

    const ii_table = ctx.table_info.getTable(.InterfaceImpl);
    var row: u32 = 1;
    while (row <= ii_table.row_count) : (row += 1) {
        const ii = try ctx.table_info.readInterfaceImpl(row);
        if (ii.class == type_row) {
            const iface_tdor = try coded.decodeTypeDefOrRef(ii.interface);
            if (iface_tdor.table == .TypeSpec) {
                const ts = ctx.table_info.readTypeSpec(iface_tdor.row) catch continue;
                const sig_blob = try ctx.heaps.getBlob(ts.signature);
                var sig_c = sig.SigCursor{ .data = sig_blob };
                const parsed = try sig.decodeSigType(allocator, ctx, &sig_c, true);
                if (parsed) |p| allocator.free(p);
            }
            const iface_name = sig.resolveTypeDefOrRefNameRaw(ctx, iface_tdor) catch continue;
            if (iface_name) |n| {
                // Strip backtick arity suffix for generic interfaces
                const backtick = std.mem.indexOfScalar(u8, n, '`');
                const clean_name = if (backtick) |bt| n[0..bt] else n;
                try ctx.registerDependency(allocator, clean_name);
                try dep.appendUniqueShortName(allocator, &ifaces_to_implement, clean_name);
            }
        }
    }

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
                // Extract factory type name from CustomAttribute blob.
                // windows-rs approach: iterate args, only use Utf8 strings
                // that contain '.' (fully-qualified type name) and resolve
                // to an actual interface. This correctly skips the
                // ActivatableAttribute(uint version, ...) overload which
                // has no factory type.
                const blob = try ctx.heaps.getBlob(ca.value);
                if (blob.len > 3 and blob[0] == 0x01 and blob[1] == 0x00) {
                    const factory_name = extractFactoryTypeFromBlob(blob[2..]);
                    if (factory_name) |name| {
                        try ctx.registerDependency(allocator, name);
                        try dep.appendUniqueShortName(allocator, &ifaces_to_implement, name);
                    }
                }
            }
        }
    }

    var iface_head: usize = 0;
    while (iface_head < ifaces_to_implement.items.len) : (iface_head += 1) {
        const iface = ifaces_to_implement.items[iface_head];
        const iface_row = nav.findTypeDefRow(ctx, iface) catch continue;
        var required = dep.collectRequiredInterfaces(allocator, ctx, iface_row) catch continue;
        defer {
            for (required.items) |item| allocator.free(item);
            required.deinit(allocator);
        }
        for (required.items) |req| {
            try dep.appendUniqueShortName(allocator, &ifaces_to_implement, req);
        }
    }

    try writer.print("pub const {s} = extern struct {{\n", .{type_name});
    if (default_iface_short) |short| {
        try writer.print("    pub const IID = {s}.IID;\n", .{short});
        try writer.writeAll("    lpVtbl: *const VTable,\n");
        try writer.print("    pub const VTable = {s}.VTable;\n", .{short});
    }

    for (ifaces_to_implement.items) |iface| {
        const iface_trimmed = std.mem.trim(u8, iface, " \t\r\n\x00");
        if (iface_trimmed.len == 0) continue;
        if (default_iface_short) |short| {
            if (std.mem.eql(u8, iface_trimmed, short)) continue;
        }
        try writer.print("    pub const Requires_{s} = true; // requires {s}\n", .{ iface_trimmed, iface_trimmed });
    }

    var emitted_methods = std.StringHashMap(void).init(allocator);
    defer {
        var it = emitted_methods.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        emitted_methods.deinit();
    }

    for (ifaces_to_implement.items) |iface| {
        var iface_methods = dep.collectInterfaceMethodsByName(allocator, ctx, iface) catch continue;
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
    const type_name_raw = try ctx.heaps.getString(type_def.type_name);
    const type_name = if (std.mem.indexOfScalar(u8, type_name_raw, '`')) |bt| type_name_raw[0..bt] else type_name_raw;
    const ns = try ctx.heaps.getString(type_def.type_namespace);
    const is_winrt = !std.mem.startsWith(u8, ns, "Windows.Win32.") and !std.mem.startsWith(u8, ns, "Windows.Wdk.");

    if (is_winrt) {
        try emitInterface(allocator, writer, ctx, "", type_name, null);
        try emitDelegateImpl(writer, type_name);
        try writer.print("pub const IID_{s} = {s}.IID;\n\n", .{ type_name, type_name });
        return;
    }

    const method_range_info = try nav.methodRange(ctx.table_info, type_row);
    var ii = method_range_info.start;
    var invoke_row: ?u32 = null;
    while (ii < method_range_info.end_exclusive) : (ii += 1) {
        const m = try ctx.table_info.readMethodDef(ii);
        const name = try ctx.heaps.getString(m.name);
        if (std.mem.eql(u8, name, "Invoke")) {
            invoke_row = ii;
            break;
        }
    }

    if (invoke_row) |inv_row| {
        const m = try ctx.table_info.readMethodDef(inv_row);
        const sig_blob = try ctx.heaps.getBlob(m.signature);
        var sig_c = sig.SigCursor{ .data = sig_blob };
        _ = sig_c.readByte();
        const param_count = sig_c.readCompressedUInt() orelse 0;
        const ret_type_opt = try sig.decodeSigType(allocator, ctx, &sig_c, false);
        const ret_type_raw = ret_type_opt orelse "void";
        defer if (ret_type_opt != null) allocator.free(ret_type_raw);

        var param_names_meta = try sig.collectParamNames(allocator, ctx, inv_row);
        defer param_names_meta.deinit(allocator);

        var params = std.ArrayList(u8).empty;
        defer params.deinit(allocator);

        var p_idx: u32 = 0;
        while (p_idx < param_count) : (p_idx += 1) {
            _ = (sig_c.pos < sig_c.data.len and sig_c.data[sig_c.pos] == 0x10);
            const p_type_opt = try sig.decodeSigType(allocator, ctx, &sig_c, false);
            const p_type_raw = p_type_opt orelse "?*anyopaque";
            defer if (p_type_opt != null) allocator.free(p_type_raw);

            const p_type = if (std.mem.eql(u8, p_type_raw, "anyopaque"))
                "?*anyopaque"
            else if (tp.isBuiltinType(p_type_raw))
                p_type_raw
            else if (std.mem.startsWith(u8, p_type_raw, "*") or std.mem.startsWith(u8, p_type_raw, "?"))
                p_type_raw
            else if (tp.isKnownStruct(p_type_raw) or std.mem.eql(u8, p_type_raw, "EventRegistrationToken"))
                p_type_raw
            else
                "?*anyopaque";

            if (p_idx > 0) try params.appendSlice(allocator, ", ");

            const p_name = if (p_idx < param_names_meta.items.len) param_names_meta.items[p_idx] else "p";
            const sanitized = try tp.sanitizeIdentifier(allocator, p_name);
            defer allocator.free(sanitized);

            try params.writer(allocator).print("{s}: {s}", .{ sanitized, p_type });
        }

        try writer.print("pub const {s} = ?*const fn ({s}) callconv(.winapi) {s};\n\n", .{ type_name, params.items, ret_type_raw });
    }
}

fn emitDelegateImpl(writer: anytype, type_name: []const u8) !void {
    try writer.print(
        \\pub fn {0s}Impl(comptime Context: type, comptime CallbackFn: type) type {{
        \\    return struct {{
        \\        const Self = @This();
        \\        const Delegate = {0s};
        \\
        \\        pub const ComHeader = extern struct {{
        \\            lpVtbl: *const Delegate.VTable,
        \\        }};
        \\
        \\        com: ComHeader,
        \\        allocator: @import("std").mem.Allocator,
        \\        ref_count: @import("std").atomic.Value(u32),
        \\        context: *Context,
        \\        callback: CallbackFn,
        \\        delegate_iid: ?*const GUID = null,
        \\
        \\        const S_OK: HRESULT = 0;
        \\        const E_NOINTERFACE: HRESULT = @bitCast(@as(u32, 0x80004002));
        \\
        \\        const vtable_instance = Delegate.VTable{{
        \\            .QueryInterface = &queryInterfaceFn,
        \\            .AddRef = &addRefFn,
        \\            .Release = &releaseFn,
        \\            .GetIids = null,
        \\            .GetRuntimeClassName = null,
        \\            .GetTrustLevel = null,
        \\            .Invoke = &invokeFn,
        \\        }};
        \\
        \\        pub fn create(allocator: @import("std").mem.Allocator, context: *Context, callback: CallbackFn) !*Self {{
        \\            const self = try allocator.create(Self);
        \\            self.* = .{{
        \\                .com = .{{ .lpVtbl = &vtable_instance }},
        \\                .allocator = allocator,
        \\                .ref_count = @import("std").atomic.Value(u32).init(1),
        \\                .context = context,
        \\                .callback = callback,
        \\            }};
        \\            return self;
        \\        }}
        \\
        \\        pub fn createWithIid(allocator: @import("std").mem.Allocator, context: *Context, callback: CallbackFn, iid: *const GUID) !*Self {{
        \\            const self = try allocator.create(Self);
        \\            self.* = .{{
        \\                .com = .{{ .lpVtbl = &vtable_instance }},
        \\                .allocator = allocator,
        \\                .ref_count = @import("std").atomic.Value(u32).init(1),
        \\                .context = context,
        \\                .callback = callback,
        \\                .delegate_iid = iid,
        \\            }};
        \\            return self;
        \\        }}
        \\
        \\        pub fn comPtr(self: *Self) *anyopaque {{
        \\            return @ptrCast(&self.com);
        \\        }}
        \\
        \\        pub fn release(self: *Self) void {{
        \\            _ = self.com.lpVtbl.Release(self.comPtr());
        \\        }}
        \\
        \\        fn fromComPtr(ptr: *anyopaque) *Self {{
        \\            const header: *ComHeader = @ptrCast(@alignCast(ptr));
        \\            return @fieldParentPtr("com", header);
        \\        }}
        \\
        \\        fn guidEql(a: *const GUID, b: *const GUID) bool {{
        \\            return a.data1 == b.data1 and a.data2 == b.data2 and a.data3 == b.data3 and @import("std").mem.eql(u8, &a.data4, &b.data4);
        \\        }}
        \\
        \\        fn queryInterfaceFn(this: *anyopaque, riid: *const GUID, ppv: *?*anyopaque) callconv(.winapi) HRESULT {{
        \\            const IID_IUnknown = GUID{{ .data1 = 0x00000000, .data2 = 0x0000, .data3 = 0x0000, .data4 = .{{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 }} }};
        \\            const IID_IAgileObject = GUID{{ .data1 = 0x94ea2b94, .data2 = 0xe9cc, .data3 = 0x49e0, .data4 = .{{ 0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90 }} }};
        \\            const self = fromComPtr(this);
        \\            if (guidEql(riid, &IID_IUnknown) or guidEql(riid, &IID_IAgileObject)) {{
        \\                ppv.* = this;
        \\                _ = self.ref_count.fetchAdd(1, .monotonic);
        \\                return S_OK;
        \\            }}
        \\            if (self.delegate_iid) |iid| {{
        \\                if (guidEql(riid, iid)) {{
        \\                    ppv.* = this;
        \\                    _ = self.ref_count.fetchAdd(1, .monotonic);
        \\                    return S_OK;
        \\                }}
        \\            }}
        \\            ppv.* = null;
        \\            return E_NOINTERFACE;
        \\        }}
        \\
        \\        fn addRefFn(this: *anyopaque) callconv(.winapi) u32 {{
        \\            const self = fromComPtr(this);
        \\            return self.ref_count.fetchAdd(1, .monotonic) + 1;
        \\        }}
        \\
        \\        fn releaseFn(this: *anyopaque) callconv(.winapi) u32 {{
        \\            const self = fromComPtr(this);
        \\            const prev = self.ref_count.fetchSub(1, .monotonic);
        \\            const next = prev - 1;
        \\            if (next == 0) self.allocator.destroy(self);
        \\            return next;
        \\        }}
        \\
        \\        fn invokeFn(this: *anyopaque, sender: ?*anyopaque, args: ?*anyopaque) callconv(.winapi) HRESULT {{
        \\            const self = fromComPtr(this);
        \\            const cb_ptr_info = @typeInfo(CallbackFn).pointer;
        \\            const fn_info = @typeInfo(cb_ptr_info.child).@"fn";
        \\            const sender_t = fn_info.params[1].type.?;
        \\            const args_t = fn_info.params[2].type.?;
        \\            if (sender_t == ?*anyopaque and args_t == ?*anyopaque) {{
        \\                self.callback(self.context, sender, args);
        \\            }} else if (sender_t == ?*anyopaque and args_t == *anyopaque) {{
        \\                const a = args orelse return S_OK;
        \\                self.callback(self.context, sender, a);
        \\            }} else if (sender_t == *anyopaque and args_t == ?*anyopaque) {{
        \\                const s = sender orelse return S_OK;
        \\                self.callback(self.context, s, args);
        \\            }} else {{
        \\                const s = sender orelse return S_OK;
        \\                const a = args orelse return S_OK;
        \\                self.callback(self.context, s, a);
        \\            }}
        \\            return S_OK;
        \\        }}
        \\    }};
        \\}}
        \\
    , .{type_name});
}
