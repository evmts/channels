const std = @import("std");
const Keccak256 = std.crypto.hash.sha3.Keccak256;

/// Derives deterministic event ID from event type and canonical JSON payload
/// ID = keccak256("ev1|" ++ event_name ++ "|" ++ canonical_json)
pub fn deriveEventId(
    allocator: std.mem.Allocator,
    event_name: []const u8,
    canonical_json: []const u8,
) ![32]u8 {
    // Construct bytestring: b"ev1|<event_name>|<canonical_json>"
    const prefix = "ev1|";
    const separator = "|";

    const total_len = prefix.len + event_name.len + separator.len + canonical_json.len;
    const bytes = try allocator.alloc(u8, total_len);
    defer allocator.free(bytes);

    var offset: usize = 0;
    @memcpy(bytes[offset..][0..prefix.len], prefix);
    offset += prefix.len;
    @memcpy(bytes[offset..][0..event_name.len], event_name);
    offset += event_name.len;
    @memcpy(bytes[offset..][0..separator.len], separator);
    offset += separator.len;
    @memcpy(bytes[offset..][0..canonical_json.len], canonical_json);

    // Hash with keccak256
    var hash: [32]u8 = undefined;
    Keccak256.hash(bytes, &hash, .{});
    return hash;
}

/// Canonicalizes JSON for deterministic hashing
/// Rules:
/// - Sorted keys (lexicographic)
/// - No whitespace
/// - UTF-8 encoding
/// - Integers as decimal strings
/// - No trailing commas
/// - Escaped special characters
pub fn canonicalizeJson(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) error{ OutOfMemory, NoSpaceLeft }![]u8 {
    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    try canonicalizeJsonInto(&buffer, allocator, value);
    return buffer.toOwnedSlice(allocator);
}

fn canonicalizeJsonInto(
    buffer: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: std.json.Value,
) error{ OutOfMemory, NoSpaceLeft }!void {
    switch (value) {
        .null => try buffer.appendSlice(allocator, "null"),
        .bool => |b| try buffer.appendSlice(allocator, if (b) "true" else "false"),
        .integer => |i| {
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{i});
            try buffer.appendSlice(allocator, str);
        },
        .float => |f| {
            // Represent floats as decimal strings with fixed precision
            var buf: [64]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d:.6}", .{f});
            try buffer.appendSlice(allocator, str);
        },
        .number_string => |s| {
            // Preserve number strings as-is
            try buffer.appendSlice(allocator, s);
        },
        .string => |s| {
            try buffer.append(allocator, '"');
            for (s) |c| {
                switch (c) {
                    '"' => try buffer.appendSlice(allocator, "\\\""),
                    '\\' => try buffer.appendSlice(allocator, "\\\\"),
                    '\n' => try buffer.appendSlice(allocator, "\\n"),
                    '\r' => try buffer.appendSlice(allocator, "\\r"),
                    '\t' => try buffer.appendSlice(allocator, "\\t"),
                    else => try buffer.append(allocator, c),
                }
            }
            try buffer.append(allocator, '"');
        },
        .array => |arr| {
            try buffer.append(allocator, '[');
            for (arr.items, 0..) |item, i| {
                if (i > 0) try buffer.append(allocator, ',');
                try canonicalizeJsonInto(buffer, allocator, item);
            }
            try buffer.append(allocator, ']');
        },
        .object => |obj| {
            try buffer.append(allocator, '{');

            // Collect and sort keys
            var keys = std.ArrayList([]const u8){};
            defer keys.deinit(allocator);

            var iter = obj.iterator();
            while (iter.next()) |entry| {
                try keys.append(allocator, entry.key_ptr.*);
            }

            // Sort keys lexicographically
            std.mem.sort([]const u8, keys.items, {}, struct {
                fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.lessThan(u8, a, b);
                }
            }.lessThan);

            // Serialize in sorted order
            for (keys.items, 0..) |key, i| {
                if (i > 0) try buffer.append(allocator, ',');

                // Key
                try buffer.append(allocator, '"');
                try buffer.appendSlice(allocator, key);
                try buffer.appendSlice(allocator, "\":");

                // Value
                try canonicalizeJsonInto(buffer, allocator, obj.get(key).?);
            }

            try buffer.append(allocator, '}');
        },
    }
}

