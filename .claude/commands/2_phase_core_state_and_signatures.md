# P2: Core State & Signatures

**Meta:** P2 | Deps: P1 | Owner: Core

## Zig 0.15 Crypto/ABI

**std.crypto native:**
- `std.crypto.ecc.Secp256k1` - curve ops, basePoint
- `std.crypto.sign.ecdsa.EcdsaSecp256k1Sha256` - signing (NOT recovery)
- `std.crypto.hash.sha3.Keccak256` - Ethereum hash

**No recovery in stdlib** - need external lib (voltaire/primitives provides complete solution)

**u256:**
- Native: `u256` primitive (max u65535)
- Ethereum ABI: represent as `[32]u8` for encoding
- BigInt: `std.math.big.int.Managed` for arbitrary precision

**Rec:** Use voltaire/primitives (Ethereum ABI + secp256k1 recovery) - proven in guillotine-mini
**⚠️ Security:** Voltaire crypto marked UNAUDITED - use for testing/development, plan audit before production

## Summary

Channel state primitives: State/FixedPart/VariablePart structures, secp256k1 signatures, ABI encoding, ChannelId generation. Foundation for all protocols - without state types, cannot represent/verify channel updates. Preserves proven state channel model, replaces strings with tagged unions, integrates event sourcing.

## Objectives

- OBJ-1: State/FixedPart/VariablePart + ABI encoding
- OBJ-2: secp256k1 sign/verify with recovery
- OBJ-3: Keccak256 (Ethereum-compatible)
- OBJ-4: ChannelId generation (matches proven patterns)
- OBJ-5: Emit events for state operations

## Success Criteria

**Done when:**
- Types defined: State, FixedPart, VariablePart, Outcome, Signature
- ABI encoding byte-identical to reference implementations
- ChannelId 100% match to test vectors
- Signature verify + pubkey recovery 100% correct
- State hash deterministic
- Events emit for all ops (100% cov)
- Perf: <10ms P95 sign+verify
- 60+ tests, 90%+ cov
- 2 ADRs approved (sig scheme, ABI encoding)
- Docs + demo

**Exit gates:** Tests pass, cross-impl match, benchmarks met, code review (2+)

## Architecture

**Components:**
```
Protocol Layer (P3+)
  ↓ uses State types
State Module: State, Signature, Outcome
  → ABI Encoding / Hashing (Ethereum-compat)
  ↓ emits events
EventStore (P1)
```

**Flow:** Create State → ChannelId=hash(FixedPart) → ABI encode → Keccak256 → Sign → Emit StateSigned → Receive → Verify recovery → Emit StateVerified

## ADRs

**ADR-0004: Signature Scheme**
- Q: Which sig scheme?
- Opts: A) secp256k1 recoverable | B) ed25519 | C) BLS
- Rec: A
- Why: Ethereum compat, address recovery, proven, HW wallet vs ⚠️ slower than ed25519 (ok <5ms)

**ADR-0005: State Encoding**
- Q: Encoding format?
- Opts: A) Ethereum ABI packed | B) JSON | C) Custom binary | D) RLP
- Rec: A
- Why: Contract compat, deterministic, standard pattern vs ⚠️ complex (padding rules)

**ADR-0006: ChannelId Generation**
- Q: How compute ID?
- Opts: A) Hash(FixedPart) | B) Random UUID | C) Hash(Participants, Nonce)
- Rec: A (full FixedPart)
- Why: Deterministic, prevents collisions, standard pattern
- Formula: `Keccak256(abi.encode(participants, nonce, appDef, challengeDuration))`

## Data Structures

