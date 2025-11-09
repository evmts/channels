const std = @import("std");
const EventStore = @import("store.zig").EventStore;
const Event = @import("events.zig").Event;
const Allocator = std.mem.Allocator;

/// Reconstructed state for an objective (simplified for Phase 1)
pub const ObjectiveState = struct {
    objective_id: [32]u8,
    status: ObjectiveStatus,
    event_count: usize,
    created_at: u64,
    completed_at: ?u64,

    pub const ObjectiveStatus = enum {
        Created,
        Approved,
        Rejected,
        Cranked,
        Completed,
    };

    pub fn init(objective_id: [32]u8, timestamp: u64) ObjectiveState {
        return .{
            .objective_id = objective_id,
            .status = .Created,
            .event_count = 0,
            .created_at = timestamp,
            .completed_at = null,
        };
    }

    /// Apply an event to this state, returning updated state
    pub fn apply(self: ObjectiveState, event: Event) !ObjectiveState {
        var next = self;
        next.event_count += 1;

        switch (event) {
            .objective_created => |e| {
                if (std.mem.eql(u8, &self.objective_id, &e.objective_id)) {
                    next.status = .Created;
                }
            },
            .objective_approved => |e| {
                if (std.mem.eql(u8, &self.objective_id, &e.objective_id)) {
                    next.status = .Approved;
                }
            },
            .objective_rejected => |e| {
                if (std.mem.eql(u8, &self.objective_id, &e.objective_id)) {
                    next.status = .Rejected;
                }
            },
            .objective_cranked => |e| {
                if (std.mem.eql(u8, &self.objective_id, &e.objective_id)) {
                    next.status = .Cranked;
                }
            },
            .objective_completed => |e| {
                if (std.mem.eql(u8, &self.objective_id, &e.objective_id)) {
                    next.status = .Completed;
                    next.completed_at = e.timestamp_ms;
                }
            },
            else => {
                // Ignore non-objective events
            },
        }

        return next;
    }
};

/// Reconstructed state for a channel (simplified for Phase 1)
pub const ChannelState = struct {
    channel_id: [32]u8,
    status: ChannelStatus,
    latest_turn_num: u64,
    latest_supported_turn: u64,
    event_count: usize,
    created_at: u64,
    finalized_at: ?u64,

    pub const ChannelStatus = enum {
        Created,
        Open,
        Finalized,
    };

    pub fn init(channel_id: [32]u8, timestamp: u64) ChannelState {
        return .{
            .channel_id = channel_id,
            .status = .Created,
            .latest_turn_num = 0,
            .latest_supported_turn = 0,
            .event_count = 0,
            .created_at = timestamp,
            .finalized_at = null,
        };
    }

    /// Apply an event to this state, returning updated state
    pub fn apply(self: ChannelState, event: Event) !ChannelState {
        var next = self;
        next.event_count += 1;

        switch (event) {
            .channel_created => |e| {
                if (std.mem.eql(u8, &self.channel_id, &e.channel_id)) {
                    next.status = .Created;
                }
            },
            .state_signed => |e| {
                if (std.mem.eql(u8, &self.channel_id, &e.channel_id)) {
                    if (e.turn_num > next.latest_turn_num) {
                        next.latest_turn_num = e.turn_num;
                    }
                    next.status = .Open;
                }
            },
            .state_received => |e| {
                if (std.mem.eql(u8, &self.channel_id, &e.channel_id)) {
                    if (e.turn_num > next.latest_turn_num) {
                        next.latest_turn_num = e.turn_num;
                    }
                    next.status = .Open;
                }
            },
            .state_supported_updated => |e| {
                if (std.mem.eql(u8, &self.channel_id, &e.channel_id)) {
                    if (e.supported_turn > next.latest_supported_turn) {
                        next.latest_supported_turn = e.supported_turn;
                    }
                }
            },
            .channel_finalized => |e| {
                if (std.mem.eql(u8, &self.channel_id, &e.channel_id)) {
                    next.status = .Finalized;
                    next.finalized_at = e.timestamp_ms;
                }
            },
            else => {
                // Ignore non-channel events
            },
        }

        return next;
    }
};

