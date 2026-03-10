const std = @import("std");
const win_zig_metadata = @import("win_zig_metadata");
const pe = win_zig_metadata.pe;
const metadata_mod = win_zig_metadata.metadata;
const tables = win_zig_metadata.tables;
const streams = win_zig_metadata.streams;
const coded = win_zig_metadata.coded_index;

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

/// Strip backtick suffix from a type name (e.g. "IVector`1" -> "IVector").
pub fn stripTick(name: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, name, '`')) |pos| name[0..pos] else name;
}

// ---------------------------------------------------------------------------
// Core types
// ---------------------------------------------------------------------------

/// Location of a TypeDef within the unified set of WinMD files.
pub const TypeLocation = struct {
    file_idx: u16,
    row: u32,
};

/// One loaded WinMD file.
pub const FileEntry = struct {
    path: []const u8,
    raw_data: []const u8,
    table_info: tables.Info,
    heaps: streams.Heaps,
};

/// List of TypeLocations (same name may appear in multiple files).
pub const LocList = std.ArrayListUnmanaged(TypeLocation);

/// Inner map: type name (backtick-stripped) -> list of locations.
pub const NameMap = std.StringHashMapUnmanaged(LocList);

// ---------------------------------------------------------------------------
// loadWinMD
// ---------------------------------------------------------------------------

pub const LoadError = pe.PeError || metadata_mod.MetadataError || tables.TableError || error{MissingStream};

/// Read a WinMD file from disk and return a FileEntry with parsed tables and heaps.
pub fn loadWinMD(allocator: std.mem.Allocator, path: []const u8) LoadError!FileEntry {
    const data = std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024 * 1024) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Truncated,
    };

    const pe_info = try pe.parse(allocator, data);
    const md_info = try metadata_mod.parse(allocator, pe_info);

    const table_stream = md_info.getStream("#~") orelse
        md_info.getStream("#-") orelse
        return error.MissingStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStream;
    const blob_stream = md_info.getStream("#Blob") orelse return error.MissingStream;
    const guid_stream = md_info.getStream("#GUID");

    const table_info = try tables.parse(table_stream.data);

    const heaps = streams.Heaps{
        .strings = strings_stream.data,
        .blob = blob_stream.data,
        .guid = if (guid_stream) |gs| gs.data else &.{},
    };

    return FileEntry{
        .path = path,
        .raw_data = data,
        .table_info = table_info,
        .heaps = heaps,
    };
}

// ---------------------------------------------------------------------------
// UnifiedIndex  —  two-level HashMap (namespace -> name -> Vec<TypeLocation>)
// ---------------------------------------------------------------------------

