const std = @import("std");
const testing = std.testing;
const DirectFundObjective = @import("directfund.zig").DirectFundObjective;
const ObjectiveEvent = @import("types.zig").ObjectiveEvent;
const WaitingFor = @import("types.zig").WaitingFor;
const SideEffect = @import("types.zig").SideEffect;
const FixedPart = @import("../state/types.zig").FixedPart;
const Outcome = @import("../state/types.zig").Outcome;
const Allocation = @import("../state/types.zig").Allocation;
const Address = @import("../state/types.zig").Address;
const Signature = @import("../state/types.zig").Signature;

// Test helpers
fn makeAddress(byte: u8) Address {
    return [_]u8{byte} ** 20;
}

fn makeObjectiveId(byte: u8) [32]u8 {
    return [_]u8{byte} ** 32;
}

fn makeFixedPart(a: std.mem.Allocator) !FixedPart {
    const participants = try a.alloc(Address, 2);
    participants[0] = makeAddress(0xAA);
    participants[1] = makeAddress(0xBB);

    return FixedPart{
        .participants = participants,
        .channel_nonce = 42,
        .app_definition = makeAddress(0x00),
        .challenge_duration = 86400,
    };
}

fn makeOutcome(a: std.mem.Allocator) !Outcome {
    const allocations = try a.alloc(Allocation, 2);
    allocations[0] = Allocation{
        .destination = makeAddress(0xAA) ++ [_]u8{0} ** 12,
        .amount = 1000,
        .allocation_type = .simple,
        .metadata = "",
    };
    allocations[1] = Allocation{
        .destination = makeAddress(0xBB) ++ [_]u8{0} ** 12,
        .amount = 2000,
        .allocation_type = .simple,
        .metadata = "",
    };

    return Outcome{
        .asset = makeAddress(0xFF),
        .allocations = allocations,
    };
}

// ========== Tests ==========

test "DirectFund: initial state is Unapproved" {
    const a = testing.allocator;
    const fixed = try makeFixedPart(a);
    defer fixed.deinit(a);

    const outcome = try makeOutcome(a);
    defer outcome.deinit(a);

    var obj = try DirectFundObjective.init(
        makeObjectiveId(0x01),
        0, // Alice
        fixed,
        outcome,
        a,
    );
    defer obj.deinit(a);

    try testing.expectEqual(.Unapproved, obj.status);
    try testing.expectEqual(.approval, obj.waitingFor());
}

test "DirectFund: approval triggers prefund state" {
    const a = testing.allocator;
    const fixed = try makeFixedPart(a);
    defer fixed.deinit(a);

    const outcome = try makeOutcome(a);
    defer outcome.deinit(a);

    var obj = try DirectFundObjective.init(
        makeObjectiveId(0x01),
        0,
        fixed,
        outcome,
        a,
    );
    defer obj.deinit(a);

    // Crank with approval
    const result = try obj.crank(.approval_granted, a);
    defer result.deinit(a);

    try testing.expectEqual(.Approved, obj.status);
    try testing.expect(result.side_effects.len == 1);
    try testing.expect(result.side_effects[0] == .send_message);

    // Should have signed our prefund
    try testing.expect(obj.prefund_signatures[0] != null);
}

test "DirectFund: receiving prefund signatures completes prefund phase" {
    const a = testing.allocator;
    const fixed = try makeFixedPart(a);
    defer fixed.deinit(a);

    const outcome = try makeOutcome(a);
    defer outcome.deinit(a);

    var obj = try DirectFundObjective.init(
        makeObjectiveId(0x01),
        0,
        fixed,
        outcome,
        a,
    );
    defer obj.deinit(a);

    // Approve
    const r1 = try obj.crank(.approval_granted, a);
    defer r1.deinit(a);

    // Receive Bob's prefund signature
    const prefund = try obj.generatePrefundState(a);
    defer prefund.deinit(a);

    const bob_sig = Signature{ .r = [_]u8{0xCC} ** 32, .s = [_]u8{0xDD} ** 32, .v = 27 };

    const prefund_clone = try prefund.clone(a);
    defer prefund_clone.deinit(a);

    const r2 = try obj.crank(
        .{ .state_received = .{
            .channel_id = obj.channel_id,
            .turn_num = 0,
            .state = prefund_clone,
            .signature = bob_sig,
            .from = makeAddress(0xBB),
        } },
        a,
    );
    defer r2.deinit(a);

    // Both signatures should be present
    try testing.expect(obj.prefund_signatures[0] != null);
    try testing.expect(obj.prefund_signatures[1] != null);
    try testing.expect(obj.allPrefundSigned());
}

