const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Address = [20]u8;
pub const Bytes32 = [32]u8;
pub const ChannelId = Bytes32;

pub const FixedPart = struct {
    participants: []Address,
    channel_nonce: u64,
    app_definition: Address,
    challenge_duration: u32,

    pub fn clone(self: FixedPart, a: Allocator) !FixedPart {
        const participants_copy = try a.alloc(Address, self.participants.len);
        @memcpy(participants_copy, self.participants);
        return FixedPart{
            .participants = participants_copy,
            .channel_nonce = self.channel_nonce,
            .app_definition = self.app_definition,
            .challenge_duration = self.challenge_duration,
        };
    }

    pub fn deinit(self: FixedPart, a: Allocator) void {
        a.free(self.participants);
    }
};

pub const VariablePart = struct {
    app_data: []const u8,
    outcome: Outcome,
    turn_num: u64,
    is_final: bool,

    pub fn clone(self: VariablePart, a: Allocator) !VariablePart {
        const app_data_copy = try a.dupe(u8, self.app_data);
        const outcome_copy = try self.outcome.clone(a);
        return VariablePart{
            .app_data = app_data_copy,
            .outcome = outcome_copy,
            .turn_num = self.turn_num,
            .is_final = self.is_final,
        };
    }

    pub fn deinit(self: VariablePart, a: Allocator) void {
        a.free(self.app_data);
        self.outcome.deinit(a);
    }
};

pub const State = struct {
    // Fixed
    participants: []Address,
    channel_nonce: u64,
    app_definition: Address,
    challenge_duration: u32,
    // Variable
    app_data: []const u8,
    outcome: Outcome,
    turn_num: u64,
    is_final: bool,

    pub fn fixedPart(self: State) FixedPart {
        return FixedPart{
            .participants = self.participants,
            .channel_nonce = self.channel_nonce,
            .app_definition = self.app_definition,
            .challenge_duration = self.challenge_duration,
        };
    }

    pub fn variablePart(self: State, a: Allocator) !VariablePart {
        return VariablePart{
            .app_data = try a.dupe(u8, self.app_data),
            .outcome = try self.outcome.clone(a),
            .turn_num = self.turn_num,
            .is_final = self.is_final,
        };
    }

    pub fn clone(self: State, a: Allocator) !State {
        const participants_copy = try a.alloc(Address, self.participants.len);
        @memcpy(participants_copy, self.participants);
        const app_data_copy = try a.dupe(u8, self.app_data);
        const outcome_copy = try self.outcome.clone(a);

        return State{
            .participants = participants_copy,
            .channel_nonce = self.channel_nonce,
            .app_definition = self.app_definition,
            .challenge_duration = self.challenge_duration,
            .app_data = app_data_copy,
            .outcome = outcome_copy,
            .turn_num = self.turn_num,
            .is_final = self.is_final,
        };
    }

    pub fn deinit(self: State, a: Allocator) void {
        a.free(self.participants);
        a.free(self.app_data);
        self.outcome.deinit(a);
    }
};

pub const Signature = struct {
    r: [32]u8,
    s: [32]u8,
    v: u8,

    pub fn toBytes(self: Signature) [65]u8 {
        var result: [65]u8 = undefined;
        @memcpy(result[0..32], &self.r);
        @memcpy(result[32..64], &self.s);
        result[64] = self.v;
        return result;
    }

    pub fn fromBytes(bytes: [65]u8) Signature {
        var r: [32]u8 = undefined;
        var s: [32]u8 = undefined;
        @memcpy(&r, bytes[0..32]);
        @memcpy(&s, bytes[32..64]);
        return Signature{
            .r = r,
            .s = s,
            .v = bytes[64],
        };
    }
};

pub const Outcome = struct {
    asset: Address,
    allocations: []Allocation,

    pub fn clone(self: Outcome, a: Allocator) !Outcome {
        const allocations_copy = try a.alloc(Allocation, self.allocations.len);
        for (self.allocations, 0..) |alloc, i| {
            allocations_copy[i] = try alloc.clone(a);
        }
        return Outcome{
            .asset = self.asset,
            .allocations = allocations_copy,
        };
    }

    pub fn deinit(self: Outcome, a: Allocator) void {
        for (self.allocations) |alloc| {
            alloc.deinit(a);
        }
        a.free(self.allocations);
    }
};

pub const Allocation = struct {
    destination: Bytes32,
    amount: u256,
    allocation_type: AllocationType,
    metadata: []const u8,

    pub const AllocationType = enum(u8) {
        simple = 0,
        guarantee = 1,
    };

    pub fn clone(self: Allocation, a: Allocator) !Allocation {
        const metadata_copy = try a.dupe(u8, self.metadata);
        return Allocation{
            .destination = self.destination,
            .amount = self.amount,
            .allocation_type = self.allocation_type,
            .metadata = metadata_copy,
        };
    }

    pub fn deinit(self: Allocation, a: Allocator) void {
        a.free(self.metadata);
    }
};
