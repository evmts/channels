const std = @import("std");
const testing = std.testing;
const types = @import("../state/types.zig");
const sig_mod = @import("signature.zig");

const Signature = types.Signature;
const Address = types.Address;
const Bytes32 = types.Bytes32;

// Test helpers
fn makeHash(seed: u8) Bytes32 {
    return [_]u8{seed} ** 32;
}

fn makePrivateKey(seed: u8) Bytes32 {
    // In real usage, private keys should be cryptographically random
    // For tests, we use deterministic generation
    var key: [32]u8 = undefined;
    key[0] = seed;
    // Fill rest with pattern to ensure valid scalar (< secp256k1 order)
    var i: usize = 1;
    while (i < 32) : (i += 1) {
        key[i] = @intCast((seed + i) % 256);
    }
    return key;
}

test "signHash - produces valid signature" {
    const hash = makeHash(0xAA);
    const private_key = makePrivateKey(0x01);

    const signature = try sig_mod.signHash(hash, private_key);

    // Signature should have 32-byte r, 32-byte s, 1-byte v
    try testing.expect(signature.r.len == 32);
    try testing.expect(signature.s.len == 32);
    // v is recovery id (typically 0, 1, 27, or 28 depending on implementation)
    try testing.expect(signature.v < 4 or signature.v == 27 or signature.v == 28);
}

test "signHash - deterministic (same inputs produce same signature)" {
    const hash = makeHash(0xBB);
    const private_key = makePrivateKey(0x02);

    const sig1 = try sig_mod.signHash(hash, private_key);
    const sig2 = try sig_mod.signHash(hash, private_key);
    const sig3 = try sig_mod.signHash(hash, private_key);

    // All signatures should be identical (deterministic signing)
    try testing.expectEqualSlices(u8, &sig1.r, &sig2.r);
    try testing.expectEqualSlices(u8, &sig1.s, &sig2.s);
    try testing.expectEqual(sig1.v, sig2.v);

    try testing.expectEqualSlices(u8, &sig2.r, &sig3.r);
    try testing.expectEqualSlices(u8, &sig2.s, &sig3.s);
    try testing.expectEqual(sig2.v, sig3.v);
}

test "signHash - different hashes produce different signatures" {
    const hash1 = makeHash(0xAA);
    const hash2 = makeHash(0xBB);
    const private_key = makePrivateKey(0x01);

    const sig1 = try sig_mod.signHash(hash1, private_key);
    const sig2 = try sig_mod.signHash(hash2, private_key);

    // Signatures should be different
    const same_r = std.mem.eql(u8, &sig1.r, &sig2.r);
    const same_s = std.mem.eql(u8, &sig1.s, &sig2.s);
    const same_v = sig1.v == sig2.v;

    try testing.expect(!(same_r and same_s and same_v));
}

test "signHash - different private keys produce different signatures" {
    const hash = makeHash(0xCC);
    const key1 = makePrivateKey(0x01);
    const key2 = makePrivateKey(0x02);

    const sig1 = try sig_mod.signHash(hash, key1);
    const sig2 = try sig_mod.signHash(hash, key2);

    // Signatures should be different
    const same_r = std.mem.eql(u8, &sig1.r, &sig2.r);
    const same_s = std.mem.eql(u8, &sig1.s, &sig2.s);
    const same_v = sig1.v == sig2.v;

    try testing.expect(!(same_r and same_s and same_v));
}

test "recoverAddress - roundtrip (sign then recover)" {
    const hash = makeHash(0xDD);
    const private_key = makePrivateKey(0x03);

    // Sign the hash
    const signature = try sig_mod.signHash(hash, private_key);

    // Recover address from signature
    const recovered_addr = try sig_mod.recoverAddress(hash, signature);

    // Recovered address should be valid (20 bytes)
    try testing.expect(recovered_addr.len == 20);

    // Sign again with same key and verify we get same address
    const signature2 = try sig_mod.signHash(hash, private_key);
    const recovered_addr2 = try sig_mod.recoverAddress(hash, signature2);

    try testing.expectEqualSlices(u8, &recovered_addr, &recovered_addr2);
}

