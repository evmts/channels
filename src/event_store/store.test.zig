const std = @import("std");
const testing = std.testing;
const EventStore = @import("store.zig").EventStore;
const EventOffset = @import("store.zig").EventOffset;
const Event = @import("events.zig").Event;
const ObjectiveCreatedEvent = @import("events.zig").ObjectiveCreatedEvent;

/// Test helper: create a test event with given ID
fn makeTestEvent(id: u32) Event {
    var obj_id: [32]u8 = undefined;
    std.mem.writeInt(u32, obj_id[0..4], id, .little);

    var chan_id: [32]u8 = undefined;
    std.mem.writeInt(u32, chan_id[0..4], id, .little);

    return Event{
        .objective_created = .{
            .timestamp_ms = @intCast(std.time.milliTimestamp()),
            .objective_id = obj_id,
            .objective_type = .DirectFund,
            .channel_id = chan_id,
            .participants = &[_][20]u8{},
        },
    };
}

test "EventStore: init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    try testing.expectEqual(@as(EventOffset, 0), store.len());
}

test "EventStore: append single event" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    const event = makeTestEvent(1);
    const offset = try store.append(event);

    try testing.expectEqual(@as(EventOffset, 0), offset);
    try testing.expectEqual(@as(EventOffset, 1), store.len());
}

test "EventStore: append multiple events" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const event = makeTestEvent(i);
        const offset = try store.append(event);
        try testing.expectEqual(@as(EventOffset, i), offset);
    }

    try testing.expectEqual(@as(EventOffset, 100), store.len());
}

test "EventStore: readAt single event" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    const event = makeTestEvent(42);
    const offset = try store.append(event);

    const read_event = try store.readAt(offset);
    try testing.expectEqual(Event.objective_created, std.meta.activeTag(read_event.*));
}

test "EventStore: readAt out of bounds" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    const result = store.readAt(0);
    try testing.expectError(error.OffsetOutOfBounds, result);
}

test "EventStore: readRange" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    // Append 10 events
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        _ = try store.append(makeTestEvent(i));
    }

    // Read events 3-7
    const events = try store.readRange(3, 7);
    defer allocator.free(events);

    try testing.expectEqual(@as(usize, 4), events.len);
}

test "EventStore: readRange invalid" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    _ = try store.append(makeTestEvent(1));

    // Start >= end
    try testing.expectError(error.InvalidRange, store.readRange(5, 5));
    // End > length
    try testing.expectError(error.InvalidRange, store.readRange(0, 10));
}

test "EventStore: readAll" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    // Empty store
    const empty = try store.readAll();
    try testing.expectEqual(@as(usize, 0), empty.len);

    // Append some events
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        _ = try store.append(makeTestEvent(i));
    }

    const events = try store.readAll();
    defer allocator.free(events);
    try testing.expectEqual(@as(usize, 5), events.len);
}

test "EventStore: subscriber receives events" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    const S = struct {
        var received_count: usize = 0;
        var last_offset: EventOffset = 0;

        fn callback(event: Event, offset: EventOffset) void {
            _ = event;
            received_count += 1;
            last_offset = offset;
        }
    };

    _ = try store.subscribe(S.callback);

    _ = try store.append(makeTestEvent(1));
    _ = try store.append(makeTestEvent(2));

    try testing.expectEqual(@as(usize, 2), S.received_count);
    try testing.expectEqual(@as(EventOffset, 1), S.last_offset);
}

test "EventStore: multiple subscribers" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    const S = struct {
        var count1: usize = 0;
        var count2: usize = 0;

        fn callback1(event: Event, offset: EventOffset) void {
            _ = event;
            _ = offset;
            count1 += 1;
        }

        fn callback2(event: Event, offset: EventOffset) void {
            _ = event;
            _ = offset;
            count2 += 1;
        }
    };

    _ = try store.subscribe(S.callback1);
    _ = try store.subscribe(S.callback2);

    _ = try store.append(makeTestEvent(1));

    try testing.expectEqual(@as(usize, 1), S.count1);
    try testing.expectEqual(@as(usize, 1), S.count2);
}

test "EventStore: pointer stability after multiple appends" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    // Append first event and keep pointer
    _ = try store.append(makeTestEvent(1));
    const first_event = try store.readAt(0);

    // Append many more events (trigger multiple segment allocations)
    var i: u32 = 0;
    while (i < 2000) : (i += 1) {
        _ = try store.append(makeTestEvent(i + 2));
    }

    // Original pointer should still be valid (SegmentedList stable pointers)
    const first_event_again = try store.readAt(0);
    try testing.expectEqual(first_event, first_event_again);
}

test "EventStore: concurrent appends" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    const S = struct {
        fn appendMany(s: *EventStore, count: usize, wg: *std.Thread.WaitGroup) void {
            defer wg.finish();
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                // Thread.Pool.spawn requires infallible callbacks, so we use unreachable
                // In tests, allocation failures would cause test framework to report failure anyway
                _ = s.append(makeTestEvent(i)) catch unreachable;
            }
        }
    };

    var wg: std.Thread.WaitGroup = .{};
    const num_threads = 10;
    const appends_per_thread = 100;

    var t: usize = 0;
    while (t < num_threads) : (t += 1) {
        wg.start();
        try pool.spawn(S.appendMany, .{ store, appends_per_thread, &wg });
    }

    pool.waitAndWork(&wg);

    // All appends should succeed
    const expected_total = num_threads * appends_per_thread;
    try testing.expectEqual(@as(EventOffset, expected_total), store.len());
}

test "EventStore: concurrent reads during appends" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    // Pre-populate with some events
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        _ = try store.append(makeTestEvent(i));
    }

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    const S = struct {
        fn reader(s: *EventStore, wg: *std.Thread.WaitGroup) void {
            defer wg.finish();
            var j: usize = 0;
            while (j < 100) : (j += 1) {
                const current_len = s.len();
                if (current_len > 0) {
                    _ = s.readAt(@intCast(j % current_len)) catch unreachable;
                }
            }
        }

        fn writer(s: *EventStore, wg: *std.Thread.WaitGroup) void {
            defer wg.finish();
            var j: u32 = 0;
            while (j < 50) : (j += 1) {
                _ = s.append(makeTestEvent(j + 1000)) catch unreachable;
            }
        }
    };

    var wg: std.Thread.WaitGroup = .{};

    // Start readers and writers
    var t: usize = 0;
    while (t < 5) : (t += 1) {
        wg.start();
        try pool.spawn(S.reader, .{ store, &wg });
        wg.start();
        try pool.spawn(S.writer, .{ store, &wg });
    }

    pool.waitAndWork(&wg);

    // Verify final count
    try testing.expectEqual(@as(EventOffset, 100 + 5 * 50), store.len());
}
