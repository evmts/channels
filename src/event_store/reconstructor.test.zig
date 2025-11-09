const std = @import("std");
const testing = std.testing;
const EventStore = @import("store.zig").EventStore;
const StateReconstructor = @import("reconstructor.zig").StateReconstructor;
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

test "StateReconstructor: init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();
}

test "StateReconstructor: objective not found" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    const obj_id = makeObjectiveId(999);
    const result = reconstructor.reconstructObjective(obj_id);
    try testing.expectError(error.ObjectiveNotFound, result);
}

test "StateReconstructor: objective created" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    const obj_id = makeObjectiveId(1);
    const chan_id = makeChannelId(1);

    _ = try store.append(Event{
        .objective_created = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id,
            .objective_type = .DirectFund,
            .channel_id = chan_id,
            .participants = &[_][20]u8{},
        },
    });

    const state = try reconstructor.reconstructObjective(obj_id);
    try testing.expectEqual(ObjectiveState.ObjectiveStatus.Created, state.status);
    try testing.expectEqual(@as(usize, 1), state.event_count);
}

test "StateReconstructor: objective lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    const obj_id = makeObjectiveId(2);
    const chan_id = makeChannelId(2);

    // Created
    _ = try store.append(Event{
        .objective_created = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id,
            .objective_type = .DirectFund,
            .channel_id = chan_id,
            .participants = &[_][20]u8{},
        },
    });

    // Approved
    _ = try store.append(Event{
        .objective_approved = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id,
            .approver = null,
        },
    });

    // Cranked
    _ = try store.append(Event{
        .objective_cranked = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id,
            .side_effects_count = 1,
            .waiting = false,
        },
    });

    // Completed
    const completion_time = timestamp();
    _ = try store.append(Event{
        .objective_completed = .{
            .timestamp_ms = completion_time,
            .objective_id = obj_id,
            .success = true,
            .final_channel_state = null,
        },
    });

    const state = try reconstructor.reconstructObjective(obj_id);
    try testing.expectEqual(ObjectiveState.ObjectiveStatus.Completed, state.status);
    try testing.expectEqual(@as(usize, 4), state.event_count);
    try testing.expect(state.completed_at != null);
}

test "StateReconstructor: objective rejected" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    const obj_id = makeObjectiveId(3);
    const chan_id = makeChannelId(3);

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
        .objective_rejected = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id,
            .reason = "test rejection",
            .error_code = null,
        },
    });

    const state = try reconstructor.reconstructObjective(obj_id);
    try testing.expectEqual(ObjectiveState.ObjectiveStatus.Rejected, state.status);
}

test "StateReconstructor: channel not found" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    const chan_id = makeChannelId(999);
    const result = reconstructor.reconstructChannel(chan_id);
    try testing.expectError(error.ChannelNotFound, result);
}

test "StateReconstructor: channel created" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    const chan_id = makeChannelId(10);

    _ = try store.append(Event{
        .channel_created = .{
            .timestamp_ms = timestamp(),
            .channel_id = chan_id,
            .participants = &[_][20]u8{},
            .channel_nonce = 1,
            .app_definition = [_]u8{0} ** 20,
            .challenge_duration = 100,
        },
    });

    const state = try reconstructor.reconstructChannel(chan_id);
    try testing.expectEqual(ChannelState.ChannelStatus.Created, state.status);
    try testing.expectEqual(@as(usize, 1), state.event_count);
}

test "StateReconstructor: channel state progression" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    const chan_id = makeChannelId(11);

    // Created
    _ = try store.append(Event{
        .channel_created = .{
            .timestamp_ms = timestamp(),
            .channel_id = chan_id,
            .participants = &[_][20]u8{},
            .channel_nonce = 1,
            .app_definition = [_]u8{0} ** 20,
            .challenge_duration = 100,
        },
    });

    // State signed (turn 1)
    const state_hash: [32]u8 = undefined;
    _ = try store.append(Event{
        .state_signed = .{
            .timestamp_ms = timestamp(),
            .channel_id = chan_id,
            .state_hash = state_hash,
            .turn_num = 1,
            .signer = undefined,
            .signature = undefined,
            .is_final = false,
            .app_data_hash = null,
        },
    });

    // State received (turn 2)
    _ = try store.append(Event{
        .state_received = .{
            .timestamp_ms = timestamp(),
            .channel_id = chan_id,
            .state_hash = state_hash,
            .turn_num = 2,
            .signer = undefined,
            .signature = undefined,
            .is_final = false,
            .peer_id = null,
        },
    });

    // Supported turn updated
    _ = try store.append(Event{
        .state_supported_updated = .{
            .timestamp_ms = timestamp(),
            .channel_id = chan_id,
            .supported_turn = 2,
            .state_hash = state_hash,
            .num_signatures = 2,
            .prev_supported_turn = 0,
        },
    });

    const state = try reconstructor.reconstructChannel(chan_id);
    try testing.expectEqual(ChannelState.ChannelStatus.Open, state.status);
    try testing.expectEqual(@as(u64, 2), state.latest_turn_num);
    try testing.expectEqual(@as(u64, 2), state.latest_supported_turn);
}

test "StateReconstructor: channel finalized" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    const chan_id = makeChannelId(12);

    _ = try store.append(Event{
        .channel_created = .{
            .timestamp_ms = timestamp(),
            .channel_id = chan_id,
            .participants = &[_][20]u8{},
            .channel_nonce = 1,
            .app_definition = [_]u8{0} ** 20,
            .challenge_duration = 100,
        },
    });

    const finalized_time = timestamp();
    _ = try store.append(Event{
        .channel_finalized = .{
            .timestamp_ms = finalized_time,
            .channel_id = chan_id,
            .final_turn = 10,
            .final_state_hash = undefined,
        },
    });

    const state = try reconstructor.reconstructChannel(chan_id);
    try testing.expectEqual(ChannelState.ChannelStatus.Finalized, state.status);
    try testing.expect(state.finalized_at != null);
}

test "StateReconstructor: multiple objectives isolated" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = try EventStore.init(allocator);
    defer store.deinit();

    var reconstructor = try StateReconstructor.init(allocator, store);
    defer reconstructor.deinit();

    const obj_id1 = makeObjectiveId(100);
    const obj_id2 = makeObjectiveId(200);
    const chan_id = makeChannelId(1);

    // Objective 1: Created → Approved
    _ = try store.append(Event{
        .objective_created = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id1,
            .objective_type = .DirectFund,
            .channel_id = chan_id,
            .participants = &[_][20]u8{},
        },
    });

    _ = try store.append(Event{
        .objective_approved = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id1,
            .approver = null,
        },
    });

    // Objective 2: Created → Rejected
    _ = try store.append(Event{
        .objective_created = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id2,
            .objective_type = .VirtualFund,
            .channel_id = chan_id,
            .participants = &[_][20]u8{},
        },
    });

    _ = try store.append(Event{
        .objective_rejected = .{
            .timestamp_ms = timestamp(),
            .objective_id = obj_id2,
            .reason = "test",
            .error_code = null,
        },
    });

    // Verify objectives are independent
    const state1 = try reconstructor.reconstructObjective(obj_id1);
    const state2 = try reconstructor.reconstructObjective(obj_id2);

    try testing.expectEqual(ObjectiveState.ObjectiveStatus.Approved, state1.status);
    try testing.expectEqual(@as(usize, 2), state1.event_count);

    try testing.expectEqual(ObjectiveState.ObjectiveStatus.Rejected, state2.status);
    try testing.expectEqual(@as(usize, 2), state2.event_count);
}
