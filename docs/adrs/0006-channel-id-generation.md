# ADR-0006: ChannelId Generation

<adr-metadata>
**Status:** Accepted | **Date:** 2025-11-08 | **Deciders:** Core Team | **Related:** ADR-0004, ADR-0005 | **Phase:** 2
</adr-metadata>

## Context

<context>
**Problem:** State channels need unique, deterministic identifiers. ChannelId must: uniquely identify channel across network, be deterministically generated from channel parameters (same params → same ID), prevent collisions, and match L1 adjudicator contract ID generation.

**Constraints:**
- Deterministic: same FixedPart → same ChannelId
- Collision-resistant: astronomically unlikely two channels get same ID
- L1 compatible: Zig and Solidity produce identical IDs
- Efficient: generation <1ms
- Standard: use Ethereum-standard hashing (keccak256)

**Assumptions:**
- FixedPart contains all channel-identifying parameters (participants, nonce, appDef, challengeDuration)
- Participants coordinate nonce selection (prevent intentional collisions)
- 256-bit hash provides sufficient collision resistance

**Affected:**
- Channel creation (generate ID for new channel)
- Event store (index channels by ID)
- Network protocol (identify channels in messages)
- L1 adjudicator (verify ChannelId matches state)
- Channel lookup (find channel by ID)
</context>

## Drivers

<drivers>
**Top 5 factors (prioritized):**
1. **Determinism (10):** Same FixedPart must always produce same ID
2. **Collision Resistance (10):** Near-zero probability of duplicate IDs
3. **L1 Compatibility (9):** Solidity and Zig produce identical IDs
4. **Standard Algorithm (8):** Use proven hash function (keccak256)
5. **Performance (6):** Generate ID <1ms

**Ex:** keccak256(abi.encodePacked(FixedPart)) provides determinism (hash function), collision resistance (256-bit output space = 2^256 possibilities), Ethereum L1 compatibility (native keccak256), and proven algorithm (Ethereum standard).
</drivers>

## Options

<options>
### Opt 1: keccak256(abi.encodePacked(FixedPart))

**Desc:** Hash ABI-encoded FixedPart using Ethereum keccak256. Standard Nitro Protocol approach.

**Pros:**
- ✅ Ethereum standard (keccak256 native)
- ✅ L1 compatible (Solidity can compute identically)
- ✅ Deterministic (hash function property)
- ✅ Collision-resistant (256-bit hash space)
- ✅ Voltaire implementation available
- ✅ Matches Nitro Protocol / go-nitro

**Cons:**
- ❌ Requires ABI encoding dependency
- ❌ Slightly slower than raw hash (encoding overhead)

**Effort:** Small (Voltaire Hash + ABI encoding available)

```zig
pub fn channelId(fixed: FixedPart, allocator: Allocator) !ChannelId {
    const encoded = try encodeFixedPart(fixed, allocator);
    defer allocator.free(encoded);
    return Hash.keccak256(encoded);
}
```

### Opt 2: keccak256(participants || nonce)

**Desc:** Hash only participants and nonce (minimal approach).

**Pros:**
- ✅ Simpler (fewer fields)
- ✅ Faster (less to encode)

**Cons:**
- ❌ Incomplete (ignores appDef, challengeDuration)
- ❌ Different channels with same participants+nonce but different apps would collide
- ❌ Not standard (deviates from Nitro Protocol)
- ❌ L1 incompatible (adjudicator uses full FixedPart)

**Effort:** Small

### Opt 3: Random UUID

**Desc:** Generate random 128-bit or 256-bit UUID.

**Pros:**
- ✅ Simple generation
- ✅ No encoding dependency

