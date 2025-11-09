const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");

test "FixedPart - construction and clone" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    const participants = try allocator.alloc(types.Address, 2);
    participants[0] = alice;
    participants[1] = bob;

    const fixed = types.FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const cloned = try fixed.clone(allocator);
    defer cloned.deinit(allocator);
    defer fixed.deinit(allocator);

    try testing.expectEqual(fixed.channel_nonce, cloned.channel_nonce);
    try testing.expectEqual(fixed.challenge_duration, cloned.challenge_duration);
    try testing.expectEqualSlices(u8, &fixed.app_definition, &cloned.app_definition);
    try testing.expectEqual(fixed.participants.len, cloned.participants.len);
    for (fixed.participants, cloned.participants) |orig, copy| {
        try testing.expectEqualSlices(u8, &orig, &copy);
    }
}

test "VariablePart - construction and clone" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const app_data = try allocator.dupe(u8, "test_data");
    // Note: variable.deinit will free app_data, don't double-free

    const allocations = try allocator.alloc(types.Allocation, 1);
    allocations[0] = types.Allocation{
        .destination = [_]u8{0x01} ** 32,
        .amount = 100,
        .allocation_type = .simple,
        .metadata = "",
    };

    const outcome = types.Outcome{
        .asset = [_]u8{0x00} ** 20,
        .allocations = allocations,
    };

    const variable = types.VariablePart{
        .app_data = app_data,
        .outcome = outcome,
        .turn_num = 5,
        .is_final = false,
    };

    const cloned = try variable.clone(allocator);
    defer cloned.deinit(allocator);
    defer variable.deinit(allocator);

    try testing.expectEqualStrings(variable.app_data, cloned.app_data);
    try testing.expectEqual(variable.turn_num, cloned.turn_num);
    try testing.expectEqual(variable.is_final, cloned.is_final);
    try testing.expectEqualSlices(u8, &variable.outcome.asset, &cloned.outcome.asset);
    try testing.expectEqual(variable.outcome.allocations.len, cloned.outcome.allocations.len);
}

test "State - construction and methods" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    const participants = try allocator.alloc(types.Address, 2);
    participants[0] = alice;
    participants[1] = bob;

    const app_data = try allocator.dupe(u8, "state_data");
    // Note: state.deinit will free app_data

    const allocations = try allocator.alloc(types.Allocation, 1);
    allocations[0] = types.Allocation{
        .destination = [_]u8{0x01} ** 32,
        .amount = 200,
        .allocation_type = .simple,
        .metadata = "",
    };

    const outcome = types.Outcome{
        .asset = [_]u8{0x00} ** 20,
        .allocations = allocations,
    };

    const state = types.State{
        .participants = participants,
        .channel_nonce = 7,
        .app_definition = [_]u8{0xDD} ** 20,
        .challenge_duration = 3600,
        .app_data = app_data,
        .outcome = outcome,
        .turn_num = 10,
        .is_final = false,
    };

    // Test fixedPart extraction
    const fixed = state.fixedPart();
    try testing.expectEqual(state.participants.ptr, fixed.participants.ptr);
    try testing.expectEqual(state.channel_nonce, fixed.channel_nonce);
    try testing.expectEqualSlices(u8, &state.app_definition, &fixed.app_definition);
    try testing.expectEqual(state.challenge_duration, fixed.challenge_duration);

    // Test variablePart extraction
    const variable = try state.variablePart(allocator);
    defer variable.deinit(allocator);
    try testing.expectEqualStrings(state.app_data, variable.app_data);
    try testing.expectEqual(state.turn_num, variable.turn_num);
    try testing.expectEqual(state.is_final, variable.is_final);

    // Test clone
    const cloned = try state.clone(allocator);
    defer cloned.deinit(allocator);
    defer state.deinit(allocator);

    try testing.expectEqual(state.channel_nonce, cloned.channel_nonce);
    try testing.expectEqual(state.turn_num, cloned.turn_num);
    try testing.expectEqualStrings(state.app_data, cloned.app_data);
}

test "State - turn number monotonicity invariant" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    const participants = try allocator.alloc(types.Address, 2);
    participants[0] = alice;
    participants[1] = bob;

    const app_data = try allocator.dupe(u8, "");
    const allocations = try allocator.alloc(types.Allocation, 1);
    allocations[0] = types.Allocation{
        .destination = [_]u8{0x01} ** 32,
        .amount = 100,
        .allocation_type = .simple,
        .metadata = "",
    };

    const outcome = types.Outcome{
        .asset = [_]u8{0x00} ** 20,
        .allocations = allocations,
    };

    // Create state with turn 0
    const state0 = types.State{
        .participants = participants,
        .channel_nonce = 1,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
        .app_data = app_data,
        .outcome = outcome,
        .turn_num = 0,
        .is_final = false,
    };

    // Clone and increment turn number
    var state1 = try state0.clone(allocator);
    state1.turn_num = 1;

    defer state0.deinit(allocator);
    defer state1.deinit(allocator);

    // Verify turn 1 > turn 0 (monotonicity)
    try testing.expect(state1.turn_num > state0.turn_num);
}

test "Signature - bytes conversion roundtrip" {
    const sig = types.Signature{
        .r = [_]u8{0x01} ** 32,
        .s = [_]u8{0x02} ** 32,
        .v = 27,
    };

    const bytes = sig.toBytes();
    const decoded = types.Signature.fromBytes(bytes);

    try testing.expectEqualSlices(u8, &sig.r, &decoded.r);
    try testing.expectEqualSlices(u8, &sig.s, &decoded.s);
    try testing.expectEqual(sig.v, decoded.v);
}

test "Outcome - construction and clone" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const allocations = try allocator.alloc(types.Allocation, 2);
    allocations[0] = types.Allocation{
        .destination = [_]u8{0xAA} ** 32,
        .amount = 100,
        .allocation_type = .simple,
        .metadata = "",
    };
    allocations[1] = types.Allocation{
        .destination = [_]u8{0xBB} ** 32,
        .amount = 200,
        .allocation_type = .guarantee,
        .metadata = "",
    };

    const outcome = types.Outcome{
        .asset = [_]u8{0xCC} ** 20,
        .allocations = allocations,
    };

    const cloned = try outcome.clone(allocator);
    defer cloned.deinit(allocator);
    defer outcome.deinit(allocator);

    try testing.expectEqualSlices(u8, &outcome.asset, &cloned.asset);
    try testing.expectEqual(outcome.allocations.len, cloned.allocations.len);
    for (outcome.allocations, cloned.allocations) |orig, copy| {
        try testing.expectEqualSlices(u8, &orig.destination, &copy.destination);
        try testing.expectEqual(orig.amount, copy.amount);
        try testing.expectEqual(orig.allocation_type, copy.allocation_type);
    }
}

test "Allocation - construction and clone" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const metadata = try allocator.dupe(u8, "allocation_metadata");
    // Note: alloc.deinit will free metadata

    const alloc = types.Allocation{
        .destination = [_]u8{0xFF} ** 32,
        .amount = 500,
        .allocation_type = .simple,
        .metadata = metadata,
    };

    const cloned = try alloc.clone(allocator);
    defer cloned.deinit(allocator);
    defer alloc.deinit(allocator);

    try testing.expectEqualSlices(u8, &alloc.destination, &cloned.destination);
    try testing.expectEqual(alloc.amount, cloned.amount);
    try testing.expectEqual(alloc.allocation_type, cloned.allocation_type);
    try testing.expectEqualStrings(alloc.metadata, cloned.metadata);
}
