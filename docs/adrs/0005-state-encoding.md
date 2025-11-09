# ADR-0005: State Encoding

<adr-metadata>
**Status:** Accepted | **Date:** 2025-11-08 | **Deciders:** Core Team | **Related:** ADR-0004, ADR-0006 | **Phase:** 2
</adr-metadata>

## Context

<context>
**Problem:** State channel state must be encoded into bytes for: hashing (signatures), serialization (storage/network), and L1 verification (adjudicator contract). Encoding must be deterministic (same state → same bytes) and compatible across Zig off-chain and Solidity on-chain implementations.

**Constraints:**
- Deterministic: identical state must produce identical bytes
- Ethereum L1 compatibility: adjudicator contract must decode
- Cross-language: Zig and Solidity must produce/consume same format
- Efficient: encoding performance <1ms for typical state
- Standard: prefer established formats over custom binary

**Assumptions:**
- State structures stable (FixedPart, VariablePart defined)
- Voltaire ABI encoding library available (integrated Phase 2)
- L1 adjudicator uses Solidity abi.encodePacked()

**Affected:**
- State hashing (signatures verify over encoded state)
- ChannelId generation (hash of encoded FixedPart)
- Event storage (serialized state)
- L1 adjudicator contract (state decoding)
- Network protocol (state transmission)
</context>

## Drivers

<drivers>
**Top 5 factors (prioritized):**
1. **Determinism (10):** Same state must always encode identically
2. **L1 Compatibility (10):** Solidity adjudicator must decode/verify
3. **Cross-impl Consistency (9):** Zig encoding = Solidity encoding
4. **Standard Format (7):** Use established format, not custom binary
5. **Performance (6):** Encode typical state <1ms

**Ex:** Ethereum ABI encoding is deterministic, has Solidity native support (abi.encodePacked), proven in production (all Ethereum contracts), and has libraries in multiple languages (ethers.js, web3.py, Voltaire).
</drivers>

## Options

<options>
### Opt 1: Ethereum ABI Packed Encoding

**Desc:** Use Solidity abi.encodePacked() format via Voltaire AbiEncoding. Tightly packed, no padding, deterministic, Ethereum-standard.

**Pros:**
- ✅ Ethereum native (abi.encodePacked in Solidity)
- ✅ Deterministic (same values → same bytes)
- ✅ Voltaire implementation available
- ✅ L1 contract can decode/verify
- ✅ No padding overhead (packed format)
- ✅ Cross-impl test vectors available (Ethereum contracts)

**Cons:**
- ❌ More complex than JSON (binary format)
- ❌ Not human-readable (debugging harder)
- ❌ Voltaire implementation not extensively tested

**Effort:** Small (Voltaire integration complete)

```zig
const values = [_]abi.AbiValue{
    abi.AbiValue{ .uint64 = state.turn_num },
    abi.addressValue(Address{ .bytes = state.app_definition }),
    abi.bytesValue(state.app_data),
};
const encoded = try abi.encodePacked(allocator, &values);
```

### Opt 2: JSON Encoding

**Desc:** Serialize state to JSON. Human-readable, standard format.

**Pros:**
- ✅ Human-readable (debugging easy)
- ✅ Standard format (every language)
- ✅ Simple implementation

**Cons:**
- ❌ Non-deterministic (field order, whitespace, number formatting)
- ❌ No Solidity native support (complex L1 parsing)
- ❌ Larger size (text overhead)
- ❌ Slower parsing

**Effort:** Small (std.json available)

### Opt 3: RLP Encoding

**Desc:** Recursive Length Prefix (Ethereum transaction encoding).

**Pros:**
- ✅ Ethereum-adjacent (used for tx encoding)
- ✅ Deterministic
- ✅ Compact

**Cons:**
- ❌ No Solidity abi.decode support (custom parsing)
- ❌ Less standard than ABI encoding for smart contracts
- ❌ No Voltaire implementation

**Effort:** Medium (implement RLP encoder)

### Opt 4: Protocol Buffers

**Desc:** Google protobuf binary serialization.

**Pros:**
- ✅ Efficient
- ✅ Schema evolution support
- ✅ Cross-language

**Cons:**
- ❌ No Solidity support
- ❌ Non-deterministic (optional fields, default values)
- ❌ Additional dependency

**Effort:** Medium (protobuf compiler + runtime)

### Comparison

|Criterion (weight)|ABI Packed (Opt1)|JSON (Opt2)|RLP (Opt3)|Protobuf (Opt4)|
|------------------|-----------------|-----------|----------|---------------|
|Determinism (10)|10→100|2→20|10→100|6→60|
|L1 Compat (10)|10→100|2→20|6→60|2→20|
|Cross-impl (9)|10→90|4→36|7→63|6→54|
|Standard (7)|10→70|8→56|6→42|7→49|
|Performance (6)|9→54|5→30|8→48|9→54|
|**Total**|**414**|**162**|**313**|**237**|
</options>

## Decision

<decision>
**Choose:** Ethereum ABI Packed Encoding via Voltaire

**Why:**
- Best L1 compatibility (Solidity abi.encodePacked native)
- Deterministic (same state → same bytes, critical for signatures)
- Standard in Ethereum smart contract ecosystem
- Voltaire implementation available (integration complete)
- Cross-impl test vectors available (Ethereum contracts)

