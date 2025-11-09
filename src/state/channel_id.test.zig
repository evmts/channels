const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const channel_id = @import("channel_id.zig");

test "ChannelId - deterministic generation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    const participants = try allocator.alloc(types.Address, 2);
    defer allocator.free(participants);
    participants[0] = alice;
    participants[1] = bob;

    const fixed = types.FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    // Generate ID twice - should be identical (deterministic)
    const id1 = try channel_id.channelId(fixed, allocator);
    const id2 = try channel_id.channelId(fixed, allocator);

    try testing.expectEqualSlices(u8, &id1, &id2);
}

test "ChannelId - deterministic with 1000 iterations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    const participants = try allocator.alloc(types.Address, 2);
    defer allocator.free(participants);
    participants[0] = alice;
    participants[1] = bob;

    const fixed = types.FixedPart{
        .participants = participants,
        .channel_nonce = 123,
        .app_definition = [_]u8{0xDD} ** 20,
        .challenge_duration = 3600,
    };

    // Generate first ID
    const reference_id = try channel_id.channelId(fixed, allocator);

    // Generate 1000 more times - all should match
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const id = try channel_id.channelId(fixed, allocator);
        try testing.expectEqualSlices(u8, &reference_id, &id);
    }
}

test "ChannelId - different nonce produces different ID" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    const participants = try allocator.alloc(types.Address, 2);
    defer allocator.free(participants);
    participants[0] = alice;
    participants[1] = bob;

    const fixed1 = types.FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const fixed2 = types.FixedPart{
        .participants = participants,
        .channel_nonce = 43, // Different nonce
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const id1 = try channel_id.channelId(fixed1, allocator);
    const id2 = try channel_id.channelId(fixed2, allocator);

    try testing.expect(!std.mem.eql(u8, &id1, &id2));
}

test "ChannelId - different participants produces different ID" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    const charlie: types.Address = [_]u8{0xCC} ** 20;

    const participants1 = try allocator.alloc(types.Address, 2);
    defer allocator.free(participants1);
    participants1[0] = alice;
    participants1[1] = bob;

    const participants2 = try allocator.alloc(types.Address, 2);
    defer allocator.free(participants2);
    participants2[0] = alice;
    participants2[1] = charlie; // Different participant

    const fixed1 = types.FixedPart{
        .participants = participants1,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const fixed2 = types.FixedPart{
        .participants = participants2,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const id1 = try channel_id.channelId(fixed1, allocator);
    const id2 = try channel_id.channelId(fixed2, allocator);

    try testing.expect(!std.mem.eql(u8, &id1, &id2));
}

test "ChannelId - different app_definition produces different ID" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    const participants = try allocator.alloc(types.Address, 2);
    defer allocator.free(participants);
    participants[0] = alice;
    participants[1] = bob;

    const fixed1 = types.FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const fixed2 = types.FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = [_]u8{0xFF} ** 20, // Different app
        .challenge_duration = 86400,
    };

    const id1 = try channel_id.channelId(fixed1, allocator);
    const id2 = try channel_id.channelId(fixed2, allocator);

    try testing.expect(!std.mem.eql(u8, &id1, &id2));
}

test "ChannelId - different challenge_duration produces different ID" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    const participants = try allocator.alloc(types.Address, 2);
    defer allocator.free(participants);
    participants[0] = alice;
    participants[1] = bob;

    const fixed1 = types.FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const fixed2 = types.FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 3600, // Different duration
    };

    const id1 = try channel_id.channelId(fixed1, allocator);
    const id2 = try channel_id.channelId(fixed2, allocator);

    try testing.expect(!std.mem.eql(u8, &id1, &id2));
}

test "ChannelId - different participant count produces different ID" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;
    const charlie: types.Address = [_]u8{0xCC} ** 20;

    const participants2 = try allocator.alloc(types.Address, 2);
    defer allocator.free(participants2);
    participants2[0] = alice;
    participants2[1] = bob;

    const participants3 = try allocator.alloc(types.Address, 3);
    defer allocator.free(participants3);
    participants3[0] = alice;
    participants3[1] = bob;
    participants3[2] = charlie;

    const fixed1 = types.FixedPart{
        .participants = participants2,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const fixed2 = types.FixedPart{
        .participants = participants3,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const id1 = try channel_id.channelId(fixed1, allocator);
    const id2 = try channel_id.channelId(fixed2, allocator);

    try testing.expect(!std.mem.eql(u8, &id1, &id2));
}

test "ChannelId - participant order matters" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const alice: types.Address = [_]u8{0xAA} ** 20;
    const bob: types.Address = [_]u8{0xBB} ** 20;

    const participants1 = try allocator.alloc(types.Address, 2);
    defer allocator.free(participants1);
    participants1[0] = alice;
    participants1[1] = bob;

    const participants2 = try allocator.alloc(types.Address, 2);
    defer allocator.free(participants2);
    participants2[0] = bob;
    participants2[1] = alice; // Reversed order

    const fixed1 = types.FixedPart{
        .participants = participants1,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const fixed2 = types.FixedPart{
        .participants = participants2,
        .channel_nonce = 42,
        .app_definition = [_]u8{0x00} ** 20,
        .challenge_duration = 86400,
    };

    const id1 = try channel_id.channelId(fixed1, allocator);
    const id2 = try channel_id.channelId(fixed2, allocator);

    // Different order should produce different ID
    try testing.expect(!std.mem.eql(u8, &id1, &id2));
}

// TODO: Add cross-implementation test vector from Ethereum contract
// This would verify that our Zig implementation produces the same ChannelId
// as the Solidity adjudicator contract for the same FixedPart inputs
// test "ChannelId - matches Ethereum contract test vector" {}