test "DirectFund: deposit detected after prefund triggers postfund" {
    const a = testing.allocator;
    const fixed = try makeFixedPart(a);
    defer fixed.deinit(a);

    const outcome = try makeOutcome(a);
    defer outcome.deinit(a);

    var obj = try DirectFundObjective.init(
        makeObjectiveId(0x01),
        0,
        fixed,
        outcome,
        a,
    );
    defer obj.deinit(a);

    // Approve
    const r1 = try obj.crank(.approval_granted, a);
    defer r1.deinit(a);

    // Complete prefund (both sign)
    obj.prefund_signatures[1] = Signature{ .r = [_]u8{0xCC} ** 32, .s = [_]u8{0xDD} ** 32, .v = 27 };

    // Alice deposits
    obj.deposits_detected[0] = true;

    // Bob deposits
    const r2 = try obj.crank(
        .{ .deposit_detected = .{
            .channel_id = obj.channel_id,
            .asset = outcome.asset,
            .amount = 2000,
            .depositor = makeAddress(0xBB),
        } },
        a,
    );
    defer r2.deinit(a);

    // Should emit postfund message
    try testing.expect(r2.side_effects.len == 1);
    try testing.expect(r2.side_effects[0] == .send_message);

    // Should have signed our postfund
    try testing.expect(obj.postfund_signatures[0] != null);
}

test "DirectFund: all postfund signatures complete objective" {
    const a = testing.allocator;
    const fixed = try makeFixedPart(a);
    defer fixed.deinit(a);

    const outcome = try makeOutcome(a);
    defer outcome.deinit(a);

    var obj = try DirectFundObjective.init(
        makeObjectiveId(0x01),
        0,
        fixed,
        outcome,
        a,
    );
    defer obj.deinit(a);

    // Fast-forward to postfund phase
    obj.status = .Approved;
    obj.prefund_signatures[0] = Signature{ .r = [_]u8{0xAA} ** 32, .s = [_]u8{0xBB} ** 32, .v = 27 };
    obj.prefund_signatures[1] = Signature{ .r = [_]u8{0xCC} ** 32, .s = [_]u8{0xDD} ** 32, .v = 27 };
    obj.deposits_detected[0] = true;
    obj.deposits_detected[1] = true;
    obj.postfund_signatures[0] = Signature{ .r = [_]u8{0xEE} ** 32, .s = [_]u8{0xFF} ** 32, .v = 27 };

    // Receive Bob's postfund
    const postfund = try obj.generatePostfundState(a);
    defer postfund.deinit(a);

    const postfund_clone = try postfund.clone(a);
    defer postfund_clone.deinit(a);

    const r = try obj.crank(
        .{ .state_received = .{
            .channel_id = obj.channel_id,
            .turn_num = 3,
            .state = postfund_clone,
            .signature = Signature{ .r = [_]u8{0x11} ** 32, .s = [_]u8{0x22} ** 32, .v = 27 },
            .from = makeAddress(0xBB),
        } },
        a,
    );
    defer r.deinit(a);

    try testing.expectEqual(.Complete, obj.status);
    try testing.expectEqual(.nothing, obj.waitingFor());
}

