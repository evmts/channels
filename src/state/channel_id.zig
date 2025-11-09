const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives");
const crypto_pkg = @import("crypto");

const ChannelId = types.ChannelId;
const FixedPart = types.FixedPart;
const Hash = crypto_pkg.Hash;
const abi = primitives.AbiEncoding;

/// Generate deterministic ChannelId from FixedPart using Ethereum-compatible formula:
/// ChannelId = keccak256(abi.encodePacked(participants, nonce, appDef, challengeDuration))
///
/// This matches the Nitro Protocol and Ethereum L1 adjudicator contract.
/// Same FixedPart will always produce same ChannelId (deterministic).
/// 256-bit hash provides collision resistance.
pub fn channelId(fixed: FixedPart, allocator: std.mem.Allocator) !ChannelId {
    // Build array with all values: participants addresses + nonce + appDef + challengeDuration
    const num_values = fixed.participants.len + 3; // participants + 3 fixed fields
    var all_values = try allocator.alloc(abi.AbiValue, num_values);
    defer allocator.free(all_values);

    // Add each participant address individually
    for (fixed.participants, 0..) |addr, i| {
        const prim_addr = primitives.Address.Address{ .bytes = addr };
        all_values[i] = abi.addressValue(prim_addr);
    }

    // Add fixed fields after participants
    const app_addr = primitives.Address.Address{ .bytes = fixed.app_definition };
    all_values[fixed.participants.len] = abi.AbiValue{ .uint64 = fixed.channel_nonce };
    all_values[fixed.participants.len + 1] = abi.addressValue(app_addr);
    all_values[fixed.participants.len + 2] = abi.AbiValue{ .uint32 = fixed.challenge_duration };

    // Encode all values together
    const encoded = try abi.encodePacked(allocator, all_values);
    defer allocator.free(encoded);

    // Keccak256 hash
    return Hash.keccak256(encoded);
}
