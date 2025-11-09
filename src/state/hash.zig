const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives");
const crypto_pkg = @import("crypto");

const State = types.State;
const VariablePart = types.VariablePart;
const Outcome = types.Outcome;
const Allocation = types.Allocation;
const Bytes32 = types.Bytes32;
const Hash = crypto_pkg.Hash;
const abi = primitives.AbiEncoding;

/// Compute deterministic hash of State using Ethereum ABI encoding + Keccak256.
/// Same State will always produce same hash (deterministic).
/// This hash is signed by participants to authorize state transitions.
///
/// Encoding strategy: ABI encode complete State struct (all fields)
/// Order: participants, channel_nonce, app_definition, challenge_duration,
///        app_data, outcome, turn_num, is_final
pub fn hashState(state: State, allocator: std.mem.Allocator) !Bytes32 {
    // Count total values needed for encoding
    // participants (n addresses) + nonce + appDef + challenge + appData + outcome + turn + isFinal
    const num_participant_values = state.participants.len;
    const num_outcome_values = 1 + (state.outcome.allocations.len * 4); // asset + (dest + amount + type + metadata per alloc)
    const total_values = num_participant_values + 3 + 2 + num_outcome_values + 2;

    var values = try allocator.alloc(abi.AbiValue, total_values);
    defer allocator.free(values);

    var idx: usize = 0;

    // 1. Participants
    for (state.participants) |addr| {
        const prim_addr = primitives.Address.Address{ .bytes = addr };
        values[idx] = abi.addressValue(prim_addr);
        idx += 1;
    }

    // 2. Channel nonce
    values[idx] = abi.AbiValue{ .uint64 = state.channel_nonce };
    idx += 1;

    // 3. App definition
    const app_addr = primitives.Address.Address{ .bytes = state.app_definition };
    values[idx] = abi.addressValue(app_addr);
    idx += 1;

    // 4. Challenge duration
    values[idx] = abi.AbiValue{ .uint32 = state.challenge_duration };
    idx += 1;

    // 5. App data (as bytes)
    values[idx] = abi.AbiValue{ .bytes = state.app_data };
    idx += 1;

    // 6. Outcome - asset address
    const asset_addr = primitives.Address.Address{ .bytes = state.outcome.asset };
    values[idx] = abi.addressValue(asset_addr);
    idx += 1;

    // 7. Outcome - allocations
    for (state.outcome.allocations) |alloc| {
        // Destination (bytes32)
        values[idx] = abi.AbiValue{ .bytes32 = alloc.destination };
        idx += 1;

        // Amount (u256)
        values[idx] = abi.AbiValue{ .uint256 = alloc.amount };
        idx += 1;

        // Allocation type (u8)
        values[idx] = abi.AbiValue{ .uint8 = @intFromEnum(alloc.allocation_type) };
        idx += 1;

        // Metadata (bytes)
        values[idx] = abi.AbiValue{ .bytes = alloc.metadata };
        idx += 1;
    }

    // 8. Turn number
    values[idx] = abi.AbiValue{ .uint64 = state.turn_num };
    idx += 1;

    // 9. Is final (bool as u8)
    values[idx] = abi.AbiValue{ .uint8 = if (state.is_final) 1 else 0 };
    idx += 1;

    // Encode all values
    const encoded = try abi.encodePacked(allocator, values);
    defer allocator.free(encoded);

    // Keccak256 hash
    return Hash.keccak256(encoded);
}

/// Compute hash of VariablePart only (for efficiency when FixedPart is known).
/// Useful for protocols that operate on same channel with different variable parts.
pub fn hashVariablePart(variable: VariablePart, allocator: std.mem.Allocator) !Bytes32 {
    const num_outcome_values = 1 + (variable.outcome.allocations.len * 4);
    const total_values = 1 + num_outcome_values + 2; // appData + outcome + turn + isFinal

    var values = try allocator.alloc(abi.AbiValue, total_values);
    defer allocator.free(values);

    var idx: usize = 0;

    // 1. App data
    values[idx] = abi.AbiValue{ .bytes = variable.app_data };
    idx += 1;

    // 2. Outcome - asset
    const asset_addr = primitives.Address.Address{ .bytes = variable.outcome.asset };
    values[idx] = abi.addressValue(asset_addr);
    idx += 1;

    // 3. Outcome - allocations
    for (variable.outcome.allocations) |alloc| {
        values[idx] = abi.AbiValue{ .bytes32 = alloc.destination };
        idx += 1;
        values[idx] = abi.AbiValue{ .uint256 = alloc.amount };
        idx += 1;
        values[idx] = abi.AbiValue{ .uint8 = @intFromEnum(alloc.allocation_type) };
        idx += 1;
        values[idx] = abi.AbiValue{ .bytes = alloc.metadata };
        idx += 1;
    }

    // 4. Turn number
    values[idx] = abi.AbiValue{ .uint64 = variable.turn_num };
    idx += 1;

    // 5. Is final
    values[idx] = abi.AbiValue{ .uint8 = if (variable.is_final) 1 else 0 };
    idx += 1;

    const encoded = try abi.encodePacked(allocator, values);
    defer allocator.free(encoded);

    return Hash.keccak256(encoded);
}
