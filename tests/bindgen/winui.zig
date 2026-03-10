// WinUI test umbrella — aggregates all WinUI probe tests into one binary
// so they share cached WinMD contexts.
comptime {
    _ = @import("winui/type_resolution.zig");
    _ = @import("winui/delegate.zig");
    _ = @import("winui/shape.zig");
    _ = @import("winui/value_types.zig");
    _ = @import("winui/canary.zig");
}