/// State reconstructor: folds events to derive state
pub const StateReconstructor = struct {
    allocator: Allocator,
    event_store: *EventStore,

    const Self = @This();

    pub fn init(allocator: Allocator, event_store: *EventStore) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .event_store = event_store,
        };
        return self;
    }

    /// Reconstruct objective state from events
    pub fn reconstructObjective(self: *Self, objective_id: [32]u8) !ObjectiveState {
        const events = try self.getObjectiveEvents(objective_id);
        defer self.allocator.free(events);

        if (events.len == 0) {
            return error.ObjectiveNotFound;
        }

        // Initialize state from first event
        var state = switch (events[0]) {
            .objective_created => |e| ObjectiveState.init(e.objective_id, e.timestamp_ms),
            else => return error.InvalidFirstEvent,
        };

        // Fold remaining events
        for (events) |event| {
            state = try state.apply(event);
        }

        return state;
    }

    /// Reconstruct channel state from events
    pub fn reconstructChannel(self: *Self, channel_id: [32]u8) !ChannelState {
        const events = try self.getChannelEvents(channel_id);
        defer self.allocator.free(events);

        if (events.len == 0) {
            return error.ChannelNotFound;
        }

        // Initialize state from first event
        var state = switch (events[0]) {
            .channel_created => |e| ChannelState.init(e.channel_id, e.timestamp_ms),
            else => return error.InvalidFirstEvent,
        };

        // Fold remaining events
        for (events) |event| {
            state = try state.apply(event);
        }

        return state;
    }

    /// Get all events for a specific objective.
    /// Caller must free returned slice.
    fn getObjectiveEvents(self: *Self, objective_id: [32]u8) ![]Event {
        const all_events = try self.event_store.readAll();
        defer self.allocator.free(all_events);

        // Count matching events
        var count: usize = 0;
        for (all_events) |event| {
            if (isObjectiveEvent(event, objective_id)) {
                count += 1;
            }
        }

        // Allocate result
        const result = try self.allocator.alloc(Event, count);
        errdefer self.allocator.free(result);

        // Copy matching events
        var i: usize = 0;
        for (all_events) |event| {
            if (isObjectiveEvent(event, objective_id)) {
                result[i] = event;
                i += 1;
            }
        }

        return result;
    }

    /// Get all events for a specific channel.
    /// Caller must free returned slice.
    fn getChannelEvents(self: *Self, channel_id: [32]u8) ![]Event {
        const all_events = try self.event_store.readAll();
        defer self.allocator.free(all_events);

        // Count matching events
        var count: usize = 0;
        for (all_events) |event| {
            if (isChannelEvent(event, channel_id)) {
                count += 1;
            }
        }

        // Allocate result
        const result = try self.allocator.alloc(Event, count);
        errdefer self.allocator.free(result);

        // Copy matching events
        var i: usize = 0;
        for (all_events) |event| {
            if (isChannelEvent(event, channel_id)) {
                result[i] = event;
                i += 1;
            }
        }

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }
};

/// Check if event is related to the given objective
fn isObjectiveEvent(event: Event, objective_id: [32]u8) bool {
    return switch (event) {
        .objective_created => |e| std.mem.eql(u8, &e.objective_id, &objective_id),
        .objective_approved => |e| std.mem.eql(u8, &e.objective_id, &objective_id),
        .objective_rejected => |e| std.mem.eql(u8, &e.objective_id, &objective_id),
        .objective_cranked => |e| std.mem.eql(u8, &e.objective_id, &objective_id),
        .objective_completed => |e| std.mem.eql(u8, &e.objective_id, &objective_id),
        else => false,
    };
}

/// Check if event is related to the given channel
fn isChannelEvent(event: Event, channel_id: [32]u8) bool {
    return switch (event) {
        .channel_created => |e| std.mem.eql(u8, &e.channel_id, &channel_id),
        .state_signed => |e| std.mem.eql(u8, &e.channel_id, &channel_id),
        .state_received => |e| std.mem.eql(u8, &e.channel_id, &channel_id),
        .state_supported_updated => |e| std.mem.eql(u8, &e.channel_id, &channel_id),
        .channel_finalized => |e| std.mem.eql(u8, &e.channel_id, &channel_id),
        else => false,
    };
}
