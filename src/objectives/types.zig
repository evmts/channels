const std = @import("std");
const Allocator = std.mem.Allocator;
const State = @import("../state/types.zig").State;
const Address = @import("../state/types.zig").Address;
const Signature = @import("../state/types.zig").Signature;
const ChannelId = @import("../state/types.zig").ChannelId;

/// Unique identifier for an objective instance
pub const ObjectiveId = [32]u8;

/// Type of objective protocol
pub const ObjectiveType = enum {
    DirectFund,
    DirectDefund,
    VirtualFund,
    VirtualDefund,
};

/// Objective execution status
pub const ObjectiveStatus = enum {
    Unapproved,
    Approved,
    Rejected,
    Complete,
};

/// What the objective is currently waiting for
pub const WaitingFor = union(enum) {
    nothing,
    approval, // Waiting for policymaker approval
    complete_prefund, // Waiting for all prefund signatures
    my_turn_to_fund, // Waiting for our turn to deposit on-chain
    complete_funding, // Waiting for all deposits to appear on-chain
    complete_postfund, // Waiting for all postfund signatures

    pub fn isBlocked(self: WaitingFor) bool {
        return self != .nothing;
    }
};

/// Side effects to be dispatched by the engine
pub const SideEffect = union(enum) {
    send_message: Message,
    submit_tx: Transaction,
    emit_event: EmittedEvent,

    pub const Message = struct {
        to: []const Address,
        payload: MessagePayload,

        pub const MessagePayload = union(enum) {
            signed_state: SignedState,
            objective_request: ObjectiveRequest,
        };

        pub const SignedState = struct {
            state: State,
            signature: Signature,
        };

        pub const ObjectiveRequest = struct {
            objective_id: ObjectiveId,
            objective_type: ObjectiveType,
        };
    };

    pub const Transaction = struct {
        to: Address,
        data: []const u8,
        value: u256,
    };

    pub const EmittedEvent = struct {
        event_type: []const u8,
        payload: []const u8,
    };

    pub fn deinit(self: SideEffect, a: Allocator) void {
        switch (self) {
            .send_message => |msg| {
                a.free(msg.to);
                switch (msg.payload) {
                    .signed_state => |ss| ss.state.deinit(a),
                    .objective_request => {},
                }
            },
            .submit_tx => |tx| a.free(tx.data),
            .emit_event => |evt| {
                a.free(evt.event_type);
                a.free(evt.payload);
            },
        }
    }

    pub fn clone(self: SideEffect, a: Allocator) !SideEffect {
        return switch (self) {
            .send_message => |msg| blk: {
                const to_copy = try a.alloc(Address, msg.to.len);
                @memcpy(to_copy, msg.to);
                const payload_copy = switch (msg.payload) {
                    .signed_state => |ss| Message.MessagePayload{
                        .signed_state = .{
                            .state = try ss.state.clone(a),
                            .signature = ss.signature,
                        },
                    },
                    .objective_request => |or_val| Message.MessagePayload{
                        .objective_request = or_val,
                    },
                };
                break :blk SideEffect{
                    .send_message = .{
                        .to = to_copy,
                        .payload = payload_copy,
                    },
                };
            },
            .submit_tx => |tx| SideEffect{
                .submit_tx = .{
                    .to = tx.to,
                    .data = try a.dupe(u8, tx.data),
                    .value = tx.value,
                },
            },
            .emit_event => |evt| SideEffect{
                .emit_event = .{
                    .event_type = try a.dupe(u8, evt.event_type),
                    .payload = try a.dupe(u8, evt.payload),
                },
            },
        };
    }
};

/// Result of cranking an objective
pub const CrankResult = struct {
    side_effects: []SideEffect,
    waiting_for: WaitingFor,

    pub fn deinit(self: CrankResult, a: Allocator) void {
        for (self.side_effects) |effect| {
            effect.deinit(a);
        }
        a.free(self.side_effects);
    }
};

/// Events that can trigger objective state transitions
pub const ObjectiveEvent = union(enum) {
    approval_granted,
    state_signed: StateSigned,
    state_received: StateReceived,
    deposit_detected: DepositDetected,

    pub const StateSigned = struct {
        channel_id: ChannelId,
        turn_num: u64,
        state: State,
        signature: Signature,
    };

    pub const StateReceived = struct {
        channel_id: ChannelId,
        turn_num: u64,
        state: State,
        signature: Signature,
        from: Address,
    };

    pub const DepositDetected = struct {
        channel_id: ChannelId,
        asset: Address,
        amount: u256,
        depositor: Address,
    };
};
