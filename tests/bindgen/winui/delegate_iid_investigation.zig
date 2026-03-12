/// Verified: non-generic delegate IIDs come directly from the WinMD GuidAttribute.
/// No pinterface computation is needed for non-generic delegates.
const std = @import("std");
const support = @import("test_support");
const ctx_mod = support.context;
const guidmod = ctx_mod.winmd2zig.guidmod;
const nav = ctx_mod.winmd2zig.nav;

fn getMetadataGuidForDelegate(_: std.mem.Allocator, delegate_name: []const u8) !guidmod.Guid {
    const xaml = try support.winui.ensureXamlCtx();
    const uctx = xaml.emitCtx();
    const row = try ctx_mod.findTypeByShortName(uctx, delegate_name) orelse return error.TypeNotFound;
    const guid_blob = try nav.extractGuid(uctx, row);
    return guidmod.Guid.fromBlob(guid_blob);
}

test "non-generic delegate IIDs: metadata GUID is the correct runtime IID" {
    const alloc = std.testing.allocator;

    // For non-generic delegates, the metadata GuidAttribute IS the runtime IID.
    // No delegate({guid}) pinterface computation is needed.
    const delegates = [_]struct { name: []const u8, expected_iid: []const u8 }{
        .{ .name = "RoutedEventHandler", .expected_iid = "dae23d85-69ca-5bdf-805b-6161a3a215cc" },
        .{ .name = "SizeChangedEventHandler", .expected_iid = "8d7b1a58-14c6-51c9-892c-9fcce368e77d" },
        .{ .name = "SelectionChangedEventHandler", .expected_iid = "a232390d-0e34-595e-8931-fa928a9909f4" },
    };

    for (delegates) |d| {
        const metadata_guid = getMetadataGuidForDelegate(alloc, d.name) catch |e| {
            if (e == error.SkipZigTest) return e;
            return e;
        };
        const metadata_str = try metadata_guid.toDashedLowerAlloc(alloc);
        defer alloc.free(metadata_str);

        // Verify delegateIid returns the same GUID
        const runtime_iid = try guidmod.delegateIid(metadata_guid, alloc);
        const runtime_str = try runtime_iid.toDashedLowerAlloc(alloc);
        defer alloc.free(runtime_str);

        try std.testing.expectEqualStrings(d.expected_iid, metadata_str);
        try std.testing.expectEqualStrings(d.expected_iid, runtime_str);
    }
}
