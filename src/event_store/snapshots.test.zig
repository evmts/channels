const std = @import("std");
const testing = std.testing;
const SnapshotManager = @import("snapshots.zig").SnapshotManager;
const Snapshot = @import("snapshots.zig").Snapshot;

test "SnapshotManager: init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mgr = try SnapshotManager.init(allocator);
    defer mgr.deinit();

    try testing.expectEqual(@as(usize, 1000), mgr.interval);
    try testing.expectEqual(@as(usize, 0), mgr.count());
}

test "SnapshotManager: custom interval" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mgr = try SnapshotManager.initWithInterval(allocator, 100);
    defer mgr.deinit();

    try testing.expectEqual(@as(usize, 100), mgr.interval);
}

test "SnapshotManager: create and get snapshot" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mgr = try SnapshotManager.init(allocator);
    defer mgr.deinit();

    const data = "test snapshot data";
    try mgr.createSnapshot(1000, data);

    const snapshot = mgr.getSnapshot(1000);
    try testing.expect(snapshot != null);
    try testing.expectEqual(@as(u64, 1000), snapshot.?.offset);
    try testing.expectEqualStrings(data, snapshot.?.data);
}

test "SnapshotManager: get nonexistent snapshot" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mgr = try SnapshotManager.init(allocator);
    defer mgr.deinit();

    const snapshot = mgr.getSnapshot(999);
    try testing.expect(snapshot == null);
}

test "SnapshotManager: getLatestSnapshot" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mgr = try SnapshotManager.initWithInterval(allocator, 100);
    defer mgr.deinit();

    // Create snapshots at 100, 200, 300
    try mgr.createSnapshot(100, "snapshot@100");
    try mgr.createSnapshot(200, "snapshot@200");
    try mgr.createSnapshot(300, "snapshot@300");

    // Get latest before 250 (should be 200)
    const snap1 = mgr.getLatestSnapshot(250);
    try testing.expect(snap1 != null);
    try testing.expectEqual(@as(u64, 200), snap1.?.offset);

    // Get latest before 100 (should be none)
    const snap2 = mgr.getLatestSnapshot(100);
    try testing.expect(snap2 == null);

    // Get latest before 1000 (should be 300)
    const snap3 = mgr.getLatestSnapshot(1000);
    try testing.expect(snap3 != null);
    try testing.expectEqual(@as(u64, 300), snap3.?.offset);
}

test "SnapshotManager: shouldSnapshot" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mgr = try SnapshotManager.initWithInterval(allocator, 1000);
    defer mgr.deinit();

    try testing.expect(!mgr.shouldSnapshot(0));
    try testing.expect(!mgr.shouldSnapshot(999));
    try testing.expect(mgr.shouldSnapshot(1000));
    try testing.expect(!mgr.shouldSnapshot(1001));
    try testing.expect(mgr.shouldSnapshot(2000));
    try testing.expect(mgr.shouldSnapshot(3000));
}

test "SnapshotManager: nextSnapshotOffset" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mgr = try SnapshotManager.initWithInterval(allocator, 1000);
    defer mgr.deinit();

    try testing.expectEqual(@as(u64, 1000), mgr.nextSnapshotOffset(0));
    try testing.expectEqual(@as(u64, 1000), mgr.nextSnapshotOffset(500));
    try testing.expectEqual(@as(u64, 1000), mgr.nextSnapshotOffset(999));
    try testing.expectEqual(@as(u64, 2000), mgr.nextSnapshotOffset(1000));
    try testing.expectEqual(@as(u64, 2000), mgr.nextSnapshotOffset(1500));
}

test "SnapshotManager: replace existing snapshot" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mgr = try SnapshotManager.init(allocator);
    defer mgr.deinit();

    try mgr.createSnapshot(1000, "first");
    try mgr.createSnapshot(1000, "second");

    const snapshot = mgr.getSnapshot(1000);
    try testing.expect(snapshot != null);
    try testing.expectEqualStrings("second", snapshot.?.data);
    try testing.expectEqual(@as(usize, 1), mgr.count());
}

test "SnapshotManager: count snapshots" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mgr = try SnapshotManager.initWithInterval(allocator, 100);
    defer mgr.deinit();

    try testing.expectEqual(@as(usize, 0), mgr.count());

    try mgr.createSnapshot(100, "s1");
    try testing.expectEqual(@as(usize, 1), mgr.count());

    try mgr.createSnapshot(200, "s2");
    try testing.expectEqual(@as(usize, 2), mgr.count());

    try mgr.createSnapshot(300, "s3");
    try testing.expectEqual(@as(usize, 3), mgr.count());
}

test "SnapshotManager: multiple snapshots with intervals" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mgr = try SnapshotManager.initWithInterval(allocator, 1000);
    defer mgr.deinit();

    // Simulate creating snapshots at regular intervals
    var offset: u64 = 1000;
    while (offset <= 5000) : (offset += 1000) {
        const data = try std.fmt.allocPrint(allocator, "snapshot@{d}", .{offset});
        defer allocator.free(data);
        try mgr.createSnapshot(offset, data);
    }

    try testing.expectEqual(@as(usize, 5), mgr.count());

    // Verify we can retrieve each snapshot
    try testing.expect(mgr.getSnapshot(1000) != null);
    try testing.expect(mgr.getSnapshot(2000) != null);
    try testing.expect(mgr.getSnapshot(3000) != null);
    try testing.expect(mgr.getSnapshot(4000) != null);
    try testing.expect(mgr.getSnapshot(5000) != null);
}

test "SnapshotManager: getLatestSnapshot with gaps" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mgr = try SnapshotManager.init(allocator);
    defer mgr.deinit();

    // Create snapshots with gaps
    try mgr.createSnapshot(1000, "s1");
    try mgr.createSnapshot(3000, "s3");
    try mgr.createSnapshot(5000, "s5");

    // Query between snapshots
    const snap1 = mgr.getLatestSnapshot(2500);
    try testing.expect(snap1 != null);
    try testing.expectEqual(@as(u64, 1000), snap1.?.offset);

    const snap2 = mgr.getLatestSnapshot(4500);
    try testing.expect(snap2 != null);
    try testing.expectEqual(@as(u64, 3000), snap2.?.offset);

    const snap3 = mgr.getLatestSnapshot(6000);
    try testing.expect(snap3 != null);
    try testing.expectEqual(@as(u64, 5000), snap3.?.offset);
}
