const std = @import("std");
const events = @import("events.zig");
const id_module = @import("id.zig");
const testing = std.testing;

const Event = events.Event;
const ValidationCtx = events.ValidationCtx;

// Test helper to create validation context
// Returns a fresh EventStore for each test call to avoid state pollution
const StoreModule = @import("store.zig");
const EventStore = StoreModule.EventStore;

fn createTestCtx() !struct { ctx: ValidationCtx, store: *EventStore } {
    const allocator = testing.allocator;
    const store = try allocator.create(EventStore);
    store.* = .{
        .allocator = allocator,
        .events = .{},
        .subscribers = std.ArrayList(StoreModule.EventCallback){},
        .rw_lock = .{},
        .count = std.atomic.Value(u64).init(0),
    };
    return .{ .ctx = ValidationCtx.init(store), .store = store };
}

fn cleanupStore(store: *EventStore) void {
    store.deinit();
    testing.allocator.destroy(store);
}

// ===== Objective Events Tests =====

test "ObjectiveCreatedEvent - valid event passes validation" {
    const allocator = testing.allocator;

    var participants = try allocator.alloc([20]u8, 2);
    defer allocator.free(participants);

    participants[0] = [_]u8{0x74} ++ [_]u8{0} ** 19;
    participants[1] = [_]u8{0x86} ++ [_]u8{0} ** 19;

    const evt = events.ObjectiveCreatedEvent{
        .timestamp_ms = 1704067200000,
        .objective_id = [_]u8{0xaa} ** 32,
        .objective_type = .DirectFund,
        .channel_id = [_]u8{0xbb} ** 32,
        .participants = participants,
    };

    const result = try createTestCtx();
    defer cleanupStore(result.store);
    try evt.validate(&result.ctx);
}

test "ObjectiveCreatedEvent - rejects too few participants" {
    const allocator = testing.allocator;

    var participants = try allocator.alloc([20]u8, 1);
    defer allocator.free(participants);

    participants[0] = [_]u8{0x74} ++ [_]u8{0} ** 19;

    const evt = events.ObjectiveCreatedEvent{
        .timestamp_ms = 1704067200000,
        .objective_id = [_]u8{0xaa} ** 32,
        .objective_type = .DirectFund,
        .channel_id = [_]u8{0xbb} ** 32,
        .participants = participants,
    };

    const result = try createTestCtx();
    defer cleanupStore(result.store);
    try testing.expectError(error.InsufficientParticipants, evt.validate(&result.ctx));
}

test "ObjectiveApprovedEvent - validates objective existence" {
    const allocator = testing.allocator;
    const result = try createTestCtx();
    defer cleanupStore(result.store);

    // First add objective to store
    var participants = try allocator.alloc([20]u8, 2);
    defer allocator.free(participants);
    participants[0] = [_]u8{0x74} ++ [_]u8{0} ** 19;
    participants[1] = [_]u8{0x86} ++ [_]u8{0} ** 19;

    const objective_created = Event{
        .objective_created = events.ObjectiveCreatedEvent{
            .timestamp_ms = 1704067200000,
            .objective_id = [_]u8{0xaa} ** 32,
            .objective_type = .DirectFund,
            .channel_id = [_]u8{0xbb} ** 32,
            .participants = participants,
        },
    };
    _ = try result.store.append(objective_created);

    const evt = events.ObjectiveApprovedEvent{
        .timestamp_ms = 1704067200000,
        .objective_id = [_]u8{0xaa} ** 32,
        .approver = [_]u8{0x74} ++ [_]u8{0} ** 19,
    };

    try evt.validate(&result.ctx);
}

