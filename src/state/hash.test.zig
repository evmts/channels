const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const hash_mod = @import("hash.zig");

const Address = types.Address;
const Bytes32 = types.Bytes32;
const State = types.State;
const VariablePart = types.VariablePart;
const Outcome = types.Outcome;
const Allocation = types.Allocation;

// Test helpers
fn makeAddress(seed: u8) Address {
    return [_]u8{seed} ** 20;
}

fn makeBytes32(seed: u8) Bytes32 {
    return [_]u8{seed} ** 32;
}

test "hashState - deterministic for same State" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Create minimal state
    const participants = try allocator.alloc(Address, 2);
    defer allocator.free(participants);
    participants[0] = makeAddress(0xAA);
    participants[1] = makeAddress(0xBB);

    const allocations = try allocator.alloc(Allocation, 1);
    defer allocator.free(allocations);
    allocations[0] = Allocation{
        .destination = makeBytes32(0xCC),
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = &[_]u8{},
    };

    const outcome = Outcome{
        .asset = makeAddress(0x00),
        .allocations = allocations,
    };

    const state = State{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = makeAddress(0xFF),
        .challenge_duration = 86400,
        .app_data = &[_]u8{},
        .outcome = outcome,
        .turn_num = 0,
        .is_final = false,
    };

    // Hash multiple times
    const hash1 = try hash_mod.hashState(state, allocator);
    const hash2 = try hash_mod.hashState(state, allocator);
    const hash3 = try hash_mod.hashState(state, allocator);

    // All should be identical
    try testing.expectEqualSlices(u8, &hash1, &hash2);
    try testing.expectEqualSlices(u8, &hash2, &hash3);
}

test "hashState - different states produce different hashes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // State 1
    const participants1 = try allocator.alloc(Address, 2);
    defer allocator.free(participants1);
    participants1[0] = makeAddress(0xAA);
    participants1[1] = makeAddress(0xBB);

    const allocations1 = try allocator.alloc(Allocation, 1);
    defer allocator.free(allocations1);
    allocations1[0] = Allocation{
        .destination = makeBytes32(0xCC),
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = &[_]u8{},
    };

    const outcome1 = Outcome{
        .asset = makeAddress(0x00),
        .allocations = allocations1,
    };

    const state1 = State{
        .participants = participants1,
        .channel_nonce = 42,
        .app_definition = makeAddress(0xFF),
        .challenge_duration = 86400,
        .app_data = &[_]u8{},
        .outcome = outcome1,
        .turn_num = 0,
        .is_final = false,
    };

    // State 2 - different turn number
    const participants2 = try allocator.alloc(Address, 2);
    defer allocator.free(participants2);
    participants2[0] = makeAddress(0xAA);
    participants2[1] = makeAddress(0xBB);

    const allocations2 = try allocator.alloc(Allocation, 1);
    defer allocator.free(allocations2);
    allocations2[0] = Allocation{
        .destination = makeBytes32(0xCC),
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = &[_]u8{},
    };

    const outcome2 = Outcome{
        .asset = makeAddress(0x00),
        .allocations = allocations2,
    };

    const state2 = State{
        .participants = participants2,
        .channel_nonce = 42,
        .app_definition = makeAddress(0xFF),
        .challenge_duration = 86400,
        .app_data = &[_]u8{},
        .outcome = outcome2,
        .turn_num = 1, // Different turn number
        .is_final = false,
    };

    const hash1 = try hash_mod.hashState(state1, allocator);
    const hash2 = try hash_mod.hashState(state2, allocator);

    // Should be different
    try testing.expect(!std.mem.eql(u8, &hash1, &hash2));
}

