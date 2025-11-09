//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

// Event store modules
pub const event_store = struct {
    pub const events = @import("event_store/events.zig");
    pub const id = @import("event_store/id.zig");
    pub const store = @import("event_store/store.zig");
    pub const reconstructor = @import("event_store/reconstructor.zig");
    pub const snapshots = @import("event_store/snapshots.zig");
};

// State modules
pub const state = struct {
    pub const types = @import("state/types.zig");
    pub const channel_id = @import("state/channel_id.zig");
};

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

// Import all tests
test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("event_store/events.test.zig");
    _ = @import("event_store/id.zig");
    _ = @import("event_store/store.test.zig");
    _ = @import("event_store/reconstructor.test.zig");
    _ = @import("event_store/snapshots.test.zig");
    _ = @import("event_store/integration.test.zig");
    _ = @import("state/types.test.zig");
    _ = @import("state/channel_id.test.zig");
}