pub const UnifiedIndex = struct {
    /// Owned copy of the file entries (index owns them, like windows-rs Vec<File>).
    files: []const FileEntry,
    /// namespace -> { name -> [TypeLocation, ...] }
    /// Keys are owned copies (like windows-rs String keys).
    types: std.StringHashMapUnmanaged(NameMap),
    /// (file_idx << 32 | outer_row) -> [inner_row, ...]
    nested: std.AutoHashMapUnmanaged(u48, std.ArrayListUnmanaged(u32)),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *UnifiedIndex) void {
        // Free owned keys and inner structures
        var ns_it = self.types.iterator();
        while (ns_it.next()) |ns_entry| {
            var name_map = ns_entry.value_ptr;
            var name_it = name_map.iterator();
            while (name_it.next()) |name_entry| {
                self.allocator.free(name_entry.key_ptr.*);
                name_entry.value_ptr.deinit(self.allocator);
            }
            name_map.deinit(self.allocator);
            self.allocator.free(ns_entry.key_ptr.*);
        }
        self.types.deinit(self.allocator);
        // Free nested lists
        var nested_it = self.nested.iterator();
        while (nested_it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.nested.deinit(self.allocator);
        // Free owned files array
        self.allocator.free(self.files);
    }

    /// Build a unified index. Takes ownership of `files` by copying the slice.
    /// Walks every TypeDef and NestedClass in every file.
    /// Same name in multiple files → all locations are kept (Vec).
    /// Errors are propagated — never silently swallowed.
    pub fn init(allocator: std.mem.Allocator, files: []const FileEntry) !UnifiedIndex {
        // Own the files (like windows-rs Vec<File>)
        const owned_files = try allocator.dupe(FileEntry, files);
        errdefer allocator.free(owned_files);

        var types = std.StringHashMapUnmanaged(NameMap){};
        errdefer deinitTypes(allocator, &types);
        var nested_map = std.AutoHashMapUnmanaged(u48, std.ArrayListUnmanaged(u32)){};
        errdefer deinitNested(allocator, &nested_map);

        for (owned_files, 0..) |file, fi| {
            const file_idx: u16 = @intCast(fi);

            // --- TypeDef registration ---
            const td_table = file.table_info.getTable(.TypeDef);
            if (td_table.present) {
                var row: u32 = 1;
                while (row <= td_table.row_count) : (row += 1) {
                    const td = try file.table_info.readTypeDef(row);
                    const raw_ns = try file.heaps.getString(td.type_namespace);
                    const raw_name = try file.heaps.getString(td.type_name);

                    // Skip <Module> and nested types (empty namespace)
                    if (raw_ns.len == 0) continue;

                    const name = stripTick(raw_name);
                    if (name.len == 0) continue;

                    const loc = TypeLocation{ .file_idx = file_idx, .row = row };

                    // Two-level insert: types[namespace][name].append(loc)
                    // Keys are owned copies (like windows-rs to_string())
                    const ns_gop = try types.getOrPut(allocator, raw_ns);
                    if (!ns_gop.found_existing) {
                        const owned_ns = try allocator.dupe(u8, raw_ns);
                        ns_gop.key_ptr.* = owned_ns;
                        ns_gop.value_ptr.* = NameMap{};
                    }
                    const name_gop = try ns_gop.value_ptr.getOrPut(allocator, name);
                    if (!name_gop.found_existing) {
                        const owned_name = try allocator.dupe(u8, name);
                        name_gop.key_ptr.* = owned_name;
                        name_gop.value_ptr.* = LocList{};
                    }
                    try name_gop.value_ptr.append(allocator, loc);
                }
            }

            // --- NestedClass registration ---
            const nc_table = file.table_info.getTable(.NestedClass);
            if (nc_table.present) {
                var nc_row: u32 = 1;
                while (nc_row <= nc_table.row_count) : (nc_row += 1) {
                    const nc = try file.table_info.readNestedClass(nc_row);
                    const outer_key = (@as(u48, file_idx) << 32) | nc.enclosing_class;
                    const gop = try nested_map.getOrPut(allocator, outer_key);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = std.ArrayListUnmanaged(u32){};
                    }
                    try gop.value_ptr.append(allocator, nc.nested_class);
                }
            }
        }

        return UnifiedIndex{
            .files = owned_files,
            .types = types,
            .nested = nested_map,
            .allocator = allocator,
        };
    }

    fn deinitTypes(allocator: std.mem.Allocator, types: *std.StringHashMapUnmanaged(NameMap)) void {
        var ns_it = types.iterator();
        while (ns_it.next()) |ns_entry| {
            var name_it = ns_entry.value_ptr.iterator();
            while (name_it.next()) |name_entry| {
                allocator.free(name_entry.key_ptr.*);
                name_entry.value_ptr.deinit(allocator);
            }
            ns_entry.value_ptr.deinit(allocator);
            allocator.free(ns_entry.key_ptr.*);
        }
        types.deinit(allocator);
    }

    fn deinitNested(allocator: std.mem.Allocator, nested: *std.AutoHashMapUnmanaged(u48, std.ArrayListUnmanaged(u32))) void {
        var it = nested.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        nested.deinit(allocator);
    }

    // ----- Lookup API (windows-rs equivalent) -----

    /// Get all locations for a (namespace, name) pair.
    /// Returns empty slice if not found.
    pub fn get(self: *const UnifiedIndex, namespace: []const u8, name: []const u8) []const TypeLocation {
        const ns_map = self.types.get(namespace) orelse return &.{};
        const stripped = stripTick(name);
        const list = ns_map.get(stripped) orelse return &.{};
        return list.items;
    }

    /// Get the single location for (namespace, name). Panics if zero or multiple matches.
    pub fn expect(self: *const UnifiedIndex, namespace: []const u8, name: []const u8) TypeLocation {
        const locs = self.get(namespace, name);
        if (locs.len == 0) std.debug.panic("type not found: {s}.{s}", .{ namespace, name });
        if (locs.len > 1) std.debug.panic("more than one type found: {s}.{s}", .{ namespace, name });
        return locs[0];
    }

    /// Check whether a namespace exists.
    pub fn containsNamespace(self: *const UnifiedIndex, namespace: []const u8) bool {
        return self.types.contains(namespace);
    }

    /// Get nested types for a given outer type. Returns TypeLocations
    /// (same file as the outer type, since nested types are file-local).
    pub fn getNested(self: *const UnifiedIndex, allocator: std.mem.Allocator, loc: TypeLocation) ![]const TypeLocation {
        const key = (@as(u48, loc.file_idx) << 32) | loc.row;
        const rows = self.nested.get(key) orelse return &.{};
        const result = try allocator.alloc(TypeLocation, rows.items.len);
        for (rows.items, 0..) |inner_row, i| {
            result[i] = .{ .file_idx = loc.file_idx, .row = inner_row };
        }
        return result;
    }

    // ----- Compatibility API (used by existing callers) -----

    /// Look up a type by fully-qualified name ("Namespace.TypeName").
    /// Returns the first match (primary file wins since files are loaded in order).
    pub fn findByFullName(self: *const UnifiedIndex, full_name: []const u8) ?TypeLocation {
        const stripped = stripTick(full_name);
        // Split "Namespace.Name" on the last dot
        if (std.mem.lastIndexOfScalar(u8, stripped, '.')) |dot| {
            const ns = stripped[0..dot];
            const name = stripped[dot + 1 ..];
            const locs = self.get(ns, name);
            return if (locs.len > 0) locs[0] else null;
        } else {
            // No dot — try as short name
            return self.findByShortName(stripped);
        }
    }

    /// Look up a type by its short (unqualified) name.
    /// Scans all namespaces and returns the match from the lowest file_idx (primary wins).
    pub fn findByShortName(self: *const UnifiedIndex, short_name: []const u8) ?TypeLocation {
        const stripped = stripTick(short_name);
        var best: ?TypeLocation = null;
        var ns_it = self.types.iterator();
        while (ns_it.next()) |ns_entry| {
            if (ns_entry.value_ptr.get(stripped)) |list| {
                if (list.items.len > 0) {
                    const candidate = list.items[0];
                    if (best == null or candidate.file_idx < best.?.file_idx) {
                        best = candidate;
                    }
                }
            }
        }
        return best;
    }

    /// Resolve a TypeRef row from `file` into a TypeLocation.
    /// Uses namespace + name from the TypeRef to look up directly in the two-level map.
    pub fn resolveTypeRef(self: *const UnifiedIndex, file: *const FileEntry, type_ref_row: u32) ?TypeLocation {
        const tr = file.table_info.readTypeRef(type_ref_row) catch return null;
        const raw_name = file.heaps.getString(tr.type_name) catch return null;
        const raw_ns = file.heaps.getString(tr.type_namespace) catch return null;
        const name = stripTick(raw_name);
        const locs = self.get(raw_ns, name);
        return if (locs.len > 0) locs[0] else null;
    }

    /// Resolve a decoded TypeDefOrRef coded index to a TypeLocation.
    pub fn resolveTypeDefOrRef(self: *const UnifiedIndex, file: *const FileEntry, tdor: coded.Decoded) ?TypeLocation {
        switch (tdor.table) {
            .TypeDef => {
                for (self.files, 0..) |*f, i| {
                    if (f == file) return TypeLocation{ .file_idx = @intCast(i), .row = tdor.row };
                }
                return null;
            },
            .TypeRef => {
                return self.resolveTypeRef(file, tdor.row);
            },
            .TypeSpec => {
                const ts = file.table_info.readTypeSpec(tdor.row) catch return null;
                const blob = file.heaps.getBlob(ts.signature) catch return null;
                if (blob.len == 0) return null;
                const lead = blob[0];
                if (lead == 0x11 or lead == 0x12) {
                    const cu = streams.decodeCompressedUInt(blob[1..]) catch return null;
                    const inner = coded.decodeTypeDefOrRef(@intCast(cu.value)) catch return null;
                    return self.resolveTypeDefOrRef(file, inner);
                } else if (lead == 0x15) {
                    if (blob.len < 3) return null;
                    const cu = streams.decodeCompressedUInt(blob[2..]) catch return null;
                    const inner = coded.decodeTypeDefOrRef(@intCast(cu.value)) catch return null;
                    return self.resolveTypeDefOrRef(file, inner);
                }
                return null;
            },
            else => return null,
        }
    }

    /// Return the FileEntry for the given location.
    pub fn fileOf(self: *const UnifiedIndex, loc: TypeLocation) *const FileEntry {
        return &self.files[loc.file_idx];
    }

    /// Read the TypeDefRow at the given location.
    pub fn readTypeDef(self: *const UnifiedIndex, loc: TypeLocation) !tables.TypeDefRow {
        return self.files[loc.file_idx].table_info.readTypeDef(loc.row);
    }

    /// Allocate a "Namespace.TypeName" string for the type at `loc`.
    pub fn typeFullNameAlloc(self: *const UnifiedIndex, allocator: std.mem.Allocator, loc: TypeLocation) ![]u8 {
        const file = self.files[loc.file_idx];
        const td = try file.table_info.readTypeDef(loc.row);
        const raw_name = try file.heaps.getString(td.type_name);
        const raw_ns = try file.heaps.getString(td.type_namespace);
        const name = stripTick(raw_name);
        const ns = raw_ns;

        if (ns.len > 0) {
            const buf = try allocator.alloc(u8, ns.len + 1 + name.len);
            @memcpy(buf[0..ns.len], ns);
            buf[ns.len] = '.';
            @memcpy(buf[ns.len + 1 ..], name);
            return buf;
        } else {
            const buf = try allocator.alloc(u8, name.len);
            @memcpy(buf, name);
            return buf;
        }
    }

    /// Iterate all types across all namespaces.
    /// Returns (namespace, name, TypeLocation) triples — same as windows-rs iter().
    pub fn allTypes(self: *const UnifiedIndex) TypeIterator {
        return TypeIterator.init(self);
    }

    /// Check whether (namespace, name) exists.
    pub fn contains(self: *const UnifiedIndex, namespace: []const u8, name: []const u8) bool {
        return self.get(namespace, name).len > 0;
    }
};

