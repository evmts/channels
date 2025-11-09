const std = @import("std");
const testing = std.testing;
const DirectFundObjective = @import("directfund.zig").DirectFundObjective;
const ObjectiveEvent = @import("types.zig").ObjectiveEvent;
const WaitingFor = @import("types.zig").WaitingFor;
const SideEffect = @import("types.zig").SideEffect;
const MockChainService = @import("mocks.zig").MockChainService;
const MockMessageService = @import("mocks.zig").MockMessageService;
const FixedPart = @import("../state/types.zig").FixedPart;
const Outcome = @import("../state/types.zig").Outcome;
const Allocation = @import("../state/types.zig").Allocation;
const Address = @import("../state/types.zig").Address;

// Test helpers
fn makeAddress(byte: u8) Address {
    return [_]u8{byte} ** 20;
}

fn makeObjectiveId(byte: u8) [32]u8 {
    return [_]u8{byte} ** 32;
}

test "Integration: 2-party channel funding end-to-end" {
    const a = testing.allocator;

    // Setup participants
    const alice_addr = makeAddress(0xAA);
    const bob_addr = makeAddress(0xBB);

    const participants = try a.alloc(Address, 2);
    defer a.free(participants);
    participants[0] = alice_addr;
    participants[1] = bob_addr;

    const fixed = FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = makeAddress(0x00),
        .challenge_duration = 86400,
    };

    const allocations = try a.alloc(Allocation, 2);
    defer a.free(allocations);
    allocations[0] = Allocation{
        .destination = alice_addr ++ [_]u8{0} ** 12,
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = "",
    };
    allocations[1] = Allocation{
        .destination = bob_addr ++ [_]u8{0} ** 12,
        .amount = 2000,
        .allocation_type = .simple,
        .metadata = "",
    };

    const outcome = Outcome{
        .asset = makeAddress(0xFF),
        .allocations = allocations,
    };

    // Create objectives for both parties
    var alice_obj = try DirectFundObjective.init(
        makeObjectiveId(0x01),
        0, // Alice
        fixed,
        outcome,
        a,
    );
    defer alice_obj.deinit(a);

    var bob_obj = try DirectFundObjective.init(
        makeObjectiveId(0x01),
        1, // Bob
        fixed,
        outcome,
        a,
    );
    defer bob_obj.deinit(a);

    // Mock services
    var chain = MockChainService.init(a);
    defer chain.deinit();

    var messages = MockMessageService.init(a);
    defer messages.deinit();

    // ========== PHASE 1: Approval & Prefund ==========

    // Alice approves and sends prefund
    {
        const result = try alice_obj.crank(.approval_granted, a);
        defer result.deinit(a);

        try testing.expectEqual(.Approved, alice_obj.status);
        try testing.expect(result.side_effects.len == 1);

        // Dispatch message
        const msg = result.side_effects[0].send_message;
        try messages.sendMessage(msg);
    }

    // Bob approves and sends prefund
    {
        const result = try bob_obj.crank(.approval_granted, a);
        defer result.deinit(a);

        try testing.expectEqual(.Approved, bob_obj.status);

        const msg = result.side_effects[0].send_message;
        try messages.sendMessage(msg);
    }

    // Exchange prefund signatures
    // Alice receives Bob's prefund
    {
        const prefund = try bob_obj.generatePrefundState(a);
        defer prefund.deinit(a);

        const prefund_clone = try prefund.clone(a);
        defer prefund_clone.deinit(a);

        const result = try alice_obj.crank(
            .{ .state_received = .{
                .channel_id = alice_obj.channel_id,
                .turn_num = 0,
                .state = prefund_clone,
                .signature = bob_obj.prefund_signatures[1].?,
                .from = bob_addr,
            } },
            a,
        );
        defer result.deinit(a);

        // Alice's turn to deposit - should emit tx
        try testing.expect(result.side_effects.len == 1);
        try testing.expect(result.side_effects[0] == .submit_tx);

        // Submit Alice's deposit
        const tx = result.side_effects[0].submit_tx;
        try chain.submitDeposit(tx, alice_obj.channel_id, alice_addr);
    }

    // Alice detects her own deposit
    {
        const result = try alice_obj.crank(
            .{ .deposit_detected = .{
                .channel_id = alice_obj.channel_id,
                .asset = outcome.asset,
                .amount = 1000,
                .depositor = alice_addr,
            } },
            a,
        );
        defer result.deinit(a);
        // Alice waiting for Bob's deposit
    }

    // Bob receives Alice's prefund
    {
        const prefund = try alice_obj.generatePrefundState(a);
        defer prefund.deinit(a);

        const prefund_clone = try prefund.clone(a);
        defer prefund_clone.deinit(a);

        const result = try bob_obj.crank(
            .{ .state_received = .{
                .channel_id = bob_obj.channel_id,
                .turn_num = 0,
                .state = prefund_clone,
                .signature = alice_obj.prefund_signatures[0].?,
                .from = alice_addr,
            } },
            a,
        );
        defer result.deinit(a);

        // Bob waits for Alice to deposit first
        try testing.expectEqual(.complete_funding, bob_obj.waitingFor());
    }

    // ========== PHASE 2: Deposits ==========

    // Alice's deposit detected by Bob
    {
        const result = try bob_obj.crank(
            .{ .deposit_detected = .{
                .channel_id = bob_obj.channel_id,
                .asset = outcome.asset,
                .amount = 1000,
                .depositor = alice_addr,
            } },
            a,
        );
        defer result.deinit(a);

        // Now Bob's turn - should emit deposit tx
        try testing.expect(result.side_effects.len == 1);
        try testing.expect(result.side_effects[0] == .submit_tx);

        // Submit Bob's deposit
        const tx = result.side_effects[0].submit_tx;
        try chain.submitDeposit(tx, bob_obj.channel_id, bob_addr);
    }

    // Bob detects his own deposit
    {
        const result = try bob_obj.crank(
            .{ .deposit_detected = .{
                .channel_id = bob_obj.channel_id,
                .asset = outcome.asset,
                .amount = 2000,
                .depositor = bob_addr,
            } },
            a,
        );
        defer result.deinit(a);
        // Bob should emit postfund now (all deposits detected)
        try testing.expect(result.side_effects.len == 1);
        try testing.expect(result.side_effects[0] == .send_message);

        const msg = result.side_effects[0].send_message;
        try messages.sendMessage(msg);
    }

    // Alice detects Bob's deposit
    {
        const result = try alice_obj.crank(
            .{ .deposit_detected = .{
                .channel_id = alice_obj.channel_id,
                .asset = outcome.asset,
                .amount = 2000,
                .depositor = bob_addr,
            } },
            a,
        );
        defer result.deinit(a);

        // All deposits complete - should emit postfund
        try testing.expect(result.side_effects.len == 1);
        try testing.expect(result.side_effects[0] == .send_message);

        const msg = result.side_effects[0].send_message;
        try messages.sendMessage(msg);
    }

    // ========== PHASE 3: Postfund ==========

    // Alice receives Bob's postfund
    {
        const postfund = try bob_obj.generatePostfundState(a);
        defer postfund.deinit(a);

        const postfund_clone = try postfund.clone(a);
        defer postfund_clone.deinit(a);

        const result = try alice_obj.crank(
            .{ .state_received = .{
                .channel_id = alice_obj.channel_id,
                .turn_num = 3,
                .state = postfund_clone,
                .signature = bob_obj.postfund_signatures[1].?,
                .from = bob_addr,
            } },
            a,
        );
        defer result.deinit(a);

        // Alice complete!
        try testing.expectEqual(.Complete, alice_obj.status);
        try testing.expectEqual(.nothing, alice_obj.waitingFor());
    }

    // Bob receives Alice's postfund
    {
        const postfund = try alice_obj.generatePostfundState(a);
        defer postfund.deinit(a);

        const postfund_clone = try postfund.clone(a);
        defer postfund_clone.deinit(a);

        const result = try bob_obj.crank(
            .{ .state_received = .{
                .channel_id = bob_obj.channel_id,
                .turn_num = 3,
                .state = postfund_clone,
                .signature = alice_obj.postfund_signatures[0].?,
                .from = alice_addr,
            } },
            a,
        );
        defer result.deinit(a);

        // Bob complete!
        try testing.expectEqual(.Complete, bob_obj.status);
        try testing.expectEqual(.nothing, bob_obj.waitingFor());
    }

    // ========== Verify Final State ==========

    try testing.expect(chain.hasDeposited(alice_obj.channel_id, alice_addr));
    try testing.expect(chain.hasDeposited(bob_obj.channel_id, bob_addr));

    const msg_count = messages.countSignedStateMessages();
    if (msg_count < 4) {
        std.debug.print("Expected >= 4 messages, got {}\n", .{msg_count});
    }
    try testing.expect(msg_count >= 4); // 2 prefund + 2 postfund

    // Both objectives have same channel ID
    try testing.expect(std.mem.eql(u8, &alice_obj.channel_id, &bob_obj.channel_id));

    // All signatures present
    try testing.expect(alice_obj.allPrefundSigned());
    try testing.expect(alice_obj.allDepositsDetected());
    try testing.expect(alice_obj.allPostfundSigned());
    try testing.expect(bob_obj.allPrefundSigned());
    try testing.expect(bob_obj.allDepositsDetected());
    try testing.expect(bob_obj.allPostfundSigned());
}

