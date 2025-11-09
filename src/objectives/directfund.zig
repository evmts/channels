const std = @import("std");
const array_list = std.array_list;
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const State = @import("../state/types.zig").State;
const FixedPart = @import("../state/types.zig").FixedPart;
const VariablePart = @import("../state/types.zig").VariablePart;
const Outcome = @import("../state/types.zig").Outcome;
const Signature = @import("../state/types.zig").Signature;
const Address = @import("../state/types.zig").Address;
const ChannelId = @import("../state/types.zig").ChannelId;
const channel_id = @import("../state/channel_id.zig");

pub const ObjectiveId = types.ObjectiveId;
pub const ObjectiveStatus = types.ObjectiveStatus;
pub const WaitingFor = types.WaitingFor;
pub const SideEffect = types.SideEffect;
pub const CrankResult = types.CrankResult;
pub const ObjectiveEvent = types.ObjectiveEvent;

/// DirectFund protocol: Prefund → Deposit → Postfund
/// Establishes funded channel between participants
pub const DirectFundObjective = struct {
    id: ObjectiveId,
    channel_id: ChannelId,
    status: ObjectiveStatus,
    my_index: u8, // Which participant are we (0-indexed)

    // Channel parameters
    fixed: FixedPart,
    funding_outcome: Outcome,

    // Protocol state tracking
    prefund_signatures: []?Signature, // One per participant
    postfund_signatures: []?Signature, // One per participant
    deposits_detected: []bool, // One per participant

    allocator: Allocator,

    pub fn init(
        objective_id: ObjectiveId,
        my_index: u8,
        fixed: FixedPart,
        funding_outcome: Outcome,
        a: Allocator,
    ) !DirectFundObjective {
        const n = fixed.participants.len;

        const prefund_sigs = try a.alloc(?Signature, n);
        @memset(prefund_sigs, null);

        const postfund_sigs = try a.alloc(?Signature, n);
        @memset(postfund_sigs, null);

        const deposits = try a.alloc(bool, n);
        @memset(deposits, false);

        const cid = try channel_id.channelId(fixed, a);

        return DirectFundObjective{
            .id = objective_id,
            .channel_id = cid,
            .status = .Unapproved,
            .my_index = my_index,
            .fixed = try fixed.clone(a),
            .funding_outcome = try funding_outcome.clone(a),
            .prefund_signatures = prefund_sigs,
            .postfund_signatures = postfund_sigs,
            .deposits_detected = deposits,
            .allocator = a,
        };
    }

    pub fn deinit(self: DirectFundObjective, a: Allocator) void {
        self.fixed.deinit(a);
        self.funding_outcome.deinit(a);
        a.free(self.prefund_signatures);
        a.free(self.postfund_signatures);
        a.free(self.deposits_detected);
    }

    /// Compute what we're currently waiting for
    pub fn waitingFor(self: DirectFundObjective) WaitingFor {
        if (self.status == .Unapproved) return .approval;
        if (self.status == .Complete or self.status == .Rejected) return .nothing;

        // Check prefund phase
        if (!self.allPrefundSigned()) return .complete_prefund;

        // Check funding phase
        if (!self.allDepositsDetected()) {
            // Check if it's our turn to deposit
            if (self.isMyTurnToDeposit()) {
                return .my_turn_to_fund;
            }
            return .complete_funding;
        }

        // Check postfund phase
        if (!self.allPostfundSigned()) return .complete_postfund;

        return .nothing;
    }

    /// Pure state transition + side effect computation
    pub fn crank(self: *DirectFundObjective, event: ObjectiveEvent, a: Allocator) !CrankResult {
        var effects = array_list.AlignedManaged(SideEffect, null).init(a);
        errdefer {
            for (effects.items) |effect| effect.deinit(a);
            effects.deinit();
        }

        switch (event) {
            .approval_granted => {
                if (self.status == .Unapproved) {
                    self.status = .Approved;

                    // Generate and sign prefund state
                    const prefund = try self.generatePrefundState(a);
                    defer prefund.deinit(a);

                    const sig = try self.signState(prefund);
                    self.prefund_signatures[self.my_index] = sig;

                    // Send to all other participants
                    const peers = try self.otherParticipants(a);
                    // NOTE: peers ownership transferred to SideEffect

                    try effects.append(.{
                        .send_message = .{
                            .to = peers,
                            .payload = .{
                                .signed_state = .{
                                    .state = try prefund.clone(a),
                                    .signature = sig,
                                },
                            },
                        },
                    });
                }
            },

            .state_received => |sr| {
                if (!std.mem.eql(u8, &sr.channel_id, &self.channel_id)) {
                    return error.WrongChannel;
                }

                // Determine if this is prefund or postfund
                if (sr.turn_num == 0) {
                    // Prefund state (turn 0)
                    const signer_idx = try self.findParticipantIndex(sr.from);
                    if (self.prefund_signatures[signer_idx] == null) {
                        self.prefund_signatures[signer_idx] = sr.signature;
                    }

                    // If all prefund signed and we haven't deposited, check if our turn
                    if (self.allPrefundSigned() and !self.deposits_detected[self.my_index]) {
                        if (self.isMyTurnToDeposit()) {
                            // Emit deposit transaction
                            const deposit_tx = try self.generateDepositTx(a);
                            try effects.append(.{ .submit_tx = deposit_tx });
                        }
                    }
                } else if (sr.turn_num == 3) {
                    // Postfund state (turn 3 for 2-party)
                    const signer_idx = try self.findParticipantIndex(sr.from);
                    if (self.postfund_signatures[signer_idx] == null) {
                        self.postfund_signatures[signer_idx] = sr.signature;
                    }

                    // Check if complete
                    if (self.allPostfundSigned()) {
                        self.status = .Complete;
                    }
                }
            },

            .deposit_detected => |dd| {
                if (!std.mem.eql(u8, &dd.channel_id, &self.channel_id)) {
                    return error.WrongChannel;
                }

                const depositor_idx = try self.findParticipantIndex(dd.depositor);
                self.deposits_detected[depositor_idx] = true;

                // Check if it's now our turn to deposit
                if (!self.deposits_detected[self.my_index] and self.isMyTurnToDeposit()) {
                    const deposit_tx = try self.generateDepositTx(a);
                    try effects.append(.{ .submit_tx = deposit_tx });
                }

                // If all deposits detected, generate and send postfund
                if (self.allDepositsDetected() and self.postfund_signatures[self.my_index] == null) {
                    const postfund = try self.generatePostfundState(a);
                    defer postfund.deinit(a);

                    const sig = try self.signState(postfund);
                    self.postfund_signatures[self.my_index] = sig;

                    const peers = try self.otherParticipants(a);
                    // NOTE: peers ownership transferred to SideEffect

                    try effects.append(.{
                        .send_message = .{
                            .to = peers,
                            .payload = .{
                                .signed_state = .{
                                    .state = try postfund.clone(a),
                                    .signature = sig,
                                },
                            },
                        },
                    });

                    // Check if we already have all postfund sigs (edge case)
                    if (self.allPostfundSigned()) {
                        self.status = .Complete;
                    }
                }
            },

            .state_signed => {
                // Local state signing - already handled in approval/deposit logic
            },
        }

        return CrankResult{
            .side_effects = try effects.toOwnedSlice(),
            .waiting_for = self.waitingFor(),
        };
    }

    // ========== Helper Functions ==========

    pub fn allPrefundSigned(self: DirectFundObjective) bool {
        for (self.prefund_signatures) |sig| {
            if (sig == null) return false;
        }
        return true;
    }

    pub fn allPostfundSigned(self: DirectFundObjective) bool {
        for (self.postfund_signatures) |sig| {
            if (sig == null) return false;
        }
        return true;
    }

    pub fn allDepositsDetected(self: DirectFundObjective) bool {
        for (self.deposits_detected) |deposited| {
            if (!deposited) return false;
        }
        return true;
    }

    pub fn isMyTurnToDeposit(self: DirectFundObjective) bool {
        // Deposit in order of participant index
        // Our turn if all previous participants have deposited
        for (self.deposits_detected, 0..) |deposited, i| {
            if (i < self.my_index and !deposited) return false;
            if (i == self.my_index and !deposited) return true;
        }
        return false; // Already deposited
    }

    pub fn generatePrefundState(self: DirectFundObjective, a: Allocator) !State {
        // Prefund: turn 0, empty allocations (no funds yet)
        const empty_outcome = Outcome{
            .asset = self.funding_outcome.asset,
            .allocations = &[_]@import("../state/types.zig").Allocation{},
        };

        return State{
            .participants = try a.dupe(Address, self.fixed.participants),
            .channel_nonce = self.fixed.channel_nonce,
            .app_definition = self.fixed.app_definition,
            .challenge_duration = self.fixed.challenge_duration,
            .app_data = try a.dupe(u8, ""),
            .outcome = try empty_outcome.clone(a),
            .turn_num = 0,
            .is_final = false,
        };
    }

    pub fn generatePostfundState(self: DirectFundObjective, a: Allocator) !State {
        // Postfund: turn 3 (2-party), with funded allocations
        const n = self.fixed.participants.len;
        const turn = (n * 2) - 1; // Formula: 2n-1 for n participants

        return State{
            .participants = try a.dupe(Address, self.fixed.participants),
            .channel_nonce = self.fixed.channel_nonce,
            .app_definition = self.fixed.app_definition,
            .challenge_duration = self.fixed.challenge_duration,
            .app_data = try a.dupe(u8, ""),
            .outcome = try self.funding_outcome.clone(a),
            .turn_num = turn,
            .is_final = false,
        };
    }

    fn signState(self: DirectFundObjective, state: State) !Signature {
        // TODO: Real signing via crypto module
        // For now, return mock signature
        _ = self;
        _ = state;
        return Signature{
            .r = [_]u8{0xAA} ** 32,
            .s = [_]u8{0xBB} ** 32,
            .v = 27,
        };
    }

    fn generateDepositTx(self: DirectFundObjective, a: Allocator) !SideEffect.Transaction {
        // TODO: Real contract encoding
        // For now, mock transaction
        const my_allocation = self.funding_outcome.allocations[self.my_index];

        return SideEffect.Transaction{
            .to = self.funding_outcome.asset, // Asset contract
            .data = try a.dupe(u8, "mock_deposit_call"),
            .value = my_allocation.amount,
        };
    }

    fn findParticipantIndex(self: DirectFundObjective, addr: Address) !u8 {
        for (self.fixed.participants, 0..) |p, i| {
            if (std.mem.eql(u8, &p, &addr)) {
                return @intCast(i);
            }
        }
        return error.ParticipantNotFound;
    }

    fn otherParticipants(self: DirectFundObjective, a: Allocator) ![]Address {
        const n = self.fixed.participants.len;
        const peers = try a.alloc(Address, n - 1);
        var idx: usize = 0;
        for (self.fixed.participants, 0..) |p, i| {
            if (i != self.my_index) {
                peers[idx] = p;
                idx += 1;
            }
        }
        return peers;
    }
};
