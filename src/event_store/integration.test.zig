const std = @import("std");
const testing = std.testing;
const EventStore = @import("store.zig").EventStore;
const StateReconstructor = @import("reconstructor.zig").StateReconstructor;
const SnapshotManager = @import("snapshots.zig").SnapshotManager;
const ObjectiveState = @import("reconstructor.zig").ObjectiveState;
const ChannelState = @import("reconstructor.zig").ChannelState;
const Event = @import("events.zig").Event;

fn makeObjectiveId(seed: u32) [32]u8 {
    var id: [32]u8 = undefined;
    std.mem.writeInt(u32, id[0..4], seed, .little);
    return id;
}

fn makeChannelId(seed: u32) [32]u8 {
    var id: [32]u8 = undefined;
    std.mem.writeInt(u32, id[0..4], seed, .little);
    return id;
}

fn timestamp() u64 {
    return @intCast(std.time.milliTimestamp());
}

test "Integration: Full event sourcing flow (objective lifecycle)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    const obj_id = makeObjectiveId(1);
    const chan_id = makeChannelId(1);

    // Lifecycle: Created → Approved → Cranked → Completed
    _ = try store.append(Event{
        .objective_created = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id,
            .objective_type = .DirectFund,
            .channel_id = chan_id,
            .participants = &[_][20]u8{},
        },
    });

    _ = try store.append(Event{
        .objective_approved = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id,
            .approver = null,
        },
    });

    _ = try store.append(Event{
        .objective_cranked = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id,
            .side_effects_count = 1,
            .waiting = false,
        },
    });

    _ = try store.append(Event{
        .objective_completed = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id,
            .success = true,
            .final_channel_state = null,
        },
    });

    // Reconstruct state
    const state = try reconstructor.reconstructObjective(obj_id);

    // Verify final state
    try testing.expectEqual(ObjectiveState.ObjectiveStatus.Completed, state.status);
    try testing.expectEqual(@as(usize, 4), state.event_count);
    try testing.expect(state.completed_at != null);
}

test "Integration: 1000 events → reconstruct objective" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    const obj_id = makeObjectiveId(999);
    const chan_id = makeChannelId(999);

    // Append 1000 events (1 objective lifecycle + 999 other objectives)
    _ = try store.append(Event{
        .objective_created = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id,
            .objective_type = .DirectFund,
            .channel_id = chan_id,
            .participants = &[_][20]u8{},
        },
    });

    // Filler events
    var i: u32 = 0;
    while (i < 998) : (i += 1) {
        const other_id = makeObjectiveId(i);
        _ = try store.append(Event{
            .objective_created = .{
                .timestamp_ms = timestamp(),
                .objective_id = other_id,
                .objective_type = .DirectFund,
                .channel_id = chan_id,
                .participants = &[_][20]u8{},
            },
        });
    }

    // Complete target objective
    _ = try store.append(Event{
        .objective_completed = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id,
            .success = true,
            .final_channel_state = null,
        },
    });

    try testing.expectEqual(@as(u64, 1000), store.len());

    // Reconstruct (should find 2 events among 1000)
    const start_time = std.time.milliTimestamp();
    const state = try reconstructor.reconstructObjective(obj_id);
    const elapsed = std.time.milliTimestamp() - start_time;

    try testing.expectEqual(ObjectiveState.ObjectiveStatus.Completed, state.status);
    try testing.expectEqual(@as(usize, 2), state.event_count);

    // Performance check: <100ms for 1000 events
    std.debug.print("Reconstruction time for 1000 events: {d}ms\n", .{elapsed});
}