/// Iterator over all (namespace, name, TypeLocation) triples.
pub const TypeEntry = struct {
    namespace: []const u8,
    name: []const u8,
    loc: TypeLocation,
};

pub const TypeIterator = struct {
    ns_iter: std.StringHashMapUnmanaged(NameMap).Iterator,
    current_ns: ?[]const u8,
    current_name: ?[]const u8,
    name_iter: ?std.StringHashMapUnmanaged(LocList).Iterator,
    current_locs: ?[]const TypeLocation,
    loc_pos: usize,

    fn init(index: *const UnifiedIndex) TypeIterator {
        var it: TypeIterator = .{
            .ns_iter = index.types.iterator(),
            .current_ns = null,
            .current_name = null,
            .name_iter = null,
            .current_locs = null,
            .loc_pos = 0,
        };
        it.advanceToValid();
        return it;
    }

    fn advanceToValid(self: *TypeIterator) void {
        // Try advancing within current locs
        if (self.current_locs) |locs| {
            if (self.loc_pos < locs.len) return; // already valid
        }
        // Advance to next name
        while (true) {
            if (self.name_iter) |*ni| {
                if (ni.next()) |name_entry| {
                    self.current_name = name_entry.key_ptr.*;
                    self.current_locs = name_entry.value_ptr.items;
                    self.loc_pos = 0;
                    if (name_entry.value_ptr.items.len > 0) return;
                    continue;
                }
            }
            // Advance to next namespace
            if (self.ns_iter.next()) |ns_entry| {
                self.current_ns = ns_entry.key_ptr.*;
                self.name_iter = ns_entry.value_ptr.iterator();
                continue;
            }
            // Exhausted
            self.current_locs = null;
            return;
        }
    }

    pub fn next(self: *TypeIterator) ?TypeEntry {
        if (self.current_locs == null) return null;
        const locs = self.current_locs.?;
        if (self.loc_pos >= locs.len) return null;

        const entry = TypeEntry{
            .namespace = self.current_ns.?,
            .name = self.current_name.?,
            .loc = locs[self.loc_pos],
        };
        self.loc_pos += 1;
        if (self.loc_pos >= locs.len) {
            self.advanceToValid();
        }
        return entry;
    }
};

