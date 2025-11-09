const std = @import("std");

// TODO: Will be regenerated from Phase 1b - EventStore dependency
// const EventStore = @import("store.zig").EventStore;

/// Objective lifecycle events
pub const ObjectiveCreatedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    objective_id: [32]u8,
    objective_type: ObjectiveType,
    channel_id: [32]u8,
    participants: [][20]u8,

    pub const ObjectiveType = enum {
        DirectFund,
        DirectDefund,
        VirtualFund,
        VirtualDefund,
    };

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        _ = ctx;
        if (self.participants.len < 2) return error.InsufficientParticipants;
        if (self.participants.len > 255) return error.TooManyParticipants;
        // Precondition: objective_id must be unique (checked by caller against store)
    }
};

pub const ObjectiveApprovedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    objective_id: [32]u8,
    approver: ?[20]u8,

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        // Precondition: objective must exist and be in unapproved state
        if (!ctx.objectiveExists(self.objective_id)) return error.ObjectiveNotFound;
        // Postcondition: objective transitions to approved state
    }
};

pub const ObjectiveRejectedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    objective_id: [32]u8,
    reason: []const u8,
    error_code: ?[]const u8,

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (!ctx.objectiveExists(self.objective_id)) return error.ObjectiveNotFound;
        // Postcondition: objective transitions to rejected state
    }
};

pub const ObjectiveCrankedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    objective_id: [32]u8,
    side_effects_count: u32,
    waiting: bool,

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (!ctx.objectiveExists(self.objective_id)) return error.ObjectiveNotFound;
        // Precondition: objective must be approved
        // Postcondition: side effects recorded, waiting flag updated
    }
};

pub const ObjectiveCompletedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    objective_id: [32]u8,
    success: bool,
    final_channel_state: ?[32]u8,

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (!ctx.objectiveExists(self.objective_id)) return error.ObjectiveNotFound;
        // Postcondition: objective transitions to completed state (terminal)
    }
};

/// Channel state events
pub const ChannelCreatedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    channel_id: [32]u8,
    participants: [][20]u8,
    channel_nonce: u64,
    app_definition: [20]u8,
    challenge_duration: u32,

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (self.participants.len < 2) return error.InsufficientParticipants;
        if (self.participants.len > 255) return error.TooManyParticipants;
        if (self.challenge_duration < 1) return error.InvalidChallengeDuration;
        // Precondition: channel_id must be derived from fixed part via keccak256
        // Postcondition: channel exists in store with fixed part materialized
        _ = ctx;
    }
};

pub const StateSignedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    channel_id: [32]u8,
    turn_num: u64,
    state_hash: [32]u8,
    signer: [20]u8,
    signature: [65]u8,
    is_final: bool,
    app_data_hash: ?[32]u8,

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (!ctx.channelExists(self.channel_id)) return error.ChannelNotFound;
        // Precondition: turn_num = prev.turn_num + 1 (sequential turns)
        // Precondition: signer ∈ participants
        // Precondition: signature valid over state_hash
        // Postcondition: latest_signed_turn := turn_num
    }
};

pub const StateReceivedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    channel_id: [32]u8,
    turn_num: u64,
    state_hash: [32]u8,
    signer: [20]u8,
    signature: [65]u8,
    is_final: bool,
    peer_id: ?[]const u8,

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (!ctx.channelExists(self.channel_id)) return error.ChannelNotFound;
        // Precondition: signature valid over state_hash
        // Precondition: signer ∈ participants
        // Postcondition: state stored, may trigger supported-updated event
    }
};

pub const StateSupportedUpdatedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    channel_id: [32]u8,
    supported_turn: u64,
    state_hash: [32]u8,
    num_signatures: u32,
    prev_supported_turn: u64,

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (!ctx.channelExists(self.channel_id)) return error.ChannelNotFound;
        // Precondition: supported_turn > prev_supported_turn
        // Precondition: num_signatures >= required threshold
        // Postcondition: channel.supported_turn := supported_turn
        if (self.supported_turn <= self.prev_supported_turn) return error.InvalidTurnProgression;
        if (self.num_signatures == 0) return error.NoSignatures;
    }
};

pub const ChannelFinalizedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    channel_id: [32]u8,
    final_turn: u64,
    final_state_hash: [32]u8,

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (!ctx.channelExists(self.channel_id)) return error.ChannelNotFound;
        // Precondition: all participants signed state with isFinal=true
        // Postcondition: channel can be concluded off-chain
    }
};

/// Chain bridge events
pub const DepositDetectedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    channel_id: [32]u8,
    block_num: u64,
    tx_index: u32,
    tx_hash: ?[32]u8,
    asset: [20]u8,
    amount_deposited: []const u8, // decimal string
    now_held: []const u8, // decimal string

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (!ctx.channelExists(self.channel_id)) return error.ChannelNotFound;
        // Precondition: chain event observed at block_num
        // Postcondition: channel holdings updated
    }
};

pub const AllocationUpdatedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    channel_id: [32]u8,
    block_num: u64,
    tx_index: u32,
    tx_hash: ?[32]u8,
    asset: [20]u8,
    new_amount: []const u8, // decimal string

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (!ctx.channelExists(self.channel_id)) return error.ChannelNotFound;
    }
};