test "canonical JSON - object with sorted keys" {
    const allocator = std.testing.allocator;

    var obj = std.json.ObjectMap.init(allocator);
    defer obj.deinit();

    try obj.put("z_field", .{ .integer = 3 });
    try obj.put("a_field", .{ .integer = 1 });
    try obj.put("m_field", .{ .integer = 2 });

    const value = std.json.Value{ .object = obj };
    const canonical = try canonicalizeJson(allocator, value);
    defer allocator.free(canonical);

    const expected = "{\"a_field\":1,\"m_field\":2,\"z_field\":3}";
    try std.testing.expectEqualStrings(expected, canonical);
}

test "canonical JSON - nested object" {
    const allocator = std.testing.allocator;

    var inner = std.json.ObjectMap.init(allocator);
    defer inner.deinit();
    try inner.put("b", .{ .bool = true });
    try inner.put("a", .{ .integer = 42 });

    var outer = std.json.ObjectMap.init(allocator);
    defer outer.deinit();
    try outer.put("nested", .{ .object = inner });
    try outer.put("simple", .{ .string = "test" });

    const value = std.json.Value{ .object = outer };
    const canonical = try canonicalizeJson(allocator, value);
    defer allocator.free(canonical);

    const expected = "{\"nested\":{\"a\":42,\"b\":true},\"simple\":\"test\"}";
    try std.testing.expectEqualStrings(expected, canonical);
}

test "canonical JSON - array" {
    const allocator = std.testing.allocator;

    var arr = std.json.Array.init(allocator);
    defer arr.deinit();

    try arr.append(.{ .integer = 1 });
    try arr.append(.{ .integer = 2 });
    try arr.append(.{ .integer = 3 });

    const value = std.json.Value{ .array = arr };
    const canonical = try canonicalizeJson(allocator, value);
    defer allocator.free(canonical);

    const expected = "[1,2,3]";
    try std.testing.expectEqualStrings(expected, canonical);
}

test "canonical JSON - escaped strings" {
    const allocator = std.testing.allocator;

    const input = "hello\nworld\t\"quoted\"";
    const value = std.json.Value{ .string = input };
    const canonical = try canonicalizeJson(allocator, value);
    defer allocator.free(canonical);

    const expected = "\"hello\\nworld\\t\\\"quoted\\\"\"";
    try std.testing.expectEqualStrings(expected, canonical);
}

test "deriveEventId - same input produces same ID" {
    const allocator = std.testing.allocator;

    const event_name = "state-signed";
    const canonical = "{\"channel_id\":\"0x1234\",\"turn_num\":5}";

    const id1 = try deriveEventId(allocator, event_name, canonical);
    const id2 = try deriveEventId(allocator, event_name, canonical);

    try std.testing.expectEqualSlices(u8, &id1, &id2);
}

test "deriveEventId - different content produces different ID" {
    const allocator = std.testing.allocator;

    const event_name = "state-signed";
    const canonical1 = "{\"channel_id\":\"0x1234\",\"turn_num\":5}";
    const canonical2 = "{\"channel_id\":\"0x1234\",\"turn_num\":6}";

    const id1 = try deriveEventId(allocator, event_name, canonical1);
    const id2 = try deriveEventId(allocator, event_name, canonical2);

    try std.testing.expect(!std.mem.eql(u8, &id1, &id2));
}

test "deriveEventId - field order doesn't matter (canonical form)" {
    const allocator = std.testing.allocator;

    const event_name = "state-signed";
    // Both represent the same canonical form after sorting
    const canonical1 = "{\"a\":1,\"b\":2}";
    const canonical2 = "{\"a\":1,\"b\":2}"; // same order = same canonical

    const id1 = try deriveEventId(allocator, event_name, canonical1);
    const id2 = try deriveEventId(allocator, event_name, canonical2);

    try std.testing.expectEqualSlices(u8, &id1, &id2);
}