```zig
pub const Address = [20]u8;
pub const Bytes32 = [32]u8;
pub const ChannelId = Bytes32;

pub const FixedPart = struct {
    participants: []Address,
    channel_nonce: u64,
    app_definition: Address,
    challenge_duration: u32,

    pub fn channelId(self: FixedPart, a: Allocator) !ChannelId;
    pub fn clone(self: FixedPart, a: Allocator) !FixedPart;
};

pub const VariablePart = struct {
    app_data: []const u8,
    outcome: Outcome,
    turn_num: u64,
    is_final: bool,

    pub fn clone(self: VariablePart, a: Allocator) !VariablePart;
};

pub const State = struct {
    // Fixed
    participants: []Address,
    channel_nonce: u64,
    app_definition: Address,
    challenge_duration: u32,
    // Variable
    app_data: []const u8,
    outcome: Outcome,
    turn_num: u64,
    is_final: bool,

    pub fn fixedPart(self: State) FixedPart;
    pub fn variablePart(self: State, a: Allocator) !VariablePart;
    pub fn channelId(self: State, a: Allocator) !ChannelId;
    pub fn hash(self: State, a: Allocator) !Bytes32;
    pub fn sign(self: State, a: Allocator, pk: [32]u8) !Signature;
    pub fn recoverSigner(self: State, a: Allocator, sig: Signature) !Address;
    pub fn clone(self: State, a: Allocator) !State;
};

pub const Signature = struct {
    r: [32]u8,
    s: [32]u8,
    v: u8,

    pub fn toBytes(self: Signature) [65]u8;
    pub fn fromBytes(bytes: [65]u8) Signature;
};

pub const Outcome = struct {
    asset: Address,
    allocations: []Allocation,

    pub fn clone(self: Outcome, a: Allocator) !Outcome;
};

pub const Allocation = struct {
    destination: Bytes32,
    amount: u256,
    allocation_type: AllocationType,
    metadata: []const u8,

    pub const AllocationType = enum(u8) { simple, guarantee };
    pub fn clone(self: Allocation, a: Allocator) !Allocation;
};
```

**Invariants:**
- ChannelId deterministic
- Turns monotonic: `state[n+1].turn_num > state[n].turn_num`
- Participants ordered: `participants[i]` signs turns `i mod len`
- Sig valid: `recoverSigner(state, sig) in participants`
- Final immutable: `is_final == true` → no updates

## APIs

```zig
// Sign Ethereum message (prefix + rehash + sign)
pub fn signEthereumMessage(hash: Bytes32, pk: [32]u8) !Signature;

// Recover address from signature
pub fn recoverEthereumMessageSigner(hash: Bytes32, sig: Signature) !Address;

// ABI encode tuple
pub fn abiEncode(a: Allocator, values: anytype) ![]u8;

// Emit events
pub fn emitStateSigned(store: *EventStore, state: State, sig: Signature, a: Allocator) !void;
pub fn emitStateReceived(store: *EventStore, state: State, sig: Signature, from: Address, a: Allocator) !void;
```

## Implementation

**W1:** ADRs, core types (State/FixedPart/VariablePart), ChannelId generation
**W2:** secp256k1 integration, ABI encoding
**W3:** State hashing, sign/verify, unit tests
**W4:** Cross-impl test vs reference implementations, event integration, benchmarks, demo

**Tasks:**
- T1: Define structs (S, P0)
- T2: Define Outcome/Allocation/Signature (S, P0)
- T3: ChannelId generation (M, P0)
- T4: State hashing (L, P0)
- T5: secp256k1 lib integration (M, P0)
- T6: Sign creation (M, P0)
- T7: Verify/recovery (M, P0)
- T8: ABI encoding (L, P0)
- T9: Event emission (M, P1)
- T10-13: Tests, benchmarks, ADRs, docs

**Path:** T1→T3→T4→T5→T6→T7→Cross-impl test

## Testing

**Unit:** 60+ tests, 90%+ cov
- ChannelId deterministic
- State hash deterministic
- Sig roundtrip correct
- ABI encoding byte-match
- Event emission complete

**Integration:**
- Full lifecycle: Create → Sign → Verify → Emit → Reconstruct
- Cross-impl: Our encoding matches reference implementations byte-for-byte

**Benchmarks:**
- ChannelId: <1ms
- State hash: <2ms
- Sign+verify: <10ms P95

## Dependencies