**Cons:**
- ❌ Non-deterministic (critical flaw - participants can't independently compute same ID)
- ❌ L1 incompatible (adjudicator can't regenerate ID from state)
- ❌ Coordination required (Alice generates, must send to Bob)

**Effort:** Small

### Opt 4: Hash(JSON(FixedPart))

**Desc:** Serialize FixedPart to JSON, hash the JSON.

**Pros:**
- ✅ Human-readable intermediate format

**Cons:**
- ❌ Non-deterministic (JSON field order, whitespace)
- ❌ L1 incompatible (Solidity can't easily parse JSON)
- ❌ Slower (JSON serialization overhead)

**Effort:** Small

### Comparison

|Criterion (weight)|keccak(ABI) (Opt1)|keccak(minimal) (Opt2)|UUID (Opt3)|keccak(JSON) (Opt4)|
|------------------|------------------|----------------------|-----------|-------------------|
|Determinism (10)|10→100|10→100|0→0|4→40|
|Collision Resist (10)|10→100|10→100|9→90|10→100|
|L1 Compat (9)|10→90|3→27|0→0|2→18|
|Standard (8)|10→80|6→48|7→56|5→40|
|Performance (6)|8→48|9→54|10→60|6→36|
|**Total**|**418**|**329**|**206**|**234**|
</options>

## Decision

<decision>
**Choose:** keccak256(abi.encodePacked(participants, nonce, appDefinition, challengeDuration))

**Why:**
- Deterministic: participants can independently compute same ID from FixedPart
- Collision-resistant: 256-bit hash space makes collisions astronomically unlikely
- L1 compatible: Solidity adjudicator uses same formula
- Standard: matches Nitro Protocol, go-nitro, nitro-protocol contracts
- Complete: includes all identifying parameters (prevents incomplete collisions)

**Trade-offs accepted:**
- ABI encoding dependency (acceptable, already required for ADR-0005)
- Slightly slower than minimal hash (acceptable, <1ms target easily met)

**Formula:**
```
ChannelId = keccak256(abi.encodePacked(
    participants,        // address[] - channel parties
    channel_nonce,       // uint64 - prevent replay across channels
    app_definition,      // address - application logic contract
    challenge_duration   // uint32 - dispute timeout
))
```
</decision>

## Consequences

<consequences>
**Pos:**
- ✅ Deterministic generation (both parties compute same ID)
- ✅ L1 adjudicator can verify ChannelId matches state
- ✅ Collision-resistant (2^256 space, birthday attack requires 2^128 channels)
- ✅ Standard approach (cross-implementation compatibility)
- ✅ Complete (all identifying params included)

**Neg:**
- ❌ ABI encoding dependency (adds complexity)
- ❌ Slightly slower than raw hash (encoding overhead)

**Mitigate:**
- Dependency → Already required for state encoding (ADR-0005)
- Performance → <1ms easily achievable (hash + encode fast)
</consequences>

## Implementation

<implementation>
**Structure:**
```
src/state/channel_id.zig         # ChannelId generation
src/state/channel_id.test.zig    # Determinism, collision, cross-impl tests
```

**API:**
```zig
const ChannelId = types.ChannelId;
const FixedPart = types.FixedPart;

pub fn channelId(fixed: FixedPart, allocator: Allocator) !ChannelId {
    // Build ABI values for participants array
    var participant_values = try allocator.alloc(abi.AbiValue, fixed.participants.len);
    defer allocator.free(participant_values);

    for (fixed.participants, 0..) |addr, i| {
        const prim_addr = primitives.Address.Address{ .bytes = addr };
        participant_values[i] = abi.addressValue(prim_addr);
    }

    // Encode participants array
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
```

**Tests:**
- Unit: determinism (same FixedPart → same ID, 1000 iterations)
- Unit: different nonce → different ID
- Unit: different participants → different ID
- Unit: different appDef → different ID
- Unit: different challengeDuration → different ID
- Cross-impl: Ethereum contract test vector (compute in Solidity, verify match in Zig)
- Performance: generation <1ms P95

**Docs:**
- `docs/architecture/channel-id.md` - Design doc
- Code comments explaining formula choice

**Cross-impl Test Vector:**
```solidity
// Solidity reference implementation
function getChannelId(
    address[] memory participants,
    uint256 channelNonce,
    address appDefinition,
    uint32 challengeDuration
) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(
        participants,
        channelNonce,
        appDefinition,
        challengeDuration
    ));
}
```

Compare Zig channelId() output against Solidity getChannelId() for same inputs.
</implementation>

## Validation

<validation>
**Metrics:**
- Determinism: 100% (1000 generations of same FixedPart → identical ID)
- Cross-impl match: 100% (Zig ID = Solidity ID for test vectors)
- Collision resistance: 0 collisions in 1M random FixedParts
- Performance: <1ms P95, <0.5ms P50
- Memory usage: <5KB per generation

**Monitor:**
- Cross-impl test failures (should be 0)
- ChannelId generation performance regression
- Memory leaks in generation

**Review:**
- 3mo: Determinism holding? Cross-impl tests passing?
- 6mo: Performance acceptable? Any collisions observed?
- 12mo: Still best choice? Ethereum upgrades?

**Revise if:**
- Non-determinism discovered (critical bug, must fix immediately)
- L1 adjudicator changes formula (upgrade to match)
- Collision observed (investigate, upgrade hash if needed)
- Performance bottleneck >1ms P95 (optimize encoding)
</validation>

## Related

<related>
**ADR Dependencies:**
- **Depends on:** ADR-0005 (State Encoding) - uses ABI encoding
- **Informs:** Channel creation protocol (Phase 3)
- **Informs:** Event store indexing (channels indexed by ID)

**Project Context:**
- **PRD:** [prd.md](../prd.md) §3.1 - Channel Identification
- **Context:** [context.md](../context.md) - Nitro Protocol (ChannelId generation)
- **Phase:** [.claude/commands/2_phase_core_state_and_signatures.md](../../.claude/commands/2_phase_core_state_and_signatures.md)
- **Architecture:** [docs/architecture/channel-id.md](../architecture/channel-id.md) (TBD)

**Implementation:**
- **Code:** `src/state/channel_id.zig`
- **Tests:** `src/state/channel_id.test.zig`
- **Voltaire:** `../voltaire/src/crypto.zig` (Hash.keccak256)

**External References:**
- [Nitro Protocol Spec](https://docs.statechannels.org/) - ChannelId formula
- [go-nitro](https://github.com/statechannels/go-nitro) - Reference implementation
- [nitro-protocol](https://github.com/statechannels/nitro-protocol) - Solidity contracts
- [Keccak256 Spec](https://keccak.team/keccak.html) - Hash function specification
</related>

<changelog>
- 2025-11-08: Initial (Accepted) - Phase 2 Day 1
</changelog>