**Trade-offs accepted:**
- Non-human-readable (binary format, debugging harder)
- Voltaire library not extensively tested (acceptable, can cross-verify with Solidity)

**Mitigation:**
- Debugging → Implement hex dump utility for encoded state
- Testing → Cross-impl test vectors (encode in Zig, decode in Solidity)
- Verification → Compare against Ethereum contract encoding for same inputs
</decision>

## Consequences

<consequences>
**Pos:**
- ✅ L1 adjudicator can decode state (abi.decode in Solidity)
- ✅ Deterministic hashing (signatures verifiable)
- ✅ Standard format (tooling available)
- ✅ Compact encoding (no padding overhead)
- ✅ Cross-implementation compatibility (Zig ↔ Solidity)

**Neg:**
- ❌ Binary format (harder to debug than JSON)
- ❌ Voltaire library not audited (same as ADR-0004)

**Mitigate:**
- Debugging → Hex dump utility, pretty-print decoded state
- Audit → Document requirement, include in Phase 12 security audit
- Testing → Extensive cross-impl test vectors (encode/decode in both languages)
</consequences>

## Implementation

<implementation>
**Structure:**
```
src/abi/encoder.zig              # Wrapper over Voltaire AbiEncoding
src/abi/encoder.test.zig         # Encoding tests, cross-impl vectors
src/state/hash.zig               # Hash encoded state (for signatures)
```

**API:**
```zig
// Encode FixedPart for ChannelId generation
pub fn encodeFixedPart(fixed: FixedPart, allocator: Allocator) ![]u8 {
    // Build participant values
    var participant_values = try allocator.alloc(abi.AbiValue, fixed.participants.len);
    defer allocator.free(participant_values);
    for (fixed.participants, 0..) |addr, i| {
        const prim_addr = primitives.Address.Address{ .bytes = addr };
        participant_values[i] = abi.addressValue(prim_addr);
    }

    // Encode participants + nonce + appDef + challengeDuration
    // ...
}

// Encode State for signing/hashing
pub fn encodeState(state: State, allocator: Allocator) ![]u8 {
    // Encode all state fields (FixedPart + VariablePart)
    // ...
}
```

**Tests:**
- Unit: encode simple state, verify determinism (encode twice → identical)
- Cross-impl: Ethereum test vectors (encode in Zig, decode in Solidity, verify match)
- Edge cases: empty arrays, zero values, max uint256
- Performance: encode typical state <1ms

**Docs:**
- `docs/architecture/encoding.md` - Design doc
- Code comments explaining ABI encoding choices

**Cross-impl Test Vectors:**
```solidity
// Solidity test contract
contract EncodingTest {
    function encodeFixedPart(
        address[] memory participants,
        uint256 nonce,
        address appDef,
        uint32 challengeDuration
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(participants, nonce, appDef, challengeDuration));
    }
}
```

Compare Zig channelId() output against Solidity encodeFixedPart() for same inputs.
</implementation>

## Validation

<validation>
**Metrics:**
- Encoding determinism: 100% (1000 encodes of same state → identical bytes)
- Cross-impl match: 100% (Zig encoding = Solidity encoding for test vectors)
- Performance: <1ms P95 for typical state (2 participants, 1KB app_data)
- Memory usage: <10KB per encode operation

**Monitor:**
- Cross-impl test failures (should be 0)
- Encoding performance regression
- Memory leaks in encoder

**Review:**
- 3mo: Determinism holding? Cross-impl tests passing?
- 6mo: Performance acceptable? Any encoding bugs?
- 12mo: Still best choice? Voltaire library updates?

**Revise if:**
- Non-determinism discovered (critical bug, must fix immediately)
- L1 adjudicator changes encoding format (upgrade)
- Performance bottleneck >1ms P95 (optimize or reconsider)
- Voltaire library abandoned (migrate to alternative)
</validation>

## Related

<related>
**ADR Dependencies:**
- **Depends on:** Voltaire integration (build.zig, build.zig.zon)
- **Informs:** ADR-0004 (Signature Scheme) - signatures over encoded state
- **Informs:** ADR-0006 (ChannelId Generation) - ChannelId from encoded FixedPart

**Project Context:**
- **PRD:** [prd.md](../prd.md) §3.3 - State Encoding
- **Context:** [context.md](../context.md) - Nitro Protocol (ABI encoding)
- **Phase:** [.claude/commands/2_phase_core_state_and_signatures.md](../../.claude/commands/2_phase_core_state_and_signatures.md)
- **Architecture:** [docs/architecture/encoding.md](../architecture/encoding.md) (TBD)

**Implementation:**
- **Code:** `src/abi/encoder.zig`
- **Tests:** `src/abi/encoder.test.zig`
- **Voltaire:** `../voltaire/src/primitives/abi_encoding.zig`

**External References:**
- [Solidity ABI Spec](https://docs.soliditylang.org/en/latest/abi-spec.html) - Official encoding spec
- [Nitro Protocol](https://github.com/statechannels/go-nitro) - ABI encoding usage
- [Voltaire ABI](https://github.com/jsign/voltaire/tree/main/primitives/abi_encoding) - Zig implementation
- [EIP-712](https://eips.ethereum.org/EIPS/eip-712) - Structured data hashing (future consideration)
</related>

<changelog>
- 2025-11-08: Initial (Accepted) - Phase 2 Day 1
</changelog>