test "recoverAddress - different signatures recover different addresses" {
    const hash = makeHash(0xEE);
    const key1 = makePrivateKey(0x04);
    const key2 = makePrivateKey(0x05);

    const sig1 = try sig_mod.signHash(hash, key1);
    const sig2 = try sig_mod.signHash(hash, key2);

    const addr1 = try sig_mod.recoverAddress(hash, sig1);
    const addr2 = try sig_mod.recoverAddress(hash, sig2);

    // Different keys should produce different addresses
    try testing.expect(!std.mem.eql(u8, &addr1, &addr2));
}

test "verifySignature - valid signature returns true" {
    const hash = makeHash(0xFF);
    const private_key = makePrivateKey(0x06);

    // Sign and recover address
    const signature = try sig_mod.signHash(hash, private_key);
    const expected_signer = try sig_mod.recoverAddress(hash, signature);

    // Verify should return true
    const is_valid = try sig_mod.verifySignature(hash, signature, expected_signer);
    try testing.expect(is_valid);
}

test "verifySignature - wrong signer returns false" {
    const hash = makeHash(0x11);
    const private_key = makePrivateKey(0x07);

    // Sign with one key
    const signature = try sig_mod.signHash(hash, private_key);

    // Try to verify with different address
    const wrong_signer = [_]u8{0xFF} ** 20;

    // Verify should return false
    const is_valid = try sig_mod.verifySignature(hash, signature, wrong_signer);
    try testing.expect(!is_valid);
}

test "verifySignature - tampered signature returns false" {
    const hash = makeHash(0x22);
    const private_key = makePrivateKey(0x08);

    // Sign and get correct signer
    const signature = try sig_mod.signHash(hash, private_key);
    const expected_signer = try sig_mod.recoverAddress(hash, signature);

    // Tamper with signature
    var tampered = signature;
    tampered.r[0] = ~tampered.r[0]; // Flip bits

    // Verify should return false (or error if signature is invalid)
    const is_valid = sig_mod.verifySignature(hash, tampered, expected_signer) catch false;
    try testing.expect(!is_valid);
}

test "Signature.toBytes and fromBytes roundtrip" {
    const hash = makeHash(0x33);
    const private_key = makePrivateKey(0x09);

    const original = try sig_mod.signHash(hash, private_key);

    // Convert to bytes
    const bytes = original.toBytes();
    try testing.expect(bytes.len == 65);

    // Convert back
    const recovered = Signature.fromBytes(bytes);

    // Should be identical
    try testing.expectEqualSlices(u8, &original.r, &recovered.r);
    try testing.expectEqualSlices(u8, &original.s, &recovered.s);
    try testing.expectEqual(original.v, recovered.v);
}

test "signHash - multiple signatures with different keys" {
    const hash = makeHash(0x44);

    // Create 10 different signatures
    var addresses: [10]Address = undefined;

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const key = makePrivateKey(@intCast(i + 10));
        const sig = try sig_mod.signHash(hash, key);
        addresses[i] = try sig_mod.recoverAddress(hash, sig);
    }

    // All addresses should be unique
    var j: usize = 0;
    while (j < 10) : (j += 1) {
        var k: usize = j + 1;
        while (k < 10) : (k += 1) {
            try testing.expect(!std.mem.eql(u8, &addresses[j], &addresses[k]));
        }
    }
}

test "signHash - consistency check (100 iterations)" {
    const hash = makeHash(0x55);
    const private_key = makePrivateKey(0x0A);

    // First signature as reference
    const reference = try sig_mod.signHash(hash, private_key);
    const reference_addr = try sig_mod.recoverAddress(hash, reference);

    // Sign 100 times and verify all produce same result
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const sig = try sig_mod.signHash(hash, private_key);
        const addr = try sig_mod.recoverAddress(hash, sig);

        try testing.expectEqualSlices(u8, &reference.r, &sig.r);
        try testing.expectEqualSlices(u8, &reference.s, &sig.s);
        try testing.expectEqual(reference.v, sig.v);
        try testing.expectEqualSlices(u8, &reference_addr, &addr);
    }
}

// TODO: Add cross-implementation test vectors when we have ethers.js reference
// For now, we rely on roundtrip tests and Voltaire's implementation
test "signHash - matches ethers.js signatures (PLACEHOLDER)" {
    // Will be implemented once we have reference signatures from ethers.js
    // For now, we rely on roundtrip tests above
    try testing.expect(true);
}
