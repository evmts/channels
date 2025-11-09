# ADR-0004: Signature Scheme

<adr-metadata>
**Status:** Accepted | **Date:** 2025-11-08 | **Deciders:** Core Team | **Related:** ADR-0005, ADR-0006 | **Phase:** 2
</adr-metadata>

## Context

<context>
**Problem:** State channels require cryptographic signatures for state updates. Participants sign state transitions, and signatures must be verifiable both off-chain (channel operation) and on-chain (dispute resolution).

**Constraints:**
- Ethereum L1 compatibility (adjudicator contract verification)
- Address recovery required (participants identified by Ethereum address)
- Hardware wallet support for user security
- Must verify signatures in both Zig (off-chain) and Solidity (on-chain)

**Assumptions:**
- Participants hold Ethereum-compatible private keys (secp256k1)
- Signature verification performance <10ms acceptable
- Voltaire crypto library provides correct implementation (UNAUDITED)

**Affected:**
- All state channel protocols (P3-P9)
- Adjudicator smart contract (signature verification)
- Participant clients (signing state updates)
- Event store (signature storage)
</context>

## Drivers

<drivers>
**Top 5 factors (prioritized):**
1. **Ethereum Compatibility (10):** L1 adjudicator must verify signatures
2. **Address Recovery (9):** Identify signer without storing public keys
3. **Security (9):** Proven, battle-tested cryptography
4. **Hardware Wallet Support (7):** Users can sign with Ledger/Trezor
5. **Performance (6):** Sign/verify operations <10ms P95

**Ex:** secp256k1 recoverable signatures enable address recovery (no pubkey storage), Ethereum smart contract compatibility (ecrecover precompile), and hardware wallet support (standard Bitcoin/Ethereum curve).
</drivers>

## Options

<options>
### Opt 1: secp256k1 Recoverable Signatures

**Desc:** ECDSA signatures on secp256k1 curve with recovery parameter (65-byte r,s,v format). Address recovered from signature+hash via ecrecover.

**Pros:**
- ✅ Ethereum native (ecrecover precompile)
- ✅ Address recovery eliminates pubkey storage
- ✅ Hardware wallet standard
- ✅ Battle-tested (Bitcoin, Ethereum)
- ✅ Voltaire provides implementation

**Cons:**
- ❌ Slower than ed25519 (~10ms vs ~2ms)
- ❌ Larger signatures (65 bytes vs 64 bytes)
- ❌ Voltaire implementation UNAUDITED

**Effort:** Small (Voltaire integration complete)

```zig
const sig = try Crypto.unaudited_signHash(state_hash, private_key);
const addr = try Crypto.unaudited_recoverAddress(state_hash, sig);
```

### Opt 2: ed25519 Signatures

**Desc:** EdDSA signatures on Curve25519. Faster signing/verification, smaller keys.

**Pros:**
- ✅ Faster (2-3ms sign+verify)
- ✅ Deterministic nonces (safer)
- ✅ Simpler implementation

**Cons:**
- ❌ No Ethereum L1 support (no ed25519 precompile)
- ❌ No address recovery (must store pubkeys)
- ❌ Limited hardware wallet support
- ❌ Incompatible with existing Ethereum tooling

**Effort:** Medium (custom L1 verification contract)

### Opt 3: BLS Signatures

**Desc:** Boneh-Lynn-Shacham signatures. Enables signature aggregation.

**Pros:**
- ✅ Signature aggregation (n sigs → 1 sig)
- ✅ Reduces on-chain data

**Cons:**
- ❌ No Ethereum L1 support
- ❌ More complex cryptography
- ❌ Slower verification
- ❌ No hardware wallet support
- ❌ No Voltaire implementation

**Effort:** Extra-Large (implement crypto + L1 verification)

### Comparison

|Criterion (weight)|secp256k1 (Opt1)|ed25519 (Opt2)|BLS (Opt3)|
|------------------|----------------|--------------|----------|
|Ethereum Compat (10)|10→100|2→20|2→20|
|Address Recovery (9)|10→90|0→0|0→0|
|Security (9)|10→90|10→90|8→72|
|Hardware Wallet (7)|10→70|4→28|2→14|
|Performance (6)|6→36|10→60|4→24|
|**Total**|**386**|**198**|**130**|
</options>

## Decision

<decision>
**Choose:** secp256k1 recoverable signatures via Voltaire crypto library

**Why:**
- Best Ethereum compatibility (ecrecover precompile)
- Address recovery eliminates pubkey storage complexity
- Hardware wallet support critical for user security
- Proven cryptography (Bitcoin/Ethereum track record)
- Voltaire integration already complete

**Trade-offs accepted:**
- Performance (~10ms vs ~2ms ed25519) acceptable for channel operations
- UNAUDITED Voltaire crypto requires security disclosure + audit before production

