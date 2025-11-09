/// ABI Encoder - Thin wrapper over Voltaire's AbiEncoding for state-specific patterns.
///
/// This module provides convenience functions for encoding state channel primitives
/// using Ethereum ABI packed encoding. All encoding uses Voltaire's primitives.AbiEncoding.
///
/// For direct access to ABI encoding, import primitives.AbiEncoding directly.
/// This wrapper exists to provide domain-specific helpers and documentation.

const std = @import("std");
const primitives = @import("primitives");

/// Re-export Voltaire's ABI types for convenience
pub const AbiValue = primitives.AbiEncoding.AbiValue;
pub const encodePacked = primitives.AbiEncoding.encodePacked;
pub const addressValue = primitives.AbiEncoding.addressValue;

/// Helper to create address ABI value from 20-byte array
pub fn encodeAddress(addr: [20]u8) AbiValue {
    const prim_addr = primitives.Address.Address{ .bytes = addr };
    return addressValue(prim_addr);
}

/// Helper to create bytes32 ABI value
pub fn encodeBytes32(bytes: [32]u8) AbiValue {
    return AbiValue{ .bytes32 = bytes };
}

/// Helper to create dynamic bytes ABI value
pub fn encodeBytes(bytes: []const u8) AbiValue {
    return AbiValue{ .bytes = bytes };
}

/// Helper to create uint64 ABI value
pub fn encodeUint64(value: u64) AbiValue {
    return AbiValue{ .uint64 = value };
}

/// Helper to create uint32 ABI value
pub fn encodeUint32(value: u32) AbiValue {
    return AbiValue{ .uint32 = value };
}

/// Helper to create uint8 ABI value
pub fn encodeUint8(value: u8) AbiValue {
    return AbiValue{ .uint8 = value };
}

/// Helper to create uint256 ABI value
pub fn encodeUint256(value: u256) AbiValue {
    return AbiValue{ .uint256 = value };
}

/// Helper to create bool ABI value (encoded as uint8)
pub fn encodeBool(value: bool) AbiValue {
    return AbiValue{ .uint8 = if (value) 1 else 0 };
}