test "Integration: objective IDs match between participants" {
    const a = testing.allocator;

    const participants = try a.alloc(Address, 2);
    defer a.free(participants);
    participants[0] = makeAddress(0xAA);
    participants[1] = makeAddress(0xBB);

    const fixed = FixedPart{
        .participants = participants,
        .channel_nonce = 123,
        .app_definition = makeAddress(0x00),
        .challenge_duration = 86400,
    };

    const allocations = try a.alloc(Allocation, 2);
    defer a.free(allocations);
    allocations[0] = Allocation{
        .destination = makeAddress(0xAA) ++ [_]u8{0} ** 12,
        .amount = 500,
        .allocation_type = .simple,
        .metadata = "",
    };
    allocations[1] = Allocation{
        .destination = makeAddress(0xBB) ++ [_]u8{0} ** 12,
        .amount = 500,
        .allocation_type = .simple,
        .metadata = "",
    };

    const outcome = Outcome{
        .asset = makeAddress(0xFF),
        .allocations = allocations,
    };

    // Use same objective ID (coordinated via protocol)
    const shared_obj_id = makeObjectiveId(0x99);

    var alice = try DirectFundObjective.init(shared_obj_id, 0, fixed, outcome, a);
    defer alice.deinit(a);

    var bob = try DirectFundObjective.init(shared_obj_id, 1, fixed, outcome, a);
    defer bob.deinit(a);

    // Both should derive same channel ID
    try testing.expect(std.mem.eql(u8, &alice.channel_id, &bob.channel_id));
    try testing.expect(std.mem.eql(u8, &alice.id, &bob.id));
}
