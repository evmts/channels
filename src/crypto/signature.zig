const std = @import("std");
const types = @import("../state/types.zig");
const crypto_pkg = @import("crypto");

const Signature = types.Signature;
const Address = types.Address;
const Bytes32 = types.Bytes32;
const Crypto = crypto_pkg.Crypto;

/// Sign a hash using secp256k1 recoverable signature (Ethereum-compatible).
/// Returns signature in {r, s, v} format (65 bytes total).
///
/// SECURITY WARNING: Uses Voltaire crypto implementation which is UNAUDITED.
/// Suitable for development/testing only. Production use requires security audit.
///
/// Private key must be 32 bytes (secp256k1 scalar).
pub fn signHash(hash: Bytes32, private_key: Bytes32) !Signature {
    // Use Voltaire's unaudited signing implementation
    const voltaire_sig = try Crypto.unaudited_signHash(hash, private_key);

    // Convert Voltaire's Signature to bytes, then to our Signature format
    const sig_bytes = voltaire_sig.toBytes();
    return Signature.fromBytes(sig_bytes);
}

/// Recover the Ethereum address from a signature and hash.
/// This is the core of Ethereum's signature verification - if the recovered
/// address matches the expected signer, the signature is valid.
///
/// SECURITY WARNING: Uses Voltaire crypto implementation which is UNAUDITED.
/// Suitable for development/testing only. Production use requires security audit.
pub fn recoverAddress(hash: Bytes32, signature: Signature) !Address {
    const sig_bytes = signature.toBytes();

    // Convert bytes back to Voltaire's Signature format
    const voltaire_sig = crypto_pkg.Crypto.Signature.fromBytes(sig_bytes);

    // Use Voltaire's unaudited recovery implementation
    const addr = try Crypto.unaudited_recoverAddress(hash, voltaire_sig);

    return addr.bytes;
}

/// Verify a signature by recovering the address and comparing to expected signer.
/// Returns true if signature is valid (recovered address matches expected).
pub fn verifySignature(hash: Bytes32, signature: Signature, expected_signer: Address) !bool {
    const recovered = try recoverAddress(hash, signature);
    return std.mem.eql(u8, &recovered, &expected_signer);
}
