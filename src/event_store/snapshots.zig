const std = @import("std");
const EventStore = @import("store.zig").EventStore;
const EventOffset = @import("store.zig").EventOffset;
const Allocator = std.mem.Allocator;

/// Snapshot of state at a specific event offset
pub const Snapshot = struct {
    offset: EventOffset,
    timestamp_ms: u64,
    data: []const u8, // Serialized state (JSON for Phase 1)

    pub fn deinit(self: *Snapshot, allocator: Allocator) void {
        allocator.free(self.data);
    }
};

/// Manages snapshots for performance optimization.
/// Creates snapshots every N events (default 1000) to speed up reconstruction.
/// Based on ADR-0001: Snapshots are cache, not source of truth.
pub const SnapshotManager = struct {
    allocator: Allocator,
    interval: usize, // Create snapshot every N events
    snapshots: std.AutoHashMap(EventOffset, Snapshot),

    const Self = @This();

    /// Initialize snapshot manager with default interval (1000)
    pub fn init(allocator: Allocator) !*Self {
        return try initWithInterval(allocator, 1000);
    }

    /// Initialize with custom snapshot interval
    pub fn initWithInterval(allocator: Allocator, interval: usize) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .interval = interval,
            .snapshots = std.AutoHashMap(EventOffset, Snapshot).init(allocator),
        };

        return self;
    }

    /// Create a snapshot at the given offset with serialized data.
    /// Caller must ensure offset is valid and data is properly serialized.
    pub fn createSnapshot(
        self: *Self,
        offset: EventOffset,
        data: []const u8,
    ) !void {
        // Copy data (caller may free their copy)
        const data_copy = try self.allocator.dupe(u8, data);
        errdefer self.allocator.free(data_copy);

        const snapshot = Snapshot{
            .offset = offset,
            .timestamp_ms = @intCast(std.time.milliTimestamp()),
            .data = data_copy,
        };

        // Store snapshot (replaces existing if any)
        const result = try self.snapshots.getOrPut(offset);
        if (result.found_existing) {
            // Free old snapshot data before replacing
            self.allocator.free(result.value_ptr.data);
        }
        result.value_ptr.* = snapshot;
    }

    /// Get the latest snapshot before the given offset.
    /// Returns null if no snapshot exists before offset.
    pub fn getLatestSnapshot(self: *Self, before: EventOffset) ?Snapshot {
        var latest: ?Snapshot = null;
        var latest_offset: EventOffset = 0;

        var iter = self.snapshots.iterator();
        while (iter.next()) |entry| {
            if (entry.key_ptr.* < before and entry.key_ptr.* >= latest_offset) {
                latest_offset = entry.key_ptr.*;
                latest = entry.value_ptr.*;
            }
        }

        return latest;
    }

    /// Get snapshot at exact offset, or null if none exists
    pub fn getSnapshot(self: *Self, offset: EventOffset) ?Snapshot {
        return self.snapshots.get(offset);
    }

    /// Check if a snapshot should be created at this offset
    pub fn shouldSnapshot(self: *Self, offset: EventOffset) bool {
        if (offset == 0) return false;
        return (offset % self.interval) == 0;
    }

    /// Get the next offset where a snapshot should be created
    pub fn nextSnapshotOffset(self: *Self, current: EventOffset) EventOffset {
        const remainder = current % self.interval;
        if (remainder == 0) {
            return current + self.interval;
        } else {
            return current + (self.interval - remainder);
        }
    }

    /// Get count of snapshots
    pub fn count(self: *Self) usize {
        return self.snapshots.count();
    }

    /// Prune old snapshots, keeping only the latest N per offset range.
    /// For Phase 1, keeps all snapshots (pruning deferred to Phase 4).
    pub fn prune(self: *Self, keep_latest: usize) !void {
        _ = self;
        _ = keep_latest;
        // Phase 1: No pruning (in-memory only, bounded test scenarios)
        // Phase 4: Implement pruning strategy for persistent storage
    }

    /// Free all resources
    pub fn deinit(self: *Self) void {
        // Free all snapshot data
        var iter = self.snapshots.valueIterator();
        while (iter.next()) |snapshot| {
            self.allocator.free(snapshot.data);
        }
        self.snapshots.deinit();
        self.allocator.destroy(self);
    }
};