test "ObjectiveRejectedEvent - includes reason and error code" {
    const allocator = testing.allocator;
    const result = try createTestCtx();
    defer cleanupStore(result.store);

    // First add objective to store
    var participants = try allocator.alloc([20]u8, 2);
    defer allocator.free(participants);
    participants[0] = [_]u8{0x74} ++ [_]u8{0} ** 19;
    participants[1] = [_]u8{0x86} ++ [_]u8{0} ** 19;

    const objective_created = Event{
        .objective_created = events.ObjectiveCreatedEvent{
            .timestamp_ms = 1704067200000,
            .objective_id = [_]u8{0xaa} ** 32,
            .objective_type = .DirectFund,
            .channel_id = [_]u8{0xbb} ** 32,
            .participants = participants,
        },
    };
    _ = try result.store.append(objective_created);

    const reason = try allocator.dupe(u8, "Insufficient collateral");
    defer allocator.free(reason);

    const error_code = try allocator.dupe(u8, "COLLATERAL_TOO_LOW");
    defer allocator.free(error_code);

    const evt = events.ObjectiveRejectedEvent{
        .timestamp_ms = 1704067200000,
        .objective_id = [_]u8{0xaa} ** 32,
        .reason = reason,
        .error_code = error_code,
    };

    try evt.validate(&result.ctx);
}

test "ObjectiveCrankedEvent - tracks side effects" {
    const allocator = testing.allocator;
    const result = try createTestCtx();
    defer cleanupStore(result.store);

    // First add objective to store
    var participants = try allocator.alloc([20]u8, 2);
    defer allocator.free(participants);
    participants[0] = [_]u8{0x74} ++ [_]u8{0} ** 19;
    participants[1] = [_]u8{0x86} ++ [_]u8{0} ** 19;

    const objective_created = Event{
        .objective_created = events.ObjectiveCreatedEvent{
            .timestamp_ms = 1704067200000,
            .objective_id = [_]u8{0xaa} ** 32,
            .objective_type = .DirectFund,
            .channel_id = [_]u8{0xbb} ** 32,
            .participants = participants,
        },
    };
    _ = try result.store.append(objective_created);

    const evt = events.ObjectiveCrankedEvent{
        .timestamp_ms = 1704067200000,
        .objective_id = [_]u8{0xaa} ** 32,
        .side_effects_count = 3,
        .waiting = false,
    };

    try evt.validate(&result.ctx);
}

test "ObjectiveCompletedEvent - success flag" {
    const allocator = testing.allocator;
    const result = try createTestCtx();
    defer cleanupStore(result.store);

    // First add objective to store
    var participants = try allocator.alloc([20]u8, 2);
    defer allocator.free(participants);
    participants[0] = [_]u8{0x74} ++ [_]u8{0} ** 19;
    participants[1] = [_]u8{0x86} ++ [_]u8{0} ** 19;

    const objective_created = Event{
        .objective_created = events.ObjectiveCreatedEvent{
            .timestamp_ms = 1704067200000,
            .objective_id = [_]u8{0xaa} ** 32,
            .objective_type = .DirectFund,
            .channel_id = [_]u8{0xbb} ** 32,
            .participants = participants,
        },
    };
    _ = try result.store.append(objective_created);

    const evt = events.ObjectiveCompletedEvent{
        .timestamp_ms = 1704067200000,
        .objective_id = [_]u8{0xaa} ** 32,
        .success = true,
        .final_channel_state = [_]u8{0xcc} ** 32,
    };

    try evt.validate(&result.ctx);
}

// ===== Channel State Events Tests =====