**Mitigation:**
- Document Voltaire audit requirement in production checklist
- Mark all crypto functions with `unaudited_*` prefix
- Add security warning in docs/architecture/security.md
- Plan security audit for Phase 12 (Production Hardening)
</decision>

## Consequences

<consequences>
**Pos:**
- ✅ Ethereum L1 adjudicator can verify signatures (ecrecover)
- ✅ No pubkey storage (recovered from signature)
- ✅ Hardware wallet compatibility (Ledger/Trezor)
- ✅ Standard tooling support (ethers.js, web3.py, etc.)
- ✅ Proven cryptography (decades of use)

**Neg:**
- ❌ Slower than ed25519 (~10ms vs ~2ms)
- ❌ Larger signatures (65 bytes vs 64 bytes)
- ❌ UNAUDITED implementation (Voltaire)

**Mitigate:**
- Performance → Acceptable for channel ops (not per-transaction, per-state-update)
- Size → 65 bytes negligible in state channel context
- Audit → Document requirement, plan audit Phase 12, security disclosure
</consequences>

## Implementation

<implementation>
**Structure:**
```
src/crypto/signature.zig         # Sign/verify wrapper over Voltaire
src/crypto/signature.test.zig    # Roundtrip, recovery, cross-impl tests
src/state/hash.zig               # State hashing before signing
```

**API:**
```zig
pub fn signState(state: State, private_key: [32]u8, allocator: Allocator) !Signature {
    const state_hash = try hashState(state, allocator);
    return try Crypto.unaudited_signHash(state_hash, private_key);
}

pub fn recoverSigner(state: State, sig: Signature, allocator: Allocator) !Address {
    const state_hash = try hashState(state, allocator);
    return try Crypto.unaudited_recoverAddress(state_hash, sig);
}
```

**Tests:**
- Unit: signature roundtrip, bytes conversion, error cases
- Integration: sign state → recover address → verify matches
- Cross-impl: Ethereum test vectors (sign in Zig, verify in Solidity)
- Performance: sign+verify <10ms P95

**Docs:**
- `docs/architecture/signatures.md` - Design doc
- `docs/security.md` - Voltaire audit requirement
- `README.md` - Security disclosure (UNAUDITED crypto)

**Security Warnings:**
- Mark all functions using Voltaire crypto with UNAUDITED comment
- Add WARNING in README.md about production use
- Document audit requirement in Phase 12 checklist
</implementation>

## Validation

<validation>
**Metrics:**
- Sign+verify performance: <10ms P95, <5ms P50
- Signature verification success rate: 100% (no false negatives/positives)
- Cross-impl compatibility: 100% match with Ethereum ecrecover
- Memory usage: <1KB per sign/verify operation

**Monitor:**
- Signature verification failures (should be 0 for valid sigs)
- Performance regression tests (sign/verify latency)
- Cross-impl test suite (Ethereum contract compatibility)

**Review:**
- 3mo: Performance acceptable? Any verification failures?
- 6mo: Voltaire audit status? Alternative libraries available?
- 12mo: Still best choice? New Ethereum precompiles?

**Revise if:**
- Voltaire audit reveals vulnerabilities (migrate to audited library)
- Performance bottleneck >10ms P95 (optimize or consider ed25519 for off-chain)
- Ethereum adds ed25519 precompile (re-evaluate)
- Hardware wallet support degrades (investigate)
</validation>

## Related

<related>
**ADR Dependencies:**
- **Informs:** ADR-0005 (State Encoding) - signatures over ABI-encoded state
- **Informs:** ADR-0006 (ChannelId Generation) - participants identified by address

**Project Context:**
- **PRD:** [prd.md](../prd.md) §3.2 - Cryptographic Verification
- **Context:** [context.md](../context.md) - Nitro Protocol (secp256k1 signatures)
- **Phase:** [.claude/commands/2_phase_core_state_and_signatures.md](../../.claude/commands/2_phase_core_state_and_signatures.md)
- **Architecture:** [docs/architecture/signatures.md](../architecture/signatures.md) (TBD)

**Implementation:**
- **Code:** `src/crypto/signature.zig`
- **Tests:** `src/crypto/signature.test.zig`
- **Voltaire:** `../voltaire/src/crypto.zig`

**External References:**
- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf) - ECDSA + ecrecover
- [secp256k1 Spec](https://www.secg.org/sec2-v2.pdf) - Curve parameters
- [Nitro Protocol](https://github.com/statechannels/go-nitro) - secp256k1 usage
- [Voltaire](https://github.com/jsign/voltaire) - Zig Ethereum primitives (UNAUDITED)
</related>

<changelog>
- 2025-11-08: Initial (Accepted) - Phase 2 Day 1
</changelog>