test "hashState - different is_final produces different hashes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const participants1 = try allocator.alloc(Address, 2);
    defer allocator.free(participants1);
    participants1[0] = makeAddress(0xAA);
    participants1[1] = makeAddress(0xBB);

    const allocations1 = try allocator.alloc(Allocation, 1);
    defer allocator.free(allocations1);
    allocations1[0] = Allocation{
        .destination = makeBytes32(0xCC),
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = &[_]u8{},
    };

    const outcome1 = Outcome{
        .asset = makeAddress(0x00),
        .allocations = allocations1,
    };

    const state1 = State{
        .participants = participants1,
        .channel_nonce = 42,
        .app_definition = makeAddress(0xFF),
        .challenge_duration = 86400,
        .app_data = &[_]u8{},
        .outcome = outcome1,
        .turn_num = 0,
        .is_final = false,
    };

    const participants2 = try allocator.alloc(Address, 2);
    defer allocator.free(participants2);
    participants2[0] = makeAddress(0xAA);
    participants2[1] = makeAddress(0xBB);

    const allocations2 = try allocator.alloc(Allocation, 1);
    defer allocator.free(allocations2);
    allocations2[0] = Allocation{
        .destination = makeBytes32(0xCC),
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = &[_]u8{},
    };

    const outcome2 = Outcome{
        .asset = makeAddress(0x00),
        .allocations = allocations2,
    };

    const state2 = State{
        .participants = participants2,
        .channel_nonce = 42,
        .app_definition = makeAddress(0xFF),
        .challenge_duration = 86400,
        .app_data = &[_]u8{},
        .outcome = outcome2,
        .turn_num = 0,
        .is_final = true, // Different is_final
    };

    const hash1 = try hash_mod.hashState(state1, allocator);
    const hash2 = try hash_mod.hashState(state2, allocator);

    try testing.expect(!std.mem.eql(u8, &hash1, &hash2));
}

test "hashState - different app_data produces different hashes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const participants1 = try allocator.alloc(Address, 2);
    defer allocator.free(participants1);
    participants1[0] = makeAddress(0xAA);
    participants1[1] = makeAddress(0xBB);

    const allocations1 = try allocator.alloc(Allocation, 1);
    defer allocator.free(allocations1);
    allocations1[0] = Allocation{
        .destination = makeBytes32(0xCC),
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = &[_]u8{},
    };

    const outcome1 = Outcome{
        .asset = makeAddress(0x00),
        .allocations = allocations1,
    };

    const state1 = State{
        .participants = participants1,
        .channel_nonce = 42,
        .app_definition = makeAddress(0xFF),
        .challenge_duration = 86400,
        .app_data = &[_]u8{ 0x01, 0x02, 0x03 },
        .outcome = outcome1,
        .turn_num = 0,
        .is_final = false,
    };

    const participants2 = try allocator.alloc(Address, 2);
    defer allocator.free(participants2);
    participants2[0] = makeAddress(0xAA);
    participants2[1] = makeAddress(0xBB);

    const allocations2 = try allocator.alloc(Allocation, 1);
    defer allocator.free(allocations2);
    allocations2[0] = Allocation{
        .destination = makeBytes32(0xCC),
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = &[_]u8{},
    };

    const outcome2 = Outcome{
        .asset = makeAddress(0x00),
        .allocations = allocations2,
    };

    const state2 = State{
        .participants = participants2,
        .channel_nonce = 42,
        .app_definition = makeAddress(0xFF),
        .challenge_duration = 86400,
        .app_data = &[_]u8{ 0x04, 0x05, 0x06 }, // Different app_data
        .outcome = outcome2,
        .turn_num = 0,
        .is_final = false,
    };

    const hash1 = try hash_mod.hashState(state1, allocator);
    const hash2 = try hash_mod.hashState(state2, allocator);

    try testing.expect(!std.mem.eql(u8, &hash1, &hash2));
}