test "ChannelCreatedEvent - validates challenge duration" {
    const allocator = testing.allocator;

    var participants = try allocator.alloc([20]u8, 2);
    defer allocator.free(participants);

    participants[0] = [_]u8{0x74} ++ [_]u8{0} ** 19;
    participants[1] = [_]u8{0x86} ++ [_]u8{0} ** 19;

    const evt = events.ChannelCreatedEvent{
        .timestamp_ms = 1704067200000,
        .channel_id = [_]u8{0x12} ** 32,
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = [_]u8{0xaa} ++ [_]u8{0} ** 19,
        .challenge_duration = 3600,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

test "ChannelCreatedEvent - rejects zero challenge duration" {
    const allocator = testing.allocator;

    var participants = try allocator.alloc([20]u8, 2);
    defer allocator.free(participants);

    participants[0] = [_]u8{0x74} ++ [_]u8{0} ** 19;
    participants[1] = [_]u8{0x86} ++ [_]u8{0} ** 19;

    const evt = events.ChannelCreatedEvent{
        .timestamp_ms = 1704067200000,
        .channel_id = [_]u8{0x12} ** 32,
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = [_]u8{0xaa} ++ [_]u8{0} ** 19,
        .challenge_duration = 0, // invalid
    };

    const ctx = createTestCtx();
    try testing.expectError(error.InvalidChallengeDuration, evt.validate(&ctx));
}

test "StateSignedEvent - full event structure" {
    const evt = events.StateSignedEvent{
        .timestamp_ms = 1704067200000,
        .channel_id = [_]u8{0x12} ** 32,
        .turn_num = 5,
        .state_hash = [_]u8{0xab} ** 32,
        .signer = [_]u8{0x74} ++ [_]u8{0} ** 19,
        .signature = [_]u8{0x99} ** 65,
        .is_final = false,
        .app_data_hash = [_]u8{0} ** 32,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

test "StateReceivedEvent - includes peer ID" {
    const allocator = testing.allocator;
    const peer_id = try allocator.dupe(u8, "peer-node-123");
    defer allocator.free(peer_id);

    const evt = events.StateReceivedEvent{
        .timestamp_ms = 1704067200000,
        .channel_id = [_]u8{0x12} ** 32,
        .turn_num = 6,
        .state_hash = [_]u8{0xcd} ** 32,
        .signer = [_]u8{0x86} ++ [_]u8{0} ** 19,
        .signature = [_]u8{0x77} ** 65,
        .is_final = false,
        .peer_id = peer_id,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

test "StateSupportedUpdatedEvent - enforces turn progression" {
    const evt = events.StateSupportedUpdatedEvent{
        .timestamp_ms = 1704067200000,
        .channel_id = [_]u8{0x12} ** 32,
        .supported_turn = 10,
        .state_hash = [_]u8{0xef} ** 32,
        .num_signatures = 2,
        .prev_supported_turn = 8,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

test "StateSupportedUpdatedEvent - rejects backwards turn progression" {
    const evt = events.StateSupportedUpdatedEvent{
        .timestamp_ms = 1704067200000,
        .channel_id = [_]u8{0x12} ** 32,
        .supported_turn = 5, // less than prev
        .state_hash = [_]u8{0xef} ** 32,
        .num_signatures = 2,
        .prev_supported_turn = 10,
    };

    const ctx = createTestCtx();
    try testing.expectError(error.InvalidTurnProgression, evt.validate(&ctx));
}

test "StateSupportedUpdatedEvent - rejects zero signatures" {
    const evt = events.StateSupportedUpdatedEvent{
        .timestamp_ms = 1704067200000,
        .channel_id = [_]u8{0x12} ** 32,
        .supported_turn = 10,
        .state_hash = [_]u8{0xef} ** 32,
        .num_signatures = 0, // invalid
        .prev_supported_turn = 8,
    };

    const ctx = createTestCtx();
    try testing.expectError(error.NoSignatures, evt.validate(&ctx));
}

test "ChannelFinalizedEvent - tracks finalization" {
    const evt = events.ChannelFinalizedEvent{
        .timestamp_ms = 1704067200000,
        .channel_id = [_]u8{0x12} ** 32,
        .final_turn = 42,
        .final_state_hash = [_]u8{0xff} ** 32,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

// ===== Chain Bridge Events Tests =====

test "DepositDetectedEvent - tracks on-chain deposit" {
    const allocator = testing.allocator;
    const amount = try allocator.dupe(u8, "1000000000000000000");
    defer allocator.free(amount);
    const held = try allocator.dupe(u8, "1000000000000000000");
    defer allocator.free(held);

    const evt = events.DepositDetectedEvent{
        .timestamp_ms = 1704067200000,
        .channel_id = [_]u8{0x12} ** 32,
        .block_num = 12345678,
        .tx_index = 42,
        .tx_hash = [_]u8{0xfe} ** 32,
        .asset = [_]u8{0} ** 20,
        .amount_deposited = amount,
        .now_held = held,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

test "ChallengeRegisteredEvent - includes finalization time" {
    const evt = events.ChallengeRegisteredEvent{
        .timestamp_ms = 1704067200000,
        .channel_id = [_]u8{0x12} ** 32,
        .block_num = 12345678,
        .tx_index = 50,
        .tx_hash = [_]u8{0xaa} ** 32,
        .turn_num_record = 15,
        .finalization_time = 1704070800, // +1 hour
        .challenger = [_]u8{0x74} ++ [_]u8{0} ** 19,
        .is_final = false,
        .candidate_state_hash = [_]u8{0xbb} ** 32,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

test "ChallengeClearedEvent - clears challenge" {
    const evt = events.ChallengeClearedEvent{
        .timestamp_ms = 1704067200000,
        .channel_id = [_]u8{0x12} ** 32,
        .block_num = 12345700,
        .tx_index = 55,
        .tx_hash = [_]u8{0xcc} ** 32,
        .new_turn_num_record = 20,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

test "ChannelConcludedEvent - concludes on-chain" {
    const evt = events.ChannelConcludedEvent{
        .timestamp_ms = 1704067200000,
        .channel_id = [_]u8{0x12} ** 32,
        .block_num = 12345800,
        .tx_index = 60,
        .tx_hash = [_]u8{0xdd} ** 32,
        .finalized_at_turn = 50,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

test "WithdrawCompletedEvent - tracks withdrawal" {
    const allocator = testing.allocator;
    const amount = try allocator.dupe(u8, "500000000000000000");
    defer allocator.free(amount);

    const evt = events.WithdrawCompletedEvent{
        .timestamp_ms = 1704067200000,
        .channel_id = [_]u8{0x12} ** 32,
        .block_num = 12345900,
        .tx_index = 65,
        .tx_hash = [_]u8{0xee} ** 32,
        .recipient = [_]u8{0x74} ++ [_]u8{0} ** 19,
        .asset = [_]u8{0} ** 20,
        .amount = amount,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

// ===== Messaging Events Tests =====

test "MessageSentEvent - tracks sent message" {
    const allocator = testing.allocator;
    const peer = try allocator.dupe(u8, "peer-123");
    defer allocator.free(peer);
    const payload_type = try allocator.dupe(u8, "ObjectivePayload");
    defer allocator.free(payload_type);

    const evt = events.MessageSentEvent{
        .timestamp_ms = 1704067200000,
        .message_id = [_]u8{0x99} ** 32,
        .peer_id = peer,
        .objective_id = [_]u8{0xaa} ** 32,
        .payload_type = payload_type,
        .payload_size_bytes = 512,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

test "MessageReceivedEvent - tracks received message" {
    const allocator = testing.allocator;
    const peer = try allocator.dupe(u8, "peer-456");
    defer allocator.free(peer);

    const evt = events.MessageReceivedEvent{
        .timestamp_ms = 1704067200000,
        .message_id = [_]u8{0x88} ** 32,
        .peer_id = peer,
        .objective_id = [_]u8{0xbb} ** 32,
        .payload_type = null,
        .payload_size_bytes = 256,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

test "MessageAckedEvent - tracks roundtrip time" {
    const allocator = testing.allocator;
    const peer = try allocator.dupe(u8, "peer-789");
    defer allocator.free(peer);

    const evt = events.MessageAckedEvent{
        .timestamp_ms = 1704067200000,
        .message_id = [_]u8{0x77} ** 32,
        .peer_id = peer,
        .roundtrip_ms = 150,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

test "MessageDroppedEvent - categorizes errors" {
    const allocator = testing.allocator;
    const peer = try allocator.dupe(u8, "peer-bad");
    defer allocator.free(peer);
    const reason = try allocator.dupe(u8, "Signature verification failed");
    defer allocator.free(reason);

    const evt = events.MessageDroppedEvent{
        .timestamp_ms = 1704067200000,
        .message_id = [_]u8{0x66} ** 32,
        .peer_id = peer,
        .reason = reason,
        .error_code = .signature_invalid,
        .payload_size_bytes = 128,
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

// ===== Event Union Tests =====

test "Event union - wraps all event types" {
    const allocator = testing.allocator;

    var participants = try allocator.alloc([20]u8, 2);
    defer allocator.free(participants);
    participants[0] = [_]u8{0x74} ++ [_]u8{0} ** 19;
    participants[1] = [_]u8{0x86} ++ [_]u8{0} ** 19;

    const evt_created = Event{
        .objective_created = events.ObjectiveCreatedEvent{
            .timestamp_ms = 1704067200000,
            .objective_id = [_]u8{0xaa} ** 32,
            .objective_type = .DirectFund,
            .channel_id = [_]u8{0xbb} ** 32,
            .participants = participants,
        },
    };

    const ctx = createTestCtx();
    try evt_created.validate(&ctx);
}

test "Event union - validates via switch" {
    const allocator = testing.allocator;

    const reason = try allocator.dupe(u8, "test");
    defer allocator.free(reason);

    const evt = Event{
        .objective_rejected = events.ObjectiveRejectedEvent{
            .timestamp_ms = 1704067200000,
            .objective_id = [_]u8{0xaa} ** 32,
            .reason = reason,
            .error_code = null,
        },
    };

    const ctx = createTestCtx();
    try evt.validate(&ctx);
}

// ===== Golden Test Vector Tests =====

test "Golden vector - state-signed event ID stability" {
    const allocator = testing.allocator;

    // Canonical JSON from golden file
    const canonical = "{\"app_data_hash\":\"0x0000000000000000000000000000000000000000000000000000000000000000\",\"channel_id\":\"0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef\",\"event_version\":1,\"is_final\":false,\"signature\":\"0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12\",\"signer\":\"0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0\",\"state_hash\":\"0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd\",\"timestamp_ms\":1704067200000,\"turn_num\":5}";

    const event_id = try id_module.deriveEventId(allocator, "state-signed", canonical);

    // ID should be deterministic - same input always produces same hash
    const event_id_2 = try id_module.deriveEventId(allocator, "state-signed", canonical);
    try testing.expectEqualSlices(u8, &event_id, &event_id_2);
}

test "Golden vector - objective-created event ID stability" {
    const allocator = testing.allocator;

    const canonical = "{\"channel_id\":\"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"event_version\":1,\"objective_id\":\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"objective_type\":\"DirectFund\",\"participants\":[\"0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0\",\"0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199\"],\"timestamp_ms\":1704067200000}";

    const event_id = try id_module.deriveEventId(allocator, "objective-created", canonical);
    const event_id_2 = try id_module.deriveEventId(allocator, "objective-created", canonical);

    try testing.expectEqualSlices(u8, &event_id, &event_id_2);
}

test "Golden vector - different events produce different IDs" {
    const allocator = testing.allocator;

    const canonical1 = "{\"event_version\":1,\"timestamp_ms\":1704067200000,\"turn_num\":5}";
    const canonical2 = "{\"event_version\":1,\"timestamp_ms\":1704067200000,\"turn_num\":6}";

    const id1 = try id_module.deriveEventId(allocator, "state-signed", canonical1);
    const id2 = try id_module.deriveEventId(allocator, "state-signed", canonical2);

    try testing.expect(!std.mem.eql(u8, &id1, &id2));
}

test "Serialization round-trip - canonical JSON preserves semantics" {
    const allocator = testing.allocator;

    var obj = std.json.ObjectMap.init(allocator);
    defer obj.deinit();

    try obj.put("channel_id", .{ .string = "0x1234" });
    try obj.put("turn_num", .{ .integer = 5 });
    try obj.put("event_version", .{ .integer = 1 });

    const value = std.json.Value{ .object = obj };
    const canonical = try id_module.canonicalizeJson(allocator, value);
    defer allocator.free(canonical);

    // Keys should be sorted
    const expected = "{\"channel_id\":\"0x1234\",\"event_version\":1,\"turn_num\":5}";
    try testing.expectEqualStrings(expected, canonical);
}