test "DirectFund: WaitingFor tracks protocol phases correctly" {
    const a = testing.allocator;
    const fixed = try makeFixedPart(a);
    defer fixed.deinit(a);

    const outcome = try makeOutcome(a);
    defer outcome.deinit(a);

    var obj = try DirectFundObjective.init(
        makeObjectiveId(0x01),
        0,
        fixed,
        outcome,
        a,
    );
    defer obj.deinit(a);

    // Unapproved
    try testing.expectEqual(.approval, obj.waitingFor());

    // Approved but no prefund sigs
    obj.status = .Approved;
    obj.prefund_signatures[0] = Signature{ .r = [_]u8{0xAA} ** 32, .s = [_]u8{0xBB} ** 32, .v = 27 };
    try testing.expectEqual(.complete_prefund, obj.waitingFor());

    // Prefund complete, no deposits
    obj.prefund_signatures[1] = Signature{ .r = [_]u8{0xCC} ** 32, .s = [_]u8{0xDD} ** 32, .v = 27 };
    try testing.expectEqual(.my_turn_to_fund, obj.waitingFor());

    // Alice deposited, waiting for Bob
    obj.deposits_detected[0] = true;
    try testing.expectEqual(.complete_funding, obj.waitingFor());

    // All deposited, no postfund sigs
    obj.deposits_detected[1] = true;
    try testing.expectEqual(.complete_postfund, obj.waitingFor());

    // Alice signed postfund
    obj.postfund_signatures[0] = Signature{ .r = [_]u8{0xEE} ** 32, .s = [_]u8{0xFF} ** 32, .v = 27 };
    try testing.expectEqual(.complete_postfund, obj.waitingFor());

    // Complete
    obj.postfund_signatures[1] = Signature{ .r = [_]u8{0x11} ** 32, .s = [_]u8{0x22} ** 32, .v = 27 };
    obj.status = .Complete;
    try testing.expectEqual(.nothing, obj.waitingFor());
}

test "DirectFund: prefund state has turn 0 and empty outcome" {
    const a = testing.allocator;
    const fixed = try makeFixedPart(a);
    defer fixed.deinit(a);

    const outcome = try makeOutcome(a);
    defer outcome.deinit(a);

    var obj = try DirectFundObjective.init(
        makeObjectiveId(0x01),
        0,
        fixed,
        outcome,
        a,
    );
    defer obj.deinit(a);

    const prefund = try obj.generatePrefundState(a);
    defer prefund.deinit(a);

    try testing.expectEqual(@as(u64, 0), prefund.turn_num);
    try testing.expect(prefund.outcome.allocations.len == 0);
    try testing.expect(!prefund.is_final);
}

test "DirectFund: postfund state has correct turn and funded outcome" {
    const a = testing.allocator;
    const fixed = try makeFixedPart(a);
    defer fixed.deinit(a);

    const outcome = try makeOutcome(a);
    defer outcome.deinit(a);

    var obj = try DirectFundObjective.init(
        makeObjectiveId(0x01),
        0,
        fixed,
        outcome,
        a,
    );
    defer obj.deinit(a);

    const postfund = try obj.generatePostfundState(a);
    defer postfund.deinit(a);

    const n = fixed.participants.len;
    const expected_turn = (n * 2) - 1; // 2*2-1 = 3 for 2 participants

    try testing.expectEqual(@as(u64, expected_turn), postfund.turn_num);
    try testing.expect(postfund.outcome.allocations.len == 2);
    try testing.expectEqual(@as(u256, 1000), postfund.outcome.allocations[0].amount);
    try testing.expectEqual(@as(u256, 2000), postfund.outcome.allocations[1].amount);
}

test "DirectFund: deposit ordering - second participant waits" {
    const a = testing.allocator;
    const fixed = try makeFixedPart(a);
    defer fixed.deinit(a);

    const outcome = try makeOutcome(a);
    defer outcome.deinit(a);

    // Bob is participant 1
    var obj = try DirectFundObjective.init(
        makeObjectiveId(0x01),
        1, // Bob
        fixed,
        outcome,
        a,
    );
    defer obj.deinit(a);

    obj.status = .Approved;
    obj.prefund_signatures[0] = Signature{ .r = [_]u8{0xAA} ** 32, .s = [_]u8{0xBB} ** 32, .v = 27 };
    obj.prefund_signatures[1] = Signature{ .r = [_]u8{0xCC} ** 32, .s = [_]u8{0xDD} ** 32, .v = 27 };

    // Bob's turn? No - Alice (index 0) hasn't deposited yet
    try testing.expect(!obj.isMyTurnToDeposit());

    // Alice deposits
    obj.deposits_detected[0] = true;

    // Now it's Bob's turn
    try testing.expect(obj.isMyTurnToDeposit());
}
