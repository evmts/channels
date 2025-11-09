const std = @import("std");
const events = @import("events.zig");
const testing = std.testing;

const Event = events.Event;

test "Event union - basic construction" {
    const obj_id = [_]u8{0xaa} ** 32;
    const event = Event{
        .objective_created = .{
            .event_version = 1,
            .timestamp_ms = 1704067200000,
            .objective_id = obj_id,
            .objective_type = .DirectFund,
            .channel_id = [_]u8{0xbb} ** 32,
            .participants = &[_][20]u8{},
        },
    };

    try testing.expectEqual(std.meta.Tag(Event).objective_created, @as(std.meta.Tag(Event), event));
}

test "Event union - all 20 event types exist" {
    // Verify all event types from Phase 1a are present (20 total)
    const type_info = @typeInfo(Event);
    const field_count = switch (type_info) {
        .@"union" => |u| u.fields.len,
        else => @compileError("Event should be a union type"),
    };
    try testing.expectEqual(20, field_count);

    // Spot check that key event tags exist
    const has_objective_created = @hasField(Event, "objective_created");
    const has_state_signed = @hasField(Event, "state_signed");
    const has_channel_finalized = @hasField(Event, "channel_finalized");

    try testing.expect(has_objective_created);
    try testing.expect(has_state_signed);
    try testing.expect(has_channel_finalized);
}
