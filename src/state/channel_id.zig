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
    // Build ABI values for participants array
    var participant_values = try allocator.alloc(abi.AbiValue, fixed.participants.len);
    defer allocator.free(participant_values);

    for (fixed.participants, 0..) |addr, i| {
        const prim_addr = primitives.Address.Address{ .bytes = addr };
        participant_values[i] = abi.addressValue(prim_addr);
    }

    // Encode participants array separately (dynamic type)
    const participants_encoded = try abi.encodePacked(allocator, participant_values);
    defer allocator.free(participants_encoded);

    // Build values for fixed fields
    const app_addr = primitives.Address.Address{ .bytes = fixed.app_definition };
    const values = [_]abi.AbiValue{
        abi.AbiValue{ .uint64 = fixed.channel_nonce },
        abi.addressValue(app_addr),
        abi.AbiValue{ .uint32 = fixed.challenge_duration },
    };

    // Encode fixed fields
    const fixed_encoded = try abi.encodePacked(allocator, &values);
    defer allocator.free(fixed_encoded);

    // Concatenate: participants + nonce + appDef + challengeDuration
    const total_len = participants_encoded.len + fixed_encoded.len;
    const combined = try allocator.alloc(u8, total_len);
    defer allocator.free(combined);

    @memcpy(combined[0..participants_encoded.len], participants_encoded);
    @memcpy(combined[participants_encoded.len..], fixed_encoded);

    // Keccak256 hash
    return Hash.keccak256(combined);
}