test "hashState - different allocation amounts produce different hashes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const participants1 = try allocator.alloc(Address, 2);
    defer allocator.free(participants1);
    participants1[0] = makeAddress(0xAA);
    participants1[1] = makeAddress(0xBB);

    const allocations1 = try allocator.alloc(Allocation, 1);
    defer allocator.free(allocations1);
    allocations1[0] = Allocation{
        .destination = makeBytes32(0xCC),
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = &[_]u8{},
    };

    const outcome1 = Outcome{
        .asset = makeAddress(0x00),
        .allocations = allocations1,
    };

    const state1 = State{
        .participants = participants1,
        .channel_nonce = 42,
        .app_definition = makeAddress(0xFF),
        .challenge_duration = 86400,
        .app_data = &[_]u8{},
        .outcome = outcome1,
        .turn_num = 0,
        .is_final = false,
    };

    const participants2 = try allocator.alloc(Address, 2);
    defer allocator.free(participants2);
    participants2[0] = makeAddress(0xAA);
    participants2[1] = makeAddress(0xBB);

    const allocations2 = try allocator.alloc(Allocation, 1);
    defer allocator.free(allocations2);
    allocations2[0] = Allocation{
        .destination = makeBytes32(0xCC),
        .amount = 2000, // Different amount
        .allocation_type = .simple,
        .metadata = &[_]u8{},
    };

    const outcome2 = Outcome{
        .asset = makeAddress(0x00),
        .allocations = allocations2,
    };

    const state2 = State{
        .participants = participants2,
        .channel_nonce = 42,
        .app_definition = makeAddress(0xFF),
        .challenge_duration = 86400,
        .app_data = &[_]u8{},
        .outcome = outcome2,
        .turn_num = 0,
        .is_final = false,
    };

    const hash1 = try hash_mod.hashState(state1, allocator);
    const hash2 = try hash_mod.hashState(state2, allocator);

    try testing.expect(!std.mem.eql(u8, &hash1, &hash2));
}

test "hashState - no memory leaks with multiple calls" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const participants = try allocator.alloc(Address, 2);
    defer allocator.free(participants);
    participants[0] = makeAddress(0xAA);
    participants[1] = makeAddress(0xBB);

    const allocations = try allocator.alloc(Allocation, 1);
    defer allocator.free(allocations);
    allocations[0] = Allocation{
        .destination = makeBytes32(0xCC),
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = &[_]u8{},
    };

    const outcome = Outcome{
        .asset = makeAddress(0x00),
        .allocations = allocations,
    };

    const state = State{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = makeAddress(0xFF),
        .challenge_duration = 86400,
        .app_data = &[_]u8{},
        .outcome = outcome,
        .turn_num = 0,
        .is_final = false,
    };

    // Call multiple times to check for leaks
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = try hash_mod.hashState(state, allocator);
    }

    // GPA will detect leaks on deinit
}

test "hashVariablePart - deterministic for same VariablePart" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const allocations = try allocator.alloc(Allocation, 1);
    defer allocator.free(allocations);
    allocations[0] = Allocation{
        .destination = makeBytes32(0xCC),
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = &[_]u8{},
    };

    const outcome = Outcome{
        .asset = makeAddress(0x00),
        .allocations = allocations,
    };

    const variable = VariablePart{
        .app_data = &[_]u8{},
        .outcome = outcome,
        .turn_num = 0,
        .is_final = false,
    };

    const hash1 = try hash_mod.hashVariablePart(variable, allocator);
    const hash2 = try hash_mod.hashVariablePart(variable, allocator);
    const hash3 = try hash_mod.hashVariablePart(variable, allocator);

    try testing.expectEqualSlices(u8, &hash1, &hash2);
    try testing.expectEqualSlices(u8, &hash2, &hash3);
}

test "hashVariablePart - different turn numbers produce different hashes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const allocations1 = try allocator.alloc(Allocation, 1);
    defer allocator.free(allocations1);
    allocations1[0] = Allocation{
        .destination = makeBytes32(0xCC),
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = &[_]u8{},
    };

    const outcome1 = Outcome{
        .asset = makeAddress(0x00),
        .allocations = allocations1,
    };

    const variable1 = VariablePart{
        .app_data = &[_]u8{},
        .outcome = outcome1,
        .turn_num = 0,
        .is_final = false,
    };

    const allocations2 = try allocator.alloc(Allocation, 1);
    defer allocator.free(allocations2);
    allocations2[0] = Allocation{
        .destination = makeBytes32(0xCC),
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = &[_]u8{},
    };

    const outcome2 = Outcome{
        .asset = makeAddress(0x00),
        .allocations = allocations2,
    };

    const variable2 = VariablePart{
        .app_data = &[_]u8{},
        .outcome = outcome2,
        .turn_num = 1, // Different turn
        .is_final = false,
    };

    const hash1 = try hash_mod.hashVariablePart(variable1, allocator);
    const hash2 = try hash_mod.hashVariablePart(variable2, allocator);

    try testing.expect(!std.mem.eql(u8, &hash1, &hash2));
}
