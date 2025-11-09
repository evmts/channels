const std = @import("std");
const Event = @import("events.zig").Event;
const Allocator = std.mem.Allocator;

/// Offset into the event log (0-indexed)
pub const EventOffset = u64;

/// Callback function type for event subscribers
pub const EventCallback = *const fn (Event, EventOffset) void;

/// Subscription handle returned by subscribe()
pub const SubscriptionId = usize;

/// Thread-safe, append-only event store with stable pointers.
/// Based on ADR-0003: Uses SegmentedList for pointer stability during subscriber callbacks.
pub const EventStore = struct {
    allocator: Allocator,
    events: std.SegmentedList(Event, 1024),
    subscribers: std.ArrayList(EventCallback),
    rw_lock: std.Thread.RwLock,
    count: std.atomic.Value(u64),

    const Self = @This();

    /// Initialize a new EventStore.
    /// Caller owns returned pointer and must call deinit().
    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .events = .{},
            .subscribers = std.ArrayList(EventCallback){},
            .rw_lock = .{},
            .count = std.atomic.Value(u64).init(0),
        };

        return self;
    }

    /// Append an event to the log atomically.
    /// Notifies all subscribers after append completes.
    /// Thread-safe: uses write lock.
    pub fn append(self: *Self, event: Event) !EventOffset {
        self.rw_lock.lock();
        defer self.rw_lock.unlock();

        const offset = self.count.fetchAdd(1, .monotonic);
        try self.events.append(self.allocator, event);

        // Notify subscribers with stable pointer
        // SegmentedList guarantees pointer validity (ADR-0003)
        const event_ptr = self.events.at(offset);
        for (self.subscribers.items) |callback| {
            callback(event_ptr.*, offset);
        }

        return offset;
    }

    /// Read a single event at the given offset.
    /// Returns pointer to event (valid until EventStore.deinit).
    /// Thread-safe: uses read lock.
    pub fn readAt(self: *Self, offset: EventOffset) !*const Event {
        self.rw_lock.lockShared();
        defer self.rw_lock.unlockShared();

        if (offset >= self.count.load(.monotonic)) {
            return error.OffsetOutOfBounds;
        }

        return self.events.at(offset);
    }

    /// Read events from start (inclusive) to end (exclusive).
    /// Caller must free returned slice.
    /// Thread-safe: uses read lock.
    pub fn readRange(self: *Self, start: EventOffset, end: EventOffset) ![]const Event {
        self.rw_lock.lockShared();
        defer self.rw_lock.unlockShared();

        const current_len = self.count.load(.monotonic);
        if (start >= current_len or end > current_len or start >= end) {
            return error.InvalidRange;
        }

        const count = end - start;
        const result = try self.allocator.alloc(Event, count);
        errdefer self.allocator.free(result);

        var i: usize = 0;
        var offset = start;
        while (offset < end) : ({
            offset += 1;
            i += 1;
        }) {
            result[i] = self.events.at(offset).*;
        }

        return result;
    }

    /// Read all events from the log.
    /// Caller must free returned slice.
    /// Thread-safe: uses read lock.
    pub fn readAll(self: *Self) ![]const Event {
        const current_len = self.len();
        if (current_len == 0) {
            return &[_]Event{};
        }
        return try self.readRange(0, current_len);
    }

    /// Subscribe to new events. Callback invoked on each append.
    /// Returns subscription ID (currently unused, for future unsubscribe support).
    /// Thread-safe: uses write lock.
    pub fn subscribe(self: *Self, callback: EventCallback) !SubscriptionId {
        self.rw_lock.lock();
        defer self.rw_lock.unlock();

        try self.subscribers.append(self.allocator, callback);
        return self.subscribers.items.len - 1;
    }

    /// Get the current number of events in the log.
    /// Lock-free operation using atomic counter.
    pub fn len(self: *const Self) EventOffset {
        return self.count.load(.monotonic);
    }

    /// Free all resources.
    pub fn deinit(self: *Self) void {
        self.events.deinit(self.allocator);
        self.subscribers.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};