pub const ChallengeRegisteredEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    channel_id: [32]u8,
    block_num: u64,
    tx_index: u32,
    tx_hash: ?[32]u8,
    turn_num_record: u64,
    finalization_time: u64, // unix timestamp
    challenger: [20]u8,
    is_final: bool,
    candidate_state_hash: ?[32]u8,

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (!ctx.channelExists(self.channel_id)) return error.ChannelNotFound;
        // Precondition: chain event references valid channel_id
        // Precondition: turn_num_record >= supported_turn
        // Postcondition: challenge registered, timer started
    }
};

pub const ChallengeClearedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    channel_id: [32]u8,
    block_num: u64,
    tx_index: u32,
    tx_hash: ?[32]u8,
    new_turn_num_record: u64,

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (!ctx.channelExists(self.channel_id)) return error.ChannelNotFound;
        // Precondition: new_turn_num_record > challenged turn
        // Postcondition: challenge cleared, timer reset
    }
};

pub const ChannelConcludedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    channel_id: [32]u8,
    block_num: u64,
    tx_index: u32,
    tx_hash: ?[32]u8,
    finalized_at_turn: ?u64,

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (!ctx.channelExists(self.channel_id)) return error.ChannelNotFound;
        // Postcondition: channel concluded on-chain, can withdraw
    }
};

pub const WithdrawCompletedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    channel_id: [32]u8,
    block_num: u64,
    tx_index: u32,
    tx_hash: ?[32]u8,
    recipient: [20]u8,
    asset: [20]u8,
    amount: []const u8, // decimal string

    pub fn validate(self: *const @This(), ctx: *const ValidationCtx) !void {
        if (!ctx.channelExists(self.channel_id)) return error.ChannelNotFound;
        // Precondition: channel concluded on-chain
        // Postcondition: funds transferred to recipient
    }
};

/// Messaging events
pub const MessageSentEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    message_id: [32]u8,
    peer_id: []const u8,
    objective_id: [32]u8,
    payload_type: ?[]const u8,
    payload_size_bytes: u32,

    pub fn validate(_: *const @This(), _: *const ValidationCtx) !void {
        // Precondition: objective exists
        // Postcondition: message queued for delivery
    }
};

pub const MessageReceivedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    message_id: [32]u8,
    peer_id: []const u8,
    objective_id: [32]u8,
    payload_type: ?[]const u8,
    payload_size_bytes: u32,

    pub fn validate(_: *const @This(), _: *const ValidationCtx) !void {
        // Postcondition: message decoded and validated
    }
};

pub const MessageAckedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    message_id: [32]u8,
    peer_id: []const u8,
    roundtrip_ms: u32,

    pub fn validate(_: *const @This(), _: *const ValidationCtx) !void {
        // Precondition: original message_sent event exists
        // Postcondition: delivery confirmed
    }
};

pub const MessageDroppedEvent = struct {
    event_version: u8 = 1,
    timestamp_ms: u64,
    message_id: ?[32]u8,
    peer_id: []const u8,
    reason: []const u8,
    error_code: ErrorCode,
    payload_size_bytes: u32,

    pub const ErrorCode = enum {
        decode_failed,
        signature_invalid,
        channel_unknown,
        payload_invalid,
        replay_attack,
    };

    pub fn validate(_: *const @This(), _: *const ValidationCtx) !void {
        // Postcondition: message rejected, reason logged
    }
};

/// Unified Event type
pub const Event = union(enum) {
    objective_created: ObjectiveCreatedEvent,
    objective_approved: ObjectiveApprovedEvent,
    objective_rejected: ObjectiveRejectedEvent,
    objective_cranked: ObjectiveCrankedEvent,
    objective_completed: ObjectiveCompletedEvent,
    channel_created: ChannelCreatedEvent,
    state_signed: StateSignedEvent,
    state_received: StateReceivedEvent,
    state_supported_updated: StateSupportedUpdatedEvent,
    channel_finalized: ChannelFinalizedEvent,
    deposit_detected: DepositDetectedEvent,
    allocation_updated: AllocationUpdatedEvent,
    challenge_registered: ChallengeRegisteredEvent,
    challenge_cleared: ChallengeClearedEvent,
    channel_concluded: ChannelConcludedEvent,
    withdraw_completed: WithdrawCompletedEvent,
    message_sent: MessageSentEvent,
    message_received: MessageReceivedEvent,
    message_acked: MessageAckedEvent,
    message_dropped: MessageDroppedEvent,

    pub fn validate(self: *const Event, ctx: *const ValidationCtx) !void {
        switch (self.*) {
            inline else => |*event| try event.validate(ctx),
        }
    }
};

/// Validation context for checking event preconditions
/// Provides access to the event store to verify objective/channel existence
// TODO: ValidationCtx will be regenerated from Phase 1b with EventStore
// Stub for now - validation methods temporarily disabled
pub const ValidationCtx = struct {
    // store: *EventStore,  // TODO: Re-enable after Phase 1b

    pub fn init() ValidationCtx {
        return ValidationCtx{};
    }

    /// Check if an objective with given ID exists in the event log
    /// TODO: Re-implement after Phase 1b EventStore regeneration
    pub fn objectiveExists(_: *const @This(), _: [32]u8) bool {
        return true; // Stub - always returns true
    }

    /// Check if a channel with given ID exists in the event log
    /// TODO: Re-implement after Phase 1b EventStore regeneration
    pub fn channelExists(_: *const @This(), _: [32]u8) bool {
        return true; // Stub - always returns true
    }
};
