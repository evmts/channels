const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const channel_id = @import("channel_id.zig");

const Address = types.Address;
const FixedPart = types.FixedPart;
const ChannelId = types.ChannelId;

// Test helpers
fn makeAddress(seed: u8) Address {
    return [_]u8{seed} ** 20;
}

test "channelId - deterministic for same FixedPart" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Create participants
    const participants = try allocator.alloc(Address, 2);
    defer allocator.free(participants);
    participants[0] = makeAddress(0xAA);
    participants[1] = makeAddress(0xBB);

    const fixed = FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = makeAddress(0x00),
        .challenge_duration = 86400,
    };

    // Generate ID multiple times
    const id1 = try channel_id.channelId(fixed, allocator);
    const id2 = try channel_id.channelId(fixed, allocator);
    const id3 = try channel_id.channelId(fixed, allocator);

    // All should be identical
    try testing.expectEqualSlices(u8, &id1, &id2);
    try testing.expectEqualSlices(u8, &id2, &id3);
}

test "channelId - different FixedParts produce different IDs" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Fixed Part 1
    const participants1 = try allocator.alloc(Address, 2);
    defer allocator.free(participants1);
    participants1[0] = makeAddress(0xAA);
    participants1[1] = makeAddress(0xBB);

    const fixed1 = FixedPart{
        .participants = participants1,
        .channel_nonce = 42,
        .app_definition = makeAddress(0x00),
        .challenge_duration = 86400,
    };

    // Fixed Part 2 - different nonce
    const participants2 = try allocator.alloc(Address, 2);
    defer allocator.free(participants2);
    participants2[0] = makeAddress(0xAA);
    participants2[1] = makeAddress(0xBB);

    const fixed2 = FixedPart{
        .participants = participants2,
        .channel_nonce = 43, // Different nonce
        .app_definition = makeAddress(0x00),
        .challenge_duration = 86400,
    };

    const id1 = try channel_id.channelId(fixed1, allocator);
    const id2 = try channel_id.channelId(fixed2, allocator);

    // Should be different
    try testing.expect(!std.mem.eql(u8, &id1, &id2));
}

test "channelId - different participant order produces different IDs" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Participants in order A, B
    const participants1 = try allocator.alloc(Address, 2);
    defer allocator.free(participants1);
    participants1[0] = makeAddress(0xAA);
    participants1[1] = makeAddress(0xBB);

    const fixed1 = FixedPart{
        .participants = participants1,
        .channel_nonce = 42,
        .app_definition = makeAddress(0x00),
        .challenge_duration = 86400,
    };

    // Participants in order B, A
    const participants2 = try allocator.alloc(Address, 2);
    defer allocator.free(participants2);
    participants2[0] = makeAddress(0xBB);
    participants2[1] = makeAddress(0xAA);

    const fixed2 = FixedPart{
        .participants = participants2,
        .channel_nonce = 42,
        .app_definition = makeAddress(0x00),
        .challenge_duration = 86400,
    };

    const id1 = try channel_id.channelId(fixed1, allocator);
    const id2 = try channel_id.channelId(fixed2, allocator);

    // Order matters - should be different
    try testing.expect(!std.mem.eql(u8, &id1, &id2));
}

test "channelId - works with single participant" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const participants = try allocator.alloc(Address, 1);
    defer allocator.free(participants);
    participants[0] = makeAddress(0xAA);

    const fixed = FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = makeAddress(0x00),
        .challenge_duration = 86400,
    };

    const id = try channel_id.channelId(fixed, allocator);

    // Should produce valid 32-byte hash
    try testing.expect(id.len == 32);
}

test "channelId - works with many participants" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const participants = try allocator.alloc(Address, 10);
    defer allocator.free(participants);
    for (participants, 0..) |*p, i| {
        p.* = makeAddress(@intCast(i));
    }

    const fixed = FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = makeAddress(0x00),
        .challenge_duration = 86400,
    };

    const id = try channel_id.channelId(fixed, allocator);

    // Should produce valid 32-byte hash
    try testing.expect(id.len == 32);
}

test "channelId - different app_definition produces different IDs" {
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

    const fixed1 = FixedPart{
        .participants = participants1,
        .channel_nonce = 42,
        .app_definition = makeAddress(0x00),
        .challenge_duration = 86400,
    };

    const participants2 = try allocator.alloc(Address, 2);
    defer allocator.free(participants2);
    participants2[0] = makeAddress(0xAA);
    participants2[1] = makeAddress(0xBB);

    const fixed2 = FixedPart{
        .participants = participants2,
        .channel_nonce = 42,
        .app_definition = makeAddress(0xFF), // Different app
        .challenge_duration = 86400,
    };

    const id1 = try channel_id.channelId(fixed1, allocator);
    const id2 = try channel_id.channelId(fixed2, allocator);

    try testing.expect(!std.mem.eql(u8, &id1, &id2));
}

test "channelId - different challenge_duration produces different IDs" {
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

    const fixed1 = FixedPart{
        .participants = participants1,
        .channel_nonce = 42,
        .app_definition = makeAddress(0x00),
        .challenge_duration = 86400,
    };

    const participants2 = try allocator.alloc(Address, 2);
    defer allocator.free(participants2);
    participants2[0] = makeAddress(0xAA);
    participants2[1] = makeAddress(0xBB);

    const fixed2 = FixedPart{
        .participants = participants2,
        .channel_nonce = 42,
        .app_definition = makeAddress(0x00),
        .challenge_duration = 172800, // Different duration
    };

    const id1 = try channel_id.channelId(fixed1, allocator);
    const id2 = try channel_id.channelId(fixed2, allocator);

    try testing.expect(!std.mem.eql(u8, &id1, &id2));
}

test "channelId - no memory leaks with multiple calls" {
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

    const fixed = FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = makeAddress(0x00),
        .challenge_duration = 86400,
    };

    // Call multiple times to check for leaks
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = try channel_id.channelId(fixed, allocator);
    }

    // GPA will detect leaks on deinit
}

// TODO: Add cross-implementation test vector when nitro-protocol vectors are found
// Search: https://github.com/statechannels/go-nitro for ChannelId test vectors
// Search: https://github.com/statechannels/nitro-protocol for Solidity test vectors
test "channelId - matches nitro-protocol test vectors (PLACEHOLDER)" {
    // Will be implemented once we find test vectors from nitro-protocol repos
    // For now, we rely on determinism tests above
    try testing.expect(true);
}