**Req:** P1 (EventStore), Zig 0.15+
**External:** voltaire/primitives (https://github.com/evmts/primitives)
**Modules:** `primitives` (Address, AbiEncoding), `crypto` (secp256k1, Keccak256), `precompiles` (unused)
**Integration pattern:** See ../guillotine-mini/build.zig.zon for proven setup
**Local dev:** ../voltaire cloned locally for reference
**⚠️ Security:** Crypto implementation marked UNAUDITED by voltaire - acceptable for P2 testing, audit required for production

**Voltaire integration:**
```bash
# Fetch dependency
zig fetch --save=primitives https://github.com/evmts/primitives/archive/refs/heads/main.tar.gz
```

**build.zig pattern:**
```zig
const primitives_dep = b.dependency("primitives", .{
    .target = target,
    .optimize = optimize,
});
const primitives_mod = primitives_dep.module("primitives");
const crypto_mod = primitives_dep.module("crypto");
const precompiles_mod = primitives_dep.module("precompiles");

// Add to module imports
.imports = &.{
    .{ .name = "primitives", .module = primitives_mod },
    .{ .name = "crypto", .module = crypto_mod },
    .{ .name = "precompiles", .module = precompiles_mod },
},
```

**Code usage:**
```zig
const primitives = @import("primitives");
const crypto_pkg = @import("crypto");
const Address = primitives.Address.Address;
const Hash = crypto_pkg.Hash;
const Crypto = crypto_pkg.Crypto;
const abi = primitives.AbiEncoding;

// ChannelId = keccak256(encodePacked(fixedPart))
const encoded = try abi.encodePacked(allocator, &abi_values);
const channel_id = Hash.keccak256(encoded);

// Sign state hash
const sig = try Crypto.unaudited_signHash(state_hash, private_key);

// Recover signer
const addr = try Crypto.unaudited_recoverAddress(state_hash, signature);
```

## Risks

|Risk|P|I|Mitigation|
|--|--|--|--|
|ABI encoding bugs|M|H|Cross-test vs reference implementations, contract vectors|
|Sig verify wrong recovery|M|H|Test vs ethers.js, proven lib|
|Keccak256 incorrect|L|H|Use tested lib (voltaire)|
|Voltaire crypto unaudited|L|M|Explicitly mark P2 as development/testing only; document audit requirement for production|
|secp256k1 integration complex|M|M|2 days allocated, test thoroughly|

## Deliverables

**Code:** `src/state/{types,channel_id,hash}.zig`, `src/crypto/signature.zig`, `src/abi/encoder.zig`, tests
**Docs:** ADR-0004/0005, arch docs (state structure, signatures, ABI), API ref
**Val:** 90%+ cov, cross-impl match, benchmarks met

## Validation Gates

- G1: ADRs approved, API designed, voltaire integrated
- G2: Code review (2+), tests pass, 90%+ cov
- G3: Cross-impl passes, benchmarks met, events work
- G4: Demo complete, docs published, P3 unblocked

## Refs

**Phases:** P1 (Events)
**ADRs:** 0004 (Sig), 0005 (ABI), 0006 (ChannelId)
**External:** State channel implementations, Ethereum ABI spec, EIP-191, secp256k1 spec
**Reference Implementation:** ../guillotine-mini - proven voltaire integration
**Voltaire Examples:** ../voltaire/examples/signature_recovery.zig - secp256k1 usage patterns

## Example

```zig
// Create state
const state = State{
    .participants = &[_]Address{alice, bob},
    .channel_nonce = 42,
    .app_definition = app,
    .challenge_duration = 86400,
    .app_data = &[_]u8{},
    .outcome = outcome,
    .turn_num = 0,
    .is_final = false,
};

// ChannelId
const id = try state.channelId(allocator);

// Sign
const sig = try state.sign(allocator, alice_key);

// Verify
const addr = try state.recoverSigner(allocator, sig);
const valid = std.mem.eql(u8, &addr, &alice);
```

---

## CONTEXT FROM PHASE 1 (Event Surface)

**Phase 1 Status:** Event types defined ✅ | EventStore implementation → Phase 1b (pending)

### Event Types Already Defined

Phase 1 delivered **20 events** including state-related events relevant to this phase:

**Channel State Events (use these):**
- [`channel-created`](../../schemas/events/channel-created.schema.json) - Emitted when ChannelId derived from FixedPart
- [`state-signed`](../../schemas/events/state-signed.schema.json) - Emitted when local party signs state
- [`state-received`](../../schemas/events/state-received.schema.json) - Emitted when remote state received/validated
- [`state-supported-updated`](../../schemas/events/state-supported-updated.schema.json) - Emitted when supported turn advances

**Implementation:**
- Event types: [src/event_store/events.zig](../../src/event_store/events.zig)
- Event schemas: [schemas/events/](../../schemas/events/)
- Event catalog: [docs/architecture/event-types.md](../../docs/architecture/event-types.md)

### Integration Requirements for Phase 2

**When implementing State operations:**

1. **ChannelId Generation:**
   ```zig
   pub fn channelId(self: FixedPart, a: Allocator) !ChannelId {
       // 1. ABI encode FixedPart
       // 2. Keccak256 hash
       // 3. Emit channel-created event
       const id = keccak256(abi_encoded);
       try emitChannelCreated(event_store, self, id, a);
       return id;
   }
   ```

2. **State Signing:**
   ```zig
   pub fn sign(self: State, a: Allocator, pk: [32]u8) !Signature {
       const state_hash = try self.hash(a);
       const sig = try signEthereumMessage(state_hash, pk);
       // Emit state-signed event
       try emitStateSigned(event_store, self, sig, a);
       return sig;
   }
   ```

3. **State Reception:**
   ```zig
   pub fn recoverSigner(self: State, a: Allocator, sig: Signature) !Address {
       const state_hash = try self.hash(a);
       const addr = try recoverEthereumMessageSigner(state_hash, sig);
       // Emit state-received event (if from remote peer)
       try emitStateReceived(event_store, self, sig, addr, a);
       return addr;
   }
   ```

**Event Emission Pattern:**
```zig
pub fn emitStateSigned(
    store: *EventStore,  // From Phase 1b (when implemented)
    state: State,
    sig: Signature,
    a: Allocator
) !void {
    const event = Event{
        .state_signed = .{
            .event_version = 1,
            .timestamp_ms = @intCast(std.time.milliTimestamp()),
            .channel_id = try state.channelId(a),
            .turn_num = state.turn_num,
            .state_hash = try state.hash(a),
            .signer = try state.recoverSigner(a, sig),
            .signature = sig.toBytes(),
            .is_final = state.is_final,
            .app_data_hash = if (state.app_data.len > 0) 
                keccak256(state.app_data) else null,
        },
    };
    _ = try store.append(event);
}
```

### State Hashing Must Match Event ID Approach

Phase 1 established canonical serialization for event IDs:
- Sorted keys (lexicographic)
- No whitespace
- Keccak256 hashing

**State.hash() should use similar approach:**
```zig
pub fn hash(self: State, a: Allocator) !Bytes32 {
    // 1. ABI encode State (deterministic, sorted)
    // 2. Keccak256 hash
    // 3. Result must be reproducible (same state → same hash)
    const encoded = try abiEncode(a, self);
    defer a.free(encoded);
    return keccak256(encoded);
}
```

**Consistency requirement:** If state is reconstructed from events, hashing it should produce same state_hash as stored in `state-signed` event.

### Test Vectors Available

Use existing golden vectors to verify compatibility:
- [testdata/events/state-signed.golden.json](../../testdata/events/state-signed.golden.json)
- Contains example state_hash, signature, channel_id values
- Phase 2 implementation should produce byte-identical hashes

### Validation Hooks

State validation can reference event history:
```zig
pub fn validate(state: State, ctx: ValidationContext) !void {
    // Check if channel exists (via event log query)
    const channel_events = try ctx.getChannelEvents(state.channelId());
    if (channel_events.len == 0) return error.ChannelNotFound;
    
    // Check turn progression (vs latest state-signed event)
    const latest = ctx.getLatestSignedTurn(state.channelId());
    if (state.turn_num <= latest) return error.InvalidTurnProgression;
}
```

### Files to Reference

**Phase 1 Deliverables:**
- Event definitions: [src/event_store/events.zig](../../src/event_store/events.zig)
- ID derivation (for consistency): [src/event_store/id.zig](../../src/event_store/id.zig)
- Event schemas: [schemas/events/state-*.schema.json](../../schemas/events/)
- Documentation: [docs/architecture/event-types.md](../../docs/architecture/event-types.md)

**Don't Re-implement:**
- Event types (already exist)
- Event ID derivation (use existing keccak256 approach)
- Canonical JSON serialization (exists in id.zig)

**Do Implement:**
- State/FixedPart/VariablePart types (new in P2)
- ABI encoding (Ethereum-specific, different from JSON)
- secp256k1 signatures (new in P2)
- Event emission helpers (bridge between State and Event types)

---

**Context Added:** 2025-11-08  
**Phase 1 Status:** Events defined, EventStore pending Phase 1b
