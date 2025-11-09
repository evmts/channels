const std = @import("std");
const array_list = std.array_list;
const Allocator = std.mem.Allocator;
const Address = @import("../state/types.zig").Address;
const ChannelId = @import("../state/types.zig").ChannelId;
const SideEffect = @import("types.zig").SideEffect;

/// Mock chain service for testing deposit detection
pub const MockChainService = struct {
    deposits: array_list.AlignedManaged(DepositRecord, null),
    allocator: Allocator,

    pub const DepositRecord = struct {
        channel_id: ChannelId,
        asset: Address,
        amount: u256,
        depositor: Address,
    };

    pub fn init(a: Allocator) MockChainService {
        return .{
            .deposits = array_list.AlignedManaged(DepositRecord, null).init(a),
            .allocator = a,
        };
    }

    pub fn deinit(self: *MockChainService) void {
        self.deposits.deinit();
    }

    /// Simulate submitting a deposit transaction
    pub fn submitDeposit(
        self: *MockChainService,
        tx: SideEffect.Transaction,
        channel_id: ChannelId,
        depositor: Address,
    ) !void {
        try self.deposits.append(.{
            .channel_id = channel_id,
            .asset = tx.to,
            .amount = tx.value,
            .depositor = depositor,
        });
    }

    /// Get all deposits for a channel
    pub fn getDeposits(self: *MockChainService, channel_id: ChannelId) ![]DepositRecord {
        var results = array_list.AlignedManaged(DepositRecord, null).init(self.allocator);
        defer results.deinit();

        for (self.deposits.items) |dep| {
            if (std.mem.eql(u8, &dep.channel_id, &channel_id)) {
                try results.append(dep);
            }
        }

        return results.toOwnedSlice();
    }

    /// Check if participant has deposited
    pub fn hasDeposited(self: *MockChainService, channel_id: ChannelId, participant: Address) bool {
        for (self.deposits.items) |dep| {
            if (std.mem.eql(u8, &dep.channel_id, &channel_id) and
                std.mem.eql(u8, &dep.depositor, &participant))
            {
                return true;
            }
        }
        return false;
    }

    /// Reset all deposits (for test isolation)
    pub fn reset(self: *MockChainService) void {
        self.deposits.clearRetainingCapacity();
    }
};

/// Mock message service for testing P2P communication
pub const MockMessageService = struct {
    messages: array_list.AlignedManaged(MessageRecord, null),
    allocator: Allocator,

    pub const MessageRecord = struct {
        to: []const Address,
        payload: SideEffect.Message.MessagePayload,

        pub fn deinit(self: MessageRecord, a: Allocator) void {
            a.free(self.to);
            switch (self.payload) {
                .signed_state => |ss| ss.state.deinit(a),
                .objective_request => {},
            }
        }
    };

    pub fn init(a: Allocator) MockMessageService {
        return .{
            .messages = array_list.AlignedManaged(MessageRecord, null).init(a),
            .allocator = a,
        };
    }

    pub fn deinit(self: *MockMessageService) void {
        for (self.messages.items) |msg| {
            msg.deinit(self.allocator);
        }
        self.messages.deinit();
    }

    /// Simulate sending a message
    pub fn sendMessage(self: *MockMessageService, msg: SideEffect.Message) !void {
        const to_copy = try self.allocator.alloc(Address, msg.to.len);
        @memcpy(to_copy, msg.to);

        const payload_copy = switch (msg.payload) {
            .signed_state => |ss| SideEffect.Message.MessagePayload{
                .signed_state = .{
                    .state = try ss.state.clone(self.allocator),
                    .signature = ss.signature,
                },
            },
            .objective_request => |or_val| SideEffect.Message.MessagePayload{
                .objective_request = or_val,
            },
        };

        try self.messages.append(.{
            .to = to_copy,
            .payload = payload_copy,
        });
    }

    /// Get all messages sent to a participant
    pub fn getMessagesTo(self: *MockMessageService, participant: Address) ![]MessageRecord {
        var results = array_list.AlignedManaged(MessageRecord, null).init(self.allocator);
        defer results.deinit();

        for (self.messages.items) |msg| {
            for (msg.to) |recipient| {
                if (std.mem.eql(u8, &recipient, &participant)) {
                    try results.append(msg);
                    break;
                }
            }
        }

        // Return references - caller doesn't own
        return results.toOwnedSlice();
    }

    /// Count messages of a specific type
    pub fn countSignedStateMessages(self: *MockMessageService) usize {
        var count: usize = 0;
        for (self.messages.items) |msg| {
            if (msg.payload == .signed_state) count += 1;
        }
        return count;
    }

    /// Reset all messages (for test isolation)
    pub fn reset(self: *MockMessageService) void {
        for (self.messages.items) |msg| {
            msg.deinit(self.allocator);
        }
        self.messages.clearRetainingCapacity();
    }
};