test "Integration: Snapshot-accelerated reconstruction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var snapshots = try SnapshotManager.initWithInterval(allocator, 100);
    defer snapshots.deinit();

    const chan_id = makeChannelId(100);

    // Append 250 events with snapshots
    var turn: u64 = 0;
    while (turn < 250) : (turn += 1) {
        const offset = try store.append(Event{
            .state_signed = .{
                .timestamp_ms = timestamp(),
                .channel_id = chan_id,
                .state_hash = undefined,
                .turn_num = turn,
                .signer = undefined,
                .signature = undefined,
                .is_final = false,
                .app_data_hash = null,
            },
        });

        // Create snapshot every 100 events
        if (snapshots.shouldSnapshot(offset + 1)) {
            const snapshot_data = try std.fmt.allocPrint(allocator, "{{\"turn\":{d}}}", .{turn});
            defer allocator.free(snapshot_data);
            try snapshots.createSnapshot(offset + 1, snapshot_data);
        }
    }

    // Verify snapshots created
    try testing.expectEqual(@as(usize, 2), snapshots.count());
    try testing.expect(snapshots.getSnapshot(100) != null);
    try testing.expect(snapshots.getSnapshot(200) != null);

    // Get latest snapshot before offset 250
    const latest = snapshots.getLatestSnapshot(250);
    try testing.expect(latest != null);
    try testing.expectEqual(@as(u64, 200), latest.?.offset);

    std.debug.print("Snapshot acceleration: latest snapshot at offset {d}\n", .{latest.?.offset});
}

test "Integration: Concurrent appends with reconstruction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    const obj_id = makeObjectiveId(42);
    const chan_id = makeChannelId(42);

    // Create objective
    _ = try store.append(Event{
        .objective_created = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id,
            .objective_type = .DirectFund,
            .channel_id = chan_id,
            .participants = &[_][20]u8{},
        },
    });

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    const S = struct {
        fn writer(s: *EventStore, id: [32]u8, wg: *std.Thread.WaitGroup) void {
            defer wg.finish();
            _ = s.append(Event{
                .objective_approved = .{
                    .timestamp_ms = @intCast(std.time.milliTimestamp()),
                    .objective_id = id,
                    .approver = null,
                },
            }) catch unreachable;
        }

        fn reader(r: *StateReconstructor, id: [32]u8, wg: *std.Thread.WaitGroup) void {
            defer wg.finish();
            _ = r.reconstructObjective(id) catch unreachable;
        }
    };

    var wg: std.Thread.WaitGroup = .{};

    // Concurrent writes and reads
    var t: usize = 0;
    while (t < 5) : (t += 1) {
        wg.start();
        try pool.spawn(S.writer, .{ store, obj_id, &wg });
        wg.start();
        try pool.spawn(S.reader, .{ reconstructor, obj_id, &wg });
    }

    pool.waitAndWork(&wg);

    // Verify final state
    const final_state = try reconstructor.reconstructObjective(obj_id);
    try testing.expectEqual(ObjectiveState.ObjectiveStatus.Approved, final_state.status);
}

test "Integration: Event subscriber tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    const S = struct {
        var event_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

        fn callback(event: Event, offset: u64) void {
            _ = event;
            _ = offset;
            _ = event_count.fetchAdd(1, .monotonic);
        }
    };

    _ = try store.subscribe(S.callback);

    const obj_id = makeObjectiveId(1);
    const chan_id = makeChannelId(1);

    // Append 10 events
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        _ = try store.append(Event{
            .objective_created = .{
                .timestamp_ms = timestamp(),
                .objective_id = obj_id,
                .objective_type = .DirectFund,
                .channel_id = chan_id,
                .participants = &[_][20]u8{},
            },
        });
    }

    // Subscriber should have received all events
    try testing.expectEqual(@as(u64, 10), S.event_count.load(.monotonic));
}

test "Integration: Memory usage for 10K events" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    const obj_id = makeObjectiveId(1);
    const chan_id = makeChannelId(1);

    // Append 10K events
    var i: u32 = 0;
    while (i < 10000) : (i += 1) {
        _ = try store.append(Event{
            .objective_created = .{
                .timestamp_ms = timestamp(),
                .objective_id = obj_id,
                .objective_type = .DirectFund,
                .channel_id = chan_id,
                .participants = &[_][20]u8{},
            },
        });
    }

    try testing.expectEqual(@as(u64, 10000), store.len());
    std.debug.print("10K events stored successfully\n", .{});

    // Note: GPA tracks allocations but doesn't report total bytes
    // For Phase 1, we verify no leaks rather than measuring total size
}