// ---------------------------------------------------------------------------
// DependencyQueue
// ---------------------------------------------------------------------------

pub const DependencyQueue = struct {
    index: *const UnifiedIndex,
    /// Dedup by short type name — since output uses short names, each name must appear once.
    seen_names: std.StringHashMapUnmanaged(void),
    queue: std.ArrayListUnmanaged(TypeLocation),
    head: usize = 0,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DependencyQueue) void {
        var it = self.seen_names.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.seen_names.deinit(self.allocator);
        self.queue.deinit(self.allocator);
    }

    pub fn init(allocator: std.mem.Allocator, index: *const UnifiedIndex) DependencyQueue {
        return .{
            .index = index,
            .seen_names = .{},
            .queue = .{},
            .head = 0,
            .allocator = allocator,
        };
    }

    pub fn enqueue(self: *DependencyQueue, loc: TypeLocation) !void {
        // Read the short type name for dedup (output uses short names).
        const file = self.index.fileOf(loc);
        const td = file.table_info.readTypeDef(loc.row) catch return;
        const raw_name = file.heaps.getString(td.type_name) catch return;
        const short = stripTick(raw_name);
        if (short.len == 0) return;

        if (self.seen_names.contains(short)) return;

        const owned = try self.allocator.dupe(u8, short);
        errdefer self.allocator.free(owned);
        try self.seen_names.put(self.allocator, owned, {});
        try self.queue.append(self.allocator, loc);
    }

    /// Resolve a type name and enqueue it.
    /// Handles "Namespace.Type", short names, and pointer/optional prefixes.
    pub fn registerByName(self: *DependencyQueue, name: []const u8) !void {
        // Strip pointer/optional prefixes: * ? []
        var stripped = name;
        while (stripped.len > 0) {
            if (stripped[0] == '*' or stripped[0] == '?' or stripped[0] == '[') {
                if (stripped[0] == '[') {
                    if (std.mem.indexOfScalar(u8, stripped, ']')) |idx| {
                        stripped = stripped[idx + 1 ..];
                    } else {
                        stripped = stripped[1..];
                    }
                } else {
                    stripped = stripped[1..];
                }
            } else break;
        }
        if (stripped.len == 0) return;

        // Skip builtin / prologue types
        const builtin_types = [_][]const u8{
            "void",      "bool",      "anyopaque",   "?*anyopaque",
            "GUID",      "HSTRING",   "isize",       "usize",
            "u8",        "i8",        "u16",         "i16",
            "u32",       "i32",       "u64",         "i64",
            "f32",       "f64",       "HWND",        "HANDLE",
            "HINSTANCE", "HMODULE",   "BOOL",        "WPARAM",
            "LPARAM",    "LPCWSTR",   "LPWSTR",      "HRESULT",
            "POINT",     "RECT",
        };
        for (builtin_types) |bt| {
            if (std.mem.eql(u8, stripped, bt)) return;
        }

        const dot = std.mem.lastIndexOfScalar(u8, stripped, '.');
        const short = if (dot) |d| stripped[d + 1 ..] else stripped;
        if (short.len == 0) return;

        // Skip well-known COM/WinRT base types and generic-tick types
        if (std.mem.eql(u8, short, "EventRegistrationToken")) return;
        if (std.mem.eql(u8, short, "IInspectable")) return;
        if (std.mem.eql(u8, short, "IUnknown")) return;
        if (std.mem.indexOfScalar(u8, stripped, '`') != null) return;

        // Must start with uppercase letter
        if (short[0] < 'A' or short[0] > 'Z') return;

        // Try full name first, then short name
        if (self.index.findByFullName(stripped)) |loc| {
            try self.enqueue(loc);
        } else if (self.index.findByShortName(short)) |loc| {
            try self.enqueue(loc);
        }
    }

    pub fn next(self: *DependencyQueue) ?TypeLocation {
        if (self.head >= self.queue.items.len) return null;
        const loc = self.queue.items[self.head];
        self.head += 1;
        return loc;
    }
};

// ---------------------------------------------------------------------------
// UnifiedContext
// ---------------------------------------------------------------------------

pub const UnifiedContext = struct {
    index: *const UnifiedIndex,
    loc: TypeLocation,
    dep_queue: *DependencyQueue,
    allocator: std.mem.Allocator,

    // Direct access — matches old Context field names
    table_info: tables.Info,
    heaps: streams.Heaps,

    pub fn make(
        index: *const UnifiedIndex,
        loc: TypeLocation,
        dep_queue: *DependencyQueue,
        allocator: std.mem.Allocator,
    ) UnifiedContext {
        const f = index.fileOf(loc);
        return .{
            .index = index,
            .loc = loc,
            .dep_queue = dep_queue,
            .allocator = allocator,
            .table_info = f.table_info,
            .heaps = f.heaps,
        };
    }

    pub fn file(self: UnifiedContext) *const FileEntry {
        return self.index.fileOf(self.loc);
    }

    pub fn registerDependency(self: UnifiedContext, _: std.mem.Allocator, name: []const u8) !void {
        try self.dep_queue.registerByName(name);
    }

    /// Empty companions — unified index removes the need.
    pub const companions: []const FileEntry = &.{};
};
