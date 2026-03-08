// NOTE: Fallback module used when ../win-zig-metadata/ directory is not available.
// build.zig prefers the sibling win-zig-metadata package when present.
pub const coded_index = @import("coded_index.zig");
pub const pe = @import("pe.zig");
pub const streams = @import("streams.zig");
pub const tables = @import("tables.zig");
pub const metadata = @import("metadata.zig");

